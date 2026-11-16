# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""
Netlist transformation for the split DIV/REM check of spec_md_check.sv (SPEC_MD_SPLIT).

Input: RTLIL of spec_md_check after proc/flatten, in which the Sail `/` (or `%`) cell has been
renamed \\sail_op_0 and the md_spec_ref one \\ref_op_0. The script
  - drives h_ref_<op>_{a,b} / h_sail_<op>_{a,b} with the original operands of the two cells,
  - drives the operand wires of the other operator pair with zero (not compared),
  - feeds \\ref_op_0 with the operands of \\sail_op_0.
After this the two cells are identical (same type, parameters and inputs), so opt_merge turns
them into one, whose output is then cut (see spec_md_check_split.sh).

Usage: spec_md_split.py <op: div|mod> <in.il> <out.il>
"""

import re
import sys

op, src, dst = sys.argv[1:]
other = 'mod' if op == 'div' else 'div'
lines = open(src).read().split('\n')

# Locate the top module and the two cells
mod_start = next(i for i, l in enumerate(lines) if l.startswith('module \\spec_md_check'))
mod_end = next(i for i in range(mod_start, len(lines)) if lines[i] == 'end')


def cell_range(name):
    start = next(i for i in range(mod_start, mod_end)
                 if re.match(r'\s*cell \S+ ' + re.escape(name) + r'$', lines[i]))
    end = next(i for i in range(start, mod_end) if lines[i].strip() == 'end')
    return start, end


def port(rng, p):
    for i in range(*rng):
        m = re.match(r'(\s*)connect \\' + p + r' (.*)$', lines[i])
        if m:
            return i, m.group(1), m.group(2)
    raise KeyError(p)


ref = cell_range('\\ref_op_0')
sail = cell_range('\\sail_op_0')
assert lines[ref[0]].split()[1] == '$' + op and lines[sail[0]].split()[1] == '$' + op

new_conns = []
for p in 'AB':
    _, _, ref_sig = port(ref, p)
    _, _, sail_sig = port(sail, p)
    new_conns.append(f'  connect \\h_ref_{op}_{p.lower()} {ref_sig}')
    new_conns.append(f'  connect \\h_sail_{op}_{p.lower()} {sail_sig}')
    new_conns.append(f"  connect \\h_ref_{other}_{p.lower()} 128'{'0' * 128}")
    new_conns.append(f"  connect \\h_sail_{other}_{p.lower()} 128'{'0' * 128}")

# Feed the reference cell with the Sail operands
for p in 'AB':
    i, ind, _ = port(ref, p)
    _, _, sail_sig = port(sail, p)
    lines[i] = f'{ind}connect \\{p} {sail_sig}'

lines[mod_end:mod_end] = new_conns
open(dst, 'w').write('\n'.join(lines))
