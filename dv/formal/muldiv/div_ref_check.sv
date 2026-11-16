// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module div_ref_check (
  input  logic        sgn,
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic        bad
);
  import md_ref_pkg::*;
  logic [31:0] div_res, rem_res;
  md_div_ref u_ref (
    .sgn, .a, .b,
    .num(), .den(), .t(), .r(), .q_part(), .quot(), .rem(),
    .div_res, .rem_res
  );
  assign bad = (spec_div(sgn, a, b) != div_res) || (spec_rem(sgn, a, b) != rem_res);
endmodule
