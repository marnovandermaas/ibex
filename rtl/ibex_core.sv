// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Matthias Baer - baermatt@student.ethz.ch                   //
//                                                                            //
// Additional contributions by:                                               //
//                 Igor Loi - igor.loi@unibo.it                               //
//                 Andreas Traber - atraber@student.ethz.ch                   //
//                 Sven Stucki - svstucki@student.ethz.ch                     //
//                 Markus Wegmann - markus.wegmann@technokrat.ch              //
//                 Davide Schiavone - pschiavo@iis.ee.ethz.ch                 //
//                                                                            //
// Design Name:    Top level module                                           //
// Project Name:   ibex                                                       //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Top level module of the RISC-V core.                       //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

`ifdef RISCV_FORMAL
  `define RVFI
`endif

// TODO put this in the makefile
`define CAP_SIZE 93
`define EXCEPTION_SIZE 22
`define INTEGER_SIZE 32

/*
parameter CAP_SIZE  = `CAP_SIZE;
parameter OTYPE_SIZE = 4;
parameter REGS_PER_QUARTER = 4;
parameter INTEGER_SIZE = 32;
parameter FLAG_SIZE = 1;
parameter PERMS_SIZE = 31;
parameter LENGTH_SIZE = 33;
parameter OFFSET_SIZE = 32;
parameter BASE_SIZE = 32;
parameter EXCEPTION_SIZE = 22;

*/



/**
 * Top level module of the ibex RISC-V core
 */
module ibex_core #(
    parameter int unsigned MHPMCounterNum   = 0,
    parameter int unsigned MHPMCounterWidth = 40,
    parameter bit RV32E                     = 0,
    parameter bit RV32M                     = 1,
    parameter int unsigned DmHaltAddr       = 32'h1A110800,
    parameter int unsigned DmExceptionAddr  = 32'h1A110808
) (
    // Clock and Reset
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        test_en_i,     // enable all clock gates for testing

    // Core ID, Cluster ID and boot address are considered more or less static
    input  logic [ 3:0] core_id_i,
    input  logic [ 5:0] cluster_id_i,
    input  logic [31:0] boot_addr_i,

    // Instruction memory interface
    output logic        instr_req_o,
    input  logic        instr_gnt_i,
    input  logic        instr_rvalid_i,
    output logic [31:0] instr_addr_o,
    input  logic [31:0] instr_rdata_i,

    // Data memory interface
    output logic        data_req_o,
    input  logic        data_gnt_i,
    input  logic        data_rvalid_i,
    output logic        data_we_o,
    output logic [7:0]  data_be_o,
    output logic [31:0] data_addr_o,
    output logic [63:0] data_wdata_o,
    output logic        data_wtag_o,
    input  logic [63:0] data_rdata_i,
    input  logic        data_rtag_i,
    input  logic        data_err_i,

    // Interrupt inputs
    input  logic        irq_i,                 // level sensitive IR lines
    input  logic [4:0]  irq_id_i,
    output logic        irq_ack_o,             // irq ack
    output logic [4:0]  irq_id_o,

    // Debug Interface
    input  logic        debug_req_i,

    // RISC-V Formal Interface
    // Does not comply with the coding standards of _i/_o suffixes, but follows
    // the convention of RISC-V Formal Interface Specification.
`ifdef RVFI
    output logic        rvfi_valid,
    output logic [63:0] rvfi_order,
    output logic [31:0] rvfi_insn,
    output logic [31:0] rvfi_insn_uncompressed,
    output logic        rvfi_trap,
    output logic        rvfi_halt,
    output logic        rvfi_intr,
    output logic [ 1:0] rvfi_mode,
    output logic [ 4:0] rvfi_rs1_addr,
    output logic [ 4:0] rvfi_rs2_addr,
    output logic [31:0] rvfi_rs1_rdata,
    output logic [31:0] rvfi_rs2_rdata,
    output logic [ 4:0] rvfi_rd_addr,
    output logic [31:0] rvfi_rd_wdata,
    output logic [31:0] rvfi_pc_rdata,
    output logic [31:0] rvfi_pc_wdata,
    output logic [31:0] rvfi_mem_addr,
    output logic [ 7:0] rvfi_mem_rmask,
    output logic [ 7:0] rvfi_mem_wmask,
    output logic [63:0] rvfi_mem_rdata,
    output logic [63:0] rvfi_mem_wdata,
`endif

`ifdef DII
    output logic        perf_imiss_o,
`endif

    // CPU Control Signals
    input  logic        fetch_enable_i

);

  import ibex_defines::*;

  // IF/ID signals
  logic        instr_valid_id;
  logic        instr_new_id;
  logic [31:0] instr_rdata_id;         // Instruction sampled inside IF stage
  logic [15:0] instr_rdata_c_id;       // Compressed instruction sampled inside IF stage
  logic        instr_is_compressed_id;
  logic        illegal_c_insn_id;      // Illegal compressed instruction sent to ID stage
  //logic [31:0] pc_if;                  // Program counter in IF stage
  logic [`CAP_SIZE-1:0] pc_if;                  // Program counter in IF stage
  //logic [31:0] pc_id;                  // Program counter in ID stage
  logic [`CAP_SIZE-1:0] pc_id;                  // Program counter in ID stage

  logic        instr_valid_clear;
  logic        pc_set;
  pc_sel_e     pc_mux_id;              // Mux selector for next PC
  exc_pc_sel_e exc_pc_mux_id;          // Mux selector for exception PC
  exc_cause_e  exc_cause;              // Exception cause

  logic        lsu_load_err;
  logic        lsu_store_err;
  logic cheri_exc;

  // LSU signals
  logic        lsu_addr_incr_req;
  logic [31:0] lsu_addr_last;
  logic [`CAP_SIZE-1:0] lsu_cap_last;
  logic [`CAP_SIZE-1:0] lsu_cap;

  // Jump and branch target and decision (EX->IF)
  //logic [31:0] jump_target_ex;
  logic [`CAP_SIZE-1:0] jump_target_ex;
  logic        branch_decision;

  logic        ctrl_busy;
  logic        if_busy;
  logic        lsu_busy;
  //core busy signals
  logic        core_busy;
  logic        core_ctrl_firstfetch, core_busy_int, core_busy_q;

  // ALU Control
  alu_op_e     alu_operator_ex;
  logic [31:0] alu_operand_a_ex;
  logic [31:0] alu_operand_b_ex;

  logic [31:0] alu_adder_result_ex;    // Used to forward computed address to LSU
  logic [`CAP_SIZE-1:0] regfile_wdata_ex;


    // CHERI
    logic                     cheri_en;
    cheri_base_opcode_e       cheri_base_opcode;
    cheri_threeop_funct7_e    cheri_threeop_opcode;
    cheri_s_a_d_funct5_e      cheri_sad_opcode;
    cheri_ccall_e      cheri_ccall_type;
    logic [`CAP_SIZE-1:0]      cheri_operand_a;
    logic [`CAP_SIZE-1:0]      cheri_operand_b;

    logic [`EXCEPTION_SIZE-1:0] cheri_exc_a;
    logic [`EXCEPTION_SIZE-1:0] cheri_exc_b;
    logic                  cheri_wrote_cap;
    logic cap_jump;


  // Multiplier Control
  logic        mult_en_ex;
  logic        div_en_ex;
  md_op_e      multdiv_operator_ex;
  logic [1:0]  multdiv_signed_mode_ex;
  logic [31:0] multdiv_operand_a_ex;
  logic [31:0] multdiv_operand_b_ex;

  // CSR control
  // TODO add SCRs
  logic        csr_access;
  csr_op_e     csr_op;
  csr_num_e    csr_addr;
  logic [31:0] csr_rdata;
  logic [31:0] csr_wdata;
  logic        illegal_csr_insn_id;    // CSR access to non-existent register,
                                       // with wrong priviledge level,
                                       // or missing write permissions

  // Data Memory Control
  logic        data_we_ex;
  logic [1:0]  data_type_ex;
  logic        data_sign_ext_ex;
  logic [2:0]  data_reg_offset_ex;
  logic        data_req_ex;
  logic [`CAP_SIZE-1:0] data_wdata_ex;
  logic [`CAP_SIZE-1:0] regfile_wdata_lsu;

  // stall control
  logic        id_in_ready;
  logic        ex_valid;

  logic        lsu_data_valid;

  // Signals between instruction core interface and pipe (if and id stages)
  logic        instr_req_int;          // Id stage asserts a req to instruction core interface

  // Interrupts
  logic        m_irq_enable;
  logic [31:0] csr_mepc, csr_depc;

  logic        csr_save_if;
  logic        csr_save_id;
  logic        csr_restore_mret_id;
  logic        csr_restore_dret_id;
  logic        csr_save_cause;
  logic [31:0] csr_mtvec;
  logic [31:0] csr_mtval;

  // debug mode and dcsr configuration
  dbg_cause_e  debug_cause;
  logic        debug_csr_save;
  logic        debug_single_step;
  logic        debug_ebreakm;

  // performance counter related signals
  logic        instr_ret;
  logic        instr_ret_compressed;
  logic        perf_imiss;
  logic        perf_jump;
  logic        perf_branch;
  logic        perf_tbranch;
  logic        perf_load;
  logic        perf_store;

  // for RVFI
  logic        illegal_insn_id, unused_illegal_insn_id; // ID stage sees an illegal instruction


  // TODO misc stuff to look at later
  logic [`CAP_SIZE-1:0] instr_auth_cap;
  logic [`INTEGER_SIZE-1:0] data_addr;
  logic [`CAP_SIZE-1:0] data_auth_cap;

  // RISC-V Formal Interface signals
`ifdef RVFI
  logic [31:0] rvfi_insn_id;
  logic [4:0]  rvfi_rs1_addr_id;
  logic [4:0]  rvfi_rs2_addr_id;
  logic [31:0] rvfi_rs1_data_d;
  logic [31:0] rvfi_rs1_data_id;
  logic [31:0] rvfi_rs1_data_q;
  logic [31:0] rvfi_rs2_data_d;
  logic [31:0] rvfi_rs2_data_id;
  logic [31:0] rvfi_rs2_data_q;
  logic [4:0]  rvfi_rd_addr_id;
  logic [4:0]  rvfi_rd_addr_q;
  logic [4:0]  rvfi_rd_addr_d;
  logic [31:0] rvfi_rd_wdata_id;
  logic [31:0] rvfi_rd_wdata_d;
  logic [31:0] rvfi_rd_wdata_q;
  logic        rvfi_rd_we_id;
  logic        rvfi_insn_new_d;
  logic        rvfi_insn_new_q;
  logic [7:0]  rvfi_mem_mask_int;
  logic [63:0] rvfi_mem_rdata_d;
  logic [63:0] rvfi_mem_rdata_q;
  logic [63:0] rvfi_mem_wdata_d;
  logic [63:0] rvfi_mem_wdata_q;
  logic [31:0] rvfi_mem_addr_d;
  logic [31:0] rvfi_mem_addr_q;
`endif

`ifdef DII
  assign perf_imiss_o = perf_imiss;
`endif

  // TODO remove this debug signal
  logic [31:0] pc_next;

  //////////////////////
  // Clock management //
  //////////////////////

  logic        clk;

  logic        clock_en;

  // if we are sleeping on a barrier let's just wait on the instruction
  // interface to finish loading instructions
  assign core_busy_int = if_busy | ctrl_busy | lsu_busy;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      core_busy_q <= 1'b0;
    end else begin
      core_busy_q <= core_busy_int;
    end
  end

  assign core_busy   = core_ctrl_firstfetch ? 1'b1 : core_busy_q;

  assign clock_en    = core_busy | irq_i | debug_req_i;

  // main clock gate of the core
  // generates all clocks except the one for the debug unit which is
  // independent
  prim_clock_gating core_clock_gate_i (
      .clk_i     ( clk_i           ),
      .en_i      ( clock_en        ),
      .test_en_i ( test_en_i       ),
      .clk_o     ( clk             )
  );

  //////////////
  // IF stage //
  //////////////

  ibex_if_stage #(
      .DmHaltAddr       ( DmHaltAddr      ),
      .DmExceptionAddr  ( DmExceptionAddr )
  ) if_stage_i (
      .clk_i                    ( clk                    ),
      .rst_ni                   ( rst_ni                 ),

      .boot_addr_i              ( boot_addr_i            ),
      .req_i                    ( instr_req_int          ), // instruction request control

      // instruction cache interface
      .instr_req_o              ( instr_req_o            ),
      // TODO make this useful for checking pc bounds
      .instr_cap_o(instr_cap),
      .instr_addr_o             ( instr_addr_o           ),
      .instr_gnt_i              ( instr_gnt_i            ),
      .instr_rvalid_i           ( instr_rvalid_i         ),
      .instr_rdata_i            ( instr_rdata_i          ),

      // outputs to ID stage
      .instr_valid_id_o         ( instr_valid_id         ),
      .instr_new_id_o           ( instr_new_id           ),
      .instr_rdata_id_o         ( instr_rdata_id         ),
      .instr_rdata_c_id_o       ( instr_rdata_c_id       ),
      .instr_is_compressed_id_o ( instr_is_compressed_id ),
      .illegal_c_insn_id_o      ( illegal_c_insn_id      ),
      .pc_if_o                  ( pc_if                  ),
      .pc_id_o                  ( pc_id                  ),

      // control signals
      .instr_valid_clear_i      ( instr_valid_clear      ),
      .pc_set_i                 ( pc_set                 ),
      .pc_mux_i                 ( pc_mux_id              ),
      .exc_pc_mux_i             ( exc_pc_mux_id          ),
      .exc_cause                ( exc_cause              ),

      // jump targets
      .jump_target_ex_i         ( jump_target_ex         ),
      .cap_jump_i(cap_jump),

      // CSRs
      .csr_mepc_i               ( csr_mepc               ), // exception return address
      .csr_depc_i               ( csr_depc               ), // debug return address
      .csr_mtvec_o              ( csr_mtvec              ), // trap-vector base address
      .scr_mtcc_i (scr_mtcc),

      // pipeline stalls
      .id_in_ready_i            ( id_in_ready            ),

      .pc_next                  ( pc_next                ),
      .if_busy_o                ( if_busy                ),
      .perf_imiss_o             ( perf_imiss             )
  );


  //////////////
  // ID stage //
  //////////////

  ibex_id_stage #(
      .RV32E ( RV32E ),
      .RV32M ( RV32M )
  ) id_stage_i (
      .clk_i                        ( clk                    ),
      .rst_ni                       ( rst_ni                 ),

      .test_en_i                    ( test_en_i              ),

      // Processor Enable
      .fetch_enable_i               ( fetch_enable_i         ),
      .ctrl_busy_o                  ( ctrl_busy              ),
      .core_ctrl_firstfetch_o       ( core_ctrl_firstfetch   ),
      .illegal_insn_o               ( illegal_insn_id        ),

      // from/to IF-ID pipeline register
      .instr_valid_i                ( instr_valid_id         ),
      .instr_new_i                  ( instr_new_id           ),
      .instr_rdata_i                ( instr_rdata_id         ),
      .instr_rdata_c_i              ( instr_rdata_c_id       ),
      .instr_is_compressed_i        ( instr_is_compressed_id ),

      // Jumps and branches
      .branch_decision_i            ( branch_decision        ),

      // IF and ID control signals
      .id_in_ready_o                ( id_in_ready            ),
      .instr_valid_clear_o          ( instr_valid_clear      ),
      .instr_req_o                  ( instr_req_int          ),
      .pc_set_o                     ( pc_set                 ),
      .pc_mux_o                     ( pc_mux_id              ),
      .exc_pc_mux_o                 ( exc_pc_mux_id          ),
      .exc_cause_o                  ( exc_cause              ),

      .illegal_c_insn_i             ( illegal_c_insn_id      ),

      .pc_id_i                      ( pc_id                  ),

      // Stalls
      .ex_valid_i                   ( ex_valid               ),
      .lsu_valid_i                  ( lsu_data_valid         ),

      .alu_operator_ex_o            ( alu_operator_ex        ),
      .alu_operand_a_ex_o           ( alu_operand_a_ex       ),
      .alu_operand_b_ex_o           ( alu_operand_b_ex       ),

      .mult_en_ex_o                 ( mult_en_ex             ),
      .div_en_ex_o                  ( div_en_ex              ),
      .multdiv_operator_ex_o        ( multdiv_operator_ex    ),
      .multdiv_signed_mode_ex_o     ( multdiv_signed_mode_ex ),
      .multdiv_operand_a_ex_o       ( multdiv_operand_a_ex   ),
      .multdiv_operand_b_ex_o       ( multdiv_operand_b_ex   ),

      // CHERI
      .cheri_en_o(cheri_en),
      .cheri_base_opcode_o(cheri_base_opcode),
      .cheri_threeop_opcode_o(cheri_threeop_opcode),
      .cheri_sad_opcode_o(cheri_sad_opcode),
      .cheri_ccall_type_o(cheri_ccall_type),
      .cheri_operand_a_o(cheri_operand_a),
      .cheri_operand_b_o(cheri_operand_b),

      .cheri_exc_a_i(cheri_exc_a),
      .cheri_exc_b_i(cheri_exc_b),
      .cheri_exc_o(cheri_exc),
      .cheri_exc_mem_i(cheri_data_exc),
      .cheri_exc_instr_i(cheri_instr_exc),
      .cheri_wrote_cap_i(cheri_wrote_cap),

      .use_cap_base_o(use_cap_base),



      // CSR ID/EX
      .csr_access_o                 ( csr_access             ),
      .csr_op_o                     ( csr_op                 ),
      .csr_save_if_o                ( csr_save_if            ), // control signal to save pc
      .csr_save_id_o                ( csr_save_id            ), // control signal to save pc
      .csr_restore_mret_id_o        ( csr_restore_mret_id    ), // control signal to restore pc
      .csr_restore_dret_id_o        ( csr_restore_dret_id    ), // control signal to restore pc
      .csr_save_cause_o             ( csr_save_cause         ),
      .csr_mtval_o                  ( csr_mtval              ),
      .illegal_csr_insn_i           ( illegal_csr_insn_id    ),

      // SCR interface
      .scr_access_o (scr_access),
      .scr_op_o (scr_op),
      .scr_rdata_i (scr_rdata),

      .scr_ddc_i (scr_ddc),
      .cheri_scr_exc_i(scr_exc),

      // LSU
      .data_req_ex_o                ( data_req_ex            ), // to load store unit
      .data_we_ex_o                 ( data_we_ex             ), // to load store unit
      .data_type_ex_o               ( data_type_ex           ), // to load store unit
      .data_sign_ext_ex_o           ( data_sign_ext_ex       ), // to load store unit
      .data_reg_offset_ex_o         ( data_reg_offset_ex     ), // to load store unit
      .data_wdata_ex_o              ( data_wdata_ex          ), // to load store unit

      .lsu_addr_incr_req_i          ( lsu_addr_incr_req      ),
      .lsu_addr_last_i              ( lsu_addr_last          ),

      .lsu_load_err_i               ( lsu_load_err           ),
      .lsu_store_err_i              ( lsu_store_err          ),

      .mem_cap_o(mem_cap),
      .mem_cap_access_o(mem_cap_access),

      // Interrupt Signals
      .irq_i                        ( irq_i                  ), // incoming interrupts
      .irq_id_i                     ( irq_id_i               ),
      .m_irq_enable_i               ( m_irq_enable           ),
      .irq_ack_o                    ( irq_ack_o              ),
      .irq_id_o                     ( irq_id_o               ),

      // Debug Signal
      .debug_cause_o                ( debug_cause            ),
      .debug_csr_save_o             ( debug_csr_save         ),
      .debug_req_i                  ( debug_req_i            ),
      .debug_single_step_i          ( debug_single_step      ),
      .debug_ebreakm_i              ( debug_ebreakm          ),

      // write data to commit in the register file
      .regfile_wdata_lsu_i          ( regfile_wdata_lsu      ),
      .regfile_wdata_ex_i           ( regfile_wdata_ex       ),
      .csr_rdata_i                  ( csr_rdata              ),

`ifdef RVFI
      .rfvi_reg_raddr_ra_o          ( rvfi_rs1_addr_id       ),
      .rfvi_reg_rdata_ra_o          ( rvfi_rs1_data_id       ),
      .rfvi_reg_raddr_rb_o          ( rvfi_rs2_addr_id       ),
      .rfvi_reg_rdata_rb_o          ( rvfi_rs2_data_id       ),
      .rfvi_reg_waddr_rd_o          ( rvfi_rd_addr_id        ),
      .rfvi_reg_wdata_rd_o          ( rvfi_rd_wdata_id       ),
      .rfvi_reg_we_o                ( rvfi_rd_we_id          ),
`endif

      // Performance Counters
      .perf_jump_o                  ( perf_jump              ),
      .perf_branch_o                ( perf_branch            ),
      .perf_tbranch_o               ( perf_tbranch           ),
      .instr_ret_o                  ( instr_ret              ),
      .instr_ret_compressed_o       ( instr_ret_compressed   )
  );

  // for RVFI only
  assign unused_illegal_insn_id = illegal_insn_id;

  ibex_ex_block #(
      .RV32M ( RV32M )
  ) ex_block_i (
      .clk_i                      ( clk                    ),
      .rst_ni                     ( rst_ni                 ),

      // ALU signal from ID stage
      .alu_operator_i             ( alu_operator_ex        ),
      .alu_operand_a_i            ( alu_operand_a_ex       ),
      .alu_operand_b_i            ( alu_operand_b_ex       ),

      // Multipler/Divider signal from ID stage
      .multdiv_operator_i         ( multdiv_operator_ex    ),
      .mult_en_i                  ( mult_en_ex             ),
      .div_en_i                   ( div_en_ex              ),
      .multdiv_signed_mode_i      ( multdiv_signed_mode_ex ),
      .multdiv_operand_a_i        ( multdiv_operand_a_ex   ),
      .multdiv_operand_b_i        ( multdiv_operand_b_ex   ),

      // CHERI
      .cheri_en_i(cheri_en),
      .cheri_base_opcode_i(cheri_base_opcode),
      .cheri_threeop_opcode_i(cheri_threeop_opcode),
      .cheri_sad_opcode_i(cheri_sad_opcode),
      .cheri_ccall_type_i(cheri_ccall_type),
      .cheri_operand_a_i(cheri_operand_a),
      .cheri_operand_b_i(cheri_operand_b),

      .cheri_exc_a_o(cheri_exc_a),
      .cheri_exc_b_o(cheri_exc_b),
      .cheri_wrote_cap_o(cheri_wrote_cap),


      // Outputs
      .alu_adder_result_ex_o      ( alu_adder_result_ex    ), // to LSU
      .regfile_wdata_ex_o         ( regfile_wdata_ex       ), // to ID

      .jump_target_o              ( jump_target_ex         ), // to IF
      .branch_decision_o          ( branch_decision        ), // to ID
      .cap_jump_o(cap_jump),

      .ex_valid_o                 ( ex_valid               )
  );

  /////////////////////
  // Load/store unit //
  /////////////////////

  // TODO find this a better home
  logic use_cap_base;

  ibex_load_store_unit  load_store_unit_i (
      .clk_i                 ( clk                 ),
      .rst_ni                ( rst_ni              ),

      // data interface
      .data_req_o            ( data_req_o          ),
      .data_gnt_i            ( data_gnt_i          ),
      .data_rvalid_i         ( data_rvalid_i       ),
      .data_err_i            ( data_err_i          ),
      .data_addr_aligned_o   ( data_addr_o         ),
      .data_we_o             ( data_we_o           ),
      .data_be_o             ( data_be           ),
      .data_wdata_o          ( data_wdata        ),
      .data_rdata_i          ( data_rdata        ),

      // actual byte address being accessed
      .data_addr_unaligned_o ( data_addr           ),

      // signals to/from ID/EX stage
      .data_we_ex_i          ( data_we_ex          ),
      .data_type_ex_i        ( data_type_ex        ),
      .data_wdata_ex_i       ( data_wdata_ex       ),
      .data_reg_offset_ex_i  ( data_reg_offset_ex  ),
      .data_sign_ext_ex_i    ( data_sign_ext_ex    ),

      .data_rdata_ex_o       ( regfile_wdata_lsu   ),
      .data_req_ex_i         ( data_req_ex         ),

      .adder_result_ex_i     ( alu_adder_result_ex ),

      .data_cap_i (mem_cap),
      .use_cap_base_i (use_cap_base),
      .cheri_mem_exc_i(cheri_data_exc),

      .addr_incr_req_o       ( lsu_addr_incr_req   ),
      .addr_last_o           ( lsu_addr_last       ),
      .data_valid_o          ( lsu_data_valid      ),

      // exception signals
      .load_err_o            ( lsu_load_err        ),
      .store_err_o           ( lsu_store_err       ),

      .busy_o                ( lsu_busy            )
  );


  /////////////////////////////////////////
  // CSRs (Control and Status Registers) //
  /////////////////////////////////////////

  assign csr_wdata  = alu_operand_a_ex;
  assign scr_wdata  = cheri_operand_a;
  assign csr_addr   = csr_num_e'(csr_access ? alu_operand_b_ex[11:0] : 12'b0);
  assign scr_addr   = scr_num_e'(scr_access ? cheri_operand_b : '0);

  assign perf_load  = data_req_o & data_gnt_i & (~data_we_o);
  assign perf_store = data_req_o & data_gnt_i & data_we_o;

  logic [`CAP_SIZE-1:0] scr_ddc;
  logic [`CAP_SIZE-1:0] scr_wdata;
  logic [`CAP_SIZE-1:0] scr_rdata;
  logic [`CAP_SIZE-1:0] scr_mtcc;
  scr_num_e scr_addr;
  scr_op_e scr_op;
  logic scr_access;
  logic scr_exc;

  ibex_cs_registers #(
      .MHPMCounterNum   ( MHPMCounterNum   ),
      .MHPMCounterWidth ( MHPMCounterWidth ),
      .RV32E            ( RV32E            ),
      .RV32M            ( RV32M            )
  ) cs_registers_i (
      .clk_i                   ( clk                    ),
      .rst_ni                  ( rst_ni                 ),

      // Core and Cluster ID from outside
      .core_id_i               ( core_id_i              ),
      .cluster_id_i            ( cluster_id_i           ),

      // Interface to CSRs (SRAM like)
      .csr_access_i            ( csr_access             ),
      .csr_addr_i              ( csr_addr               ),
      .csr_wdata_i             ( csr_wdata              ),
      .csr_op_i                ( csr_op                 ),
      .csr_rdata_o             ( csr_rdata              ),

      // Interface to SCRs
      .scr_access_i (scr_access),
      .scr_addr_i (scr_addr),
      .scr_wdata_i (scr_wdata),
      .scr_op_i (scr_op),
      .scr_rdata_o (scr_rdata),
      .exc_o(scr_exc),

      .scr_ddc_o (scr_ddc),
      .scr_mtcc_o(scr_mtcc),

      // Interrupt related control signals
      .m_irq_enable_o          ( m_irq_enable           ),
      .csr_mepc_o              ( csr_mepc               ),

      // debug
      .csr_depc_o              ( csr_depc               ),
      .debug_cause_i           ( debug_cause            ),
      .debug_csr_save_i        ( debug_csr_save         ),
      .debug_single_step_o     ( debug_single_step      ),
      .debug_ebreakm_o         ( debug_ebreakm          ),

      .pc_if_i                 ( pc_if                  ),
      .pc_id_i                 ( pc_id                  ),

      .csr_save_if_i           ( csr_save_if            ),
      .csr_save_id_i           ( csr_save_id            ),
      .csr_restore_mret_i      ( csr_restore_mret_id    ),
      .csr_restore_dret_i      ( csr_restore_dret_id    ),
      .csr_save_cause_i        ( csr_save_cause         ),
      .csr_mtvec_i             ( csr_mtvec              ),
      .csr_mcause_i            ( exc_cause              ),
      .csr_mtval_i             ( csr_mtval              ),
      .illegal_csr_insn_o      ( illegal_csr_insn_id    ),

      .instr_new_id_i          ( instr_new_id           ),

      // performance counter related signals
      .instr_ret_i             ( instr_ret              ),
      .instr_ret_compressed_i  ( instr_ret_compressed   ),
      .imiss_i                 ( perf_imiss             ),
      .pc_set_i                ( pc_set                 ),
      .jump_i                  ( perf_jump              ),
      .branch_i                ( perf_branch            ),
      .branch_taken_i          ( perf_tbranch           ),
      .mem_load_i              ( perf_load              ),
      .mem_store_i             ( perf_store             ),
      .lsu_busy_i              ( lsu_busy               )
  );

  /////////////////////////////
  // Memory access checkers
  ///////

  logic [`EXCEPTION_SIZE-1:0] cheri_data_exc;
  logic [`EXCEPTION_SIZE-1:0] cheri_instr_exc;
  logic [`CAP_SIZE-1:0] instr_cap;
  logic [`CAP_SIZE-1:0] mem_cap;
  logic mem_cap_access;
  logic [`CAP_SIZE-1:0] data_rdata;
  logic [`CAP_SIZE-1:0] data_wdata;
  logic [7:0] data_be;

  ibex_cheri_memchecker #(
      .DATA_MEM(1'b1)
  ) data_checker (
      .cap_base_i(mem_cap),
      // TODO check this is being set correctly
      // TODO this is wrong - we might try to do an unaligned access, in which case ibex will do two aligned
      // ones. the data type will not change between accesses, but the second access will be reading something that
      // is smaller than the first one. this means that the memchecker could throw an exception where one is not
      // supposed to be thrown
      .address_i(data_addr),
      .data_type_i(data_type_ex),
      .write_i(data_we_o),
      .access_capability_i(mem_cap_access),
      .mem_data_i(data_rdata_i),
      .mem_tag_i(data_rtag_i),
      .lsu_data_i(data_wdata),
      .data_be_i(data_be),

      .data_be_o(data_be_o),
      .mem_data_o(data_wdata_o),
      .mem_tag_o(data_wtag_o),
      .lsu_data_o(data_rdata),
      .cheri_mem_exc_o(cheri_data_exc)
  );

  ibex_cheri_memchecker #(
      .DATA_MEM(1'b0)
  ) instr_checker (
      // TODO this breaks when we try to jump since we're fetching an instruction which we wanted to fetch using
      // a different PCC
      .cap_base_i(instr_cap),
      .address_i(instr_addr_o),
      // TODO if we want to properly implement compressed instructions we're going to have to pass in
      // a proper type
      // for now just always say word
      .data_type_i(2'b0),
      .data_be_i(),
      .data_be_o(),

      // we never write instructions
      .write_i('0),
      // likewise, we never read capabilities from the instruction stream
      .access_capability_i('0),
      .mem_data_i(),
      .mem_tag_i('0),
      .lsu_data_i(),

      .mem_data_o(),
      .mem_tag_o(),
      .lsu_data_o(),
      .cheri_mem_exc_o(cheri_instr_exc)
  );

`ifdef RVFI
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      rvfi_halt              <= '0;
      rvfi_trap              <= '0;
      rvfi_intr              <= '0;
      rvfi_order             <= '0;
      rvfi_insn              <= '0;
      rvfi_insn_uncompressed <= '0;
      rvfi_mode              <= '0;
      rvfi_rs1_addr          <= '0;
      rvfi_rs2_addr          <= '0;
      rvfi_pc_rdata          <= '0;
      rvfi_pc_wdata          <= '0;
      rvfi_mem_rmask         <= '0;
      rvfi_mem_wmask         <= '0;
      rvfi_valid             <= '0;
      rvfi_rs1_rdata         <= '0;
      rvfi_rs2_rdata         <= '0;
      rvfi_rd_wdata          <= '0;
      rvfi_rd_addr           <= '0;
      rvfi_mem_rdata         <= '0;
      rvfi_mem_wdata         <= '0;
      rvfi_mem_addr          <= '0;
    end else begin
      rvfi_halt              <= '0;
      rvfi_trap      <= lsu_store_err || lsu_load_err || cheri_exc || illegal_insn_id;
      rvfi_intr              <= irq_ack_o;
      rvfi_order             <= rvfi_order + rvfi_valid;
      rvfi_insn              <= rvfi_insn_id;
      rvfi_insn_uncompressed <= instr_rdata_id;
      rvfi_mode              <= PRIV_LVL_M; // TODO: Update for user mode support
      rvfi_rs1_addr          <= rvfi_rs1_addr_id;
      rvfi_rs2_addr          <= rvfi_rs2_addr_id;
      rvfi_pc_rdata          <= pc_id;
      rvfi_pc_wdata  <= (pc_set || lsu_load_err || lsu_store_err || illegal_insn_id) ? (pc_mux_id == 3'b001 ? jump_target_ex : pc_next) : pcc_getAddr_o;
      rvfi_mem_rmask         <= rvfi_mem_mask_int;
      rvfi_mem_wmask         <= data_we_o ? rvfi_mem_mask_int : 8'b0000;
      rvfi_valid             <= instr_ret;
      rvfi_rs1_rdata         <= rvfi_rs1_data_d;
      rvfi_rs2_rdata         <= rvfi_rs2_data_d;
      rvfi_rd_wdata          <= rvfi_rd_wdata_d;
      rvfi_rd_addr           <= rvfi_rd_addr_d;
      rvfi_mem_rdata         <= rvfi_mem_rdata_d;
      rvfi_mem_wdata         <= rvfi_mem_wdata_d;
      rvfi_mem_addr          <= rvfi_mem_addr_d;
    end
  end

  // Keep the mem data stable for each instruction cycle
  always_comb begin
    if (rvfi_insn_new_d && lsu_data_valid) begin
      rvfi_mem_addr_d  = lsu_addr_incr_req ? rvfi_mem_addr_q : data_addr;
      rvfi_mem_rdata_d = regfile_wdata_lsu;
      rvfi_mem_wdata_d = mem_cap_access ? data_wdata_o : data_wdata_ex;
    end else begin
      rvfi_mem_addr_d  = rvfi_mem_addr_q;
      rvfi_mem_rdata_d = rvfi_mem_rdata_q;
      rvfi_mem_wdata_d = rvfi_mem_wdata_q;
    end
  end
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      rvfi_mem_addr_q  <= '0;
      rvfi_mem_rdata_q <= '0;
      rvfi_mem_wdata_q <= '0;
    end else begin
      rvfi_mem_addr_q  <= rvfi_mem_addr_d;
      rvfi_mem_rdata_q <= rvfi_mem_rdata_d;
      rvfi_mem_wdata_q <= rvfi_mem_wdata_d;
    end
  end
  // Byte enable based on data type
  always_comb begin
    unique case (data_type_ex)
      2'b00:   rvfi_mem_mask_int = 8'b0000_1111;
      2'b01:   rvfi_mem_mask_int = 8'b0000_0011;
      2'b10:   rvfi_mem_mask_int = 8'b0000_0001;
      2'b11:   rvfi_mem_mask_int = 8'b1111_1111;
    endcase
  end

  always_comb begin
    if (instr_is_compressed_id) begin
      rvfi_insn_id = {16'b0, instr_rdata_c_id};
    end else begin
      rvfi_insn_id = instr_rdata_id;
    end
  end

  // Source register data are kept stable for each instruction cycle
  always_comb begin
    if (instr_new_id) begin
      rvfi_rs1_data_d = rvfi_rs1_data_id;
      rvfi_rs2_data_d = rvfi_rs2_data_id;
    end else begin
      rvfi_rs1_data_d = rvfi_rs1_data_q;
      rvfi_rs2_data_d = rvfi_rs2_data_q;
    end
  end
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      rvfi_rs1_data_q <= '0;
      rvfi_rs2_data_q <= '0;
    end else begin
      rvfi_rs1_data_q <= rvfi_rs1_data_d;
      rvfi_rs2_data_q <= rvfi_rs2_data_d;
    end
  end

  // RD write register is refreshed only once per cycle and
  // then it is kept stable for the cycle.
  always_comb begin
    if (rvfi_insn_new_d) begin
      if (!rvfi_rd_we_id) begin
        rvfi_rd_addr_d    = '0;
        rvfi_rd_wdata_d   = '0;
      end else begin
        rvfi_rd_addr_d = rvfi_rd_addr_id;
        if (!rvfi_rd_addr_id) begin
          rvfi_rd_wdata_d = '0;
        end else begin
          rvfi_rd_wdata_d = rvfi_rd_wdata_id;
        end
      end
    end else begin
      rvfi_rd_addr_d    = rvfi_rd_addr_q;
      rvfi_rd_wdata_d   = rvfi_rd_wdata_q;
    end
  end
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      rvfi_rd_addr_q    <= '0;
      rvfi_rd_wdata_q   <= '0;
    end else begin
      rvfi_rd_addr_q    <= rvfi_rd_addr_d;
      rvfi_rd_wdata_q   <= rvfi_rd_wdata_d;
    end
  end

  always_comb begin
    if (instr_new_id) begin
      rvfi_insn_new_d = 1'b1;
    end else begin
      rvfi_insn_new_d = rvfi_insn_new_q;
    end
  end
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      rvfi_insn_new_q <= 1'b0;
    end else begin
      if (instr_ret) begin
        rvfi_insn_new_q <= 1'b0;
      end else begin
        rvfi_insn_new_q <= rvfi_insn_new_d;
      end
    end
  end

`endif



// This is needed for the RVFI signal generation
`ifdef RVFI
logic [31:0] pcc_getAddr_o;
module_wrap64_getAddr module_getAddr_a (
    .wrap64_getAddr_cap(pc_if),
    .wrap64_getAddr(pcc_getAddr_o));
`endif




endmodule
