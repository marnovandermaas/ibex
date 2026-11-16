# RV32M (multiply and divide) proofs

This sub-proof shows that for the RV32M instructions (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`) the value Ibex writes back is the one Sail computes.
SAT-based engines cannot show directly that two structurally different 32-bit multipliers or dividers agree.
This proof uses SMT solvers instead that can reason at a word level.
The proof here targets the `RV32MSingleCycle` configuration.

## The chain of lemmas

```
 Sail spec ──(1)── md_spec_ref ──(2)── RTL-shaped references ──(3)── ibex_ex_block (RTL)
```

`md_ref.sv` contains the references:

- `md_ref_pkg::md_spec_ref(funct3, a, b)` is written with exactly the expressions the Sail→SV
  compiler generates for `execute_MUL`, `execute_DIV` and `execute_REM`. That is a 256-bit
  product of 128-bit sign/zero-extended operands, and 128-bit signed `/` and `%` as in
  `spec/stub.sv`.
- `mul_ops1..4`, `mul_mac1`, `mul_lo` and `mul_hi` describe the RTL decomposition of the
  single-cycle multiplier. The operands are fed to the three 17x17 multipliers, and the plumbing
  combines the products into the result. They contain no multiplier.
- `md_div_ref` is an unrolled restoring divider. Stage `i` is exactly what the iterative RTL
  divider holds while its counter is `i`.

| Step | What | File | Tool |
|------|------|------|------|
| (1) | For every RV32M instruction, register file and other spec input (with `misa.M` set), Sail in `MAIN_IDEX` mode writes `md_spec_ref(funct3, X(rs1), X(rs2))` to `X(rd)`. | `spec_md_check.sv` | ABC (one run per funct3, see below) |
| (2a) | `md_spec_ref` DIV/REM (128-bit signed `/`, `%`, with the division by zero and overflow cases) equals `md_div_ref`, for all operands. | `div_ref_check.sv` | ABC `&cec` |
| (2b) | Multiplier plumbing: for *any* product values, `mul_lo`/`mul_hi` match a wide non-wrapping model, given some side conditions. | `mul_t1.smt2` | bitwuzla |
| (2c) | Integer algebra: with the exact products of the operands `mul_ops1..4`, the side conditions hold and the wide model equals `md_spec_ref`. This also checks the products never overflow 34 bits. | `mul_t2.smt2` | z3 (QF_NIA) |
| (3) | `ibex_ex_block` + the ID stage's `imd_val_q` register, under the environment conditions `ENV_*`: whenever an RV32M instruction completes, `result_ex` equals `md_div_ref` (division), or `mul_lo`/`mul_hi` of the products of the three multipliers, which were fed `mul_ops1..4` (multiplication). | `rtl_md_check.sv` | yosys-smtbmc (base case), bitwuzla (inductive step) |

In (3) the three multipliers are cut points, so their outputs are free. That is an
over-approximation, so it's sound, and it means the sequential proof never has to reason about
a multiplier. The real multipliers compute exact products by the semantics of SystemVerilog `*`.
Given exact products, (2b) and (2c) give equality with `md_spec_ref`.

### How the hard steps are made tractable

- **(3) induction.** The harness asserts its own inductive strengthening (`inv_mul`, `inv_div`,
  `ghost_ok`), so it is proven by 1-induction:
  - The divider reference `md_div_ref` is evaluated on the live operands, and *all* of its outputs
    (every stage) are copied into ghost registers while the unit is idle; they hold while it is
    busy. The FSM invariants then relate registers to registers (`imd_val_q == t[cnt]`, ...), and
    `ghost_ok` (the reference's defining equations, stage by stage, on the ghost registers) keeps
    the ghosts consistent.
  - Otherwise the inductive step would contain two copies of the 32-stage reference (before and
    after the step), which SAT solvers cannot relate.
  - `rtl_ind_split.sh` solves the inductive step query (dumped by yosys-smtbmc) as 40 cases on
    the pre-state: each divider FSM state, the multiplier FSM state, and in MD_COMP each counter
    value. The cases are exhaustive, so the step holds iff all are `unsat`. This takes about
    3 minutes on 16 cores.
  - The script removes yosys-smtbmc's assumption that the pre-state is not an initial state, so
    the step is checked from every pre-state, and the base case only needs step 0. (A deeper
    base case, which the step would otherwise need, runs z3 for hours.)
- **(1) for DIV and REM.** The Sail `/` (or `%`) and the one in `md_spec_ref` are textually
  identical. But their operands come through different logic (Sail's decoder and register file
  read), so a SAT sweeper must relate two 128-bit dividers, which runs out of memory. Instead
  `spec_md_check_split.sh` (with `spec_md_split.py`) checks the conjunction of:
  - the operands of the two operators are equal (when `misa.M` is set); and
  - the miter holds when both operators are replaced by one shared cell with a free output.

  Since `/` and `%` are functions, this implies the original miter. ABC's `fraig` reduces the
  result to about 40k AND gates, and `iprove` proves it.
- **(1) for MUL\*.** Sail's 256-bit product and the one in `md_spec_ref` merge structurally, so
  ABC's `&cec` proves these directly.

### Sanity checks

Bugs injected into copies of the files are found:
- the remainder's sign taken from the divisor in `ibex_multdiv_fast.sv`: (3) fails, in the
  MD_CHANGE_SIGN case;
- the same in `md_div_ref`: (3) fails;
- the sign correction of the upper multiplier operand dropped in `mul_t2.smt2`: `sat`;
- the MULH accumulator sign extension dropped in `mul_t1.smt2`: `sat`.

Together, (1)–(3) give the two assumptions in `check/muldiv.sv`:

- `MulDivResult`: if the environment conditions held in every cycle so far, then whenever an
  RV32M instruction completes in EX, `result_ex == md_spec_ref(funct3, op_a, op_b)`.
- `SpecMulDiv`: if the specification's register operands equal `op_a` and `op_b`,
  `spec_post_wX == md_spec_ref(funct3, op_a, op_b)`.

Both use the same value, on the EX block's operands. This means the main proof only ever needs
equalities, never arithmetic. In the main proof that value is left as a free value in every cycle
rather than computed by `md_spec_ref`: the assumptions then only say that *some* value satisfies
both, which is weaker, so this is sound, and it keeps the arithmetic out of the model.

In the yosys/rIC3 flow, the two are written as asserts in step 13 (`Step13_MulDivResult` and
`Step13_SpecMulDiv`). Like every property, `aig-manip` uses them as assumptions in the later steps
(`MType_ExData` onwards, the only steps that need them), and since they are in `SKIPPED_PROPS` in
`conductor.py`, they are never proof goals. A global
assumption would constrain every step, and since `SpecMulDiv` refers to the spec's output, it
would put the whole Sail model into every proof (step 0, for example, then takes over 30 minutes
instead of under one).
The Jasper flow uses plain `assume property`.

The main flow then proves (lemma `muldiv` in `thm/muldiv.proof`):
- the environment conditions hold in the core;
- the RTL operands are the spec's register operands;
- the result therefore matches when the instruction leaves EX, and in WB.

With that, the `MType_*_Data` properties are no longer skipped.

## What is trusted

- The composition of the steps above (as in the rest of the flow, an argument on paper), and in
  particular reading `mul_t1.smt2` and `mul_t2.smt2` against `md_ref.sv`. These are about 20
  lines each, and their comments give the correspondence operation by operation.
- That `md_spec_ref` really is the expression Sail generates. This is checked by (1), so it only
  matters for the readability of the assumption.
- The tools: yosys (with yosys-slang), ABC, z3 and bitwuzla.

## Running

From `dv/formal`, inside `nix develop .#oss-dev`:

```sh
make muldiv            # all of the above, results in build/muldiv/
make -C muldiv rtl     # just step (3), etc.
```

The Sail checks take a while: each funct3 elaborates for about 10 minutes and needs about 12 GB.
The DIV/REM checks then take another 10 minutes of SAT sweeping, and MUL about 20 minutes.
