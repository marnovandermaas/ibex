// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Renzo Andri - andrire@student.ethz.ch                      //
//                                                                            //
// Additional contributions by:                                               //
//                 Igor Loi - igor.loi@unibo.it                               //
//                 Sven Stucki - svstucki@student.ethz.ch                     //
//                 Andreas Traber - atraber@iis.ee.ethz.ch                    //
//                 Markus Wegmann - markus.wegmann@technokrat.ch              //
//                 Davide Schiavone - pschiavo@iis.ee.ethz.ch                 //
//                                                                            //
// Design Name:    Execute stage                                              //
// Project Name:   ibex                                                       //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Execution block: Hosts ALU and MUL/DIV unit                //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

`define CAP_SIZE 93
`define EXCEPTION_SIZE 22

/**
 * Execution stage
 *
 * Execution block: Hosts ALU and MUL/DIV unit
 */
module ibex_ex_block #(
    parameter bit RV32M = 1
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,

    // ALU
    input  ibex_defines::alu_op_e alu_operator_i,
    input  logic [31:0]           alu_operand_a_i,
    input  logic [31:0]           alu_operand_b_i,

    // Multiplier/Divider
    input  ibex_defines::md_op_e  multdiv_operator_i,
    input  logic                  mult_en_i,
    input  logic                  div_en_i,
    input  logic  [1:0]           multdiv_signed_mode_i,
    input  logic [31:0]           multdiv_operand_a_i,
    input  logic [31:0]           multdiv_operand_b_i,

    // CHERI
    input logic                     cheri_en_i,
    input ibex_defines::cheri_base_opcode_e       cheri_base_opcode_i,
    input ibex_defines::cheri_threeop_funct7_e    cheri_threeop_opcode_i,
    input ibex_defines::cheri_s_a_d_funct5_e      cheri_sad_opcode_i,
    input ibex_defines::cheri_ccall_e      cheri_ccall_type_i,
    input logic [`CAP_SIZE-1:0]      cheri_operand_a_i,
    input logic [`CAP_SIZE-1:0]      cheri_operand_b_i,

    output logic [`EXCEPTION_SIZE-1:0] cheri_exc_a_o,
    output logic [`EXCEPTION_SIZE-1:0] cheri_exc_b_o,
    output logic                  cheri_wrote_cap_o,

    // Outputs
    output logic [31:0]           alu_adder_result_ex_o, // to LSU
    // TODO should this be CAP_SIZE or should i have a separate signal?
    output logic [`CAP_SIZE-1:0]           regfile_wdata_ex_o,
    output logic [`CAP_SIZE-1:0]           jump_target_o,         // to IF
    output logic cap_jump_o,
    output logic                  branch_decision_o,     // to ID

    output logic                  ex_valid_o             // EX has valid output
);

  import ibex_defines::*;

  localparam bit MULT_TYPE = 1; // 0 -> SLOW, 1 -> FAST

  logic [31:0] alu_result, multdiv_result;

  logic [32:0] multdiv_alu_operand_b, multdiv_alu_operand_a;
  logic [33:0] alu_adder_result_ext;
  logic        alu_cmp_result, alu_is_equal_result;
  logic        multdiv_valid, multdiv_en_sel;
  logic        multdiv_en;

  logic [31:0] alu_operand_a;
  logic [31:0] alu_operand_b;
  alu_op_e alu_operator;

  logic [`CAP_SIZE-1:0] cheri_result;
  // TODO change size?
  logic [31:0] cheri_alu_operand_a;
  logic [31:0] cheri_alu_operand_b;
  alu_op_e cheri_alu_operator;

  logic [`EXCEPTION_SIZE-1:0] cheri_exc_a;
  logic [`EXCEPTION_SIZE-1:0] cheri_exc_b;
  assign cheri_exc_a_o = cheri_en_i ? cheri_exc_a : '0;
  assign cheri_exc_b_o = cheri_en_i ? cheri_exc_b : '0;

  /*
    The multdiv_i output is never selected if RV32M=0
    At synthesis time, all the combinational and sequential logic
    from the multdiv_i module are eliminated
  */

  `ifdef QUARTUS
    generate
  `endif

  if (RV32M) begin : gen_multdiv_m
    assign multdiv_en_sel     = MULT_TYPE ? div_en_i : mult_en_i | div_en_i;
    assign multdiv_en         = mult_en_i | div_en_i;
  end else begin : gen_multdiv_no_m
    assign multdiv_en_sel     = 1'b0;
    assign multdiv_en         = 1'b0;
  end

  assign alu_operand_a = cheri_en_i ? cheri_alu_operand_a : alu_operand_a_i;
  assign alu_operand_b = cheri_en_i ? cheri_alu_operand_b : alu_operand_b_i;
  assign alu_operator = cheri_en_i ? cheri_alu_operator : alu_operator_i;

  `ifdef QUARTUS
    endgenerate
  `endif

  // TODO change
  assign regfile_wdata_ex_o = multdiv_en ? multdiv_result
                            : cheri_en_i ? cheri_result
                            :              alu_result;

  // branch handling
  assign branch_decision_o  = alu_cmp_result;
  assign jump_target_o      = cheri_en_i ? cheri_result : alu_adder_result_ex_o;
  assign cap_jump_o = cheri_en_i;

  /////////
  // ALU //
  /////////

  ibex_alu alu_i (
      .operator_i          ( alu_operator            ),
      .operand_a_i         ( alu_operand_a             ),
      .operand_b_i         ( alu_operand_b             ),
      .multdiv_operand_a_i ( multdiv_alu_operand_a     ),
      .multdiv_operand_b_i ( multdiv_alu_operand_b     ),
      .multdiv_en_i        ( multdiv_en_sel            ),
      .adder_result_o      ( alu_adder_result_ex_o     ),
      .adder_result_ext_o  ( alu_adder_result_ext      ),
      .result_o            ( alu_result                ),
      .comparison_result_o ( alu_cmp_result            ),
      .is_equal_result_o   ( alu_is_equal_result       )
  );


  // CHERI ALU
  ibex_cheri_alu cheri_alu (
      .base_opcode_i(cheri_base_opcode_i),
      .threeop_opcode_i(cheri_threeop_opcode_i),
      .sad_opcode_i(cheri_sad_opcode_i),
      .ccall_type_i(cheri_ccall_type_i),

      // TODO rest of connections
      .operand_a_i(cheri_operand_a_i),
      .operand_b_i(cheri_operand_b_i),
      .returnvalue_o(cheri_result),
      .wroteCapability(cheri_wrote_cap_o),
      .alu_operand_a_o(cheri_alu_operand_a),
      .alu_operand_b_o(cheri_alu_operand_b),
      .alu_operator_o(cheri_alu_operator),
      .alu_result_i(alu_adder_result_ext[33:1]),
      .exceptions_a_o(cheri_exc_a),
      .exceptions_b_o(cheri_exc_b)

  );

  ////////////////
  // Multiplier //
  ////////////////

  `ifdef QUARTUS
    generate
  `endif

  if (!MULT_TYPE) begin : gen_multdiv_slow
    ibex_multdiv_slow multdiv_i (
        .clk_i              ( clk_i                 ),
        .rst_ni             ( rst_ni                ),
        .mult_en_i          ( mult_en_i             ),
        .div_en_i           ( div_en_i              ),
        .operator_i         ( multdiv_operator_i    ),
        .signed_mode_i      ( multdiv_signed_mode_i ),
        .op_a_i             ( multdiv_operand_a_i   ),
        .op_b_i             ( multdiv_operand_b_i   ),
        .alu_adder_ext_i    ( alu_adder_result_ext  ),
        .alu_adder_i        ( alu_adder_result_ex_o ),
        .equal_to_zero      ( alu_is_equal_result   ),
        .valid_o            ( multdiv_valid         ),
        .alu_operand_a_o    ( multdiv_alu_operand_a ),
        .alu_operand_b_o    ( multdiv_alu_operand_b ),
        .multdiv_result_o   ( multdiv_result        )
    );
  end else begin : gen_multdiv_fast
    ibex_multdiv_fast multdiv_i (
        .clk_i              ( clk_i                 ),
        .rst_ni             ( rst_ni                ),
        .mult_en_i          ( mult_en_i             ),
        .div_en_i           ( div_en_i              ),
        .operator_i         ( multdiv_operator_i    ),
        .signed_mode_i      ( multdiv_signed_mode_i ),
        .op_a_i             ( multdiv_operand_a_i   ),
        .op_b_i             ( multdiv_operand_b_i   ),
        .alu_operand_a_o    ( multdiv_alu_operand_a ),
        .alu_operand_b_o    ( multdiv_alu_operand_b ),
        .alu_adder_ext_i    ( alu_adder_result_ext  ),
        .alu_adder_i        ( alu_adder_result_ex_o ),
        .equal_to_zero      ( alu_is_equal_result   ),
        .valid_o            ( multdiv_valid         ),
        .multdiv_result_o   ( multdiv_result        )
    );
  end

  `ifdef QUARTUS
    endgenerate
  `endif

  // ALU output valid in same cycle, multiplier/divider may require multiple cycles
  assign ex_valid_o = multdiv_en ? multdiv_valid : 1'b1;

endmodule
