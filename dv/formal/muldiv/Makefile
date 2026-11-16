# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Proofs of the RV32M arithmetic used by the main proof (see README.md). Run from dv/formal with
# `make muldiv`, inside `nix develop .#oss-dev` (any shell with yosys, yosys-slang, yosys-abc, z3,
# bitwuzla, python3 and the LOWRISC_* variables set will do).

B := ../build/muldiv
IBEX_RTL := ../../../rtl
ABC ?= yosys-abc
YOSYS := yosys -m $(LOWRISC_YOSYS_SLANG)
SPEC_SRCS := ../build/ibexspec.sv ../spec/stub.sv ../spec/spec_api.sv md_ref.sv spec_md_check.sv
RTL_SRCS := $(addprefix $(IBEX_RTL)/,ibex_pkg.sv ibex_alu.sv ibex_multdiv_slow.sv \
                                     ibex_multdiv_fast.sv ibex_ex_block.sv)

.PHONY: all mul-arith div-ref rtl spec
all: mul-arith div-ref rtl spec

$(B):
	mkdir -p $@

# (2b), (2c): multiplier arithmetic
mul-arith: $(B)/mul_t1.ok $(B)/mul_t2.ok

$(B)/mul_t1.ok: mul_t1.smt2 | $(B)
	test "$$(bitwuzla mul_t1.smt2)" = unsat
	touch $@

$(B)/mul_t2.ok: mul_t2.smt2 | $(B)
	test "$$(z3 mul_t2.smt2)" = unsat
	touch $@

# (2a): spec-shaped DIV/REM == restoring division reference
div-ref: $(B)/div_ref_check.ok

$(B)/div_ref_check.aig: md_ref.sv div_ref_check.sv div_ref_check.ys | $(B)
	$(YOSYS) -q -l $(B)/div_ref_check.log -s div_ref_check.ys

$(B)/div_ref_check.ok: $(B)/div_ref_check.aig
	$(ABC) -c "&r $<; &st; &cec -m" | tee $(B)/div_ref_check.abc.log | grep -q "Networks are equivalent"
	touch $@

# (3): the EX block, 1-induction. Base case with yosys-smtbmc; the inductive step is dumped by
# yosys-smtbmc and solved by bitwuzla, split into cases on the multdiv FSM state.
rtl: $(B)/rtl_md_check.ok

$(B)/rtl_md_check.smt2: md_ref.sv rtl_md_check.sv rtl_md_check_smt.ys $(RTL_SRCS) | $(B)
	$(YOSYS) -q -l $(B)/rtl_md_check.log -s rtl_md_check_smt.ys

$(B)/rtl_md_check.ok: $(B)/rtl_md_check.smt2 rtl_ind_split.sh
	# Base case: step 0 only, which is all 1-induction needs. The step from the initial state
	# to step 1 is covered by the inductive step, since rtl_ind_split.sh removes the
	# "s0 is not initial" assumption that yosys-smtbmc adds. Deeper base checks (-t 2 and more)
	# make z3 run for hours.
	yosys-smtbmc -s z3 -t 1 $< | tee $(B)/rtl_md_check.base.log | grep -q "Status: PASSED"
	timeout 120 yosys-smtbmc -s z3 -i -t 1 --dump-smt2 $(B)/rtl_md_check.ind.smt2 $< \
	  > /dev/null 2>&1 || true
	./rtl_ind_split.sh $(B)/rtl_md_check.ind.smt2 $(B) 8
	touch $@

# (1): the Sail specification, one check per funct3. MUL* directly; DIV/REM split (see
# spec_md_check.sv and spec_md_check_split.sh).
spec: $(foreach f,0 1 2 3 4 5 6 7,$(B)/spec_md_check_f$(f).ok)

$(B)/spec_md_check_f%.aig: spec_md_check.ys $(SPEC_SRCS) | $(B)
	sed -e "s|LOWRISC_SAIL_SRC|$(LOWRISC_SAIL_SRC)|" -e "s|FUNCT3_VAL|$*|g" spec_md_check.ys \
	  > $(B)/spec_md_check_f$*.ys
	$(YOSYS) -q -l $(B)/spec_md_check_f$*.log -s $(B)/spec_md_check_f$*.ys

$(B)/spec_md_check_f0.ok $(B)/spec_md_check_f1.ok $(B)/spec_md_check_f2.ok $(B)/spec_md_check_f3.ok: \
$(B)/spec_md_check_f%.ok: $(B)/spec_md_check_f%.aig
	$(ABC) -c "&r $<; &st; &cec -m" | tee $(B)/spec_md_check_f$*.abc.log | grep -q "Networks are equivalent"
	touch $@

$(B)/spec_md_check_f4.ok $(B)/spec_md_check_f5.ok $(B)/spec_md_check_f6.ok $(B)/spec_md_check_f7.ok: \
$(B)/spec_md_check_f%.ok: $(SPEC_SRCS) spec_md_check_split.sh spec_md_check_split_run.sh spec_md_split.py | $(B)
	./spec_md_check_split_run.sh $* $(B)
	touch $@
