// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/*
RV32M (multiply and divide) support for the proof, with RV32MSingleCycle implementation.

SAT-based model checkers cannot prove a 32-bit multiply or divide equivalent to a structurally
different one in a reasonable amount of time. The arithmetic is proven separately with more
suitable engines and connected here through two assumptions:

  MulDivResult (muldiv/rtl_md_check.sv, muldiv/mul_t1.smt2, muldiv/mul_t2.smt2,
                muldiv/div_ref_check.sv):
    If the environment conditions env_* below have held in every cycle so far, then whenever an
    RV32M instruction completes in the EX block, result_ex = md_spec_ref(funct3, op_a, op_b).

  SpecMulDiv (muldiv/spec_md_check.sv):
    When the Sail specification executes an RV32M instruction whose register operands are
    op_a and op_b, it writes md_spec_ref(funct3, op_a, op_b) to rd.

*/

`define MD `CR.ex_block_i.gen_multdiv_fast.multdiv_i
`define MDS `MD.gen_mult_single_cycle

////////////////////// Environment of the EX block //////////////////////
// These mirror muldiv/rtl_md_check.sv, on the signals the ID stage drives into the EX block.

logic md_sel;
assign md_sel = `CR.mult_sel_ex | `CR.div_sel_ex;

// The multdiv controls are decoded from instr_rdata_alu_id (see ibex_decoder)
logic [2:0] md_funct3;
assign md_funct3 = `CR.instr_rdata_alu_id[14:12];

md_op_e     md_dec_operator;
logic [1:0] md_dec_signed_mode;
always_comb begin
  unique case (md_funct3)
    3'b000:  begin md_dec_operator = MD_OP_MULL; md_dec_signed_mode = 2'b00; end
    3'b001:  begin md_dec_operator = MD_OP_MULH; md_dec_signed_mode = 2'b11; end
    3'b010:  begin md_dec_operator = MD_OP_MULH; md_dec_signed_mode = 2'b01; end
    3'b011:  begin md_dec_operator = MD_OP_MULH; md_dec_signed_mode = 2'b00; end
    3'b100:  begin md_dec_operator = MD_OP_DIV;  md_dec_signed_mode = 2'b11; end
    3'b101:  begin md_dec_operator = MD_OP_DIV;  md_dec_signed_mode = 2'b00; end
    3'b110:  begin md_dec_operator = MD_OP_REM;  md_dec_signed_mode = 2'b11; end
    default: begin md_dec_operator = MD_OP_REM;  md_dec_signed_mode = 2'b00; end
  endcase
end

logic md_busy;
assign md_busy = `MDS.mult_state_q == `MDS.MULH || `MD.md_state_q != `MD.MD_IDLE;

logic        md_sel_q;
logic [2:0]  md_funct3_q;
logic [31:0] md_op_a_q, md_op_b_q;
always_ff @(posedge clk_i) begin
  md_sel_q    <= md_sel;
  md_funct3_q <= md_funct3;
  md_op_a_q   <= `CR.multdiv_operand_a_ex;
  md_op_b_q   <= `CR.multdiv_operand_b_ex;
end

logic md_env_sel, md_env_en, md_env_decode, md_env_aluop, md_env_dit, md_env_stable, md_env_ok;
assign md_env_sel    = ~(`CR.mult_sel_ex & `CR.div_sel_ex);
assign md_env_en     = (~`CR.mult_en_ex | `CR.mult_sel_ex) & (~`CR.div_en_ex | `CR.div_sel_ex);
assign md_env_decode = ~md_sel | (`CR.mult_sel_ex == ~md_funct3[2] &
                                  `CR.multdiv_operator_ex == md_dec_operator &
                                  `CR.multdiv_signed_mode_ex == md_dec_signed_mode);
assign md_env_aluop  = ~md_sel | `CR.alu_operator_ex == ALU_ADD;
assign md_env_dit    = ~`CR.data_ind_timing;
assign md_env_stable = ~md_busy |
                       (md_sel & md_sel_q & md_funct3 == md_funct3_q &
                        `CR.multdiv_operand_a_ex == md_op_a_q &
                        `CR.multdiv_operand_b_ex == md_op_b_q);
assign md_env_ok     = md_env_sel & md_env_en & md_env_decode & md_env_aluop & md_env_dit &
                       md_env_stable;

// The environment has held in every cycle before this one
logic md_env_held_q;
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) md_env_held_q <= 1'b1;
  else         md_env_held_q <= md_env_held_q & md_env_ok;
end

////////////////////// Assumptions proven in muldiv/ //////////////////////

// Stands for md_spec_ref(md_funct3, op_a, op_b) (muldiv/md_ref.sv), but is deliberately left
// undriven, so it is a free value in every cycle. This is sound: the two assumptions below then
// only require that *some* value satisfies both, which allows more traces than the concrete
// md_spec_ref would. It is also enough, since both refer to the same cycle when they are used
// together (the instruction leaving EX, see MType_ExData). And it keeps the multiply and divide
// out of the model.
logic [31:0] md_ref_value;

logic md_completes;
assign md_completes = (`CR.mult_en_ex | `CR.div_en_ex) & `CR.ex_valid & `CR.multdiv_ready_id;

// Register operands as the specification sees them
logic [31:0] md_spec_insn;
logic [31:0] md_spec_rs1, md_spec_rs2;
assign md_spec_insn = ex_compressed_instr;
assign md_spec_rs1 = md_spec_insn[19:15] == 5'd0 ? 32'h0 : pre_regs_cut[md_spec_insn[19:15]];
assign md_spec_rs2 = md_spec_insn[24:20] == 5'd0 ? 32'h0 : pre_regs_cut[md_spec_insn[24:20]];

logic md_spec_is_mtype;
assign md_spec_is_mtype = md_spec_insn[6:0] == 7'b0110011 && md_spec_insn[31:25] == 7'b0000001;

logic md_result_cond, md_result_ok, md_spec_cond, md_spec_ok;
assign md_result_cond = md_env_held_q & md_env_ok & md_completes;
assign md_result_ok   = `CR.result_ex == md_ref_value;
assign md_spec_cond   = main_mode == MAIN_IDEX & md_spec_is_mtype & `CSR.MISA_VALUE[12] &
                        md_spec_insn[14:12] == md_funct3 &
                        md_spec_rs1 == `CR.multdiv_operand_a_ex &
                        md_spec_rs2 == `CR.multdiv_operand_b_ex;
assign md_spec_ok     = spec_post_wX_en & spec_post_wX_addr == md_spec_insn[11:7] &
                        spec_post_wX == md_ref_value;

`ifdef YOSYS
// In the yosys/rIC3 flow, the assumptions only apply from step 14 on (MType_ExData and later),
// which are the only steps that need them. A global assumption constrains every step, and
// SpecMulDiv refers to the spec's output, so it would put the whole Sail model into every proof.
// aig-manip turns asserts of earlier steps into assumptions, and both are in conductor.py's
// SKIPPED_PROPS, so they are never proof goals.
Step13_MulDivResult: assert property (
  @(posedge clk_i) disable iff (~rst_ni) md_result_cond |-> md_result_ok
);
Step13_SpecMulDiv: assert property (
  @(posedge clk_i) disable iff (~rst_ni) md_spec_cond |-> md_spec_ok
);
`else
MulDivResult: assume property (md_result_cond |-> md_result_ok);
SpecMulDiv: assume property (md_spec_cond |-> md_spec_ok);
`endif

`undef MD
`undef MDS
