#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Build the split DIV/REM check of spec_md_check.sv (SPEC_MD_SPLIT, see the comment there) as an
# AIG whose single output must be constant 0.
# Usage (from dv/formal/muldiv, in the formal nix shell): spec_md_check_split.sh <funct3 4..7> <out.aig>
set -euo pipefail
F3=$1
OUT=$2
TMP=$(dirname "$OUT")/spec_split_f$F3
case $F3 in
  4|5) OP=div; STUB_LINE=29 ;;  # sail_tdiv_int in spec/stub.sv
  6|7) OP=mod; STUB_LINE=25 ;;  # sail_tmod_int in spec/stub.sv
  *) echo "funct3 must be 4..7" >&2; exit 1 ;;
esac
YOSYS="yosys -m $LOWRISC_YOSYS_SLANG -q"

$YOSYS -l $TMP.1.log -p "
read_slang --top spec_md_check -G FUNCT3=$F3 -DSYNTHESIS -DYOSYS -DSPEC_MD_SPLIT \
  ../build/ibexspec.sv ../spec/stub.sv ../spec/spec_api.sv md_ref.sv spec_md_check.sv \
  -I $LOWRISC_SAIL_SRC/lib/sv/ --single-unit --no-proc
proc
flatten
delete */t:\$print
opt
opt_clean
select -assert-count 1 t:\$$OP a:src=*stub.sv:$STUB_LINE.* %i
select -assert-count 1 t:\$$OP a:src=*md_ref.sv* %i
rename -enumerate -pattern sail_op_% t:\$$OP a:src=*stub.sv:$STUB_LINE.* %i
rename -enumerate -pattern ref_op_% t:\$$OP a:src=*md_ref.sv* %i
write_rtlil $TMP.pre.il
"

python3 spec_md_split.py $OP $TMP.pre.il $TMP.post.il

$YOSYS -l $TMP.2.log -p "
read_rtlil $TMP.post.il
hierarchy -top spec_md_check
opt_merge
select -assert-count 1 t:\$$OP a:src=*md_ref.sv* %i t:\$$OP a:src=*stub.sv:$STUB_LINE.* %i %u
cutpoint t:\$$OP a:src=*md_ref.sv* %i t:\$$OP a:src=*stub.sv:$STUB_LINE.* %i %u
opt_clean
setundef -undriven -anyseq
memory_map
opt -full
wreduce
opt_clean
techmap
opt -fast
aigmap
opt_clean
stat
write_aiger -zinit -map ${OUT%.aig}.aigmap $OUT
"
