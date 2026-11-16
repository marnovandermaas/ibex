#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Solve the inductive step query of rtl_md_check (dumped by yosys-smtbmc, see the Makefile) as a
# case split on the pre-state s0: the divider FSM state, the multiplier FSM state and, in MD_COMP,
# the iteration counter. The cases cover all values, so the step holds iff every case is unsat.
# Usage: rtl_ind_split.sh <step query .smt2> <outdir> [jobs]
set -euo pipefail
Q=$1
OUT=$2
JOBS=${3:-8}
tobin() { local n=$1 w=$2 s=""; for ((i=0;i<w;i++)); do s="$((n%2))$s"; n=$((n/2)); done; echo "$s"; }
MD='u_ex.gen_multdiv_fast.multdiv_i'
st="(|rtl_md_check_n $MD.md_state_q| s0)"
cnt="(|rtl_md_check_n $MD.div_counter_q| s0)"
mul="(|rtl_md_check_n $MD.gen_mult_single_cycle.mult_state_q| s0)"

mkdir -p "$OUT/ind_cases"
BODY="$OUT/ind_cases/body.smt2"
# Keep the assertions only (drop the dumped check-sat/get-value/exit and status annotations).
# Also drop yosys-smtbmc's "not an initial state" assumptions: without them this is plain
# 1-induction over every pre-state, including the initial one, so a base case at step 0 suffices.
grep -v "^(check-sat)\|^(get-value\|^(exit)\|^(set-info :status\|^(assert (not (|rtl_md_check_is| s[01])))$" \
  "$Q" > "$BODY"
# The two remaining queries' state and goal must still be there.
grep -q "^(assert (not (and (|rtl_md_check_a| s1) true)))$" "$BODY"
grep -q "^(assert (|rtl_md_check_t| s0 s1))$" "$BODY"
grep -q "^(assert (|rtl_md_check_a| s0))$" "$BODY"
! grep -q "rtl_md_check_is| s" "$BODY"
cases=()
for m in true false; do
  cases+=("idle_mul_$m|(and (= $st #b000) (= $mul $m))")
done
for s in 1 2 4 5 6 7; do
  b=$(tobin $s 3)
  cases+=("state$s|(= $st #b$b)")
done
for c in $(seq 0 31); do
  b=$(tobin $c 5)
  cases+=("comp_cnt$c|(and (= $st #b011) (= $cnt #b$b))")
done

run_case() {
  name=${1%%|*}; cond=${1#*|}
  f="$OUT/ind_cases/$name.smt2"
  { cat "$BODY"; echo "(assert $cond)"; echo "(check-sat)"; } > "$f"
  echo "$name $(bitwuzla "$f")"
}
export -f run_case; export BODY OUT
printf '%s\n' "${cases[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_case "$@"' _ {} | sort | tee "$OUT/ind_cases/results.txt"
! grep -v " unsat$" "$OUT/ind_cases/results.txt"
