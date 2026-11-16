// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Combinational miter: for every RV32M instruction (any rd, rs1, rs2 and register file contents,
// any value of the other specification inputs, as long as misa enables the M extension), in
// MAIN_IDEX mode the Sail specification writes md_spec_ref(funct3, X(rs1), X(rs2)) to X(rd).
// bad must be constant 0. This is the assumption SpecMulDiv in check/muldiv.sv.
//
// FUNCT3 < 8 fixes funct3 (to split the check into one smaller problem per instruction),
// FUNCT3 = 8 leaves it free.
module spec_md_check #(
  parameter int unsigned FUNCT3 = 8
) (
  input logic [31:0] regs_i [1:31],
  input logic [4:0] rs1, rs2, rd,
  input logic [2:0] funct3_i,
  input logic [31:0] misa_i,
  output logic bad
);
  logic [2:0] funct3;
  assign funct3 = FUNCT3 < 8 ? 3'(FUNCT3) : funct3_i;
  logic [31:0] insn;
  assign insn = {7'b0000001, rs2, rs1, funct3, rd, 7'b0110011};
  logic wx_en; logic [31:0] wx; logic [4:0] wx_addr;
  logic [31:0] a, b;
  assign a = rs1 == 0 ? 32'h0 : regs_i[rs1];
  assign b = rs2 == 0 ? 32'h0 : regs_i[rs2];

  spec_api #(.NREGS(32)) spec_api_i (
    .main_mode(MAIN_IDEX), .regs_i(regs_i),
    .wx_en_o(wx_en), .wx_o(wx), .wx_addr_o(wx_addr),
    .insn_bits(insn),
    .nextpc_i(), .pc_i(), .pc_o(), .misa_i(misa_i), .mip_i(),
    .mvendor_id_i(), .march_id_i(), .mimp_id_i(), .mhart_id_i(), .mconfigptr_i(),
    .mseccfg_i(), .mseccfg_o(), .pmp_cfg_i(), .pmp_cfg_o(), .pmp_addr_i(), .pmp_addr_o(),
    .mie_i(), .mie_o(), .priv_i(), .priv_o(), .mstatus_i(), .mstatus_o(),
    .mcause_i(), .mcause_o(), .mtval_i(), .mtval_o(), .mtvec_i(), .mtvec_o(),
    .mscratch_i(), .mscratch_o(), .mepc_i(), .mepc_o(), .mcounteren_i(), .mcounteren_o(),
    .int_err_o(),
    .mem_read_o(), .mem_read_snd_gran_o(), .mem_read_fst_addr_o(), .mem_read_snd_addr_o(),
    .mem_read_fst_rdata_i(), .mem_read_snd_rdata_i(),
    .mem_write_o(), .mem_write_snd_gran_o(), .mem_write_fst_addr_o(), .mem_write_snd_addr_o(),
    .mem_write_fst_wdata_o(), .mem_write_snd_wdata_o(), .mem_write_fst_be_o(), .mem_write_snd_be_o()
  );

  // The Sail spec must write md_spec_ref(funct3, rs1, rs2) to rd.
  logic bad_direct;
  assign bad_direct = misa_i[12] &&
                      !(wx_en && wx_addr == rd && wx == md_ref_pkg::md_spec_ref(funct3, a, b));

`ifdef SPEC_MD_SPLIT
  // Split check for DIV/REM (see spec_md_check_split.sh). The 128-bit `/` and `%` in Sail and in
  // md_spec_ref are textually identical. The yosys script records the operands of the reference
  // `/` and `%` in the h_ref_* wires and those of the Sail ones in h_sail_*, then feeds the
  // reference operators with the Sail operands so that each pair merges into a single cell, whose
  // output it leaves free. bad is then: the miter with a shared, unconstrained divider output, or
  // a difference in operands. As `/` and `%` are functions, bad == 0 implies bad_direct == 0.
  logic [127:0] h_ref_div_a, h_ref_div_b, h_sail_div_a, h_sail_div_b;  // driven by the script
  logic [127:0] h_ref_mod_a, h_ref_mod_b, h_sail_mod_a, h_sail_mod_b;  // driven by the script
  // (When misa disables M, Sail does not execute the instruction and bad_direct is 0 anyway, so
  // the operands only need to agree when it does.)
  assign bad = bad_direct ||
               misa_i[12] && (h_ref_div_a != h_sail_div_a || h_ref_div_b != h_sail_div_b ||
                              h_ref_mod_a != h_sail_mod_a || h_ref_mod_b != h_sail_mod_b);
`else
  assign bad = bad_direct;
`endif
endmodule
