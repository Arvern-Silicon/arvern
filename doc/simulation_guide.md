<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Simulation Guide
  <br clear="all">
</h1>

This document covers everything you need to run aRVern simulations: prerequisites,
quick-start, the day-to-day commands (`run`, `run_all`, `run_lint`, `run_benchmark`),
the regression, coverage and arch-test flows, and how to dig into waveforms when
something fails. How to *write* a test is in
[`verification_guide.md`](verification_guide.md).

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Repository Layout for Simulation](#2-repository-layout-for-simulation)
3. [Quick Start](#3-quick-start)
4. [Running Tests](#4-running-tests)
5. [Linting](#5-linting)
6. [Benchmarks](#6-benchmarks)
7. [`run_config.json` — the Central Configuration](#7-run_configjson--the-central-configuration)
8. [Waveforms and Debugging](#8-waveforms-and-debugging)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Prerequisites

aRVern's simulation flow needs a Verilog simulator, a RISC-V cross-toolchain to
assemble/compile tests, Python 3 for the runner scripts, and a sibling checkout of
the `arvern-ips` repository.

### 1.1 Required

| Item | Used for | Install (macOS / Homebrew) | Install (Debian/Ubuntu) |
|---|---|---|---|
| **`arvern-ips` checkout** next to `arvern` | The bench filelist (`bench/verilog/submit.f`) pulls the ROM/SRAM controllers, interconnect, peripheral example, custom-CSR block, PLIC, ACLINT and `arv_dtm` from `../arvern-ips/<ip>/rtl/verilog/filelist.f`; without it no test compiles | `git clone https://github.com/Arvern-Silicon/arvern-ips` in the directory that contains `arvern/` | same |
| **Icarus Verilog** (`iverilog`) | Default simulator for all directed tests | `brew install icarus-verilog` | `sudo apt install iverilog` |
| **Verilator** | Default simulator for the C benchmarks; the `./run_lint` flow; coverage (`-cov`, Verilator 5 or later) | `brew install verilator` | `sudo apt install verilator` |
| **xPack RISC-V GCC** (`riscv-none-elf-gcc`) | Assembles every `.s` test and compiles the C benchmarks | xPack installer, see below | xPack installer, see below |
| **Python 3.10+** | All driver scripts | Bundled / `brew install python` | `sudo apt install python3` |

**Why xPack GCC?** aRVern targets `riscv-none-elf` as the canonical newlib-bare-metal
prefix and relies on the xPack distribution by default (`active: xpacks` in
`sim/rtl_sim/run/run_config.json`). It ships with `_zicsr_zifencei` and the full
B/C-extension assembler support needed by the test corpus. Every assembly test
builds with it; no test needs another toolchain.

**xPack install** (macOS, Linux, Windows): download a release from
<https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/> and ensure
`riscv-none-elf-gcc` is on your `$PATH`. Verify with:

```bash
riscv-none-elf-gcc --version
```

### 1.2 Optional

| Tool | Used for | Install |
|---|---|---|
| **GTKWave** | Waveform viewing | `brew install --cask gtkwave` / `sudo apt install gtkwave` |
| **Docker** | Generating the arch-test ELFs (§4.6) | Docker Desktop / `docker.io` |

The `bin/debug/` Python helpers parse VCD files directly; no extra tool is needed.

### 1.3 Python libraries

The core sim flow (`./run`, `./run_all`, `./run_lint`) uses only the Python **standard
library** — no `pip install` needed. Third-party libraries are tiered by what they
unlock:

| Tier | Triggered by | Libraries | Install |
|---|---|---|---|
| Core sim & lint | `./run`, `./run_all`, `./run_lint` | (stdlib only) | — |
| Benchmark traces | `./run_benchmark` (writes `.log.zst`) | `zstandard` | `pip install zstandard` |
| Trace stats / snapshot compare | `benchmark_trace_snapshot`, `bench_compare`, `preprocess.py` | `pandas`, `numpy` (+ `zstandard`) | `pip install zstandard pandas numpy` |
| Interactive web viewer | `benchmark_trace_viewer` (Streamlit dashboard) | everything in `viewer/requirements.txt`: `streamlit`, `plotly`, `pandas`, `numpy`, `numba`, `zstandard` | `pip install -r sim/rtl_sim/bin/benchmark_trace_tools/viewer/requirements.txt` |

Install `zstandard` only when you start using `./run_benchmark`; install the full
viewer stack only when you want the dashboard.

### 1.4 Alternative simulators (already wired in)

The `runsim.py` driver supports several commercial / alternative simulators via the
`VERILOG_SIMULATOR` environment variable. Install whichever you have a licence for
and export the variable before running:

```bash
export VERILOG_SIMULATOR=vcs       # Synopsys VCS
export VERILOG_SIMULATOR=vsim      # Mentor Modelsim / Questa
export VERILOG_SIMULATOR=ncverilog # Cadence NC-Verilog (Xcelium-classic)
export VERILOG_SIMULATOR=verilator # Verilator (note: tests assume iverilog timing)
export VERILOG_SIMULATOR=cver      # GPL Cver
```

Default when the variable is unset: `iverilog`, except that `./run <benchmark>`
and `./run_benchmark` pick `verilator` (the C benchmarks run to hundreds of
millions of ticks). `./run_all` forces `iverilog`; `-cov` forces `verilator`. An
explicit `VERILOG_SIMULATOR` always wins.

### 1.5 Alternative toolchains

`run_config.json` ships three pre-configured toolchain profiles:

| Profile | Prefix | When to use |
|---|---|---|
| `xpacks` (default) | `riscv-none-elf-` | xPack RISC-V GCC (recommended) |
| `gcc` | `riscv64-unknown-elf-` | Build-from-source / `riscv-gnu-toolchain` install |
| `clang` | `riscv32-unknown-elf-` (LLVM) | LLVM/Clang with GCC newlib sysroot — needs LLVM at `/opt/homebrew/opt/llvm/bin/clang` (Homebrew) or equivalent |

Switch by editing the `"active"` key in `sim/rtl_sim/run/run_config.json`.

---

## 2. Repository Layout for Simulation

```
<parent>/
├── arvern-ips/                     Sibling checkout (bus IPs, ACLINT, PLIC, DTM) — required
└── arvern/
    ├── rtl/verilog/                RTL sources (single source of truth)
    ├── bench/verilog/              Testbench infrastructure (tb_arvern.v, probes,
    │                                AHB-bus model, ROM/SRAM stubs, checkers)
    ├── sim/rtl_sim/
    │   ├── src/                    Assembly tests (.s + matching .v testbench)
    │   ├── src-c/                  C benchmarks (coremark, dhrystone, embench)
    │   ├── bin/                    Python drivers, simulator scripts, debug tools
    │   │   ├── debug/              VCD inspection / asphalt trace analysis
    │   │   └── benchmark_trace_tools/  Trace parser, snapshot compare, viewer
    │   └── run/                    Working directory — everything is run from here
    │       ├── run                 Run one test
    │       ├── run_all             Full regression
    │       ├── run_lint            Verilator lint (single config + parameter sweep)
    │       ├── run_benchmark       Compile + run a benchmark; save trace
    │       ├── run_cov / view_cov  Coverage sweep and report viewer
    │       ├── benchmark_trace_snapshot / benchmark_trace_viewer
    │       ├── run_config.json     RTL parameters, toolchain, and the test registry
    │       ├── WORK/               Per-run build directories (see §4.1)
    │       └── log/                Regression logs (see §4.3)
    ├── sim/arch_test/              RISC-V ACT conformance flow (see §4.6)
    └── doc/                        (this guide, integration_guide, ...)
```

**All commands in this guide are run from `sim/rtl_sim/run/`.**

The bench memory map every test runs against (`bench/verilog/ahb_decoder.v`):

| Region | Base | Size | Notes |
|---|---|---|---|
| ROM | `0x2000_0000` | 64 KB | Reset vector; the only region loaded from the test image |
| Executable SRAM | `0x8000_0000` | 64 KB | Scratchpad, zeroed at time 0; a test can alias it over the unmapped space (`sram_x_alias_en`, [Verification Guide §7](verification_guide.md#executable-sram-alias)) |
| Non-executable SRAM | `0x8100_0000` | 64 KB | Load/store only |
| Executable SRAM at 0 | `0x0000_0000` | 4 KB | Present only with `ARV_TB_SRAM_LO_X_EN` (the arch-test flow defines it so a PMP TOR region 0 can be shown to start at 0). Unmapped in the directed flow, whose bus-error tests use address 0 as their faulting address |
| AHB peripherals #0–2 | `0x1004_0000`, `0x1004_1000`, `0x1004_2000` | 128 B each | `ahb_periph_example` |
| ACLINT | `0x0200_0000` | 64 KB | MSWI / MTIMER / SSWI |
| PLIC | `0x0C00_0000` | 4 MB | |

---

## 3. Quick Start

```bash
cd sim/rtl_sim/run

# Single test (feature-complete rtl_config defaults from run_config.json:
# RV32IMCB + S/U + PMP + debug)
./run inst_std_add

# Same test, RV32E (16 integer registers)
./run inst_rv32e_basic -e_mode

# Full regression (all enabled tests, every variant)
./run_all

# Lint
./run_lint

# A benchmark
./run_benchmark dhrystone_4mcu
```

If the first `./run` command produces `SIMULATION PASSED`, your install is good.

### 3.1 Which script do I use?

All entry points read the same `run_config.json`.

| Script | What it does | When to use |
|---|---|---|
| `./run <testname>` | Compile + simulate one or more tests against the current RTL configuration. Leaves the VCD (`tb_arvern.vcd`) and the asphalt trace (`asphalt.log`) in the run dir for debugging. | Daily development — running a specific test, reproducing a failure, debugging with waveforms. |
| `./run_all` | Iterate **every enabled** test in `run_config.json` across the full timing-variant matrix. VCDs and traces disabled. Per-iteration logs land in `log/<N>/`; the aggregated summary is printed at the end. | Pre-commit regression — verifying a change against the whole corpus. |
| `./run_lint` | Run **Verilator `--lint-only`** against the RTL (no simulator binary, no test compile). | Quick RTL syntax / linting after editing files under `rtl/verilog/`. |
| `./run_benchmark <name>` | A wrapper around `./run` specialised for benchmark workflows: VCD off by default, extracts the benchmark score (DMIPS/MHz, CoreMark/MHz, embench timing) from the simulator output, prints a binary-size summary, and saves the execution trace as a compressed `.log.zst` file under `benchmark_traces/latest/`. | Performance measurement — running CoreMark / Dhrystone / embench-iot. |
| `./run_cov`, `./view_cov` | Coverage sweep over three purpose-built RTL configurations; list/open the coverage reports under `cov/`. | Coverage closure (§4.5). |
| `./benchmark_trace_snapshot`, `./benchmark_trace_viewer` | Snapshot the latest benchmark traces for comparison; open the Streamlit dashboard. | See [`benchmarking_guide.md`](benchmarking_guide.md). |

In short: `./run` is the workhorse; `./run_all` is `./run` × every test × every
variant; `./run_lint` skips the simulator entirely; `./run_benchmark` adds the
score-extraction + trace-saving wrapper for benchmarks.

---

## 4. Running Tests

### 4.1 The `./run` command

```bash
./run <testname> [<testname> ...] [flags...]
```

`<testname>` is a `.v` stem under `src/` or a directory under `src-c/`; wildcards
(`./run 'inst_zcmp_*'`) and several names are accepted. Registration in
`run_config.json` supplies the test's `mode`, `requires` and variant filters; an
unregistered test (e.g. `hello_world`, `sandbox`) runs in standard mode. A
registered test whose `requires` is unmet by the current `rtl_config` errors out
and names the unmet expression.

On every run, `runsim.py`:

1. Regenerates `arv_parameterization.v`, `march_config.sh`, and `firmware_config.inc` from `run_config.json`
2. Flattens the bench filelist into `submit_sim.f`
3. Assembles or compiles the test, builds the simulator binary, runs it

`firmware_config.inc` is a generated GNU-`as` include that exposes the active
`rtl_config` to firmware as `.equ CFG_<NAME>, <value>` constants (e.g.
`CFG_SU_MODE_EN`, `CFG_C_EXTENSION`). A `.s` test does `.include "firmware_config.inc"`
to guard config-dependent code. It is regenerated on every call path that produces
`march_config.sh` (default run, work-dir setup, `-rtl_sweep` / `-e_mode`), in the
assembler's CWD so the plain `.include` resolves. See
[§7.1](#71-what-rtl-gets-built-rtl_config-block).

Every run executes in its own `WORK/tmpXXXX/` directory, which holds the build
products (`pmem.s`/`.elf`/`.lst`/`.ihex`, the simulator binary, `stimulus.v`) and
the raw outputs. A single `./run` keeps that directory on pass and fail; regression
keeps failures only; the **next `runsim.py` invocation deletes all of them**.

Artefacts in the run dir after a `./run` (all are symlinks into `WORK/tmp*/` —
copy them out before the next run):

| Artefact | Content | Suppressed by |
|---|---|---|
| `submit_sim.f` | The flattened filelist actually fed to the simulator | — |
| `tb_arvern.vcd` | Waveform | `-nodump` (env `SIMULATION_NODUMP=1`) |
| `asphalt.log` | Per-dispatch instruction trace ([`asphalt_trace_format.md`](asphalt_trace_format.md)) | env `SIMULATION_NOTRACE=1` (`-D NOTRACE`) — set automatically by `run_all`, `-j > 1` and `-rtl_sweep`; **not** by `-nodump` |
| `pitstop.log` | Debug-event trace (`DEBUG_EN=1`) | same switch as `asphalt.log` |

Every run prints `SIMULATION SEED: N`; feed that value back with `-seed N` to
reproduce it.

### 4.2 Flags

Timing-variant flags exercise the same test against different timing / interconnect /
IRQ stimuli. Most are useful only for stress testing; for daily development the
defaults are fine.

| Flag | Effect |
|---|---|
| `-rwsrom` / `-wsrom` | Random / fixed wait states on ROM |
| `-rwsram` / `-wssram` | Random / fixed wait states on SRAM |
| `-rwsper` / `-wsper` | Random / fixed wait states on peripherals |
| `-rsalu` / `-salu` | Random / fixed ALU stalls |
| `-gahb` | Generic AHB-Lite interconnect (deeper than the default); exclusive with `-fahb` |
| `-fahb` | Fused-SRAM AHB controller variant; exclusive with `-gahb` |
| `-rirq` | Random IRQ injection (dropped with a warning on `no_random_irq` tests) |
| `-all` | Run the test across the full 36-variant timing matrix; cannot be combined with individual variant flags. **Deletes `./log` first** |
| `-n N` | Iterations (with `-all`) |
| `-j N` | Parallel workers — accepted only with two or more test names |
| `-disable_ahb_check` | Disable the AHB-Lite protocol checker (**on by default**, unwaived on both buses). For benchmarking throughput; the benchmark flow passes it automatically |
| `-e_mode` | Build RV32E (`RV32E_EN=1`, ilp32e ABI) for this invocation without editing `run_config.json`. Only tests with `requires: "RV32E_EN==1"` run; incompatible with `-rtl_sweep` / `-rtl_config` |
| `-c_mode` | Build with the compressed `-march`. Default without it: the test's `mode` entry (`COMP` → compressed, otherwise standard). Errors if `C_EXTENSION=0` |
| `-seed N` | Pin `$urandom` seed (reproducible runs) |
| `-nodump` | Skip the VCD only; `asphalt.log` is still written |
| `-cov` | Verilator coverage for this test into `cov/single/<test>/` (§4.5) |
| `-rtl_config <N\|persona>` | **Not a timing variant** — build that sweep configuration's RTL, then run the test (§7.4) |
| `-rtl_sweep [--sweep-mode M]` | Run the test under every configuration of the sweep set (§7.4) |
| `-list` / `-list_configs` | Print the recognised test list / the numbered sweep set and exit |

Examples:

```bash
./run inst_std_add -rwsrom -rwsram        # Specific timing variants
./run inst_std_add -all                   # All 36 variants
./run inst_std_add -seed 12345            # Reproduce a specific run
./run trap_smrnmi_excp_preempt -nodump    # No waveform, trace kept
./run inst_std_add inst_std_lui -all -j 2 # Two tests in parallel
```

### 4.3 The `./run_all` regression

```bash
./run_all                 # One iteration, every enabled test, full variant matrix
./run_all -fast -j 10     # Base variant only, 10 parallel workers
./run_all -fast -rirq     # One chosen variant across the whole corpus
./run_all -n 5            # Five iterations
./run_all --stop-on-fail  # Stop on first failure
./run_all --report-show-all  # Report every test, not only failures/timeouts
./run_all -list           # Print the enabled test list and exit
./run_all -dryrun         # Show what would run
./run_all -rtl_sweep      # Regression under every sweep configuration (§7.4)
./run_all -rtl_config 14  # Regression under sweep configuration #14 only
./run_all -cov            # Whole-regression coverage (§4.5)
```

`-fast` (base variant only) accepts the individual timing-variant flags of §4.2 to
run exactly one variant over the corpus. `run_all` forces `iverilog`, disables VCD
and trace, and only runs tests whose `requires` is met — the rest are reported
`SKIPPED`.

Log layout:

| File | Content |
|---|---|
| `log/<N>/<test>-<std\|c>[-<variant>].log` | One simulator log per test × mode × variant, iteration `N` (`-rtl_sweep`: `N` = config index − 1) |
| `log/summary.<N>.log` | Per-iteration summary |
| `regressions_summary.log` (in `run/`) | Multi-iteration summary, written only when `-n > 1` |

`./log` is deleted at the start of every `./run_all` **and** of every
`./run <test> -all`; copy a regression's logs elsewhere before running anything
with `-all`.

Verdicts, as printed on the console for `./run` and classified from the log for
regressions:

| Log string | Status |
|---|---|
| `SIMULATION PASSED` | `PASSED` |
| `SIMULATION FAILED (N errors)` | `FAILED` |
| `SIMULATION FAILED` + `(simulation Timeout)` | `TIMEOUT` — the watchdog fired (§9) |
| `SIMULATION SKIPPED` | `SKIPPED` — `requires` unmet |
| no verdict string (crash, compile error) | `ABORTED` |

The bench also writes its verdict (`PASSED`, `FAILED` or `SKIPPED`) to
`sim_result.txt` in the run directory, and `rtlsim.sh` turns it into the exit status:
a run exits non-zero when it failed or wrote no verdict, so scripts and a multi-test
`./run a b -j N` see the real result (`$finish` alone always exits 0).

### 4.4 Categories of tests

The test-name prefixes (`inst_<ext>_`, `trap_<area>_`, `debug_<area>_`, `csr_`) are
defined in [`verification_guide.md` §2](verification_guide.md#2-test-naming-convention).
Two families need the sibling `arvern-ips` checkout for more than the bus fabric:

| Prefix | What it covers |
|---|---|
| `trap_irq_aclint_*` | Integration tests against [`ahb_aclint`](https://github.com/Arvern-Silicon/arvern-ips/tree/main/ahb_aclint) — MSWI, MTIMER (incl. WFI wake via mtimecmp), SSWI/SETSSIP |
| `trap_irq_plic_*` | Integration tests against [`ahb_plic`](https://github.com/Arvern-Silicon/arvern-ips/tree/main/ahb_plic) — claim/complete, priority arbitration, threshold gating, S-mode (SEIP) delegation, M-vs-S privilege isolation, WFI wake, drain ordering |
| `debug_dtm_*` | End-to-end tests through the [`arv_dtm`](https://github.com/Arvern-Silicon/arvern-ips/tree/main/arv_dtm) transport |

Benchmarks (`coremark`, `dhrystone_*`, `embench_*`) live under `src-c/`.

### 4.5 Coverage

Verilator (5 or later) line/branch/toggle coverage:

```bash
./run <test> -cov          # one test → cov/single/<test>/
./run_all -cov             # whole regression → cov/  (-cov+ accumulates, -cov-as <name> names the run)
./run_cov [-j N]           # the standard sweep: three purpose-built RTL configs (cov_max, cov_stress, cov_alt)
./view_cov [<name>]        # list the databases under cov/ and open one (HTML regenerated when stale)
```

Only the core (`rtl/verilog`) is instrumented: the testbench, the bench SoC's IPs and the
memory models carry no coverage points, which halves the C++ each build compiles.
`SIMULATION_COV_SCOPE=all` instruments the whole bench.

The three `run_cov` configurations (`COVERAGE_CONFIGS` in `bin/rtl_sweep_configs.py`)
between them elaborate every multiplier, divider, branch-latency and reset variant;
budget a night for the full sweep.

### 4.6 Arch-test conformance flow

The RISC-V Architectural Certification Tests (ACT) run from `sim/arch_test/run`,
a second flow that shares the bench and the persona table
(`bin/rtl_sweep_configs.py:PERSONAS`) but not `run_config.json`, the `.s`+`.v`
convention or the timing matrix:

```bash
cd sim/arch_test/run
./run --setup               # once: fetch the pinned suite + pull the ACT image
./run --gen -p <persona>    # generate the ELFs (Docker)
./run -p <persona> [-j N] [test|glob]   # run natively; sim.log per test under run/WORK/arvern-<persona>/tests/
./run --list-personas ; ./run --list-tests
```

Configurations, test counts, the known upstream gap and the flow's dependencies
are in [`sim/arch_test/README.md`](../sim/arch_test/README.md).

---

## 5. Linting

```bash
./run_lint                                # As-built config (run_config.json defaults)
./run_lint --rtl-defaults                 # Bare RTL module-declaration defaults
./run_lint --sweep                        # Full parameterization sweep (all modes)
./run_lint --sweep-mode corners           # Just LO/HI corners (fastest)
./run_lint --sweep-mode xprod             # Just the muldiv x-products
./run_lint -e '--timing'                  # Pass extra flags to verilator
./run_lint -w <file> | -n                 # Alternative waiver file (default waivers.vlt) / no waivers
```

`--sweep-mode <mode>` implies `--sweep` and picks the subset of the sweep set (§7.4):
`all` (default), `corners`, `ofat`, `xprod`, `default`, `personas`, `coverage`.

Verilator-only; requires `verilator` on `$PATH`. Output is the standard verilator
`--lint-only` report plus a per-config PASS/FAIL summary in sweep modes. The
flattened filelist consumed by verilator is dropped at `./submit_lint.f` for
inspection (matches the `submit_sim.f` pattern used by `./run`).

---

## 6. Benchmarks

```bash
./run_benchmark                       # Print the available benchmarks and exit
./run_benchmark dhrystone_4mcu        # Run a single benchmark (mode auto-picked)
./run_benchmark coremark -m std       # Force std (non-compressed) mode
./run_benchmark embench_crc32 -m comp # Force compressed mode
./run_benchmark -a                    # Run ALL benchmarks
./run_benchmark -a -j 8               # Parallel batch (8 workers)
./run_benchmark dhrystone_4mcu --dump # Keep the VCD (off by default for speed)
./run_benchmark coremark --rtl-config performance   # Build a persona first (§7.4)
```

Extra arguments (`-all`, `-c_mode`, …) pass through to `./run`.

**Mode auto-resolution:** `-m auto` (the default) reads `C_EXTENSION` from
`run_config.json` and picks `comp` if it's ≥ 1, otherwise `std`. An explicit
`-m std` / `-m comp` bypasses this and is honoured verbatim. The chosen mode is
printed on a status line at the start of the run.

Score + binary-size summary are printed at the end. The execution trace is
saved to `benchmark_traces/latest/trace_<test>_<mode>_<rtl-config>_<toolchain>_<variant>_<timestamp>.log.zst`
for later inspection or comparison.

Benchmark snapshots (for cross-config comparisons) live under
`benchmark_traces/snapshots/`. Scores, personas, the snapshot workflow and the
viewer are in [`benchmarking_guide.md`](benchmarking_guide.md).

---

## 7. `run_config.json` — the Central Configuration

Every command in this guide reads `sim/rtl_sim/run/run_config.json`. It is the
**single source of truth** for three things, all driven by the same file:

### 7.1 What RTL gets built (`rtl_config` block)

Every parameter from `arvern.v` is listed here with its default and the set of
legal values:

```json
"rtl_config": {
    "RV32E_EN":     { "default": 0, "allowed": [0, 1],         "description": "..." },
    "M_EXTENSION":  { "default": 2, "allowed": [0, 1, 2],      "description": "..." },
    "C_EXTENSION":  { "default": 4, "allowed": [0, 1, 2, 3, 4],"description": "..." },
    ...
}
```

On every `./run` invocation, `runsim.py` re-renders `arv_parameterization.v`
(RTL parameters), `march_config.sh` (the `-march=` string), and
`firmware_config.inc` (the `.equ CFG_<NAME>` firmware include, see §4.1) from
this block. **To change the RTL configuration, edit a `default` here and
re-run `./run`** — there is no separate "build" step. The defaults are the
feature-complete regression configuration, which differs from the `arvern.v`
module defaults (the `classic` persona).

See [`integration_guide.md`](integration_guide.md#1-configuration-parameters) for
what each parameter actually does in hardware.

### 7.2 What toolchain compiles the tests (`toolchain` block)

```json
"toolchain": {
    "active": "xpacks",
    "profiles": {
        "xpacks": { "prefix": "riscv-none-elf", ... },
        "gcc":    { "prefix": "riscv64-unknown-elf", ... },
        "clang":  { "prefix": "riscv32-unknown-elf", "cc": "/opt/.../clang ..." }
    },
    "build_config": {
        "OPTIMIZATION":    { "default": "-O2",    "allowed": ["-Os", "-O2", "-O3"] },
        "LIBC":            { "default": "newlib", "allowed": ["newlib", "newlib-nano"] },
        "RODATA_LOCATION": { "default": "ROM",    "allowed": ["ROM", "SRAM"] }
    }
}
```

Firmware-build axes under `toolchain.build_config`:

| Axis | Default | Allowed | Effect |
|---|---|---|---|
| `OPTIMIZATION` | `-O2` | `-Os` / `-O2` / `-O3` | Compiler `-O` level (emitted as the `TC_OPT` env var). Per-test `optimization` overrides still win. |
| `LIBC` | `newlib` | `newlib` / `newlib-nano` | C library — `newlib-nano` adds `--specs=nano.specs` (smaller printf/malloc/softfloat). |
| `RODATA_LOCATION` | `ROM` | `ROM` / `SRAM` | `.rodata` placement — `ROM` (next to `.text`) or `SRAM` (mirrored at boot via a dedicated crt0 + linker script). |

The active profile + `rtl_config` together drive the auto-generated
`march_config.sh` (the `-march=` string fed to gcc) and the chosen `gcc` /
`objcopy` / `objdump` / `size` binaries.

### 7.3 What tests exist and when they apply (`tests` block)

The test registry — every test that `./run`, `./run_all`, and `./run_benchmark`
know about:

```json
{ "name": "inst_zca_lwsp", "enabled": true, "mode": "BOTH",
  "requires": "C_EXTENSION>=1", ... }
```

The full field reference is
[`verification_guide.md` §5](verification_guide.md#5-registering-a-test-in-run_configjson).
What the runner does with the gating fields:

- `requires` is evaluated against the active `rtl_config`; an unmet expression
  skips the test in regression and is an error for a direct `./run`. A malformed
  expression is an error at load — it never silently passes.
- Two gates are implicit: `mode: COMP` adds `C_EXTENSION>=1`, and every
  non-benchmark test whose `requires` does not name `RV32E_EN` gets `RV32E_EN==0`
  (so it is skipped under `-e_mode`).
- `mode` and `enabled` default to `STD` and `true` when absent.
- `no_random_irq`, `no_variants`, `no_rsalu`, `no_rwsrom`, `no_fahb` filter the
  variant matrix for that test; `variants: "light"` reduces it to the base variant
  plus one with every random delay.

### 7.4 Multi-config sweeping

`bin/rtl_sweep_configs.py` defines a finite **sweep set** over the `rtl_config`
block: `default`, the LO/HI `corners`, `ofat` (one factor at a time), `xprod`
(mul/div cross-products) and the eight `personas` (`light`, `classic`,
`performance`, `ultra` and their `-dbg` twins). `--sweep-mode all` is their union;
the three `coverage` configurations (`cov_max`, `cov_stress`, `cov_alt`) are reachable
only by name. The same set is consumed by:

```bash
./run_all -rtl_sweep [--sweep-mode M]   # Rebuild the RTL per configuration, rerun the regression under each
./run <test> -rtl_sweep                 # Same, for one test
./run_lint --sweep [--sweep-mode M]     # Lint every configuration
./run_all -list_configs                 # Print the numbering
```

Because the sweep generator is the single source of truth, a lint sweep and a
sim sweep cover the same RTL configurations by construction. A sweep does not add
timing variants; per configuration, the test list is filtered by `requires`.

To reproduce one configuration, pass its 1-based index or its name to
`-rtl_config` (`./run`, `./run_all`, `./run_benchmark --rtl-config`): `14`,
`classic`, `ultra-dbg`, `cov_stress`. With a single test, `./run -rtl_config`
streams the log and keeps the VCD and trace like a plain `./run`; timing-variant
flags, `-seed` and `-all` combine with it.

---

## 8. Waveforms and Debugging

A `./run` leaves two artefacts (lifetimes and switches in §4.1):

- **`tb_arvern.vcd`** — full waveform dump. Tick resolution 100 ps; default clock 1 MHz (period 1000 ns = 10000 ticks).
- **`asphalt.log`** — one line per dispatched instruction (cycle, time, PC, instr,
  mnemonic, mem op, reg dest, size, branch, trap, priv). Full column-by-column
  spec, trailing-annotation catalogue, and snapshot file layout in
  [`asphalt_trace_format.md`](asphalt_trace_format.md).

Two bench mechanisms fail a run without the test's own checks: `error_on_exception`
(reset value 1) counts every synchronous exception as an error unless the test
clears it, and the instruction/PC checker compares each instruction dispatched
from ROM with the objdump listing and fails on an unexpected PC. Both are described
in [`verification_guide.md` §1](verification_guide.md#1-test-architecture).
Addresses in the trace and VCD map to the bench memory map in §2.

### 8.1 Opening the waveform

```bash
gtkwave tb_arvern.vcd load_waveforms.gtkw
```

`load_waveforms.gtkw` is a pre-configured save file with the standard signal
groupings (pipeline stages, AHB buses, IRQ/trap signals).

### 8.2 Debug helper scripts (run from `sim/rtl_sim/run/`)

For programmatic / scripted inspection, **prefer the dedicated helpers in
`bin/debug/`** over ad-hoc grep pipelines — they handle Zcmp multi-mem ops,
livelock heuristics, VCD signal-name resolution, and clock-period auto-detection.
The `asphalt_*` scripts work after a `-nodump` run; the `vcd_*` scripts need the VCD.

| Script | Use for |
|---|---|
| `python3 ../bin/debug/asphalt_summary.py` | Trace stats, trap/MRET counts, livelock detection. **First thing to run on any failure.** |
| `python3 ../bin/debug/asphalt_context.py --trap N --before 20` | N instructions around a trap / MRET / cycle / PC anchor |
| `python3 ../bin/debug/asphalt_diff.py pass.log fail.log` | First PC divergence between two runs |
| `python3 ../bin/debug/asphalt_annotate.py asphalt.log tb_arvern.vcd <sigs...> --cycles A:B` | Fuse firmware trace with VCD signal values per dispatch cycle |
| `python3 ../bin/debug/vcd_trace.py tb_arvern.vcd <sigs...> --cycles A:B` | Signal table over a cycle range (use `--list` / `--grep <pat>` to discover names). Workhorse tool. |
| `python3 ../bin/debug/vcd_find.py tb_arvern.vcd <sig> --rise` | Find every rising/falling edge or `--value` match for a signal |
| `python3 ../bin/debug/vcd_cause.py tb_arvern.vcd <sig> --cycle N --depth 2` | Recursive driver tree at a cycle, walking the hand-maintained graph `bin/debug/cause_tree.json` |
| `python3 ../bin/debug/vcd_gtkwave.py tb_arvern.vcd <sigs...> --cycles A:B --out dbg.gtkw` | Generate pre-zoomed GTKWave save file |

Signal names accept hierarchical form (`tb_arvern.dut.arv_fetch_inst.consume_inst`)
or any unique short suffix (`consume_inst`).

Full reference: [`sim/rtl_sim/bin/debug/DEBUG_MANUAL.md`](../sim/rtl_sim/bin/debug/DEBUG_MANUAL.md).

---

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `submit_sim.f` cannot be flattened / `arvern-ips` filelists not found | No sibling `arvern-ips` checkout | Clone it next to `arvern/` (§1.1) |
| `riscv-none-elf-gcc: command not found` | xPack toolchain not on `$PATH` | Add the xPack `bin/` to your `$PATH`, or switch `"active"` in `run_config.json` to `"gcc"` / `"clang"` |
| `iverilog: command not found` | Icarus Verilog not installed | `brew install icarus-verilog` (macOS) or distro equivalent |
| `Verilator unknown option …` (during lint or `-cov`) | Verilator too old | Verilator 5 or later is required; check `verilator --version` |
| `SIMULATION FAILED (simulation Timeout)` / status `TIMEOUT` | The test livelocked, or legitimately exceeds the watchdog | The watchdog fires at 50 ms of simulated time (50 000 cycles). `` `define LONG_TIMEOUT`` at the top of the test `.v` raises it to 500 ms (set automatically for `-rirq` and `debug_dtm_*`), `VERY_LONG_TIMEOUT` to 5 s, `NO_TIMEOUT` disables it. Run `asphalt_summary.py` to spot a livelock |
| `[ERROR] Test … cannot run with current RTL configuration` on `./run` | Test's `requires:` clause unmet | Enable the required extension in `rtl_config`, or use `-rtl_config <persona>` |
| `Test … SKIPPED` in regression | Same, in regression | Accept the skip or change `rtl_config` |
| `Warning: Benchmark pattern '…' did not match in …` | A benchmark log is incomplete (`ABORTED`-class) | Delete the stale log under `log/0/<name>.log` and re-run |
| Score drift between `-m std` and `-m comp` | Expected — comp-mode benchmarks fetch fewer bytes per instruction | Use the same `-m` flag for like-for-like comparisons |

For obscure regressions, the canonical bisection is `asphalt_diff.py` between a
known-good and a known-bad seed. `asphalt.log` is a symlink into `WORK/`, so copy
it (`cp -L`), never `mv` it:

```bash
./run inst_X -seed 1 -nodump
cp -L asphalt.log good.log
./run inst_X -seed 2 -nodump
python3 ../bin/debug/asphalt_diff.py good.log asphalt.log | head -20
```

---

## See Also

- [`verification_guide.md`](verification_guide.md) — writing and registering tests, the `x31` sync protocol, variant policy
- [`integration_guide.md`](integration_guide.md) — parameter reference, port descriptions, AHB/IRQ/NMI/CCSR interface contracts
- [`memory_and_ahb.md`](memory_and_ahb.md) — bus behaviour the bench models
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — implementation choices in UNSPECIFIED / implementation-defined cases + a few acknowledged gray-area choices
- [`arvern_instructions.md`](arvern_instructions.md) — supported instruction set
- [`asphalt_trace_format.md`](asphalt_trace_format.md) — per-instruction trace file format spec (columns, annotations, snapshot layout)
- [`benchmarking_guide.md`](benchmarking_guide.md) — benchmark scores, personas, trace snapshots and viewer
- [`../sim/arch_test/README.md`](../sim/arch_test/README.md) — arch-test configurations and results
- [`../sim/rtl_sim/bin/debug/DEBUG_MANUAL.md`](../sim/rtl_sim/bin/debug/DEBUG_MANUAL.md) — full debug-tool reference
