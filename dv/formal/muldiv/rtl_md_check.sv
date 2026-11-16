// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/*
Sequential harness for the Ibex EX block (ALU + ibex_multdiv_fast) configured with
RV32M = RV32MSingleCycle, together with a copy of the ID stage's intermediate value register.

The inputs are what the ID stage drives into the EX block. They are free, except for the following
environment conditions (ENV_*), which check/muldiv.sv shows to hold in the full core:

  ENV_SEL      mult_sel and div_sel are not both set
  ENV_EN       mult_en implies mult_sel and div_en implies div_sel
  ENV_DECODE   when an RV32M instruction is selected, mult_sel/div_sel, operator and signed_mode are
               the ibex_decoder outputs for its funct3
  ENV_ALUOP    when an RV32M instruction is selected, the ALU operator is ALU_ADD (ibex_decoder sets
               it for all RV32M instructions; other operators select different adder inputs, which
               would overlap multdiv_sel_i in the `unique case` choosing the ALU adder operands)
  ENV_DIT      data independent timing is off
  ENV_STABLE   while the multdiv unit is busy, the same instruction and operands stay selected

The ID stage's imd_val_q register is modelled here by a copy of its RTL (ibex_id_stage.sv), which
check/muldiv.sv also checks against the core.

Under these conditions the harness proves that whenever an RV32M instruction completes, i.e.
(mult_en | div_en) & ex_valid & ready:
  - DIV, DIVU, REM, REMU: result_ex equals the restoring division reference md_div_ref.
  - MUL, MULH, MULHSU, MULHU: result_ex equals the mul_lo / mul_hi plumbing applied to the outputs
    of the three 17x17 multipliers, and those multipliers were fed the operands mul_ops1..4.
    The multipliers themselves are cut (rtl_md_check_smt.ys); mul_t1.smt2 and mul_t2.smt2 show
    that this plumbing applied to the exact products is the Sail result.
The assertions inv_* and ghost_ok are the inductive strengthening, describing the multdiv FSMs in
terms of the references. `bad` is high iff the environment conditions held in every cycle since
reset (including this one) and some assertion fails, so `bad` never being high proves all
assertions. This is the statement assumed as MulDivResult in check/muldiv.sv.
*/

module rtl_md_check import ibex_pkg::*; (
  input  logic        clk_i,
  // ID/EX -> multdiv
  input  logic        mult_sel,
  input  logic        div_sel,
  input  logic        mult_en,
  input  logic        div_en,
  input  md_op_e      operator,
  input  logic [1:0]  signed_mode,
  input  logic [31:0] op_a,
  input  logic [31:0] op_b,
  input  logic        ready,
  input  logic        data_ind_timing,
  // funct3 of the instruction in ID/EX (only meaningful if it is an RV32M instruction)
  input  logic [2:0]  funct3,
  // ID/EX -> ALU and branch target ALU; irrelevant for multdiv except for ENV_ALUOP
  input  alu_op_e     alu_operator,
  input  logic [31:0] alu_operand_a,
  input  logic [31:0] alu_operand_b,
  input  logic [31:0] bt_a_operand,
  input  logic [31:0] bt_b_operand,
  output logic        bad
);
  import md_ref_pkg::*;

  // Reset for one cycle at the start
  logic rst_ni = 1'b0;
  always_ff @(posedge clk_i) rst_ni <= 1'b1;

  ////////////////////////////////// Environment //////////////////////////////////

  logic sel, is_mul;
  assign sel    = mult_sel | div_sel;
  assign is_mul = ~funct3[2];

  // ibex_decoder RV32M table
  md_op_e     dec_operator;
  logic [1:0] dec_signed_mode;
  always_comb begin
    unique case (funct3)
      F3_MUL:    begin dec_operator = MD_OP_MULL; dec_signed_mode = 2'b00; end
      F3_MULH:   begin dec_operator = MD_OP_MULH; dec_signed_mode = 2'b11; end
      F3_MULHSU: begin dec_operator = MD_OP_MULH; dec_signed_mode = 2'b01; end
      F3_MULHU:  begin dec_operator = MD_OP_MULH; dec_signed_mode = 2'b00; end
      F3_DIV:    begin dec_operator = MD_OP_DIV;  dec_signed_mode = 2'b11; end
      F3_DIVU:   begin dec_operator = MD_OP_DIV;  dec_signed_mode = 2'b00; end
      F3_REM:    begin dec_operator = MD_OP_REM;  dec_signed_mode = 2'b11; end
      default:   begin dec_operator = MD_OP_REM;  dec_signed_mode = 2'b00; end
    endcase
  end

  // Copy of the imd_val_q register in ibex_id_stage
  logic [33:0] imd_val_q[2];
  logic [33:0] imd_val_d[2];
  logic [1:0]  imd_val_we;
  for (genvar i = 0; i < 2; i++) begin : g_imd_val
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) imd_val_q[i] <= '0;
      else if (imd_val_we[i]) imd_val_q[i] <= imd_val_d[i];
    end
  end

  logic [31:0] result_ex;
  logic        ex_valid;

  ibex_ex_block #(
    .RV32M          (RV32MSingleCycle),
    .RV32B          (RV32BNone),
    .BranchTargetALU(1'b1)
  ) u_ex (
    .clk_i,
    .rst_ni,
    .alu_operator_i         (alu_operator),
    .alu_operand_a_i        (alu_operand_a),
    .alu_operand_b_i        (alu_operand_b),
    .bt_a_operand_i         (bt_a_operand),
    .bt_b_operand_i         (bt_b_operand),
    .multdiv_operator_i     (operator),
    .mult_en_i              (mult_en),
    .div_en_i               (div_en),
    .mult_sel_i             (mult_sel),
    .div_sel_i              (div_sel),
    .multdiv_signed_mode_i  (signed_mode),
    .multdiv_operand_a_i    (op_a),
    .multdiv_operand_b_i    (op_b),
    .multdiv_ready_id_i     (ready),
    .data_ind_timing_i      (data_ind_timing),
    .imd_val_we_o           (imd_val_we),
    .imd_val_d_o            (imd_val_d),
    .imd_val_q_i            (imd_val_q),
    .alu_adder_result_ex_o  (),
    .result_ex_o            (result_ex),
    .branch_target_o        (),
    .branch_decision_o      (),
    .ex_valid_o             (ex_valid)
  );

  `define MD u_ex.gen_multdiv_fast.multdiv_i
  `define MDS `MD.gen_mult_single_cycle

  logic mul_busy, div_busy, busy;
  assign mul_busy = `MDS.mult_state_q == `MDS.MULH;
  assign div_busy = `MD.md_state_q != `MD.MD_IDLE;
  assign busy     = mul_busy | div_busy;

  logic        sel_q;
  logic [2:0]  funct3_q;
  logic [31:0] op_a_q, op_b_q;
  always_ff @(posedge clk_i) begin
    sel_q    <= sel;
    funct3_q <= funct3;
    op_a_q   <= op_a;
    op_b_q   <= op_b;
  end

  logic env_sel, env_en, env_decode, env_aluop, env_dit, env_stable, env_ok;
  assign env_sel    = ~(mult_sel & div_sel);
  assign env_en     = (~mult_en | mult_sel) & (~div_en | div_sel);
  assign env_decode = ~sel | (mult_sel == is_mul & operator == dec_operator &
                              signed_mode == dec_signed_mode);
  assign env_aluop  = ~sel | alu_operator == ALU_ADD;
  assign env_dit    = ~data_ind_timing;
  assign env_stable = ~rst_ni | ~busy |
                      (sel & sel_q & funct3 == funct3_q & op_a == op_a_q & op_b == op_b_q);
  assign env_ok     = env_sel & env_en & env_decode & env_aluop & env_dit & env_stable;

  ////////////////////////////////// Multiplier //////////////////////////////////
  // The three 17x17 multipliers are cut (their outputs are free, see rtl_md_check.ys), so the
  // proof is about how the RTL routes operands into them and combines their outputs. With exact
  // products, mul_t1.smt2 and mul_t2.smt2 turn the statements below into equality with Sail.

  `define MULT(i) {`MDS.mult``i``_sign_a, `MDS.mult``i``_op_a, `MDS.mult``i``_sign_b, `MDS.mult``i``_op_b}
  mul_operands_t ops1, ops2, ops3;   // operands currently fed into the three multipliers
  logic [33:0]   res1, res2, res3;   // and their outputs
  assign ops1 = `MULT(1);
  assign ops2 = `MULT(2);
  assign ops3 = `MULT(3);
  assign res1 = `MDS.mult1_res;
  assign res2 = `MDS.mult2_res;
  assign res3 = `MDS.mult3_res;
  `undef MULT

  // Ghost copies of the MULL-cycle products (and their operands) of a MULH* instruction.
  logic          mulh_start;
  mul_operands_t g_ops1, g_ops2, g_ops3;
  logic [33:0]   g_res1, g_res2, g_res3;
  assign mulh_start = ~mul_busy & ~div_busy & mult_en & operator == MD_OP_MULH;
  always_ff @(posedge clk_i) begin
    if (mulh_start) begin
      g_ops1 <= ops1; g_ops2 <= ops2; g_ops3 <= ops3;
      g_res1 <= res1; g_res2 <= res2; g_res3 <= res3;
    end
  end

  logic is_mulh_op;
  assign is_mulh_op = funct3 inside {F3_MULH, F3_MULHSU, F3_MULHU};

  logic [31:0] mul_expected;
  logic        mul_ops_ok;
  always_comb begin
    if (mul_busy) begin
      // Second cycle of MULH*: m1..m3 from the ghosts, m4 from multiplier 3.
      mul_expected = mul_hi(signed_mode, mul_mac1(g_res1, g_res2, g_res3), res3);
      mul_ops_ok   = g_ops1 == mul_ops1(op_a, op_b) &&
                     g_ops2 == mul_ops2(signed_mode, op_a, op_b) &&
                     g_ops3 == mul_ops3(signed_mode, op_a, op_b) &&
                     ops3   == mul_ops4(signed_mode, op_a, op_b);
    end else begin
      // MUL completes in its first cycle.
      mul_expected = mul_lo(res1, mul_mac1(res1, res2, res3));
      mul_ops_ok   = ops1 == mul_ops1(op_a, op_b) &&
                     ops2 == mul_ops2(signed_mode, op_a, op_b) &&
                     ops3 == mul_ops3(signed_mode, op_a, op_b);
    end
  end

  ////////////////////////////////// Divider //////////////////////////////////
  // The reference divider is evaluated on the live operands, and all of its outputs are copied
  // into ghost registers (g_*) while the unit is not busy; they hold while it is busy, and
  // inv_div checks the live operands still match. The FSM invariants then only relate registers
  // to registers, so the induction never has to evaluate the 32-stage reference.

  logic is_div_op;
  assign is_div_op = funct3 inside {F3_DIV, F3_DIVU};

  logic [31:0] c_num, c_den, c_quot, c_rem, c_div_res, c_rem_res;
  logic [32:0] c_t [32];
  logic [31:0] c_r [32];
  logic [31:0] c_q_part [33];
  md_div_ref u_div_ref (
    .sgn(signed_mode[0]), .a(op_a), .b(op_b),
    .num(c_num), .den(c_den), .t(c_t), .r(c_r), .q_part(c_q_part), .quot(c_quot), .rem(c_rem),
    .div_res(c_div_res), .rem_res(c_rem_res)
  );

  logic [31:0] g_op_a, g_op_b;
  logic        g_sgn, g_is_div;
  logic [31:0] num, den, quot, rem, div_res, rem_res;
  logic [32:0] t [32];
  logic [31:0] r [32];
  logic [31:0] q_part [33];
  always_ff @(posedge clk_i) begin
    if (!busy) begin
      g_op_a   <= op_a;
      g_op_b   <= op_b;
      g_sgn    <= signed_mode[0];
      g_is_div <= is_div_op;
      num      <= c_num;
      den      <= c_den;
      quot     <= c_quot;
      rem      <= c_rem;
      div_res  <= c_div_res;
      rem_res  <= c_rem_res;
      t        <= c_t;
      r        <= c_r;
      q_part   <= c_q_part;
    end
  end

  logic [31:0] div_expected;
  assign div_expected = g_is_div ? div_res : rem_res;

  // The ghost registers hold the md_div_ref outputs for g_op_a, g_op_b and g_sgn: these are the
  // defining equations of md_div_ref (md_ref.sv), stage by stage, on the ghost registers.
  logic        g_sign_a, g_sign_b;
  logic [31:0] g_ge;
  logic [31:0] g_stage_ok;
  logic        ghost_ok;
  assign g_sign_a = g_sgn & g_op_a[31];
  assign g_sign_b = g_sgn & g_op_b[31];
  for (genvar i = 0; i < 32; i++) begin : g_ghost_stage
    assign g_ge[i] = t[i] >= {1'b0, den};
    if (i == 31) begin : g_first
      assign g_stage_ok[i] = t[i] == {32'h0, num[31]} &&
                             r[i] == (g_ge[i] ? 32'(t[i] - {1'b0, den}) : t[i][31:0]) &&
                             q_part[i] == (q_part[i+1] | ({31'h0, g_ge[i]} << i));
    end else begin : g_next
      assign g_stage_ok[i] = t[i] == {r[i+1], num[i]} &&
                             r[i] == (g_ge[i] ? 32'(t[i] - {1'b0, den}) : t[i][31:0]) &&
                             q_part[i] == (q_part[i+1] | ({31'h0, g_ge[i]} << i));
    end
  end
  assign ghost_ok = &g_stage_ok && q_part[32] == 32'h0 &&
                    num == (g_sign_a ? 32'(-g_op_a) : g_op_a) &&
                    den == (g_sign_b ? 32'(-g_op_b) : g_op_b) &&
                    quot == g_ge && rem == r[0] &&
                    div_res == ((g_op_b == 32'h0) ? 32'hFFFF_FFFF :
                                ((g_sign_a ^ g_sign_b) ? 32'(-quot) : quot)) &&
                    rem_res == ((g_op_b == 32'h0) ? g_op_a : (g_sign_a ? 32'(-rem) : rem));

  ////////////////////////////////// Properties //////////////////////////////////

  logic [4:0] cnt;
  assign cnt = `MD.div_counter_q;
  logic [33:0] imd0;
  assign imd0 = imd_val_q[0];

  // The result, when an M instruction completes.
  logic completes, ok_result;
  assign completes = (mult_en | div_en) & ex_valid & ready;
  always_comb begin
    ok_result = 1'b1;
    if (completes) begin
      if (mult_en) ok_result = (funct3 == F3_MUL) != mul_busy && mul_ops_ok &&
                              result_ex == mul_expected;
      else        ok_result = result_ex == div_expected;
    end
  end

  // Multiplier FSM: MULH* spend one cycle in MULL computing mac1, then wait in MULH.
  logic inv_mul;
  assign inv_mul = ~mul_busy |
                   (mult_sel & is_mulh_op & ~div_busy & imd0 == mul_mac1(g_res1, g_res2, g_res3) &&
                    g_ops1 == mul_ops1(op_a, op_b) &&
                    g_ops2 == mul_ops2(signed_mode, op_a, op_b) &&
                    g_ops3 == mul_ops3(signed_mode, op_a, op_b));

  // Divider FSM, in terms of the restoring division reference. The partial remainder bound
  // r[cnt + 1] < den is what keeps the comparison operand t[cnt] within the 32 bits the RTL
  // compares; stating it per stage keeps the induction local. div_by_zero_q is only written by
  // DIV/DIVU (REM/REMU keep a stale value, which they do not use).
  logic inv_div;
  always_comb begin
    inv_div = 1'b1;
    if (div_busy) begin
      inv_div = div_sel & ~is_mul & ~mul_busy & op_a == g_op_a & op_b == g_op_b &
                signed_mode[0] == g_sgn & is_div_op == g_is_div;
      unique case (`MD.md_state_q)
        `MD.MD_ABS_A: inv_div &= g_op_b != 0 & cnt == 5'd31 & (~g_is_div | ~`MD.div_by_zero_q);
        `MD.MD_ABS_B: inv_div &= g_op_b != 0 & cnt == 5'd31 & (~g_is_div | ~`MD.div_by_zero_q) &
                                 `MD.op_numerator_q == num & `MD.op_quotient_q == 32'h0;
        `MD.MD_COMP:  inv_div &= g_op_b != 0 & cnt != 5'd0 & (~g_is_div | ~`MD.div_by_zero_q) &
                                 `MD.op_numerator_q == num & imd_val_q[1][31:0] == den &
                                 imd0 == {1'b0, t[cnt]} & `MD.op_quotient_q == q_part[cnt + 6'd1] &
                                 (cnt == 5'd31 || r[cnt + 5'd1] < den);
        `MD.MD_LAST:  inv_div &= g_op_b != 0 & cnt == 5'd0 & (~g_is_div | ~`MD.div_by_zero_q) &
                                 `MD.op_numerator_q == num & imd_val_q[1][31:0] == den &
                                 imd0 == {1'b0, t[0]} & `MD.op_quotient_q == q_part[1] & r[1] < den;
        `MD.MD_CHANGE_SIGN:
                      inv_div &= g_op_b != 0 & (~g_is_div | ~`MD.div_by_zero_q) &
                                 imd0 == {2'b0, (g_is_div ? quot : rem)};
        `MD.MD_FINISH:
                      inv_div &= imd0[31:0] == div_expected;
        default:      inv_div = 1'b0;
      endcase
    end
  end

  logic ok;
  assign ok = ok_result & inv_mul & inv_div & ghost_ok;

  // Assumption monitor: bad only counts while all assumptions have held so far.
  logic env_held_q = 1'b1;
  // Like md_env_held_q in check/muldiv.sv, the reset cycle does not count.
  always_ff @(posedge clk_i) env_held_q <= env_held_q & (env_ok | ~rst_ni);
  assign bad = rst_ni & env_held_q & env_ok & ~ok;

`ifdef MULDIV_SMTBMC
  // For yosys-smtbmc, which checks assertions rather than an output.
  always_comb assert (!bad);
`endif

  `undef MD
  `undef MDS
endmodule
