# RISC-V Architectural Certification Tests (ACT)

This is a **second, parallel simulation flow** — it does not use `run_config.json`,
the `.s` + `.v` pair convention, the `x31` sync mechanism, or the 36-variant timing
matrix. Those belong to `sim/rtl_sim/`. See
[`doc/verification_guide.md`](../../doc/verification_guide.md) for that flow.

## What this covers

All four personas plus two arch-test-only configurations are run. Counts are
the number of generated ELFs at the pinned ACT revision:

| Configuration | Tests | Selected suites |
|---|---|---|
| `performance` | 220 | I, M, Zba/Zbb/Zbs/Zbc, Zca/Zcb (+ ZcbM/ZcbZbb crosses), Zicntr, Zicsr, Zifencei; 95 privileged (Sm/S/U exceptions + interrupts, Sscounterenw, Sstvecd, Svbare, 68 `pmp`) |
| `ultra` | 222 | as performance, plus Zihpm |
| `classic` | 109 | I, M, Zbb, Zca, Zicntr, Zicsr, Zifencei; 9 privileged (Sm, ExceptionsSm, InterruptsSm, ExceptionsZc) |
| `light` | 69 | E, Zmmul, Zca — **instruction tests only** |
| `m-pmp` | 154 | classic plus PMP: M-mode only with `pmpcfg*`/`pmpaddr*`/`mseccfg` present |
| `su-nocntr` | 210 | performance minus Zicntr: `mcounteren` present while the counters it gates are not (see below) |

`m-pmp` and `su-nocntr` are defined in `bin/run_act` (`ACT_ONLY_CONFIGS`), not in
the persona ladder; they exist to place the CSR existence map where no persona
does, which is where `Sm_mcsr-00` has leverage. ACT selects tests from the DUT
config, so the set grows and shrinks with the configuration rather than being
fixed. The instruction tests are machine-generated and far denser per encoding
than the directed corpus in `sim/rtl_sim/src/` can be; the privileged tests are
selected by the declared privilege modes (S/U configs get the S, U and PMP
suites, M-only configs the Sm suites).

## What it does not cover

- **No Zcmp, Zcmt or Smrnmi suites exist upstream at the pinned revision.** The
  Ultra persona's headline features get zero coverage here, whatever the config
  says.
- **`light` gets no privileged coverage at all.** Every test under `tests/priv/`
  declares `I` in `REQUIRED_EXTENSIONS`, so an `E`-base config selects none of
  them — there is no `rv32e` priv test directory upstream. That means light's
  most distinctive property, `SU_MODE_EN=0` (M-mode only), is not exercised here;
  `sim/rtl_sim`'s directed `trap_*` corpus covers it instead.
- **Sdtrig is excluded** (`SdtrigSm,SdtrigS,SdtrigU`) because these personas
  build with `DEBUG_EN=0`.
- **The `Sv*` tests do not apply** — arvern has no MMU, so address-translation
  coverage is limited to Svbare.
- **`su-nocntr` is 209/210 — `Sm_mcsr-00` (bin `mcountinhibit_csrrw1`) is a known
  upstream gap, not an RTL defect.** With `ZICNTR_EN=0` the core implements no
  counters, so `mcountinhibit` is read-only zero, which Priv 3.1.12 permits ("if
  the mcountinhibit register is not implemented, the implementation behaves as
  though the register were set to zero"). The suite assumes the register exists:
  the test body writes it unconditionally and the Sail reference always models
  CY/IR as writable, and neither honours `MCOUNTINHIBIT_IMPLEMENTED: false` —
  `tests/env/rvtest_setup.h` carries upstream's own TODO for exactly this
  (riscv-isa-manual #2964). Test bodies are out of scope for local patches, so
  the result stands until upstream parameterises the coverpoint.
- **One timing variant only.** There is no equivalent of the `sim/rtl_sim`
  36-variant matrix; this flow is about conformance, not timing verification.

So the two flows are complementary and neither retires the other: ACT brings
encoding density and an external reference model, `sim/rtl_sim/` keeps the
directed trap, NMI, debug and timing-variant coverage that ACT has no tests for.

## Why generation runs in Docker

The upstream ACT4 framework generates **self-checking ELFs**: it runs the Sail
reference model at generation time and bakes the expected results into each ELF.
Running them needs no reference model, no signature dump and no comparison — the
test reports its own pass/fail.

Generation is Linux-only. The `udb` Ruby gem downloads prebuilt native helpers
(`libz3`, `espresso`, `eqntott`, `must`) selected by CPU alone, with no host-OS
branch, so on macOS it fetches Linux ELF binaries and fails to load. Upstream
documents Ubuntu/Fedora only and tests exclusively on `ubuntu-*` runners.

This is a clean split rather than a workaround: **generate in the container, run
natively**. Only the ELFs cross the boundary.

## Layout

```
sim/arch_test/
├── run/
│   ├── run               entry point -- start here
│   ├── riscv-arch-test/  the upstream suite, at a pinned SHA (gitignored)
│   ├── GENERATED/        ELFs + build intermediates from the container (gitignored)
│   └── WORK/             per-test simulation scratch (gitignored)
├── bin/                  fetch_suite.sh, act_docker, run_act
└── src/                  everything aRVern-authored
    ├── stimulus_act.v    the single static stimulus for the ACT flow
    └── arvern-performance/   DUT config, one directory per persona:
                              arvern-performance.yaml, sail.json,
                              test_config.yaml, rvmodel_macros.h, link.ld
                              (arvern-light also carries arch_overlay/)
```

Two working directories, deliberately named apart: **GENERATED** is what the ACT4
container produced (it is the Makefile's `WORKDIR`, bind-mounted at `/act4/work`),
**WORK** is native simulation scratch and mirrors `sim/rtl_sim/run/WORK`.

`run/GENERATED/` sits deliberately *outside* `run/riscv-arch-test/` — bumping the
pinned SHA means deleting and re-fetching the suite, which would otherwise take
every generated ELF with it.

Each `src/arvern-<persona>/` directory is self-contained and shaped so it can be
contributed upstream as `config/cores/arvern/<persona>/` unchanged; `src/` is
mounted read-only at `/act4/config/cores/arvern` for generation. The one
exception is `arvern-light`: its `arch_overlay` line is an absolute path into
our container mount and cannot go upstream as-is — the upstream ask there is an
`E` extension in `riscv-unified-db`, after which the overlay is deleted.

**Status:** every configuration passes unwaived (`su-nocntr` 209/210, see above).
`link.ld` is byte-identical across all six and `rvmodel_macros.h` differs only in
the comment explaining why `RVMODEL_ACCESS_FAULT_ADDRESS` stays undefined (PMP
vs no-PMP builds); only the UDB yaml, `sail.json` and `test_config.yaml` differ
in substance.

`arvern-light` additionally carries `arch_overlay/ext/E.yaml`. UDB has no `E`
extension — not in the pinned gem, not on `riscv-unified-db` main — so with the
stock database no configuration can select a single `tests/rv32e/` test even
though they are generated and CI-checked. The overlay supplies the missing
definition through UDB's own `arch_overlay` mechanism; see the header of that
file. Two upstream gaps therefore stand between an RV32E core and this suite,
the second fixed by `patches/0002`.

## Usage

Everything is driven from `run/run`, mirroring `sim/rtl_sim/run/run`:

```bash
cd sim/arch_test/run

./run --setup             # fetch the pinned suite (~366 MB) + pull the ACT4 image
./run --gen               # generate ELFs for the default persona (Docker)
./run --gen -p light      # ...for another persona
./run                     # run every generated ELF on the DUT
./run Svbare_Smode        # or one test by name (globs work too)
./run --list-tests        # what is available; takes a glob to narrow
./run -p ultra -j 8       # persona + parallelism
./run -f 'Zbb-*'          # filter on ELF basename
./run --list-personas
./run --shell             # interactive shell inside the ACT4 container
```

`--setup` is a one-off. The image ships the riscv-gnu-toolchain (GCC 15 /
Binutils 2.44), sail-riscv 0.13.1 and mise, so nothing is built from source; the
first generation run does a one-time `bundle install` of the UDB gems into a
named Docker volume (`arvern-act4-home`) that persists across `--rm` runs.

`--gen` passes extra arguments through to the ACT4 Makefile, so
`./run --gen EXTENSIONS=I,M` or `DEBUG=True` work as upstream documents. Output
lands in `work/arvern-<persona>/elfs/`.

Runs are native — no container. Persona RTL parameters come from
`sim/rtl_sim/bin/rtl_sweep_configs.py:PERSONAS`, the same table the synthesis,
lint and regression sweeps use, so the two flows cannot drift. The design is
elaborated **once per persona** (the ACT stimulus is test-independent, so only
the SRAM image changes between tests), and each test runs in its own directory
under `run/WORK/arvern-<persona>/tests/` with a `sim.log`.

## Things the flow depends on

All documented at their use sites:

- **Two build adjustments apply to the ACT elaboration only**, never to a
  published persona: every PMP-bearing configuration elaborates `PMP_NR=16`
  (`ACT_PMP_NR` in `bin/run_act`) because the upstream tests hardcode region
  indices up to 7 and place their permissive background rule at
  `NUM_USABLE_PMP_ENTRIES-1` (lowest-numbered match wins, so a background below
  the region under test would mask it); and an executable SRAM is mapped at
  address 0 (`ARV_TB_SRAM_LO_X_EN`, `bench/verilog/ahb_decoder.v`) because
  `pmpsm_cfg_A_tor_zero` writes a `ret` at 0 and executes it. That region is off
  in the directed flow, whose bus-error tests use address 0 as their faulting
  address.
- The image is `$readmemh`'d into `sram_x_inst.mem` by the stimulus at `#1`, not
  at time 0 — `tb_arvern.v` zero-fills that array in a time-0 `initial` block,
  and two initial blocks writing one array race. `random_irq_enable` and
  `error_on_exception` are set past `#1` for the same reason.
- `error_on_exception = 0`: ACT tests take ECALLs and illegal instructions as
  subject matter. The ELF's self-check is the oracle; the exception monitors
  must not also vote, or a passing test still fails the run.
- `SRAM_X_SIZE` and `RESET_VECTOR` are elaboration overrides (`-P`), so nothing
  in `bench/` or `rtl/` is modified for this flow.
- **`sail.json` has its own `extensions` block that UDB does not cross-check
  against `implemented_extensions`.** When adding a persona, diff the two before
  running anything: a mismatch produces confidently-wrong expected values, and
  the failures look like RTL bugs.
- **UDB params can become *invalid*, not merely redundant, when their gating
  extension is absent.** `TIME_CSR_IMPLEMENTED` is gated on Zicntr,
  `MSTATUS_FS_LEGAL_VALUES` on F-or-S, `COUNTINHIBIT_EN` on
  `MCOUNTINHIBIT_IMPLEMENTED`, `HPM_EVENTS` on having ≥1 HPM counter. Carrying a
  richer persona's yaml down to a smaller one fails validation until they are
  deleted — `udb validate` names each one and its failing condition.
- `mimpid` carries `RTL_VERSION` and nothing else, so it is the **same for every
  persona** — but it is declared twice per persona, in the UDB yaml
  (`IMP_ID_VALUE`, hex) and in `sail.json` (`platform.impid`, decimal), and both
  must move when the version does or `Sm_mcsr-00` fails. The build configuration
  is in `marv_cfg` (0xFFF), a custom CSR no ACT test reads.

## Upstream

Fetched, not vendored — see [`THIRD_PARTY.md`](../../THIRD_PARTY.md).
Pinned revision is set in `bin/fetch_suite.sh`; bump it deliberately, since the
DUT config, generator and test sources move together.
