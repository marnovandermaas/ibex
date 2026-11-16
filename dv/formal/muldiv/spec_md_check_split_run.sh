#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Build and prove the split DIV/REM spec check for one funct3 (4..7).
# Usage (from dv/formal/muldiv): spec_md_check_split_run.sh <funct3> <outdir>
set -euo pipefail
F3=$1
OUT=$2
./spec_md_check_split.sh "$F3" "$OUT/spec_split_f$F3.aig"
# SAT sweeping (the old fraig package copes with the many free inputs), then prove the output 0.
yosys-abc -c "read $OUT/spec_split_f$F3.aig; strash; fraig; print_stats; iprove; print_stats" \
  | tee "$OUT/spec_split_f$F3.abc.log" | tail -2
grep -q "UNSATISFIABLE" "$OUT/spec_split_f$F3.abc.log"
