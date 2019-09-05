// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Renzo Andri - andrire@student.ethz.ch                      //
//                                                                            //
// Additional contributions by:                                               //
//                 Igor Loi - igor.loi@unibo.it                               //
//                 Andreas Traber - atraber@student.ethz.ch                   //
//                 Sven Stucki - svstucki@student.ethz.ch                     //
//                 Davide Schiavone - pschiavo@iis.ee.ethz.ch                 //
//                                                                            //
// Design Name:    Instruction Decode Stage                                   //
// Project Name:   ibex                                                       //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Decode stage of the core. It decodes the instructions      //
//                 and hosts the register file.                               //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

`ifdef RISCV_FORMAL
  `define RVFI
`endif

`define CAP_SIZE 93
`define EXCEPTION_SIZE 22
`define INTEGER_SIZE 32
`define FLAG_SIZE 1


//parameter CAP_SIZE  = 93;
//parameter EXCEPTION_SIZE = 22;

/**
 * Instruction Decode Stage
 *
 * Decode stage of the core. It decodes the instructions and hosts the register
 * file.
 */
module ibex_id_stage #(
    parameter bit RV32E = 0,
    parameter bit RV32M = 1
) (
    input  logic                      clk_i,
    input  logic                      rst_ni,

    input  logic                      test_en_i,

    input  logic                      fetch_enable_i,
    output logic                      ctrl_busy_o,
    output logic                      core_ctrl_firstfetch_o,
    output logic                      illegal_insn_o,

    // Interface to IF stage
    input  logic                      instr_valid_i,
    input  logic                      instr_new_i,
    input  logic [31:0]               instr_rdata_i,         // from IF-ID pipeline registers
    input  logic [15:0]               instr_rdata_c_i,       // from IF-ID pipeline registers
    input  logic                      instr_is_compressed_i,
    output logic                      instr_req_o,
    output logic                      instr_valid_clear_o,   // kill instr in IF-ID reg
    output logic                      id_in_ready_o,         // ID stage is ready for next instr

    // Jumps and branches
    input  logic                      branch_decision_i,

    // IF and ID stage signals
    output logic                      pc_set_o,
    output ibex_defines::pc_sel_e     pc_mux_o,
    output ibex_defines::exc_pc_sel_e exc_pc_mux_o,

    input  logic                      illegal_c_insn_i,

    input  logic [`CAP_SIZE-1:0]               pc_id_i,

    // Stalls
    input  logic                      ex_valid_i,     // EX stage has valid output
    input  logic                      lsu_valid_i,    // LSU has valid output, or is done

    // ALU
    output ibex_defines::alu_op_e     alu_operator_ex_o,
    output logic [31:0]               alu_operand_a_ex_o,
    output logic [31:0]               alu_operand_b_ex_o,

    // MUL, DIV
    output logic                      mult_en_ex_o,
    output logic                      div_en_ex_o,
    output ibex_defines::md_op_e      multdiv_operator_ex_o,
    output logic  [1:0]               multdiv_signed_mode_ex_o,
    output logic [31:0]               multdiv_operand_a_ex_o,
    output logic [31:0]               multdiv_operand_b_ex_o,


    // CHERI
    // signals to the CHERI ALU
    output logic                                  cheri_en_o,              // enable the CHERI ALU
    output ibex_defines::cheri_base_opcode_e      cheri_base_opcode_o,
    output ibex_defines::cheri_threeop_funct7_e   cheri_threeop_opcode_o,
    output ibex_defines::cheri_s_a_d_funct5_e     cheri_sad_opcode_o,
    output ibex_defines::cheri_ccall_e            cheri_ccall_type_o,
    output logic [`CAP_SIZE-1:0]                  cheri_operand_a_o,
    output logic [`CAP_SIZE-1:0]                  cheri_operand_b_o,

    // CHERI exception signals
    input  logic [`EXCEPTION_SIZE-1:0]      cheri_exc_a_i,
    input  logic [`EXCEPTION_SIZE-1:0]      cheri_exc_b_i,
    input  logic [`EXCEPTION_SIZE-1:0]      cheri_exc_mem_i,
    input  logic [1:0][`EXCEPTION_SIZE-1:0] cheri_exc_instr_i,
    output ibex_defines::c_exc_cause_e      cheri_cause_o,
    output logic                            cheri_exc_o,
    input  logic                            cheri_exc_scr_i,

    // whether the output from the CHERI ALU is a capability
    // this tells us whether we need to pass the output through a nullWithAddr
    input  logic cheri_wrote_cap_i,

    // tell the LSU whether it should use the address as an offset from the base or from
    // the address of the capability that was passed in
    output logic use_cap_base_o,


    // CSR
    output logic                      csr_access_o,
    output ibex_defines::csr_op_e     csr_op_o,
    output logic                      csr_save_if_o,
    output logic                      csr_save_id_o,
    output logic                      csr_restore_mret_id_o,
    output logic                      csr_restore_dret_id_o,
    output logic                      csr_save_cause_o,
    output logic [31:0]               csr_mtval_o,
    input  logic                      illegal_csr_insn_i,

    // used for saving mccsr address on exception
    output [4:0]                              reg_addr_a_o,
    output [4:0]                              reg_addr_b_o,
    output ibex_defines::c_exc_reg_mux_sel_e  csr_reg_to_save_o,

    // SCR signals
    // DDC
    input  logic [`CAP_SIZE-1:0] scr_ddc_i,

    // SCR read signals
    output logic                   scr_access_o,
    output ibex_defines::scr_op_e  scr_op_o,
    input  logic [`CAP_SIZE-1:0]   scr_rdata_i,


    // Interface to load store unit
    output logic                   data_req_ex_o,
    output logic                   data_we_ex_o,
    output logic [1:0]             data_type_ex_o,
    output logic                   data_sign_ext_ex_o,
    output logic [1:0]             data_reg_offset_ex_o,
    output logic [`CAP_SIZE-1:0]   data_wdata_ex_o,

    input  logic                   lsu_addr_incr_req_i,
    input  logic [31:0]            lsu_addr_last_i,

    output logic [`CAP_SIZE-1:0]   mem_cap_o,
    output logic                   mem_cap_access_o,

    // Interrupt signals
    input  logic                      irq_i,
    input  logic [4:0]                irq_id_i,
    input  logic                      m_irq_enable_i,
    output logic                      irq_ack_o,
    output logic [4:0]                irq_id_o,
    output ibex_defines::exc_cause_e  exc_cause_o,

    input  logic                      lsu_load_err_i,
    input  logic                      lsu_store_err_i,

    // Debug Signal
    output ibex_defines::dbg_cause_e  debug_cause_o,
    output logic                      debug_csr_save_o,
    input  logic                      debug_req_i,
    input  logic                      debug_single_step_i,
    input  logic                      debug_ebreakm_i,

    // Write back signal
    input  logic [`CAP_SIZE-1:0]      regfile_wdata_lsu_i,
    input  logic [`CAP_SIZE-1:0]      regfile_wdata_ex_i,
    input  logic [31:0]               csr_rdata_i,

`ifdef RVFI
    output logic [4:0]                rfvi_reg_raddr_ra_o,
    output logic [31:0]               rfvi_reg_rdata_ra_o,
    output logic [4:0]                rfvi_reg_raddr_rb_o,
    output logic [31:0]               rfvi_reg_rdata_rb_o,
    output logic [4:0]                rfvi_reg_waddr_rd_o,
    output logic [31:0]               rfvi_reg_wdata_rd_o,
    output logic                      rfvi_reg_we_o,
`endif

    // Performance Counters
    output logic                      perf_jump_o,    // executing a jump instr
    output logic                      perf_branch_o,  // executing a branch instr
    output logic                      perf_tbranch_o, // executing a taken branch instr
    output logic                      instr_ret_o,
    output logic                      instr_ret_compressed_o
);

  import ibex_defines::*;

  // Decoder/Controller, ID stage internal signals
  logic        illegal_insn_dec;
  logic        ebrk_insn;
  logic        mret_insn_dec;
  logic        dret_insn_dec;
  logic        ecall_insn_dec;
  logic        wfi_insn_dec;

  logic        branch_in_dec;
  logic        branch_set_n, branch_set_q;
  logic        jump_in_dec;
  logic        jump_set;

  logic        instr_executing;
  logic        instr_multicycle_done_n, instr_multicycle_done_q;
  logic        stall_lsu;
  logic        stall_multdiv;
  logic        stall_branch;
  logic        stall_jump;

  logic        stall_cheri_exc;

  // Immediate decoding and sign extension
  logic [31:0] imm_i_type;
  logic [31:0] imm_s_type;
  logic [31:0] imm_b_type;
  logic [31:0] imm_u_type;
  logic [31:0] imm_j_type;
  logic [31:0] zimm_rs1_type;

  logic [31:0] imm_a;       // contains the immediate for operand b
  logic [31:0] imm_b;       // contains the immediate for operand b

  // Signals running between controller and exception controller
  logic        irq_req_ctrl;
  logic [4:0]  irq_id_ctrl;
  logic        exc_ack, exc_kill;// handshake

  // Register file interface
  logic [4:0]  regfile_raddr_a;
  logic [4:0]  regfile_raddr_b;
  logic [4:0]  regfile_waddr;

  // integer data signals
  logic [31:0] regfile_rdata_a;
  logic [31:0] regfile_rdata_b;
  logic [`INTEGER_SIZE-1:0] regfile_wdata;

  // capability data signals
  logic [`CAP_SIZE-1:0] regfile_rdata_a_cap;
  logic [`CAP_SIZE-1:0] regfile_rdata_b_cap;
  logic [`CAP_SIZE-1:0] regfile_wdata_cap;

  rf_wd_sel_e  regfile_wdata_sel;
  logic        regfile_we;
  logic        regfile_we_wb, regfile_we_dec;

  // ALU Control
  alu_op_e     alu_operator;
  op_a_sel_e   alu_op_a_mux_sel, alu_op_a_mux_sel_dec;
  op_b_sel_e   alu_op_b_mux_sel, alu_op_b_mux_sel_dec;

  imm_a_sel_e  imm_a_mux_sel;
  imm_b_sel_e  imm_b_mux_sel, imm_b_mux_sel_dec;

  // Multiplier Control
  logic        mult_en_id, mult_en_dec; // use integer multiplier
  logic        div_en_id, div_en_dec;   // use integer division or reminder
  logic        multdiv_en_dec;
  md_op_e      multdiv_operator;
  logic [1:0]  multdiv_signed_mode;

  // CHERI operand selection
  c_op_a_sel_e    cheri_op_a_mux_sel;
  c_op_b_sel_e    cheri_op_b_mux_sel;

  // CHERI B immediate & selection
  logic [`INTEGER_SIZE-1:0] cheri_imm_b;
  cheri_imm_b_sel_e         cheri_imm_b_mux_sel;

  // signals from decoder telling us whether each operand is being used by the instruction
  // currently used for masking exceptions
  logic cheri_a_en_dec;
  logic cheri_b_en_dec;

  // nullWithAddr function inputs and outputs
  logic [`INTEGER_SIZE-1:0] nullWithAddr_i;
  logic [    `CAP_SIZE-1:0] nullWithAddr_o;
  logic [`INTEGER_SIZE-1:0] nullWithAddr2_i;
  logic [    `CAP_SIZE-1:0] nullWithAddr2_o;

  // other function inputs and outputs
  logic [`INTEGER_SIZE-1:0] a_getAddr_o;
  logic [`INTEGER_SIZE-1:0] b_getAddr_o;
  logic [`INTEGER_SIZE-1:0] rd_wdata_getAddr_o;
  logic [`INTEGER_SIZE-1:0] pc_id_i_getBase_o;
  logic [`INTEGER_SIZE-1:0] pc_id_i_getOffset_o;
  logic [   `FLAG_SIZE-1:0] pcc_getFlags_o;


  // cheri exception signals
  logic      [`EXCEPTION_SIZE-1:0] cheri_exc_a;
  logic      [`EXCEPTION_SIZE-1:0] cheri_exc_a_q; // used for latching exception info during CJALR
  logic      [`EXCEPTION_SIZE-1:0] cheri_exc_b;
  logic      [`EXCEPTION_SIZE-1:0] cheri_exc_mem;
  logic [1:0][`EXCEPTION_SIZE-1:0] cheri_exc_instr;
  logic                            cheri_exc_scr;


  // whether the current instruction is ddc-relative or relative to the current capability
  logic mem_ddc_relative;

  // Data Memory Control
  logic        data_we_id;
  logic [1:0]  data_type_id;
  logic        data_sign_ext_id;
  logic [1:0]  data_reg_offset_id;
  logic        data_req_id, data_req_dec;

  // CSR control
  logic        csr_status;

  // ALU operands
  logic [31:0] alu_operand_a;
  logic [31:0] alu_operand_b;



  // latch exception_a value so we keep the exception information from the first stage of CJALR
  // instructions
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      cheri_exc_a_q = '0;
    end else begin
      cheri_exc_a_q = cheri_exc_a;
    end
  end

  // mask out exceptions that should not be thrown
  always_comb begin
    cheri_exc_a = '0;
    cheri_exc_b = '0;
    cheri_exc_mem = '0;

    // we only want to pass on the instruction exceptions when we're reading in a new instruction
    // instr_new_i goes high only after we've accepted a new instruction by asserting in_id_ready_o
    cheri_exc_instr[0] = instr_valid_i || !instr_new_i ? cheri_exc_instr_i[0] : '0;
    cheri_exc_instr[1] = instr_valid_i || !instr_new_i ? cheri_exc_instr_i[1] : '0;

    if (cheri_a_en_dec)
      // if we were doing a CJALR, we want the exception checks from the first cycle only, since that's
      // where it does all the checks we need
      cheri_exc_a = ((jump_in_dec && cheri_en_o && !instr_new_i) ? cheri_exc_a_q : cheri_exc_a_i);

    if (cheri_b_en_dec)
      cheri_exc_b = cheri_exc_b_i;

    if (data_req_dec && !lsu_addr_incr_req_i)
      cheri_exc_mem = cheri_exc_mem_i;

    if (instr_is_compressed_i)
      cheri_exc_instr[1] = '0;
  end

  // pass register addresses to SCRs to properly set MCCSR
  assign reg_addr_a_o = regfile_raddr_a;
  assign reg_addr_b_o = regfile_raddr_b;



  // debug print
  // TODO remove, this is not really useful

  always_ff @(posedge clk_i) begin
    if (cheri_exc_o) begin
      $display("pc: %h", pc_id_i_getOffset_o);
      $display("pc base: %h", pc_id_i_getBase_o);
      $display("pc top: %h", pc_id_i_getTop_o);
      $display("exc a: %h", cheri_exc_a_i & {`EXCEPTION_SIZE-2{cheri_a_en_dec}});
      $display("exc b: %h", cheri_exc_b_i & {`EXCEPTION_SIZE-2{cheri_b_en_dec}});
      $display("exc mem: %h", cheri_exc_mem_i & {`EXCEPTION_SIZE-2{1'b1}});
      $display("exc instr: %h", cheri_exc_instr_i & {`EXCEPTION_SIZE-2{1'b1}});
      $display("exc scr: %h", cheri_exc_scr_i & {`EXCEPTION_SIZE-2{1'b1}});
      $display("capability: %h", mem_cap_o);
      $display("base: %h", z_getBase_o);
      $display("addr: %h", z_getAddr_o);
      $display("length: %h", z_getLength_o);
      $display("top: %h", z_getTop_o);
      $display("perms: %h", z_getPerms_o);
    end
  end


logic [`INTEGER_SIZE-1:0] z_getLength_o;
logic [`INTEGER_SIZE-1:0] z_getBase_o;
logic [`INTEGER_SIZE-1:0] z_getAddr_o;
logic [`INTEGER_SIZE-1:0] z_getTop_o;
logic [`INTEGER_SIZE-1:0] pc_id_i_getTop_o;
logic [`INTEGER_SIZE-1:0] z_getPerms_o;

module_wrap64_getLength module_getLength_z (
  .wrap64_getLength_cap(mem_cap_o),
    .wrap64_getLength(z_getLength_o));

module_wrap64_getBase module_getBase_z (
    .wrap64_getBase_cap     (mem_cap_o),
    .wrap64_getBase         (z_getBase_o));

module_wrap64_getAddr module_getAddr_z (
    .wrap64_getAddr_cap (mem_cap_o),
    .wrap64_getAddr     (z_getAddr_o));

module_wrap64_getTop module_getTop_z (
    .wrap64_getTop_cap (mem_cap_o),
    .wrap64_getTop     (z_getTop_o));

module_wrap64_getTop module_wrap64_getTop_z (
  .wrap64_getTop_cap    (pc_id_i),
    .wrap64_getTop      (pc_id_i_getTop_o));

module_wrap64_getPerms module_wrap64_getPerms_z (
  .wrap64_getPerms_cap    (regfile_rdata_a_cap),
    .wrap64_getPerms      (z_getPerms_o));




  /////////////
  // LSU Mux //
  /////////////

  // Misaligned loads/stores result in two aligned loads/stores, compute second address
  assign alu_op_a_mux_sel = lsu_addr_incr_req_i ? OP_A_FWD        : alu_op_a_mux_sel_dec;
  assign alu_op_b_mux_sel = lsu_addr_incr_req_i ? OP_B_IMM        : alu_op_b_mux_sel_dec;
  assign imm_b_mux_sel    = lsu_addr_incr_req_i ? IMM_B_INCR_ADDR : imm_b_mux_sel_dec;

  // choose whether we want to use DDC or the register contents as the capability providing
  // authority for the memory access
  assign mem_cap_o = mem_ddc_relative ? scr_ddc_i : regfile_rdata_a_cap;



  ///////////////////
  // Operand A MUX //
  ///////////////////

  // Immediate MUX for Operand A
  assign imm_a = (imm_a_mux_sel == IMM_A_Z) ? zimm_rs1_type : '0;

  // ALU MUX for Operand A
  always_comb begin : alu_operand_a_mux
    unique case (alu_op_a_mux_sel)
      OP_A_REG_A:  alu_operand_a = regfile_rdata_a;
      OP_A_FWD:    alu_operand_a = lsu_addr_last_i;
      OP_A_CURRPC: alu_operand_a = pc_id_i_getOffset_o;
      OP_A_IMM:    alu_operand_a = imm_a;
      default:     alu_operand_a = 'X;
    endcase
  end

  // CHERI ALU MUX for Operand A
  always_comb begin
    unique case (cheri_op_a_mux_sel)
      CHERI_OP_A_REG_CAP: cheri_operand_a_o = regfile_rdata_a_cap;
      CHERI_OP_A_REG_NUM: cheri_operand_a_o = regfile_rdata_a;
      CHERI_OP_A_REG_DDC: cheri_operand_a_o = regfile_raddr_a == '0 ? scr_ddc_i : regfile_rdata_a_cap;
      // TODO if implementing misaligned double-word capability accesses, will need a OP_A_FWD similar to above
      // at the moment we always throw an exception on unaligned double-word access so we don't care about this
      // will need to update if the spec changes to allow unaligned double-word accesses on RV32-CHERI
      CHERI_OP_A_PCC: cheri_operand_a_o = pc_id_i;
      default:          cheri_operand_a_o = 'X;
    endcase
  end



  ///////////////////
  // Operand B MUX //
  ///////////////////

  // Immediate MUX for Operand B
  always_comb begin : immediate_b_mux
    unique case (imm_b_mux_sel)
      IMM_B_I:         imm_b = imm_i_type;
      IMM_B_S:         imm_b = imm_s_type;
      IMM_B_B:         imm_b = imm_b_type;
      IMM_B_U:         imm_b = imm_u_type;
      IMM_B_J:         imm_b = imm_j_type;
      IMM_B_INCR_PC:   imm_b = instr_is_compressed_i ? 32'h2 : 32'h4;
      IMM_B_INCR_ADDR: imm_b = 32'h8;
      IMM_B_ZERO:      imm_b = 32'h0;
      default:         imm_b = 'X;
    endcase
  end

  // ALU MUX for Operand B
  assign alu_operand_b = (alu_op_b_mux_sel == OP_B_IMM) ? imm_b : regfile_rdata_b;

  // CHERI Immediate mux for operand B
  always_comb begin
    unique case (cheri_imm_b_mux_sel)
      CHERI_IMM_B_INCR_PC: cheri_imm_b = 'h4;
      CHERI_IMM_B_I:       cheri_imm_b = imm_i_type;
      CHERI_IMM_B_S:       cheri_imm_b = imm_s_type;
      CHERI_IMM_B_U:       cheri_imm_b = imm_u_type;
      CHERI_IMM_B_RS2:     cheri_imm_b = regfile_raddr_b;
      default: cheri_imm_b = 'X;
    endcase
  end

  // CHERI ALU MUX for Operand B
  always_comb begin
    unique case (cheri_op_b_mux_sel)
      CHERI_OP_B_IMM:      cheri_operand_b_o = cheri_imm_b;
      CHERI_OP_B_REG_CAP:  cheri_operand_b_o = regfile_rdata_b_cap;
      CHERI_OP_B_REG_NUM:  cheri_operand_b_o = regfile_rdata_b;
      CHERI_OP_B_REG_DDC:  cheri_operand_b_o = regfile_raddr_b == '0 ? scr_ddc_i : regfile_rdata_b_cap;
      CHERI_OP_B_PCC:      cheri_operand_b_o = pc_id_i;
      default:             cheri_operand_b_o = 'X;
    endcase
  end

  ///////////////////////
  // Register File MUX //
  ///////////////////////

  // Register file write enable mux - do not propagate illegal CSR ops, do not write when idle,
  // for loads/stores and multdiv operations write when the data is ready only
  // TODO rewrite this expression more cleanly
  assign regfile_we = (  illegal_csr_insn_i
                      || !instr_executing
                      || lsu_load_err_i
                      || cheri_exc_o       ) ? 1'b0
                                             : (  data_req_dec
                                               || multdiv_en_dec) ? regfile_we_wb
                                                                  : regfile_we_dec;

  // Register file write data mux
  // in each case:
  //    set the input to the nullWithAddr function
  //    choose whether we want the write value to be passed through that function or not
  //    set the write value
  always_comb begin : regfile_wdata_mux
    unique case (regfile_wdata_sel)
      // data is coming from the EX block, but not from the CHERI ALU
      // this means it is coming from either the MULT/DIV or ALU blocks
      RF_WD_EX: begin
        nullWithAddr_i = regfile_wdata_ex_i;
        regfile_wdata = regfile_wdata_ex_i;
        regfile_wdata_cap = nullWithAddr_o;
      end

      // data is coming from the LSU
      RF_WD_LSU: begin
        nullWithAddr_i  = regfile_wdata_lsu_i;
        regfile_wdata = regfile_wdata_lsu_i;
        regfile_wdata_cap = mem_cap_access_o ? regfile_wdata_lsu_i : nullWithAddr_o;
      end

      // data is coming from the CSRs or SCRs
      RF_WD_CSR: begin
        nullWithAddr_i  = csr_rdata_i;
        regfile_wdata = scr_access_o ? scr_rdata_i : csr_rdata_i;
        regfile_wdata_cap = scr_access_o ? scr_rdata_i : nullWithAddr_o;
      end

      // data is coming from the CHERI ALU
      RF_WD_CHERI: begin
        nullWithAddr_i = regfile_wdata_ex_i;
        regfile_wdata = regfile_wdata_ex_i;
        regfile_wdata_cap = cheri_wrote_cap_i ? regfile_wdata_ex_i : nullWithAddr_o;
      end

      default: begin
        regfile_wdata = 'X;
        regfile_wdata_cap = 'X;
        nullWithAddr_i = 'X;
      end
    endcase;
  end

  ///////////////////
  // Register File //
  ///////////////////

  ibex_register_file #( .RV32E ( RV32E ) ) registers_i (
      .clk_i        ( clk_i           ),
      .rst_ni       ( rst_ni          ),

      .test_en_i    ( test_en_i       ),

      // Read port a
      .raddr_a_i    ( regfile_raddr_a ),
      .rdata_a_o    ( regfile_rdata_a_cap ),
      // Read port b
      .raddr_b_i    ( regfile_raddr_b ),
      .rdata_b_o    ( regfile_rdata_b_cap ),
      // write port
      .waddr_a_i    ( regfile_waddr   ),
      .wdata_a_i    ( regfile_wdata_cap   ),
      .we_a_i       ( regfile_we      )
  );

  // run getAddr on the register contents for when we're doing arithmetic
  always_comb begin
    regfile_rdata_a = a_getAddr_o;
    regfile_rdata_b = b_getAddr_o;
  end

`ifdef RVFI
  assign rfvi_reg_raddr_ra_o = regfile_raddr_a;
  assign rfvi_reg_rdata_ra_o = regfile_rdata_a;
  assign rfvi_reg_raddr_rb_o = regfile_raddr_b;
  assign rfvi_reg_rdata_rb_o = regfile_rdata_b;
  assign rfvi_reg_waddr_rd_o = regfile_waddr;
  // RVFI expects the integer contents of the register - these are stored in the address
  assign rfvi_reg_wdata_rd_o = rd_wdata_getAddr_o;
  assign rfvi_reg_we_o       = regfile_we;
`endif

  /////////////
  // Decoder //
  /////////////

  ibex_decoder #(
      .RV32E ( RV32E ),
      .RV32M ( RV32M )
  ) decoder_i (
      // controller
      .illegal_insn_o                  ( illegal_insn_dec     ),
      .ebrk_insn_o                     ( ebrk_insn            ),
      .mret_insn_o                     ( mret_insn_dec        ),
      .dret_insn_o                     ( dret_insn_dec        ),
      .ecall_insn_o                    ( ecall_insn_dec       ),
      .wfi_insn_o                      ( wfi_insn_dec         ),
      .jump_set_o                      ( jump_set             ),

      // from IF-ID pipeline register
      .instr_new_i                     ( instr_new_i          ),
      .instr_rdata_i                   ( instr_rdata_i        ),
      .illegal_c_insn_i                ( illegal_c_insn_i     ),

      // immediates
      .imm_a_mux_sel_o                 ( imm_a_mux_sel        ),
      .imm_b_mux_sel_o                 ( imm_b_mux_sel_dec    ),

      .imm_i_type_o                    ( imm_i_type           ),
      .imm_s_type_o                    ( imm_s_type           ),
      .imm_b_type_o                    ( imm_b_type           ),
      .imm_u_type_o                    ( imm_u_type           ),
      .imm_j_type_o                    ( imm_j_type           ),
      .zimm_rs1_type_o                 ( zimm_rs1_type        ),

      // register file
      .regfile_wdata_sel_o             ( regfile_wdata_sel    ),
      .regfile_we_o                    ( regfile_we_dec       ),

      .regfile_raddr_a_o               ( regfile_raddr_a      ),
      .regfile_raddr_b_o               ( regfile_raddr_b      ),
      .regfile_waddr_o                 ( regfile_waddr        ),

      // ALU
      .alu_operator_o                  ( alu_operator         ),
      .alu_op_a_mux_sel_o              ( alu_op_a_mux_sel_dec ),
      .alu_op_b_mux_sel_o              ( alu_op_b_mux_sel_dec ),

      // MULT & DIV
      .mult_en_o                       ( mult_en_dec          ),
      .div_en_o                        ( div_en_dec           ),
      .multdiv_operator_o              ( multdiv_operator     ),
      .multdiv_signed_mode_o           ( multdiv_signed_mode  ),

      // CHERI
      // CHERI ALU enable signal
      .cheri_en_o(cheri_en_o),

      // CHERI ALU operation selection signals
      .cheri_base_opcode_o             ( cheri_base_opcode_o    ),
      .cheri_threeop_opcode_o          ( cheri_threeop_opcode_o ),
      .cheri_sad_opcode_o              ( cheri_sad_opcode_o     ),
      .cheri_ccall_type_o              ( cheri_ccall_type_o     ),

      // CHERI operand selection
      .cheri_op_a_mux_sel_o            ( cheri_op_a_mux_sel     ),
      .cheri_op_b_mux_sel_o            ( cheri_op_b_mux_sel     ),
      .cheri_imm_b_mux_sel_o           ( cheri_imm_b_mux_sel    ),

      // CHERI operands enable, used for masking out exceptions
      .cheri_a_en_o                    ( cheri_a_en_dec         ),
      .cheri_b_en_o                    ( cheri_b_en_dec         ),

      // tell decoder we're in capability encoding mode
      .cap_mode_i                      ( pcc_getFlags_o         ),

      // capability base selection; see comment above declaration of signal
      .use_cap_base_o                  ( use_cap_base_o         ),

      // CSRs
      .csr_access_o                    ( csr_access_o         ),
      .csr_op_o                        ( csr_op_o             ),
      .csr_status_o                    ( csr_status           ),

      // SCRs
      .scr_access_o(scr_access_o),
      .scr_op_o(scr_op_o),

      // LSU
      .data_req_o                      ( data_req_dec         ),
      .data_we_o                       ( data_we_id           ),
      .data_type_o                     ( data_type_id         ),
      .data_sign_extension_o           ( data_sign_ext_id     ),
      .data_reg_offset_o               ( data_reg_offset_id   ),

      // whether this memory access is trying to read/write a capability or not
      .mem_cap_access_o                ( mem_cap_access_o     ),

      // whether the memory access is relative to DDC
      .mem_ddc_relative_o              ( mem_ddc_relative     ),

      // jump/branches
      .jump_in_dec_o                   ( jump_in_dec          ),
      .branch_in_dec_o                 ( branch_in_dec        )
  );

  ////////////////
  // Controller //
  ////////////////

  assign illegal_insn_o = illegal_insn_dec | illegal_csr_insn_i;

  ibex_controller controller_i (
      .clk_i                          ( clk_i                  ),
      .rst_ni                         ( rst_ni                 ),

      .fetch_enable_i                 ( fetch_enable_i         ),
      .ctrl_busy_o                    ( ctrl_busy_o            ),
      .first_fetch_o                  ( core_ctrl_firstfetch_o ),

      // decoder related signals
      .illegal_insn_i                 ( illegal_insn_o         ),
      .ecall_insn_i                   ( ecall_insn_dec         ),
      .mret_insn_i                    ( mret_insn_dec          ),
      .dret_insn_i                    ( dret_insn_dec          ),
      .wfi_insn_i                     ( wfi_insn_dec           ),
      .ebrk_insn_i                    ( ebrk_insn              ),
      .csr_status_i                   ( csr_status             ),

      // from IF-ID pipeline
      .instr_valid_i                  ( instr_valid_i          ),
      .instr_i                        ( instr_rdata_i          ),
      .instr_compressed_i             ( instr_rdata_c_i        ),
      .instr_is_compressed_i          ( instr_is_compressed_i  ),

      // to IF-ID pipeline
      .instr_valid_clear_o            ( instr_valid_clear_o    ),
      .id_in_ready_o                  ( id_in_ready_o          ),

      // from prefetcher
      .instr_req_o                    ( instr_req_o            ),

      // to prefetcher
      .pc_set_o                       ( pc_set_o               ),
      .pc_mux_o                       ( pc_mux_o               ),
      .exc_pc_mux_o                   ( exc_pc_mux_o           ),
      .exc_cause_o                    ( exc_cause_o            ),

      // LSU
      .lsu_addr_last_i                ( lsu_addr_last_i        ),
      .load_err_i                     ( lsu_load_err_i         ),
      .store_err_i                    ( lsu_store_err_i        ),

      // CHERI exception signals
      .cheri_exc_o                    ( cheri_exc_o            ),
      .cheri_exc_a_i                  ( cheri_exc_a            ),
      .cheri_exc_b_i                  ( cheri_exc_b            ),
      .cheri_exc_mem_i                ( cheri_exc_mem          ),
      .cheri_exc_instr_i              ( cheri_exc_instr        ),
      .cheri_exc_scr_i                ( cheri_exc_scr_i        ),
      .cheri_cause_o                  ( cheri_cause_o          ),
      .csr_reg_to_save_o              ( csr_reg_to_save_o      ),

      // jump/branch control
      .branch_set_i                   ( branch_set_q           ),
      .jump_set_i                     ( jump_set               ),

      // Interrupt Controller Signals
      .irq_i                          ( irq_i                  ),
      .irq_req_ctrl_i                 ( irq_req_ctrl           ),
      .irq_id_ctrl_i                  ( irq_id_ctrl            ),
      .m_IE_i                         ( m_irq_enable_i         ),

      .irq_ack_o                      ( irq_ack_o              ),
      .irq_id_o                       ( irq_id_o               ),

      .exc_ack_o                      ( exc_ack                ),
      .exc_kill_o                     ( exc_kill               ),

      // CSR Controller Signals
      .csr_save_if_o                  ( csr_save_if_o          ),
      .csr_save_id_o                  ( csr_save_id_o          ),
      .csr_restore_mret_id_o          ( csr_restore_mret_id_o  ),
      .csr_restore_dret_id_o          ( csr_restore_dret_id_o  ),
      .csr_save_cause_o               ( csr_save_cause_o       ),
      .csr_mtval_o                    ( csr_mtval_o            ),

      // Debug Signal
      .debug_cause_o                  ( debug_cause_o          ),
      .debug_csr_save_o               ( debug_csr_save_o       ),
      .debug_req_i                    ( debug_req_i            ),
      .debug_single_step_i            ( debug_single_step_i    ),
      .debug_ebreakm_i                ( debug_ebreakm_i        ),

      // stall signals
      .stall_lsu_i                    ( stall_lsu              ),
      .stall_multdiv_i                ( stall_multdiv          ),
      .stall_jump_i                   ( stall_jump             ),
      .stall_branch_i                 ( stall_branch           ),
      .stall_cheri_exc_i(stall_cheri_exc),

      // Performance Counters
      .perf_jump_o                    ( perf_jump_o            ),
      .perf_tbranch_o                 ( perf_tbranch_o         )
  );

  //////////////////////////
  // Interrupt controller //
  //////////////////////////

  ibex_int_controller int_controller_i (
      .clk_i                ( clk_i              ),
      .rst_ni               ( rst_ni             ),

      // to controller
      .irq_req_ctrl_o       ( irq_req_ctrl       ),
      .irq_id_ctrl_o        ( irq_id_ctrl        ),

      .ctrl_ack_i           ( exc_ack            ),
      .ctrl_kill_i          ( exc_kill           ),

      // Interrupt signals
      .irq_i                ( irq_i              ),
      .irq_id_i             ( irq_id_i           ),

      .m_IE_i               ( m_irq_enable_i     )
  );

  //////////////
  // ID-EX/WB //
  //////////////

  // Forward decoder output to EX, WB and controller only if current instr is still
  // being executed. This is the case if the current instr is either:
  // - a new instr (not yet done)
  // - a multicycle instr that is not yet done
  assign instr_executing = (instr_new_i | ~instr_multicycle_done_q);
  assign data_req_id     = instr_executing ? data_req_dec  : 1'b0;
  assign mult_en_id      = instr_executing ? mult_en_dec   : 1'b0;
  assign div_en_id       = instr_executing ? div_en_dec    : 1'b0;

  ///////////
  // ID-EX //
  ///////////
  assign data_req_ex_o               = data_req_id;
  assign data_we_ex_o                = data_we_id;
  assign data_type_ex_o              = data_type_id;
  assign data_sign_ext_ex_o          = data_sign_ext_id;

  // pass the data to write directly from the register file or put it through a getAddr first
  assign data_wdata_ex_o             = mem_cap_access_o ? regfile_rdata_b_cap : regfile_rdata_b;
  assign data_reg_offset_ex_o        = data_reg_offset_id;

  assign alu_operator_ex_o           = alu_operator;
  assign alu_operand_a_ex_o          = alu_operand_a;
  assign alu_operand_b_ex_o          = alu_operand_b;

  assign mult_en_ex_o                = mult_en_id;
  assign div_en_ex_o                 = div_en_id;

  assign multdiv_operator_ex_o       = multdiv_operator;
  assign multdiv_signed_mode_ex_o    = multdiv_signed_mode;
  assign multdiv_operand_a_ex_o      = regfile_rdata_a;
  assign multdiv_operand_b_ex_o      = regfile_rdata_b;

  typedef enum logic { IDLE, WAIT_MULTICYCLE } id_fsm_e;
  id_fsm_e id_wb_fsm_cs, id_wb_fsm_ns;

  ////////////////////////////////
  // ID-EX/WB Pipeline Register //
  ////////////////////////////////

  always_ff @(posedge clk_i or negedge rst_ni) begin : id_wb_pipeline_reg
    if (!rst_ni) begin
      id_wb_fsm_cs            <= IDLE;
      branch_set_q            <= 1'b0;
      instr_multicycle_done_q <= 1'b0;
    end else begin
      id_wb_fsm_cs            <= id_wb_fsm_ns;
      branch_set_q            <= branch_set_n;
      instr_multicycle_done_q <= instr_multicycle_done_n;
    end
  end

  //////////////////
  // ID-EX/WB FSM //
  //////////////////

  assign multdiv_en_dec  = mult_en_dec | div_en_dec;

  always_comb begin : id_wb_fsm
    id_wb_fsm_ns            = id_wb_fsm_cs;
    instr_multicycle_done_n = instr_multicycle_done_q;
    regfile_we_wb           = 1'b0;
    stall_lsu               = 1'b0;
    stall_multdiv           = 1'b0;
    stall_jump              = 1'b0;
    stall_branch            = 1'b0;
    stall_cheri_exc         = 1'b0;
    branch_set_n            = 1'b0;
    perf_branch_o           = 1'b0;
    instr_ret_o             = 1'b0;

    unique case (id_wb_fsm_cs)

      IDLE: begin
        // only detect multicycle when instruction is new, do not re-detect after
        // execution (when waiting for next instruction from IF stage)
        if (instr_new_i) begin
          unique case (1'b1)
            data_req_dec: begin
              // LSU operation
              id_wb_fsm_ns            = WAIT_MULTICYCLE;
              stall_lsu               = 1'b1;
              instr_multicycle_done_n = 1'b0;
            end
            multdiv_en_dec: begin
              // MUL or DIV operation
              id_wb_fsm_ns            = WAIT_MULTICYCLE;
              stall_multdiv           = 1'b1;
              instr_multicycle_done_n = 1'b0;
            end
            branch_in_dec: begin
              // cond branch operation
              id_wb_fsm_ns            =  branch_decision_i ? WAIT_MULTICYCLE : IDLE;
              stall_branch            =  branch_decision_i;
              instr_multicycle_done_n = ~branch_decision_i;
              branch_set_n            =  branch_decision_i;
              perf_branch_o           =  1'b1;
              instr_ret_o             = ~branch_decision_i;
            end
            jump_in_dec: begin
              // uncond branch operation
              id_wb_fsm_ns            = WAIT_MULTICYCLE;
              stall_jump              = 1'b1;
              instr_multicycle_done_n = 1'b0;
            end
            // TODO there might be a better place for this
            cheri_en_o && (cheri_exc_o): begin
              // there's an exception in the cheri ALU
              // we want to wait for the pipeline to flush and do whatever else needs to be done
              // TODO list "whatever else needs to be done"
              id_wb_fsm_ns = WAIT_MULTICYCLE;
              stall_cheri_exc = 1'b1;
              instr_multicycle_done_n = 1'b0;
            end
            default: begin
              instr_ret_o             = 1'b1;
            end
          endcase
        end
      end

      WAIT_MULTICYCLE: begin
        if ((data_req_dec & lsu_valid_i) | (~data_req_dec & ex_valid_i)) begin
          id_wb_fsm_ns            = IDLE;
          instr_multicycle_done_n = 1'b1;
          regfile_we_wb           = regfile_we_dec;
          instr_ret_o             = 1'b1;
        end else begin
          stall_lsu               = data_req_dec;
          stall_multdiv           = multdiv_en_dec;
          stall_branch            = branch_in_dec;
          stall_jump              = jump_in_dec;
          stall_cheri_exc         = cheri_en_o && cheri_exc_o;
        end
      end

      default: begin
        id_wb_fsm_ns = id_fsm_e'(1'bX);
      end
    endcase
  end

  assign instr_ret_compressed_o = instr_ret_o & instr_is_compressed_i;

  // function module instantiation
  module_wrap64_nullWithAddr nullWithAddr (
        .wrap64_nullWithAddr_addr   (nullWithAddr_i),
        .wrap64_nullWithAddr        (nullWithAddr_o));

  module_wrap64_nullWithAddr nullWithAddr2 (
        .wrap64_nullWithAddr_addr   (nullWithAddr2_i),
        .wrap64_nullWithAddr        (nullWithAddr2_o));

  module_wrap64_getAddr module_getAddr_a (
        .wrap64_getAddr_cap         (regfile_rdata_a_cap),
        .wrap64_getAddr             (a_getAddr_o));

  module_wrap64_getAddr module_getAddr_b (
        .wrap64_getAddr_cap         (regfile_rdata_b_cap),
        .wrap64_getAddr             (b_getAddr_o));

  module_wrap64_getAddr module_getAddr_rd (
        .wrap64_getAddr_cap         (regfile_wdata_cap),
        .wrap64_getAddr             (rd_wdata_getAddr_o));

  module_wrap64_getBase module_getBase_pc_id_i (
        .wrap64_getBase_cap       (pc_id_i),
        .wrap64_getBase           (pc_id_i_getBase_o));

  module_wrap64_getOffset module_getOffset_pc_id_i (
        .wrap64_getOffset_cap       (pc_id_i),
        .wrap64_getOffset           (pc_id_i_getOffset_o));

  module_wrap64_getFlags module_getFlags_pcc (
        .wrap64_getFlags_cap        (pc_id_i),
        .wrap64_getFlags            (pcc_getFlags_o));



  ////////////////
  // Assertions //
  ////////////////

`ifndef VERILATOR
  // make sure that branch decision is valid when jumping
  assert property (
    @(posedge clk_i) (branch_decision_i !== 1'bx || branch_in_dec == 1'b0) ) else
      $display("Branch decision is X");

`ifdef CHECK_MISALIGNED
  assert property (
    @(posedge clk_i) (~lsu_addr_incr_req_i) ) else
      $display("Misaligned memory access at %x",pc_id_i);
`endif

  // the instruction delivered to the ID stage should always be valid
  assert property (
    @(posedge clk_i) (instr_valid_i & (~illegal_c_insn_i)) |-> (!$isunknown(instr_rdata_i)) ) else
      $display("Instruction is valid, but has at least one X");

  // make sure multicycles enable signals are unique
  assert property (
    @(posedge clk_i) ~(data_req_dec & multdiv_en_dec)) else
      $display("Multicycles enable signals are not unique");

`endif

endmodule
