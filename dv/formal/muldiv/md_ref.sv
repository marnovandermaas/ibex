// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/*
Reference models for the RV32M instructions, used to break the proof that Ibex's multiplier/divider
matches the Sail specification into steps that SAT-based tools can actually discharge.

Proving a 32-bit multiplier or divider equivalent to a structurally different one is far beyond what
SAT/IC3 can do directly. Instead, the proof goes through the following references (see README.md):

  Sail spec  ==(structural)==  md_spec_ref  ==(arith.)==  mul_* plumbing / md_div_ref  ==(seq.)==  RTL

- md_spec_ref uses exactly the same SV expressions as the Sail->SV output (256-bit product of
  128-bit sign/zero-extended operands, 128-bit signed `/` and `%`), so it is equivalent to the
  Sail spec by structure.
- The mul_ops1..4, mul_mac1, mul_lo and mul_hi functions follow the RTL decomposition of the
  single-cycle multiplier (three 17x17
  multipliers, two cycles for MULH, MULHSU and MULHU). They are related to md_spec_ref by the arithmetic lemmas in
  mul_t1.smt2 (bit-level plumbing) and mul_t2.smt2 (integer algebra).
- md_div_ref is an unrolled restoring divider whose intermediate stages are the values the
  iterative RTL divider holds in each cycle. It is related to md_spec_ref by SAT (div_ref_check.sv).
*/

package md_ref_pkg;

  // funct3 of the OP (0110011) / funct7 = 0000001 encodings.
  typedef enum logic [2:0] {
    F3_MUL    = 3'b000,
    F3_MULH   = 3'b001,
    F3_MULHSU = 3'b010,
    F3_MULHU  = 3'b011,
    F3_DIV    = 3'b100,
    F3_DIVU   = 3'b101,
    F3_REM    = 3'b110,
    F3_REMU   = 3'b111
  } md_funct3_e;

  // Is rs1 / rs2 interpreted as signed (Sail mul_op.signed_rs1/2, or `s` for DIV/REM)?
  function automatic logic f3_signed_rs1(logic [2:0] f3);
    return f3 inside {F3_MULH, F3_MULHSU, F3_DIV, F3_REM};
  endfunction
  function automatic logic f3_signed_rs2(logic [2:0] f3);
    return f3 inside {F3_MULH, F3_DIV, F3_REM};
  endfunction

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Spec-shaped reference. These mirror the code the Sail->SV compiler generates for
  // execute_MUL, execute_DIV and execute_REM in build/ibexspec.sv (and the sail_tdiv_int /
  // sail_tmod_int stubs in spec/stub.sv), expression for expression.
  ////////////////////////////////////////////////////////////////////////////////////////////////

  function automatic logic [127:0] spec_ext(logic s, logic [31:0] v);
    return s ? unsigned'(128'(signed'(v))) : {96'h0, v};
  endfunction

  function automatic logic [63:0] spec_mul_wide(logic s1, logic s2, logic [31:0] a, logic [31:0] b);
    logic [127:0] x, y, p;
    x = spec_ext(s1, a);
    y = spec_ext(s2, b);
    p = {unsigned'(256'(signed'({x}))) * unsigned'(256'(signed'({y})))}[127:0];
    return p[63:0];
  endfunction

  function automatic logic [31:0] spec_div(logic s, logic [31:0] a, logic [31:0] b);
    logic [127:0] x, y, q, q2;
    x = spec_ext(s, a);
    y = spec_ext(s, b);
    if (y == 128'h0) q = (~128'h1) + 128'h1;
    else             q = signed'(x) / signed'(y);
    // Signed overflow: q > xlen_max_signed => xlen_min_signed
    if (s && signed'(q) > signed'(128'h7FFF_FFFF)) q2 = unsigned'(128'(signed'(32'h8000_0000)));
    else                                           q2 = q;
    return q2[31:0];
  endfunction

  function automatic logic [31:0] spec_rem(logic s, logic [31:0] a, logic [31:0] b);
    logic [127:0] x, y, r;
    x = spec_ext(s, a);
    y = spec_ext(s, b);
    if (y == 128'h0) r = x;
    else             r = signed'(x) % signed'(y);
    return r[31:0];
  endfunction

  function automatic logic [31:0] md_spec_ref(logic [2:0] f3, logic [31:0] a, logic [31:0] b);
    logic [63:0] p;
    p = spec_mul_wide(f3_signed_rs1(f3), f3_signed_rs2(f3), a, b);
    unique case (f3)
      F3_MUL:                       return p[31:0];
      F3_MULH, F3_MULHSU, F3_MULHU: return p[63:32];
      F3_DIV:                       return spec_div(1'b1, a, b);
      F3_DIVU:                      return spec_div(1'b0, a, b);
      F3_REM:                       return spec_rem(1'b1, a, b);
      default:                      return spec_rem(1'b0, a, b);
    endcase
  endfunction

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // RTL-shaped multiplier reference (RV32MSingleCycle decomposition).
  //
  // The single-cycle multiplier uses three 17x17 signed multipliers. With a = {ah, al} and
  // b = {bh, bl}, sign_a = signed_mode[0] & a[31] and sign_b = signed_mode[1] & b[31]:
  //   MULL cycle:  m1 = al * bl,  m2 = al * {sign_b, bh},  m3 = {sign_a, ah} * bl
  //   MULH cycle:  m4 = {sign_a, ah} * {sign_b, bh}
  // The functions below are the operands of those products and the plumbing that combines the
  // products into the result. They contain no multipliers: the products are inputs, so that the
  // sequential proof never has to reason about a multiplier. mul_t1.smt2 / mul_t2.smt2 show that
  // the plumbing applied to the exact products gives the Sail result (spec_mul_wide).
  ////////////////////////////////////////////////////////////////////////////////////////////////

  typedef struct packed {
    logic [16:0] a;  // {sign, 16 bits}, interpreted as signed
    logic [16:0] b;
  } mul_operands_t;

  function automatic mul_operands_t mul_ops1(logic [31:0] a, logic [31:0] b);
    return '{a: {1'b0, a[15:0]}, b: {1'b0, b[15:0]}};
  endfunction
  function automatic mul_operands_t mul_ops2(logic [1:0] sm, logic [31:0] a, logic [31:0] b);
    return '{a: {1'b0, a[15:0]}, b: {sm[1] & b[31], b[31:16]}};
  endfunction
  function automatic mul_operands_t mul_ops3(logic [1:0] sm, logic [31:0] a, logic [31:0] b);
    return '{a: {sm[0] & a[31], a[31:16]}, b: {1'b0, b[15:0]}};
  endfunction
  function automatic mul_operands_t mul_ops4(logic [1:0] sm, logic [31:0] a, logic [31:0] b);
    return '{a: {sm[0] & a[31], a[31:16]}, b: {sm[1] & b[31], b[31:16]}};
  endfunction

  // 34-bit MULL-cycle accumulator: (m1 >> 16) + m2 + m3
  function automatic logic [33:0] mul_mac1(logic [33:0] m1, logic [33:0] m2, logic [33:0] m3);
    logic [33:0] s1;
    s1 = {18'h0, m1[31:16]};
    return $unsigned($signed(s1) + $signed(m2) + $signed(m3));
  endfunction

  // MUL result
  function automatic logic [31:0] mul_lo(logic [33:0] m1, logic [33:0] mac1);
    return {mac1[15:0], m1[15:0]};
  endfunction

  // MULH, MULHSU, MULHU result, from the MULL-cycle accumulator and m4
  function automatic logic [31:0] mul_hi(logic [1:0] sm, logic [33:0] mac1, logic [33:0] m4);
    logic [33:0] accum, mac2;
    accum[17:0]  = mac1[33:16];
    accum[33:18] = {16{(sm != 2'b00) & mac1[33]}};
    mac2 = $unsigned($signed(accum) + $signed(m4));
    return mac2[31:0];
  endfunction

endpackage

/*
Unrolled restoring divider, numbered like the iterative divider in ibex_multdiv_fast:
  N = |a|, D = |b| (absolute values only when signed)
  t[31] = {0, N[31]}
  for i = 31 downto 0:
    ge[i]  = t[i] >= D
    r[i]   = ge[i] ? t[i] - D : t[i]          (the partial remainder after bit i)
    t[i-1] = {r[i], N[i-1]}                   (the value the RTL holds in imd_val while counter = i-1)
  quotient = ge, remainder = r[0]
The quotient/remainder are only meaningful for D != 0.
*/
module md_div_ref (
  input  logic        sgn,        // signed division (DIV/REM)
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] num,        // N
  output logic [31:0] den,        // D
  output logic [32:0] t   [32],   // t[i]: comparison operand for quotient bit i
  output logic [31:0] r   [32],   // r[i]: remainder after quotient bit i
  output logic [31:0] q_part [33],// q_part[i]: quotient bits [31:i] (lower bits zero), q_part[32] = 0
  output logic [31:0] quot,       // unsigned quotient N / D
  output logic [31:0] rem,        // unsigned remainder N % D
  output logic [31:0] div_res,    // DIV/DIVU result, including the division by zero case
  output logic [31:0] rem_res     // REM/REMU result, including the division by zero case
);
  logic sign_a, sign_b;
  assign sign_a = sgn & a[31];
  assign sign_b = sgn & b[31];
  assign num = sign_a ? 32'(-a) : a;
  assign den = sign_b ? 32'(-b) : b;

  logic [31:0] ge;
  assign q_part[32] = '0;
  for (genvar i = 31; i >= 0; i--) begin : g_stage
    if (i == 31) begin : g_first
      assign t[i] = {32'h0, num[31]};
    end else begin : g_next
      assign t[i] = {r[i+1], num[i]};
    end
    assign ge[i] = t[i] >= {1'b0, den};
    assign r[i]  = ge[i] ? 32'(t[i] - {1'b0, den}) : t[i][31:0];
    assign q_part[i] = q_part[i+1] | ({31'h0, ge[i]} << i);
  end

  assign quot = ge;
  assign rem  = r[0];
  assign div_res = (b == 32'h0) ? 32'hFFFF_FFFF : ((sign_a ^ sign_b) ? 32'(-quot) : quot);
  assign rem_res = (b == 32'h0) ? a : (sign_a ? 32'(-rem) : rem);
endmodule
