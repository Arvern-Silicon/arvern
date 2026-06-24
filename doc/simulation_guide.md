<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Simulation Guide
  <br clear="all">
</h1>

This document covers everything you need to run aRVern simulations: prerequisites,
quick-start, the day-to-day commands (`run`, `run_all`, `run_lint`, `run_benchmark`),
and how to dig into waveforms when something fails.

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

aRVern's simulation flow has three groups of tools: a Verilog simulator, a RISC-V
cross-toolchain to assemble/compile tests, and Python 3 for the runner scripts.

### 1.1 Required

| Tool | Used for | Install (macOS / Homebrew) | Install (Debian/Ubuntu) |
|---|---|---|---|
| **Icarus Verilog** (`iverilog`) | Default simulator | `brew install icarus-verilog` | `sudo apt install iverilog` |
| **xPack RISC-V GCC** (`riscv-none-elf-gcc`) | Default toolchain — assembles `.s` tests and compiles C benchmarks | xPack installer, see below | xPack installer, see below |
| **Python 3.10+** | All driver scripts | Bundled / `brew install python` | `sudo apt install python3` |

**Why xPack GCC?** aRVern targets `riscv-none-elf` as the canonical newlib-bare-metal
prefix and relies on the xPack distribution by default (`active: xpacks` in
`sim/rtl_sim/run/run_config.json`). It ships with `_zicsr_zifencei` and the full
B/C-extension assembler support needed by the test corpus.

**xPack install** (macOS, Linux, Windows): download the latest release from
<https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/> and ensure
`riscv-none-elf-gcc` is on your `$PATH`. Verify with:

```bash
riscv-none-elf-gcc --version
```

### 1.2 Optional

| Tool | Used for | Install |
|---|---|---|
| **Verilator** | `./run_lint` flow (Verilator-only) | `brew install verilator` / `sudo apt install verilator` |
| **GTKWave** | Waveform viewing | `brew install --cask gtkwave` / `sudo apt install gtkwave` |
| **VCD / fst tools** | Some `debug/` Python helpers parse VCD directly; no extra tool needed | — |

### 1.3 Python libraries

The core sim flow (`./run`, `./run_all`, `./run_lint`) uses only the Python **standard
library** — no `pip install` needed. Third-party libraries are tiered by what they
unlock:

| Tier | Triggered by | Libraries | Install |
|---|---|---|---|
| Core sim & lint | `./run`, `./run_all`, `./run_lint` | (stdlib only) | — |
| Benchmark traces | `./run_benchmark` (writes `.log.zst`) | `zstandard` | `pip install zstandard` |
| Trace stats / snapshot compare | `bench_snapshot.py`, `bench_compare.py`, `preprocess.py` | `pandas`, `numpy` (+ `zstandard`) | `pip install zstandard pandas numpy` |
| Interactive web viewer | `benchmark_trace_tools/viewer/app.py` (Streamlit dashboard) | everything in `viewer/requirements.txt`: `streamlit`, `plotly`, `pandas`, `numpy`, `numba`, `zstandard` | `pip install -r sim/rtl_sim/bin/benchmark_trace_tools/viewer/requirements.txt` |

In a fresh checkout, you can run `./run`, `./run_all`, and `./run_lint` immediately
after installing iverilog / verilator / xPack GCC — no pip required. Install
`zstandard` first only when you start using `./run_benchmark`; install the full
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

Default (when `VERILOG_SIMULATOR` is unset): `iverilog`.

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
arvern/
├── rtl/verilog/                    RTL sources (single source of truth)
├── bench/verilog/                  Testbench infrastructure (tb_arvern.v, probes,
│                                    AHB-bus model, ROM/SRAM stubs)
├── sim/rtl_sim/
│   ├── src/                        Assembly tests (.s + matching .v testbench)
│   ├── src-c/                      C benchmarks (coremark, dhrystone, embench)
│   ├── bin/                        Python drivers, simulator scripts, debug tools
│   │   └── debug/                  VCD inspection / asphalt trace analysis
│   └── run/                        Working directory — everything is run from here
│       ├── run                     Run one test
│       ├── run_all                 Full regression
│       ├── run_lint                Verilator lint (single config + parameter sweep)
│       ├── run_benchmark           Compile + run a benchmark; save trace
│       └── run_config.json         RTL parameters, toolchain, and the test registry
└── doc/                            (this guide, integration_guide, ...)
```

**All commands in this guide are run from `sim/rtl_sim/run/`.**

---

## 3. Quick Start

```bash
cd sim/rtl_sim/run

# Single test (RV32IMC defaults from run_config.json)
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

There are four user-facing entry points; they all read the same `run_config.json`
but serve different daily-development purposes.

| Script | What it does | When to use |
|---|---|---|
| `./run <testname>` | Compile + simulate **one** test against the current RTL configuration. Keeps the VCD (`tb_arvern.vcd`) and the asphalt trace (`asphalt.log`) in the run dir for debugging. | Daily development — running a specific test, reproducing a failure, debugging with waveforms. |
| `./run_all` | Iterate **every enabled** test in `run_config.json` across the full timing-variant matrix. VCDs disabled by default (regression speed). Per-iteration logs land in `log/<N>/`; the aggregated summary is printed at the end. | Pre-commit regression — verifying a change against the whole corpus. |
| `./run_lint` | Run **Verilator `--lint-only`** against the RTL (no simulator binary, no test compile). | Quick RTL syntax / linting after editing files under `rtl/verilog/`. |
| `./run_benchmark <name>` | A **wrapper around `./run`** specialised for benchmark workflows: VCD off by default (for speed), extracts the benchmark score (DMIPS/MHz, CoreMark/MHz, embench timing) from the simulator output, prints a binary-size summary, and saves the execution trace as a compressed `.log.zst` file under `benchmark_traces/latest/`. The compressed trace can later be replayed by the analysis / dashboard tools in `bin/benchmark_trace_tools/`. | Performance measurement — running CoreMark / Dhrystone / embench-iot. |

In short: `./run` is the workhorse; `./run_all` is `./run` × every test × every
variant; `./run_lint` skips the simulator entirely; `./run_benchmark` adds the
score-extraction + trace-saving wrapper for benchmarks. Everything else (sweeps,
benchmark snapshots, the web viewer) builds on these four.

---

## 4. Running Tests

### 4.1 The `./run` command

```bash
./run <testname> [variant flags...]
```

`<testname>` is any test registered in `run_config.json` (and present under
`src/` or `src-c/`). On every run, `runsim.py`:

1. Regenerates `arv_parameterization.v` and `march_config.sh` from `run_config.json`
2. Flattens the bench filelist into `submit_sim.f` (symlinked from the per-test WORK dir)
3. Assembles or compiles the test, builds the simulator binary, runs it

Outputs (left in the run dir after success):
- `submit_sim.f` — the flattened filelist actually fed to the simulator
- `tb_arvern.vcd` — waveform (unless `-nodump` is passed)
- `asphalt.log` — per-cycle dispatched-instruction trace

### 4.2 Variant flags

Variant flags exercise the same test against different timing / interconnect /
IRQ stimuli. Most are useful only for stress testing; for daily development the
defaults are fine.

| Flag | Effect |
|---|---|
| `-rwsrom` / `-wsrom` | Random / fixed wait states on ROM |
| `-rwsram` / `-wssram` | Random / fixed wait states on SRAM |
| `-rwsper` / `-wsper` | Random / fixed wait states on peripherals |
| `-rsalu` / `-salu` | Random / fixed ALU stalls |
| `-gahb` | Generic AHB-Lite interconnect (deeper than the default) |
| `-fahb` | Fused-SRAM AHB controller variant |
| `-rirq` | Random IRQ injection |
| `-e_mode` | Build the test for RV32E (requires `RV32E_EN==1` in `run_config.json`) |
| `-c_mode` | Force compressed-mode build (default mode is derived from `C_EXTENSION`) |
| `-seed N` | Pin `$urandom` seed (reproducible runs) |
| `-nodump` | Skip VCD generation (faster for regression-style runs) |
| `-all` | Run the test across the full timing-variant matrix |

Examples:

```bash
./run inst_std_add -rwsrom -rwsram        # Specific timing variants
./run inst_std_add -all                   # All variants (matrix of ~36)
./run inst_std_add -seed 12345            # Reproduce a specific run
./run trap_smrnmi_excp_preempt -nodump    # Fast deterministic run (no waveform)
```

### 4.3 The `./run_all` regression

```bash
./run_all                 # One iteration, every enabled test, full variant matrix
./run_all -fast -j 10     # Base variant only (~36× faster), 10 parallel workers
./run_all -n 5            # Five iterations
./run_all --stop-on-fail  # Stop on first failure
./run_all -list           # Print the enabled test list and exit
```

Results land in `log/<iteration>/`. The aggregated summary report (PASSED / FAILED /
SKIPPED / TIMEOUT / ABORTED counts) is printed at the end.

### 4.4 Categories of tests

| Prefix | What it covers |
|---|---|
| `inst_std_*` | Base RV32I instructions (`add`, `lw`, `bne`, …) |
| `inst_m_*` | M-extension (mul/div) |
| `inst_zbb_*`, `inst_zba_*`, `inst_zbs_*`, `inst_zbc_*` | B-extension sub-extensions |
| `inst_zca_*`, `inst_zcb_*`, `inst_zcmp_*`, `inst_zcmt_*` | C-extension sub-extensions |
| `inst_csr_*`, `inst_zicntr_*`, `inst_zihpm_*` | CSR / counter behaviour |
| `inst_rv32e_*` | RV32E reduced register set (run with `-e_mode`) |
| `trap_*` | Synchronous exceptions, IRQs, NMI (`Smrnmi`), S-mode delegation |
| `trap_irq_aclint_*` | Integration tests against the bundled [`ahb_aclint`](https://github.com/Arvern-Silicon/arvern-ips/tree/main/ahb_aclint) IP — MSWI, MTIMER (incl. WFI wake via mtimecmp), SSWI/SETSSIP |
| `trap_irq_plic_*` | Integration tests against the bundled [`ahb_plic`](https://github.com/Arvern-Silicon/arvern-ips/tree/main/ahb_plic) IP — claim/complete, priority arbitration, threshold gating, S-mode (SEIP) delegation, M-vs-S privilege isolation, WFI wake, drain ordering |
| `csr_*` | CSR field-level edge cases |
| Benchmarks (`coremark`, `dhrystone_*`, `embench_*`) | Live under `src-c/` and report DMIPS/CoreMark/MHz |

The full test registry — including per-test `requires:` clauses (`C_EXTENSION>=1`,
`NMI_EN==1`, etc.) — is in `run_config.json`. Tests whose `requires:` is unmet by
the current RTL config are automatically skipped.

---

## 5. Linting

```bash
./run_lint                                # As-built config (run_config.json defaults)
./run_lint --rtl-defaults                 # Bare RTL module-declaration defaults
./run_lint --sweep                        # Full parameterization sweep (all modes)
./run_lint --sweep-mode corners           # Just LO/HI corners (fastest)
./run_lint --sweep-mode xprod             # Just the muldiv x-products
./run_lint -e '--timing'                  # Pass extra flags to verilator
```

Verilator-only; requires `verilator` on `$PATH`. Output is the standard verilator
`--lint-only` report plus a per-config PASS/FAIL summary in sweep modes.

The sweep set is the **single source of truth** shared with the simulation-side
`./run_all -rtl_sweep` regression (`sim/rtl_sim/bin/rtl_sweep_configs.py`), so a
lint pass and a sim pass cover the same RTL configurations by construction.

The flattened filelist consumed by verilator is dropped at `./submit_lint.f` for
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
```

**Mode auto-resolution:** `-m auto` (the default) reads `C_EXTENSION` from
`run_config.json` and picks `comp` if it's ≥ 1, otherwise `std`. An explicit
`-m std` / `-m comp` bypasses this and is honoured verbatim. The chosen mode is
printed on a status line at the start of the run.

Score + binary-size summary are printed at the end. The execution trace is
saved to `benchmark_traces/latest/trace_<test>_<mode>_<rtl-config>_<toolchain>_<variant>_<timestamp>.log.zst`
for later inspection or comparison.

Benchmark snapshots (for cross-config comparisons) live under
`benchmark_traces/snapshots/`. The viewer and snapshot helpers are in
`bin/benchmark_trace_tools/`.

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
from this block. **To change the RTL configuration, edit a `default` here and
re-run `./run`** — there is no separate "build" step.

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
    "optimization": "-O3"
}
```

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

Per-entry fields:

| Field | Effect |
|---|---|
| `name` | The testname you pass to `./run` |
| `enabled` | Toggle without deleting the entry |
| `mode` | `STD`, `COMP`, or `BOTH` — which instruction-mode variants to build |
| `requires` | Expression like `C_EXTENSION>=1`, `NMI_EN==1`, `RV32E_EN==1`. Tests whose `requires` isn't satisfied by the current `rtl_config` defaults are **auto-skipped** in regression. |
| `is_benchmark` | Marks a test as a benchmark — visible to `./run_benchmark`, score-extraction is enabled |
| `no_random_irq` | Suppresses random IRQ injection (for timing-sensitive sequencing tests) |
| `no_variants` | Don't run this test under the timing-variant matrix (base variant only) |
| `description` | One-line note shown in regression reports |

### 7.4 Multi-config sweeping

`bin/rtl_sweep_configs.py` defines a finite **sweep set** (default / corners /
ofat / xprod) over the `rtl_config` block. The same set is consumed by:

```bash
./run_all -rtl_sweep         # Sim sweep — every config × every enabled test
./run_lint --sweep           # Lint sweep — every config, verilator-only
```

Because the sweep generator is the single source of truth, a lint sweep and a
sim sweep are guaranteed to cover the same RTL configurations by construction.

Multi-config sweeping (every flag combination across the sweep set):

```bash
./run_all -rtl_sweep         # Sim sweep
./run_lint --sweep           # Lint sweep — same config set
```

The sweep set is defined in `bin/rtl_sweep_configs.py` (default / corners / ofat /
xprod). It is **shared** between `./run_all -rtl_sweep` and `./run_lint --sweep` so
the two are guaranteed to test the same configurations.

---

## 8. Waveforms and Debugging

Two parallel artefacts are produced on every run (unless `-nodump` is passed):

- **`tb_arvern.vcd`** — full waveform dump. Timescale 100 ps; default clock 1 MHz.
- **`asphalt.log`** — one line per dispatched instruction (cycle, PC, instr,
  mnemonic, mem op, reg dest, size, branch, trap, priv). Full column-by-column
  spec, trailing-annotation catalogue, and snapshot file layout in
  [`asphalt_trace_format.md`](asphalt_trace_format.md).

### 8.1 Opening the waveform

```bash
gtkwave tb_arvern.vcd load_waveforms.gtkw
```

`load_waveforms.gtkw` is a pre-configured save file with the standard signal
groupings (pipeline stages, AHB buses, IRQ/trap signals).

### 8.2 Debug helper scripts (run from `sim/rtl_sim/run/` after a non-`-nodump` test)

For programmatic / scripted inspection, **prefer the dedicated helpers in
`bin/debug/`** over ad-hoc grep pipelines — they handle Zcmp multi-mem ops,
livelock heuristics, VCD signal-name resolution, and clock-period auto-detection.

| Script | Use for |
|---|---|
| `python3 ../bin/debug/asphalt_summary.py` | Trace stats, trap/MRET counts, livelock detection. **First thing to run on any failure.** |
| `python3 ../bin/debug/asphalt_context.py --trap N --before 20` | N instructions around a trap / MRET / cycle / PC anchor |
| `python3 ../bin/debug/asphalt_diff.py pass.log fail.log` | First PC divergence between two runs |
| `python3 ../bin/debug/asphalt_annotate.py asphalt.log tb_arvern.vcd <sigs...> --cycles A:B` | Fuse firmware trace with VCD signal values per dispatch cycle |
| `python3 ../bin/debug/vcd_trace.py tb_arvern.vcd <sigs...> --cycles A:B` | Signal table over a cycle range (use `--list` / `--grep <pat>` to discover names). Workhorse tool. |
| `python3 ../bin/debug/vcd_find.py tb_arvern.vcd <sig> --rise` | Find every rising/falling edge or `--value` match for a signal |
| `python3 ../bin/debug/vcd_cause.py tb_arvern.vcd <sig> --cycle N --depth 2` | Recursive driver tree at a cycle (`cause_tree.json`) |
| `python3 ../bin/debug/vcd_gtkwave.py tb_arvern.vcd <sigs...> --cycles A:B --out dbg.gtkw` | Generate pre-zoomed GTKWave save file |

Signal names accept hierarchical form (`tb_arvern.dut.arv_fetch_inst.consume_inst`)
or any unique short suffix (`consume_inst`).

Full reference: [`sim/rtl_sim/bin/debug/DEBUG_MANUAL.md`](../sim/rtl_sim/bin/debug/DEBUG_MANUAL.md).

---

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `riscv-none-elf-gcc: command not found` | xPack toolchain not on `$PATH` | Add the xPack `bin/` to your `$PATH`, or switch `"active"` in `run_config.json` to `"gcc"` / `"clang"` |
| `iverilog: command not found` | Icarus Verilog not installed | `brew install icarus-verilog` (macOS) or distro equivalent |
| `Verilator unknown option …` (during lint) | Verilator too old | aRVern targets Verilator 5.x; check `verilator --version` |
| `SIMULATION SEED ... no $finish, hung` | A test livelocked | Run with `-nodump` first to see if it's a VCD-IO bottleneck; then `asphalt_summary.py` to spot the livelock pattern |
| `Test … SKIPPED` in regression | Test's `requires:` clause unmet by current RTL config | Either enable the required extension in `rtl_config`, or accept the skip |
| `Warning: Benchmark pattern '…' did not match in …` | A benchmark log is incomplete (`ABORTED`-class) | Delete the stale log under `log/0/<name>.log` and re-run |
| Score drift between `-m std` and `-m comp` | Expected — comp-mode benchmarks fetch fewer bytes per instruction | Use the same `-m` flag for like-for-like comparisons |

For obscure regressions, the canonical bisection is `asphalt_diff.py` between a
known-good and a known-bad seed:

```bash
./run inst_X -seed 1 -nodump
mv asphalt.log good.log
./run inst_X -seed 2 -nodump
python3 ../bin/debug/asphalt_diff.py good.log asphalt.log | head -20
```

---

## See Also

- [`integration_guide.md`](integration_guide.md) — parameter reference, port descriptions, AHB/IRQ/NMI/CCSR interface contracts
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — implementation choices in UNSPECIFIED / implementation-defined cases + a few acknowledged gray-area choices
- [`arvern_instructions.md`](arvern_instructions.md) — supported instruction set
- [`asphalt_trace_format.md`](asphalt_trace_format.md) — per-instruction trace file format spec (columns, annotations, snapshot layout)
- [`../sim/rtl_sim/bin/debug/DEBUG_MANUAL.md`](../sim/rtl_sim/bin/debug/DEBUG_MANUAL.md) — full debug-tool reference
