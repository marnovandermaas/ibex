// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

////////////////////////////////////////////////////////////////////////////////
// Engineer        Andreas Traber - atraber@iis.ee.ethz.ch                    //
//                                                                            //
// Additional contributions by:                                               //
//                 Matthias Baer - baermatt@student.ethz.ch                   //
//                 Igor Loi - igor.loi@unibo.it                               //
//                 Sven Stucki - svstucki@student.ethz.ch                     //
//                 Davide Schiavone - pschiavo@iis.ee.ethz.ch                 //
//                 Markus Wegmann - markus.wegmann@technokrat.ch              //
//                                                                            //
// Design Name:    Decoder                                                    //
// Project Name:   ibex                                                       //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Decoder                                                    //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

// Source/Destination register instruction index
`define REG_S1 19:15
`define REG_S2 24:20
`define REG_D  11:07

/**
 * Instruction decoder
 */
module ibex_decoder #(
    parameter bit RV32E = 0,
    parameter bit RV32M = 1
) (
    // to/from controller
    output logic                     illegal_insn_o,        // illegal instr encountered
    output logic                     ebrk_insn_o,           // trap instr encountered
    output logic                     mret_insn_o,           // return from exception instr
                                                            // encountered
    output logic                     dret_insn_o,           // return from debug instr encountered
    output logic                     ecall_insn_o,          // syscall instr encountered
    output logic                     wfi_insn_o,            // wait for interrupt instr encountered
    output logic                     jump_set_o,            // jump taken set signal

    // from IF-ID pipeline register
    input  logic                     instr_new_i,           // instruction read is new
    input  logic [31:0]              instr_rdata_i,         // instruction read from memory/cache
    input  logic                     illegal_c_insn_i,      // compressed instruction decode failed

    // immediates
    output ibex_defines::imm_a_sel_e imm_a_mux_sel_o,       // immediate selection for operand a
    output ibex_defines::imm_b_sel_e imm_b_mux_sel_o,       // immediate selection for operand b
    output logic [31:0]              imm_i_type_o,
    output logic [31:0]              imm_s_type_o,
    output logic [31:0]              imm_b_type_o,
    output logic [31:0]              imm_u_type_o,
    output logic [31:0]              imm_j_type_o,
    output logic [31:0]              zimm_rs1_type_o,

    // register file
    output ibex_defines::rf_wd_sel_e regfile_wdata_sel_o,   // RF write data selection
    output logic                     regfile_we_o,          // write enable for regfile
    output logic [4:0]               regfile_raddr_a_o,
    output logic [4:0]               regfile_raddr_b_o,
    output logic [4:0]               regfile_waddr_o,

    // ALU
    output ibex_defines::alu_op_e    alu_operator_o,        // ALU operation selection
    output ibex_defines::op_a_sel_e  alu_op_a_mux_sel_o,    // operand a selection: reg value, PC,
                                                            // immediate or zero
    output ibex_defines::op_b_sel_e  alu_op_b_mux_sel_o,    // operand b selection: reg value or
                                                            // immediate

    // MULT & DIV
    output logic                     mult_en_o,             // perform integer multiplication
    output logic                     div_en_o,              // perform integer division or
                                                            // remainder
    output ibex_defines::md_op_e     multdiv_operator_o,
    output logic [1:0]               multdiv_signed_mode_o,

    // CHERI
    output logic                     cheri_en_o,
    output ibex_defines::cheri_base_opcode_e       cheri_base_opcode_o,
    output ibex_defines::cheri_threeop_funct7_e    cheri_threeop_opcode_o,
    output ibex_defines::cheri_store_funct5_e      cheri_store_opcode_o,
    output ibex_defines::cheri_load_funct5_e       cheri_load_opcode_o,
    output ibex_defines::cheri_s_a_d_funct5_e      cheri_sad_opcode_o,
    output ibex_defines::c_op_a_sel_e          cheri_op_a_mux_sel_o,
    output ibex_defines::c_op_b_sel_e          cheri_op_b_mux_sel_o,
    output ibex_defines::cheri_imm_b_sel_e          cheri_imm_b_mux_sel_o,
    output logic cheri_a_en_o,
    output logic cheri_b_en_o,
    // TODO find this a new home
    input logic cap_mode_i,
    output logic use_cap_base_o,

    // CSRs
    output logic                     csr_access_o,          // access to CSR
    output ibex_defines::csr_op_e    csr_op_o,              // operation to perform on CSR
    output logic                     csr_status_o,          // access to xstatus CSR

    // SCRs
    output logic scr_access_o,
    output ibex_defines::scr_op_e scr_op_o,

    // LSU
    output logic                     data_req_o,            // start transaction to data memory
    output logic                     data_we_o,             // write enable
    output logic [1:0]               data_type_o,           // size of transaction: byte, half
                                                            // word or word
    output logic                     data_sign_extension_o, // sign extension for data read from
                                                            // memory
    output logic [1:0]               data_reg_offset_o,     // register byte offset for stores
    output logic mem_cap_access_o,

    // not really for LSU
    output logic mem_ddc_relative_o,

    // jump/branches
    output logic                     jump_in_dec_o,         // jump is being calculated in ALU
    output logic                     branch_in_dec_o
);

  import ibex_defines::*;

  logic        illegal_insn;
  logic        illegal_reg_rv32e;
  logic        csr_illegal;
  logic        regfile_we;

  logic [31:0] instr;

  csr_op_e     csr_op;

  opcode_e     opcode;

  cheri_base_opcode_e cheri_base_opcode;
  cheri_threeop_funct7_e cheri_threeop_opcode;
  cheri_store_funct5_e cheri_store_opcode;
  cheri_load_funct5_e cheri_load_opcode;
  cheri_s_a_d_funct5_e cheri_sad_opcode;


  assign cheri_base_opcode = cheri_base_opcode_e'(instr[14:12]);
  assign cheri_threeop_opcode = cheri_threeop_funct7_e'(instr[31:25]);
  assign cheri_store_opcode = cheri_store_funct5_e'(instr[11:7]);
  assign cheri_load_opcode = cheri_load_funct5_e'(instr[24:20]);
  assign cheri_sad_opcode = cheri_s_a_d_funct5_e'(instr[24:20]);


  assign instr = instr_rdata_i;

  //////////////////////////////////////
  // Register and immediate selection //
  //////////////////////////////////////

  // immediate extraction and sign extension
  assign imm_i_type_o = { {20{instr[31]}}, instr[31:20] };
  assign imm_s_type_o = { {20{instr[31]}}, instr[31:25], instr[11:7] };
  assign imm_b_type_o = { {19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0 };
  assign imm_u_type_o = { instr[31:12], 12'b0 };
  assign imm_j_type_o = { {12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0 };

  // immediate for CSR manipulation (zero extended)
  assign zimm_rs1_type_o = { 27'b0, instr[`REG_S1] }; // rs1

  // source registers
  assign regfile_raddr_a_o = instr[`REG_S1]; // rs1
  assign regfile_raddr_b_o = instr[`REG_S2]; // rs2

  // destination register
  assign regfile_waddr_o   = instr[`REG_D]; // rd

  ////////////////////
  // Register check //
  ////////////////////
  if (RV32E) begin
    assign illegal_reg_rv32e = ((regfile_raddr_a_o[4] && (alu_op_a_mux_sel_o == OP_A_REG_A)) ||
                                (regfile_raddr_b_o[4] && (alu_op_b_mux_sel_o == OP_B_REG_B)) ||
                                (regfile_waddr_o[4] & regfile_we));
  end else begin
    assign illegal_reg_rv32e = 1'b0;
  end

  ///////////////////////
  // CSR operand check //
  ///////////////////////
  always_comb begin : csr_operand_check
    csr_op_o = csr_op;

    // CSRRSI/CSRRCI must not write 0 to CSRs (uimm[4:0]=='0)
    // CSRRS/CSRRC must not write from x0 to CSRs (rs1=='0)
    if ((csr_op == CSR_OP_SET || csr_op == CSR_OP_CLEAR) &&
        instr[`REG_S1] == '0) begin
      csr_op_o = CSR_OP_READ;
    end
  end

  /////////////
  // Decoder //
  /////////////

  // TODO ask about this
  /* TODO: need to tell whatever is reading from registers whether it should pass the register value
   through a getAddr (if the value is an integer) or not (if it's a capability)
   This isn't needed if not using CHERI, so we'll want to wrap them with `ifdefs
      Can do this at least two ways:
        I edit this block and at every instruction, i can add an `ifdef CHERI to wrap these values
          This means that there are many `ifdefs throughout the next always_comb block
        I add in a new always_comb block at the end that is completely wrapped in an `ifdef CHERI
          The new block is then responsible solely for setting the value described above which
          tells the reader whether it needs to pass it through the getAddr
          In addition if I add in this new block, then I can move the check for opcode_CHERI into it,
          but then there are competing writes to illegal_insn since the original block doesn't recognise
          CHERI and hence will say it's an illegal instruction
  */
  always_comb begin
    jump_in_dec_o               = 1'b0;
    jump_set_o                  = 1'b0;
    branch_in_dec_o             = 1'b0;
    alu_operator_o              = ALU_SLTU;
    alu_op_a_mux_sel_o          = OP_A_IMM;
    alu_op_b_mux_sel_o          = OP_B_IMM;

    imm_a_mux_sel_o             = IMM_A_ZERO;
    imm_b_mux_sel_o             = IMM_B_I;

    mult_en_o                   = 1'b0;
    div_en_o                    = 1'b0;
    multdiv_operator_o          = MD_OP_MULL;
    multdiv_signed_mode_o       = 2'b00;

    cheri_en_o                  = 1'b0;
    cheri_imm_b_mux_sel_o       = CHERI_OP_B_REG_NUM;
    cheri_a_en_o = 1'b0;
    cheri_b_en_o = 1'b0;
    cheri_base_opcode_o = cheri_base_opcode;
    cheri_threeop_opcode_o = cheri_threeop_opcode;
    cheri_store_opcode_o = cheri_store_opcode;
    cheri_load_opcode_o = cheri_load_opcode;
    cheri_sad_opcode_o = cheri_sad_opcode;

    mem_ddc_relative_o = '0;

    regfile_wdata_sel_o         = RF_WD_EX;
    regfile_we                  = 1'b0;

    csr_access_o                = 1'b0;
    csr_status_o                = 1'b0;
    csr_illegal                 = 1'b0;
    csr_op                      = CSR_OP_READ;

    scr_access_o = 1'b0;
    scr_op_o = SCR_NONE;

    data_we_o                   = 1'b0;
    data_type_o                 = 2'b00;
    data_sign_extension_o       = 1'b0;
    data_reg_offset_o           = 2'b00;
    data_req_o                  = 1'b0;
    mem_cap_access_o = 1'b0;

    illegal_insn                = 1'b0;
    ebrk_insn_o                 = 1'b0;
    mret_insn_o                 = 1'b0;
    dret_insn_o                 = 1'b0;
    ecall_insn_o                = 1'b0;
    wfi_insn_o                  = 1'b0;

    opcode                      = opcode_e'(instr[6:0]);

    unique case (opcode)

      ///////////
      // Jumps //
      ///////////

      OPCODE_JAL: begin   // Jump and Link
        jump_in_dec_o         = 1'b1;
        if (instr_new_i) begin
          // Calculate jump target
          alu_op_a_mux_sel_o  = OP_A_CURRPC;
          alu_op_b_mux_sel_o  = OP_B_IMM;
          imm_b_mux_sel_o     = IMM_B_J;
          alu_operator_o      = ALU_ADD;
          regfile_we          = 1'b0;
          jump_set_o          = 1'b1;
        end else begin
          // Calculate and store PC+4
          alu_op_a_mux_sel_o  = OP_A_CURRPC;
          alu_op_b_mux_sel_o  = OP_B_IMM;
          imm_b_mux_sel_o     = IMM_B_INCR_PC;
          alu_operator_o      = ALU_ADD;
          regfile_we          = 1'b1;
        end
      end

      OPCODE_JALR: begin  // Jump and Link Register
        jump_in_dec_o         = 1'b1;
        if (instr_new_i) begin
          // Calculate jump target
          alu_op_a_mux_sel_o  = OP_A_REG_A;
          alu_op_b_mux_sel_o  = OP_B_IMM;
          imm_b_mux_sel_o     = IMM_B_I;
          alu_operator_o      = ALU_ADD;
          regfile_we          = 1'b0;
          jump_set_o          = 1'b1;
        end else begin
          // Calculate and store PC+4
          alu_op_a_mux_sel_o  = OP_A_CURRPC;
          alu_op_b_mux_sel_o  = OP_B_IMM;
          imm_b_mux_sel_o     = IMM_B_INCR_PC;
          alu_operator_o      = ALU_ADD;
          regfile_we          = 1'b1;
        end
        if (instr[14:12] != 3'b0) begin
          illegal_insn = 1'b1;
        end
      end

      OPCODE_BRANCH: begin // Branch
        branch_in_dec_o       = 1'b1;
        if (instr_new_i) begin
          // Evaluate branch condition
          alu_op_a_mux_sel_o  = OP_A_REG_A;
          alu_op_b_mux_sel_o  = OP_B_REG_B;
          unique case (instr[14:12])
            3'b000:  alu_operator_o = ALU_EQ;
            3'b001:  alu_operator_o = ALU_NE;
            3'b100:  alu_operator_o = ALU_LT;
            3'b101:  alu_operator_o = ALU_GE;
            3'b110:  alu_operator_o = ALU_LTU;
            3'b111:  alu_operator_o = ALU_GEU;
            default: illegal_insn   = 1'b1;
          endcase
        end else begin
          // Calculate jump target in EX
          alu_op_a_mux_sel_o  = OP_A_CURRPC;
          alu_op_b_mux_sel_o  = OP_B_IMM;
          imm_b_mux_sel_o     = IMM_B_B;
          alu_operator_o      = ALU_ADD;
          regfile_we          = 1'b0;
        end
      end

      ////////////////
      // Load/store //
      ////////////////

      OPCODE_STORE: begin
        //alu_op_a_mux_sel_o = OP_A_REG_A;
        alu_op_a_mux_sel_o  = cap_mode_i ? OP_A_IMM : OP_A_REG_A;
        alu_op_b_mux_sel_o = OP_B_REG_B;
        data_req_o         = 1'b1;
        data_we_o          = 1'b1;
        alu_operator_o     = ALU_ADD;
        use_cap_base_o = !cap_mode_i;

        if (!instr[14]) begin
          // offset from immediate
          imm_b_mux_sel_o     = IMM_B_S;
          alu_op_b_mux_sel_o  = OP_B_IMM;
        end else begin
          // Register offset is illegal since no register c available
          illegal_insn = 1'b1;
        end

        // store size
        unique case (instr[13:12])
          2'b00: data_type_o = 2'b10; // SB
          2'b01: data_type_o = 2'b01; // SH
          2'b10: data_type_o = 2'b00; // SW
          2'b11: begin
            // TODO if in cap encoding mode, need to change stuff
            data_type_o = 2'b11; // SD
            mem_cap_access_o = 1'b1;
            use_cap_base_o = 1'b0;
          end
        endcase
      end

      OPCODE_LOAD: begin
        //alu_op_a_mux_sel_o  = OP_A_REG_A;
        alu_op_a_mux_sel_o  = cap_mode_i ? OP_A_IMM : OP_A_REG_A;
        data_req_o          = 1'b1;
        regfile_wdata_sel_o = RF_WD_LSU;
        regfile_we          = 1'b1;
        data_type_o         = 2'b00;
        use_cap_base_o = !cap_mode_i;

        // offset from immediate
        alu_operator_o      = ALU_ADD;
        alu_op_b_mux_sel_o  = OP_B_IMM;
        imm_b_mux_sel_o     = IMM_B_I;

        // sign/zero extension
        data_sign_extension_o = ~instr[14];

        // load size
        unique case (instr[13:12])
          2'b00:   data_type_o = 2'b10; // LB
          2'b01:   data_type_o = 2'b01; // LH
          2'b10:   data_type_o = 2'b00; // LW
          2'b11: begin
            // TODO if in cap encoding mode, need to change stuff
            data_type_o = 2'b11; // LD
            mem_cap_access_o = 1'b1;
            use_cap_base_o = 1'b0;
          end
          //default: data_type_o = 2'b00; // illegal or reg-reg
        endcase

        // reg-reg load (different encoding)
        if (instr[14:12] == 3'b111) begin
          // offset from RS2
          alu_op_b_mux_sel_o = OP_B_REG_B;

          // sign/zero extension
          data_sign_extension_o = ~instr[30];

          // load size
          unique case (instr[31:25])
            7'b0000_000,
            7'b0100_000: data_type_o = 2'b10; // LB, LBU
            7'b0001_000,
            7'b0101_000: data_type_o = 2'b01; // LH, LHU
            7'b0010_000: data_type_o = 2'b00; // LW
            default: begin
              illegal_insn = 1'b1;
            end
          endcase
        end

        /* this is used for capability reads so needs to be commented out
        if (instr[14:12] == 3'b011) begin
          // LD -> RV64 only
          illegal_insn = 1'b1;
        end
        */
      end

      /////////
      // ALU //
      /////////

      OPCODE_LUI: begin  // Load Upper Immediate
        alu_op_a_mux_sel_o  = OP_A_IMM;
        alu_op_b_mux_sel_o  = OP_B_IMM;
        imm_a_mux_sel_o     = IMM_A_ZERO;
        imm_b_mux_sel_o     = IMM_B_U;
        alu_operator_o      = ALU_ADD;
        regfile_we          = 1'b1;
      end

      OPCODE_AUIPC: begin  // Add Upper Immediate to PC
        if (!cap_mode_i) begin
          alu_op_a_mux_sel_o  = OP_A_CURRPC;
          alu_op_b_mux_sel_o  = OP_B_IMM;
          imm_b_mux_sel_o     = IMM_B_U;
          alu_operator_o      = ALU_ADD;
          regfile_we          = 1'b1;
        end else begin
          // send this instruction to the CHERI ALU
          cheri_en_o = 1'b1;
          cheri_base_opcode_o = C_INC_OFFSET_IMM;
          cheri_op_a_mux_sel_o  = CHERI_OP_A_PCC;
          cheri_op_b_mux_sel_o  = CHERI_OP_B_IMM;
          cheri_imm_b_mux_sel_o = CHERI_IMM_B_U;
          regfile_wdata_sel_o = RF_WD_CHERI;
          regfile_we          = 1'b1;
        end
      end

      OPCODE_OP_IMM: begin // Register-Immediate ALU Operations
        alu_op_a_mux_sel_o  = OP_A_REG_A;
        alu_op_b_mux_sel_o  = OP_B_IMM;
        imm_b_mux_sel_o     = IMM_B_I;
        regfile_we          = 1'b1;

        unique case (instr[14:12])
          3'b000: alu_operator_o = ALU_ADD;  // Add Immediate
          3'b010: alu_operator_o = ALU_SLT;  // Set to one if Lower Than Immediate
          3'b011: alu_operator_o = ALU_SLTU; // Set to one if Lower Than Immediate Unsigned
          3'b100: alu_operator_o = ALU_XOR;  // Exclusive Or with Immediate
          3'b110: alu_operator_o = ALU_OR;   // Or with Immediate
          3'b111: alu_operator_o = ALU_AND;  // And with Immediate

          3'b001: begin
            alu_operator_o = ALU_SLL;  // Shift Left Logical by Immediate
            if (instr[31:25] != 7'b0) begin
              illegal_insn = 1'b1;
            end
          end

          3'b101: begin
            if (instr[31:25] == 7'b0) begin
              alu_operator_o = ALU_SRL;  // Shift Right Logical by Immediate
            end else if (instr[31:25] == 7'b010_0000) begin
              alu_operator_o = ALU_SRA;  // Shift Right Arithmetically by Immediate
            end else begin
              illegal_insn   = 1'b1;
            end
          end

          default: begin
            alu_operator_o = alu_op_e'({$bits(alu_op_e){1'bX}});
          end
        endcase
      end

      OPCODE_OP: begin  // Register-Register ALU operation
        alu_op_a_mux_sel_o = OP_A_REG_A;
        alu_op_b_mux_sel_o = OP_B_REG_B;
        regfile_we         = 1'b1;

        if (instr[31]) begin
          illegal_insn = 1'b1;
        end else if (!instr[28]) begin // non bit-manipulation instructions
          unique case ({instr[30:25], instr[14:12]})
            // RV32I ALU operations
            {6'b00_0000, 3'b000}: alu_operator_o = ALU_ADD;   // Add
            {6'b10_0000, 3'b000}: alu_operator_o = ALU_SUB;   // Sub
            {6'b00_0000, 3'b010}: alu_operator_o = ALU_SLT;   // Set Lower Than
            {6'b00_0000, 3'b011}: alu_operator_o = ALU_SLTU;  // Set Lower Than Unsigned
            {6'b00_0000, 3'b100}: alu_operator_o = ALU_XOR;   // Xor
            {6'b00_0000, 3'b110}: alu_operator_o = ALU_OR;    // Or
            {6'b00_0000, 3'b111}: alu_operator_o = ALU_AND;   // And
            {6'b00_0000, 3'b001}: alu_operator_o = ALU_SLL;   // Shift Left Logical
            {6'b00_0000, 3'b101}: alu_operator_o = ALU_SRL;   // Shift Right Logical
            {6'b10_0000, 3'b101}: alu_operator_o = ALU_SRA;   // Shift Right Arithmetic

            // supported RV32M instructions
            {6'b00_0001, 3'b000}: begin // mul
              alu_operator_o        = ALU_ADD;
              multdiv_operator_o    = MD_OP_MULL;
              mult_en_o             = RV32M ? 1'b1 : 1'b0;
              multdiv_signed_mode_o = 2'b00;
              illegal_insn          = RV32M ? 1'b0 : 1'b1;
            end
            {6'b00_0001, 3'b001}: begin // mulh
              alu_operator_o        = ALU_ADD;
              multdiv_operator_o    = MD_OP_MULH;
              mult_en_o             = RV32M ? 1'b1 : 1'b0;
              multdiv_signed_mode_o = 2'b11;
              illegal_insn          = RV32M ? 1'b0 : 1'b1;
            end
            {6'b00_0001, 3'b010}: begin // mulhsu
              alu_operator_o        = ALU_ADD;
              multdiv_operator_o    = MD_OP_MULH;
              mult_en_o             = RV32M ? 1'b1 : 1'b0;
              multdiv_signed_mode_o = 2'b01;
              illegal_insn          = RV32M ? 1'b0 : 1'b1;
            end
            {6'b00_0001, 3'b011}: begin // mulhu
              alu_operator_o        = ALU_ADD;
              multdiv_operator_o    = MD_OP_MULH;
              mult_en_o             = RV32M ? 1'b1 : 1'b0;
              multdiv_signed_mode_o = 2'b00;
              illegal_insn          = RV32M ? 1'b0 : 1'b1;
            end
            {6'b00_0001, 3'b100}: begin // div
              alu_operator_o        = ALU_ADD;
              multdiv_operator_o    = MD_OP_DIV;
              div_en_o              = RV32M ? 1'b1 : 1'b0;
              multdiv_signed_mode_o = 2'b11;
              illegal_insn          = RV32M ? 1'b0 : 1'b1;
            end
            {6'b00_0001, 3'b101}: begin // divu
              alu_operator_o        = ALU_ADD;
              multdiv_operator_o    = MD_OP_DIV;
              div_en_o              = RV32M ? 1'b1 : 1'b0;
              multdiv_signed_mode_o = 2'b00;
              illegal_insn          = RV32M ? 1'b0 : 1'b1;
            end
            {6'b00_0001, 3'b110}: begin // rem
              alu_operator_o        = ALU_ADD;
              multdiv_operator_o    = MD_OP_REM;
              div_en_o              = RV32M ? 1'b1 : 1'b0;
              multdiv_signed_mode_o = 2'b11;
              illegal_insn          = RV32M ? 1'b0 : 1'b1;
            end
            {6'b00_0001, 3'b111}: begin // remu
              alu_operator_o        = ALU_ADD;
              multdiv_operator_o    = MD_OP_REM;
              div_en_o              = RV32M ? 1'b1 : 1'b0;
              multdiv_signed_mode_o = 2'b00;
              illegal_insn          = RV32M ? 1'b0 : 1'b1;
            end
            default: begin
              illegal_insn = 1'b1;
            end
          endcase
        end
      end

      /////////////
      // Special //
      /////////////

      OPCODE_MISC_MEM: begin
        // For now, treat the fence (funct3 == 000) instruction as a nop.
        // This may not be correct in a system with caches and should be
        // revisited.
        // fence.i (funct3 == 001) was moved to a separate Zifencei extension
        // in the RISC-V ISA spec proposed for ratification, so we treat it as
        // an illegal instruction.
        if (instr[14:12] == 3'b000) begin
          alu_operator_o     = ALU_ADD; // nop
          alu_op_a_mux_sel_o = OP_A_REG_A;
          alu_op_b_mux_sel_o = OP_B_IMM;
          regfile_we         = 1'b0;
        end else begin
          illegal_insn       = 1'b1;
        end
      end

      OPCODE_SYSTEM: begin
        if (instr[14:12] == 3'b000) begin
          // non CSR related SYSTEM instructions
          alu_op_a_mux_sel_o = OP_A_REG_A;
          alu_op_b_mux_sel_o = OP_B_IMM;
          unique case (instr[31:20])
            12'h000:  // ECALL
              // environment (system) call
              ecall_insn_o = 1'b1;

            12'h001:  // ebreak
              // debugger trap
              ebrk_insn_o = 1'b1;

            12'h302:  // mret
              mret_insn_o = 1'b1;

            12'h7b2:  // dret
              dret_insn_o = 1'b1;

            12'h105:  // wfi
              wfi_insn_o = 1'b1;

            default:
              illegal_insn = 1'b1;
          endcase

          // rs1 and rd must be 0
          if (instr[`REG_S1] || instr[`REG_D]) begin
            illegal_insn = 1'b1;
          end
        end else begin
          // instruction to read/modify CSR
          csr_access_o        = 1'b1;
          regfile_wdata_sel_o = RF_WD_CSR;
          regfile_we          = 1'b1;
          alu_op_b_mux_sel_o  = OP_B_IMM;
          imm_a_mux_sel_o     = IMM_A_Z;
          imm_b_mux_sel_o     = IMM_B_I;  // CSR address is encoded in I imm

          if (instr[14]) begin
            // rs1 field is used as immediate
            alu_op_a_mux_sel_o = OP_A_IMM;
          end else begin
            alu_op_a_mux_sel_o = OP_A_REG_A;
          end

          unique case (instr[13:12])
            2'b01:   csr_op = CSR_OP_WRITE;
            2'b10:   csr_op = CSR_OP_SET;
            2'b11:   csr_op = CSR_OP_CLEAR;
            default: csr_illegal = 1'b1;
          endcase

          if (!csr_illegal) begin
            // flush pipeline on access to mstatus or debug CSRs
            if (csr_num_e'(instr[31:20]) == CSR_MSTATUS   ||
                csr_num_e'(instr[31:20]) == CSR_DCSR      ||
                csr_num_e'(instr[31:20]) == CSR_DPC       ||
                csr_num_e'(instr[31:20]) == CSR_DSCRATCH0 ||
                csr_num_e'(instr[31:20]) == CSR_DSCRATCH1) begin
              csr_status_o = 1'b1;
            end
          end

          illegal_insn = csr_illegal;
        end

      end

      OPCODE_CHERI: begin
        // set CHERI stuff
        cheri_en_o = 1'b1;
        cheri_a_en_o = 1'b1;
        cheri_op_a_mux_sel_o = CHERI_OP_A_REG_CAP;
        regfile_wdata_sel_o = RF_WD_CHERI;
        unique case (cheri_base_opcode)
          THREE_OP: begin // The instruction is a three-operand instruction
            unique case (cheri_threeop_opcode)
              // 2 in 1 out
              C_SET_BOUNDS, C_SET_BOUNDS_EXACT, C_AND_PERM,
              C_SET_FLAGS, C_SET_OFFSET, C_SET_ADDR, C_INC_OFFSET,
              C_SUB, C_TEST_SUBSET: begin
                regfile_we          = 1'b1;
                cheri_op_b_mux_sel_o = CHERI_OP_B_REG_NUM;
                cheri_b_en_o = 1'b1;
              end

              C_SPECIAL_RW: begin
                // TODO the last line in this or isn't right
                // we want to throw an illegal instruction when the SCR isn't one we've implemented, but
                // if the destination register is 0 we don't want to throw
                // TODO some registers were removed in order to be able to test against rvbs - these need readded
                if ((regfile_raddr_b_o == SCR_PCC)
                                ||(regfile_raddr_b_o == SCR_DDC)
                                ||(regfile_raddr_b_o == SCR_UTCC)
                                //||(regfile_raddr_b_o == SCR_UTDC)
                                ||(regfile_raddr_b_o == SCR_USCRATCHC)
                                ||(regfile_raddr_b_o == SCR_UEPCC)
                                ||(regfile_raddr_b_o == SCR_STCC)
                                //||(regfile_raddr_b_o == SCR_STDC)
                                ||(regfile_raddr_b_o == SCR_SSCRATCHC)
                                ||(regfile_raddr_b_o == SCR_SEPCC)
                                ||(regfile_raddr_b_o == SCR_MTCC)
                                //||(regfile_raddr_b_o == SCR_MTDC)
                                ||(regfile_raddr_b_o == SCR_MSCRATCHC)
                                ||(regfile_raddr_b_o == SCR_MEPCC)) begin
                  scr_access_o = 1'b1;
                  regfile_wdata_sel_o = RF_WD_CSR;
                  regfile_we = regfile_waddr_o != '0;
                  //scr_op_o = scr_op_e'{regfile_waddr_o != '0, regfile_raddr_a_o != '0};
                  scr_op_o = scr_op_e'{regfile_waddr_o != '0, regfile_raddr_a_o != '0};
                  cheri_en_o = 1'b1;
                  cheri_op_b_mux_sel_o = CHERI_OP_B_IMM;
                  cheri_imm_b_mux_sel_o = CHERI_IMM_B_RS2;
                end else begin
                  illegal_insn = 1'b1;
                end
              end

              C_COPY_TYPE: begin
                regfile_we          = 1'b1;
                cheri_op_b_mux_sel_o = CHERI_OP_B_REG_CAP;
                cheri_b_en_o = 1'b1;
              end

              C_SEAL: begin
                regfile_we          = 1'b1;
                cheri_op_b_mux_sel_o = CHERI_OP_B_REG_CAP;
                cheri_b_en_o = 1'b1;
              end

              C_C_SEAL: begin
                regfile_we          = 1'b1;
                cheri_op_b_mux_sel_o = CHERI_OP_B_REG_CAP;
                cheri_b_en_o = 1'b1;
              end

              C_UNSEAL: begin
                regfile_we          = 1'b1;
                cheri_op_b_mux_sel_o = CHERI_OP_B_REG_CAP;
                cheri_b_en_o = 1'b1;
              end

              C_TO_PTR: begin
                regfile_we          = 1'b1;
                cheri_op_b_mux_sel_o = CHERI_OP_B_REG_DDC;
                cheri_b_en_o = 1'b1;
              end

              C_FROM_PTR: begin
                regfile_we          = 1'b1;
                cheri_op_a_mux_sel_o = CHERI_OP_A_REG_DDC;
                cheri_op_b_mux_sel_o = CHERI_OP_B_REG_NUM;
                cheri_b_en_o = 1'b1;
              end

              C_BUILD_CAP: begin
                regfile_we          = 1'b1;
                cheri_op_a_mux_sel_o = CHERI_OP_A_REG_DDC;
                cheri_op_b_mux_sel_o = CHERI_OP_B_REG_CAP;
                cheri_b_en_o = 1'b1;
              end

              // special instructions
              // TODO stores
              // for loads and stores, we don't need to get the ALU involved apart from calculating
              // the effective address after adding the immediate.
              STORE: begin
                cheri_op_b_mux_sel_o = CHERI_OP_B_REG_NUM;
                cheri_b_en_o = 1'b1;
                mem_ddc_relative_o = ~instr[10];

                // store size
                unique case (instr[8:7])
                  2'b00:  data_type_o = 2'b10;
                  2'b01:  data_type_o = 2'b01;
                  2'b10:  data_type_o = 2'b00;
                  2'b11:  data_type_o = 2'b11;
                endcase

                if (instr[11]) begin
                  // SC versions of the stores, not available because the A extension is not supported
                  illegal_insn = 1'b1;
                end

              end

              LOAD: begin
                regfile_we          = 1'b1;
                data_req_o = 1'b1;
                regfile_wdata_sel_o = RF_WD_LSU;
                regfile_we = 1'b1;
                data_type_o = 2'b00;

                data_sign_extension_o = ~instr[22];

                mem_ddc_relative_o = ~instr[23];

                // load size
                unique case (instr[21:20])
                  2'b00:  data_type_o = 2'b10;
                  2'b01:  data_type_o = 2'b01;
                  2'b10:  data_type_o = 2'b00;
                  2'b11:  data_type_o = 2'b11;
                endcase

                if (instr[24]) begin
                  // load reserved word, not available because the A extension is not supported
                  illegal_insn = 1'b1;
                end
              end

              CCALL: begin
                if (regfile_waddr_o != 5'h1F) begin
                  cheri_op_b_mux_sel_o = CHERI_OP_B_REG_CAP;
                  cheri_b_en_o = 1'b1;
                end else begin
                  // This is a CRETURN instruction
                  // TODO implement CRETURN
                end
              end

              SOURCE_AND_DEST: begin
                // no operand b
                regfile_we          = 1'b1;
                unique case (cheri_sad_opcode)
                  C_JALR: begin
                    jump_in_dec_o = 1'b1;
                    if (instr_new_i) begin
                      // Calculate jump target
                      // there's nothing to actually calculate but we need to perform exception checks
                      cheri_op_a_mux_sel_o  = CHERI_OP_A_REG_CAP;
                      cheri_op_b_mux_sel_o  = CHERI_OP_B_PCC;
                      regfile_we          = 1'b0;
                      jump_set_o          = 1'b1;
                    end else begin
                      // Calculate and store PC+4
                      cheri_base_opcode_o = C_INC_OFFSET_IMM;
                      cheri_op_a_mux_sel_o  = CHERI_OP_A_PCC;
                      cheri_op_b_mux_sel_o  = CHERI_OP_B_IMM;
                      cheri_imm_b_mux_sel_o = CHERI_IMM_B_INCR_PC;
                      regfile_we          = 1'b1;
                    end
                  end

                  default: begin

                  end
                endcase
              end

              default: begin // Illegal instruction
                illegal_insn = 1'b1;
              end
            endcase
          end

          C_INC_OFFSET_IMM: begin //
                regfile_we          = 1'b1;
                cheri_op_b_mux_sel_o = CHERI_OP_B_IMM;
                cheri_imm_b_mux_sel_o = CHERI_IMM_B_I;
          end

          C_SET_BOUNDS_IMM: begin //
                regfile_we          = 1'b1;
                cheri_op_b_mux_sel_o = CHERI_OP_B_IMM;
                cheri_imm_b_mux_sel_o = CHERI_IMM_B_I;
          end

          default: begin // Illegal instruction
            illegal_insn = 1'b1;
          end
        endcase
      end

      // DEFAULT CASE
      default: begin
        illegal_insn = 1'b1;
      end
    endcase

    // make sure illegal compressed instructions cause illegal instruction exceptions
    if (illegal_c_insn_i) begin
      illegal_insn = 1'b1;
    end

    // make sure illegal instructions detected in the decoder do not propagate from decoder
    // into register file, LSU, EX, WB, CSRs
    // NOTE: instructions can also be detected to be illegal inside the CSRs (upon accesses with
    // insufficient privileges), in ID stage (when accessing Reg 16 or higher in RV32E config),
    // these cases are not handled here
    if (illegal_insn) begin
      regfile_we      = 1'b0;
      data_req_o      = 1'b0;
      data_we_o       = 1'b0;
      mult_en_o       = 1'b0;
      div_en_o        = 1'b0;
      jump_in_dec_o   = 1'b0;
      branch_in_dec_o = 1'b0;
      csr_access_o    = 1'b0;
    end
  end

  // make sure instructions accessing non-available registers in RV32E cause illegal
  // instruction exceptions
  assign illegal_insn_o = illegal_insn | illegal_reg_rv32e;

  // do not propgate regfile write enable if non-available registers are accessed in RV32E
  assign regfile_we_o = regfile_we & ~illegal_reg_rv32e;

endmodule // controller
