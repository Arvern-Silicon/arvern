<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Area &amp; Performance Methodology
  <br clear="all">
</h1>
---

## Table of Contents

**Part I — Results**

1. [Introduction](#1-introduction)
2. [Area Results](#2-area-results)
3. [Performance Results — Headline Speeds](#3-performance-results--headline-speeds)
4. [Performance Sensitivity Studies](#4-performance-sensitivity-studies)
5. [Per-Benchmark Detail](#5-per-benchmark-detail)

**Part II — Methodology**

6. [How Each Benchmark Works](#6-how-each-benchmark-works)
7. [Score Extraction & Sensitivity Knobs](#7-score-extraction--sensitivity-knobs)
8. [Trace Artefacts & Snapshot Workflow](#8-trace-artefacts--snapshot-workflow)

---

## 1. Introduction

The four bundled benchmarks (§1.1) and four reference personas (§1.2). Results start in §2.

### 1.1 Benchmarks at a Glance

| Benchmark | Score metric | Source |
|---|---|---|
| **CoreMark** | CoreMark/MHz | EEMBC CoreMark, port under `sim/rtl_sim/src-c/coremark/arv/` |
| **Dhrystone v2.1** | DMIPS/MHz | Standard Dhrystone, `dhrystone_v2.1/` |
| **Dhrystone 4mcu** | DMIPS/MHz | Modified Dhrystone for MCU workloads, `dhrystone_4mcu/` |
| **Embench-IoT** (22 sub-benchmarks) | ms / iteration | `embench_*/` directories |

All bundled under `sim/rtl_sim/src-c/`. Each has its own startup, its own
`Makefile`-equivalent path through `c2ihex.sh`, and its own oracle (a
`.v` testbench file in `sim/rtl_sim/src/`).

---

### 1.2 aRVern Personas

As the aRVern parameterization space is relatively big, four "typical" personas have been defined in `bin/rtl_sweep_configs.py:PERSONAS`
as reference configurations to help comparing the area and benchmark results with other cores:

| Parameter | **Light** | **Classic** | **Performance** | **Ultra** |
|---|:---:|:---:|:---:|:---:|
| `RV32E_EN` | 1 (RV32E) | 0 (RV32I) | 0 (RV32I) | 0 (RV32I) |
| `M_EXTENSION` | 1 (Zmmul) | 1 (Zmmul) | 2 (M = mul+div) | 2 (M = mul+div) |
| `MUL_TYPE` | 3 (16-cycle) | 1 (1-cycle) | 1 (1-cycle) | 1 (1-cycle) |
| `DIV_TYPE` | — | — | 1 (radix-8, 12-cycle) | 1 (radix-8, 12-cycle) |
| `B_EXTENSION` | 0 (none) | 1 (Zbb) | 4 (Zbb+Zba+Zbs+Zbc) | 4 (Zbb+Zba+Zbs+Zbc) |
| `C_EXTENSION` | 1 (Zca) | 1 (Zca) | 2 (Zca+Zcb) | 4 (Zca+Zcb+Zcmp+Zcmt) |
| `NMI_EN` | 0 | 0 | 0 | 1 |
| `SU_MODE_EN` | 0 (M-only) | 1 (M+S+U) | 1 (M+S+U) | 1 (M+S+U) |
| `ZICNTR_EN` | 0 | 1 | 1 | 1 |
| `ZIHPM_NR` | 0 | 0 | 0 | 4 |
| `CCSR_EN` | 0 | 0 | 0 | 0 |
| `SINGLE_CYCLE_BRANCH` | 1 | 1 | 1 | 1 |
| `ASYNC_RST_EN` | 1 | 1 | 1 | 1 |
| **Role** | "smal CPU — RV32E + 16c Zmmul + Zca + M-mode only (no S/U)" | "mid-range CPU — matches aRVern parameter defaults; M+S+U" | "perf-pure compute target: same engine as Ultra, no SoC-integration overhead (no NMI / Zihpm), no UOP-sequencer-bearing extensions (no Zcmp / Zcmt); M+S+U" | "feature-rich target: full B + full C + Zicntr + Zihpm + Smrnmi NMI on the same perf engine as Performance; M+S+U" |

> The personas exist as documented anchor points spanning the area / performance
> ladder and as the configurations the published numbers in §§2-5 are measured on.
> **Any other parameter configurations is first-class supported.** The integrator would then need to runs their own
> synthesis and benchmark sweeps to characterise them.
>
> The relevant knobs and how each one moves area/perf are documented in [`integration_guide.md` §1](integration_guide.md#1-configuration-parameters) and [§7.3 below](#73-sensitivity-to-rtl-configuration-knobs).




## 2. Area Results

Synthesized area for the four personas, plus per-module breakdown (with scan insertion enabled).

### 2.1 Per-persona headline

Headline area summary for the four reference personas:

| Persona | Total area | Flop count |
|---|---:|---:|
| **Light** | 29.7 kGates | ~1,360 |
| **Classic** | 49.1 kGates | ~2,140 |
| **Performance** | 59.0 kGates | ~2,220 |
| **Ultra** | 66.8 kGates | ~2,690 |

### 2.2 Per-module area breakdown

Per-module area for each persona, populated by
`./run_syn -rtl_sweep --sweep-mode personas` (see
[`synthesis_guide.md` §6](synthesis_guide.md#6-rtl-config-sweep)).
Area is reported in **kGates (NAND2-equivalent)**, with scan insertion enabled during synthesis.

|  |                                                    **Light** |                                                 **Classic** |                                              **Performance** |                                                    **Ultra** |
|---|---:|---:|---:|---:|
| **Configuration** | <i>RV32E<br/>Zmmul(16c)<br/>M-only<br/>Zca<br/><br/><br/><br/></i> | <i>RV32I<br/>Zmmul(1c)<br/>M+S+U<br/>Zca<br/>Zbb<br/>Zicntr<br/><br/></i> | <i>RV32IM<br/>1c MUL + 12c DIV<br/>M+S+U<br/>Zca + Zcb<br/>full B<br/>Zicntr<br/><br/></i> | <i>RV32IMC<br/>1c MUL + 12c DIV<br/>M+S+U<br/>full C<br/>full B<br/>Zicntr + Zihpm×4<br/>Smrnmi NMI</i> |
| Integer Register File | 10.1 | 19.5 | 19.5 | 19.6 |
| ALU<br/>*(incl. enabled B-ext sub-extensions)* | 1.4 | 2.5 | 6.7 | 6.8 |
| MUL / DIV<br/>*(M-extension, when present)* | 2.1 | 5.7 | 11.1 | 11.2 |
| Instruction Decode<br/>*(unified RV32I/E + C)* | 5.4 | 5.5 | 5.7 | 6.1 |
| Instruction Fetch<br/>*(including prefetch buffer)* | 4.4 | 4.4 | 4.4 | 4.4 |
| Load/Store Unit | 1.7 | 1.7 | 1.7 | 1.8 |
| CSR core<br/>*(mtraps + ids + decode + read-mux)* | 4.5 | 7.4 | 7.5 | 9.0 |
| CSR Zicntr<br/>*(cycle / instret + U-mode shadows)* | 0.0 | 2.3 | 2.3 | 2.3 |
| CSR Zihpm<br/>*(mhpmcounter3–N + event selectors)* | 0.0 | 0.0 | 0.0 | 4.5 |
| UOP Sequencer<br/>*(Zcmp / Zcmt, when present)* | 0.0 | 0.0 | 0.0 | 1.1 |
| **Total (aRVern)** | **29.7** | **49.1** | **59.0** | **66.8** |
| Sequential cells (flop count) | ~1,360 | ~2,140 | ~2,220 | ~2,690 |

> **Note:** kGate area is a synthesis-only estimate. Different target nodes and/or synthesis tools will give different results.

> **Reset architecture:** the numbers above are for the default **asynchronous**
> reset (`ASYNC_RST_EN=1`). Selecting **synchronous** reset (`ASYNC_RST_EN=0`)
> trims roughly **5 %** off total area — async-reset flops carry a dedicated
> async clear/preset port (a larger cell) on *every* flop, whereas a sync reset
> folds into the data path and maps to smaller plain D-flops. Measured on Ultra:
> **66.8 → ~63.3 kGates**. The trade-off is that synchronous reset requires a
> running clock during reset assertion. See
> [`synthesis_guide.md` §7.5](synthesis_guide.md#75-arv_dff-register-primitive--flatten-before-compile)
> and the `ASYNC_RST_EN` parameter in
> [`integration_guide.md`](integration_guide.md#parameters).

**On the CSR core row:** Light's CSR core (**4.5 kGates**) is **2.9
kGates** smaller than Classic/Performance's (7.4 / 7.5 kGates). Light
differs from those personas on two CSR-relevant axes simultaneously:
`SU_MODE_EN=0` (no S-mode shadow CSRs, no `sret`/`sfence.vma` decode,
mideleg/medeleg RAZ/WI — see
[`integration_guide.md`](integration_guide.md#parameters) for the
parameter spec) and `RV32E_EN=1` (narrower CSR↔regfile data paths). The
visible 2.9-kGate delta bundles both effects, with the S+U bolt-on
dominating. First-order projections: an M+S+U RV32I Light would land at
~32.6 kGates total instead of **29.7**; an M-only RV32E Classic would
shrink its CSR core to ~4.5 kGates and total to ~46.2 kGates. To
isolate either axis cleanly, run the persona sweep with one axis held
fixed at a time.


## 3. Performance Results — Headline Speeds

### 3.1 -O2 canonical numbers

Headline speed metrics at **`-O2`** (Embench / CoreMark / Dhrystone reporting
convention). For per-persona `-Os / -O2 / -O3` sensitivity, see §3.2.

| Metric | **Light** | **Classic** | **Performance** | **Ultra** |
|---|---:|---:|---:|---:|
| **CoreMark / MHz** ↑ (`-O2`) | 2.10 | 3.14 | 3.57 | 3.54 |
| **Dhrystone 4mcu — DMIPS / MHz** ↑ (`-O2`) | 1.63 | 1.75 | 1.95 | 1.95 |
| **Dhrystone v2.1 — DMIPS / MHz** ↑ (`-O2`) | 1.60 | 1.72 | 1.93 | 1.93 |
| **Embench-IoT — Speed/MHz** ↑ (M4 = 1.0; geomean over 22, `-O2`) | 0.72 | 0.97 | 1.32 | 1.32 |
| **Area — NAND2-equivalent kgates** | 30 | 49 | 59 | 67 |

All measurements: xPack `riscv-none-elf-gcc` 14.2 with newlib, comp-mode
binaries where C-ext present, zero-wait-state test SoC.

Performance and Ultra share an identical perf engine and therefore isolates the **area cost of feature completeness while holding raw per-MHz perf nearly constant** (the Zcmp/Zcmt presence in Ultra costs a small amount on call-heavy benchmarks but generally wins on code size).

**A note on the Embench Speed Score.** The Embench Speed Score reported in the
tables is the geometric mean of 22 per-benchmark speed ratios against the M4 baseline.
As with any aggregate, individual workloads can deviate substantially from the geomean
— a single bottlenecked benchmark (16-cycle MUL on Light, no HW DIV on Classic, soft-FP
on Performance/Ultra) can pull the geomean down by a lot even when most workloads cluster
within ±20% of the central tendency. **Always check the per-benchmark detail in §5.1**
if your target workload doesn't match the "average" Embench profile.

Reproduce:

```bash
# benchmarks for one persona
cd sim/rtl_sim/run
./run_benchmark -a -j 8 --rtl-config light          # or classic / performance / ultra
python3 ../bin/benchmark_trace_tools/bench_snapshot.py save --name light

# synth for one persona
cd synthesis/synopsys
./run_syn -rtl_config light -lib <lib_flavor>       # or classic / performance / ultra

# or run all four at once
./run_lint --sweep-mode personas                    # 4 lint passes
./run_syn -rtl_sweep --sweep-mode personas          # 4 synth runs
```

### 3.2 Optimization sensitivity (4 personas × 3 -O levels)

Each persona's headline speed metrics at all three commonly-reported
compile levels (`-Os` code-size-optimised, `-O2` canonical / paper-grade,
`-O3` compiler-headroom maximum). The full per-bench detail of §5.1 is
at `-O2` only — these compact tables surface only the geomean of each
metric so the four personas × three optimization levels stays scannable.
Code size is not reported here — see the §3 intro for why.

Persona columns follow the §1.2 parameter vectors verbatim. Of
particular note: **Light is `SU_MODE_EN=0` (M-mode only)** while the
other three are `SU_MODE_EN=1` (M+S+U). The benchmarks themselves run
entirely from M-mode and never execute `sret`/`sfence.vma`, so the
speed scores below are *not* affected by the SU_MODE_EN setting — but
the parameter difference matters for area (see §2.2) and for fair
apples-to-apples per-persona reading.

#### Embench Speed Score (geomean over 22, M4 = 1.0; higher = faster than M4)

| Persona | `-Os` | `-O2` | `-O3` |
|---|---:|---:|---:|
| **Light** | 0.64 | 0.72 | 0.77 |
| **Classic** | 0.84 | 0.97 | 1.07 |
| **Performance** | 1.22 | 1.32 | 1.48 |
| **Ultra** | 1.22 | 1.32 | 1.49 |

#### CoreMark / MHz (higher = faster per MHz)

| Persona | `-Os` | `-O2` | `-O3` |
|---|---:|---:|---:|
| **Light** | 1.68 | 2.10 | 2.11 |
| **Classic** | 2.39 | 3.14 | 3.06 |
| **Performance** | 2.78 | 3.57 | 3.47 |
| **Ultra** | 2.75 | 3.54 | 3.48 |

#### Dhrystone 4mcu — DMIPS / MHz (higher = faster per MHz)

| Persona | `-Os` | `-O2` | `-O3` |
|---|---:|---:|---:|
| **Light** | 1.13 | 1.63 | 1.63 |
| **Classic** | 1.14 | 1.75 | 1.75 |
| **Performance** | 1.31 | 1.95 | 2.00 |
| **Ultra** | 1.28 | 1.95 | 2.00 |

#### Dhrystone v2.1 — DMIPS / MHz (higher = faster per MHz)

Reported alongside `dhrystone_4mcu` because the two variants exercise
subtly different code paths (see [§6 Dhrystone](#dhrystone--dmipsmhz)).
`v2.1` is the upstream-faithful build; `4mcu` is the MCU-port. Numbers
diverge mostly on `-Os` where the v2.1 inlining patterns and the 4mcu
non-malloc layout interact differently with the compiler.

| Persona | `-Os` | `-O2` | `-O3` |
|---|---:|---:|---:|
| **Light** | 1.12 | 1.60 | 1.60 |
| **Classic** | 1.13 | 1.72 | 1.72 |
| **Performance** | 1.31 | 1.93 | 1.96 |
| **Ultra** | 1.27 | 1.93 | 1.96 |

**Why all three levels are worth reporting.** `-Os` is the level you'd
ship if code size dominates — it gives you the smallest binary, but
some speed loss. `-O2` is what Embench / CoreMark / Dhrystone publications
cite by convention, and what most ARM Cortex-M reference numbers use, so
it's the level cross-core comparisons should anchor on. `-O3` exposes
the additional speed available if your firmware build can afford the size growth from unrolling + inlining. Where the `-Os ↔ -O3`
spread is *narrow* on a bench, the workload is genuinely compute-bound;
where it's *wide*, the bench is sensitive to compiler heuristics
(typically loop unrolling and function inlining decisions).

For honest reporting outside this doc, **always cite the `-O` level with
the number**. "aRVern Classic scores 0.97 on Embench Speed" is
ambiguous; "aRVern Classic scores 0.97 on Embench Speed at `-O2`" is
not.


## 4. Performance Sensitivity Studies

Three orthogonal sensitivity axes measured on the Performance persona (where the
trade-offs matter most): branch-latency knob (`SINGLE_CYCLE_BRANCH`), memory layout
(`.rodata` in ROM vs. SRAM), and C library choice (newlib vs newlib-nano). All reported
against the canonical Performance baseline at `SCB=1`, `.rodata` in ROM, newlib, `-O2`.

### 4.1 SCB, `.rodata` layout, and libc sensitivity

Three orthogonal trade-offs measured on the Performance persona (the configuration most
likely to be both Fmax-constrained and `.rodata`-heavy):

- **Branch-latency knob (`SINGLE_CYCLE_BRANCH`)**: `SCB=1` (default) gives zero-bubble taken
  branches at the cost of a combinational `inst_hrdata → inst_haddr` Fmax loop. Flipping to
  `SCB=0` registers that path (one-bubble taken branch) for higher Fmax headroom at the
  cost of IPC. See [`memory_and_ahb.md` §9](memory_and_ahb.md#9-single_cycle_branch-address-phase-stability)
  for the address-phase-stability detail.
- **Memory layout (`.rodata` location)**: by default, `.rodata` is linked into the same ROM
  region as `.text`, so the instruction and data buses can contend at the ROM port when a
  workload has heavy `.rodata` access (AES S-boxes, SHA constants, Montgomery tables,
  soft-FP coefficients). The alternative is a startup-time copy of `.rodata` into SRAM
  (`-DRODATA_TO_SRAM` build flag), trading SRAM footprint and boot time for eliminated bus
  contention. See [the `.rodata` contention discussion in §4.2](#42-decision-rules) for
  the trade-off framing.
- **C library (newlib vs newlib-nano)**: the baseline links against newlib (full ISO C,
  large soft-FP `printf`/`fwrite`, optimised `memcpy`/`memset`/`strcmp`). Swapping in
  newlib-nano (`--specs=nano.specs`) shrinks `.text` substantially but replaces several
  hot string/memory routines with smaller, byte-oriented implementations. The cost is
  workload-dependent: zero for workloads whose timed body never calls libc (CoreMark's
  iteration, ~half of the Embench suite), but material for any hot path that calls
  `memcpy`/`memset`/`strcmp`/`strchr`/`memmove` — Dhrystone (`strcpy`-dominated, −17 %)
  and the libc-heavy Embench benches like `tarfind` (+145 %), `statemate` (+48 %), or
  `wikisort` (+21 %). See [§4.1 libc observations](#libc-knob--observations-from-the-data-above)
  for the bimodal per-bench breakdown.

All variant columns share the **Performance baseline (SCB=1,
`-O2`)** as reference. All other parameters held constant (RV32IM, 1-cycle MUL, radix-8
DIV, full B, Zca+Zcb, Zicntr).

| Benchmark | M4 reference (ms) | Performance baseline<br/>(SCB=1, `.rodata`→ROM, newlib,  ms) | Performance + SCB=0<br/>(`.rodata`→ROM, newlib, ms) | Performance baseline<br/>+ `.rodata`→SRAM (SCB=1, newlib, ms) | Performance baseline<br/>+ newlib-nano (SCB=1, `.rodata`→ROM, ms) |
|---|---:|---:|---:|---:|---:|
| aha-mont64 | 4004 | 4333 | 4728 | 4333 | 4333 |
| crc32 | 4010 | 3657 | 4180 | 3657 | 3657 |
| cubic | 3931 | 7199 | 7737 | 7180 | 7219 |
| edn | 4010 | 3457 | 3804 | 3448 | 3457 |
| huffbench | 4120 | 2248 | 2558 | 2246 | 2663 |
| matmult-int | 3985 | 3551 | 3930 | 3551 | 3551 |
| md5sum | 4002 | 1999 | 2164 | 1994 | 2353 |
| minver | 3998 | 4960 | 5520 | 4960 | 4960 |
| nbody | 2808 | 3482 | 3793 | 3474 | 3480 |
| nettle-aes | 4026 | 4137 | 4217 | 3633 | 4137 |
| nettle-sha256 | 3997 | 2745 | 2784 | 2744 | 2946 |
| nsichneu | 4001 | 3013 | 3444 | 3013 | 3013 |
| picojpeg | 4030 | 3406 | 3748 | 3404 | 3427 |
| primecount | 3834 | 2657 | 2945 | 2657 | 2657 |
| qrduino | 4253 | 2839 | 3081 | 2838 | 2873 |
| sglib-combined | 3981 | 2652 | 2975 | 2644 | 2635 |
| slre | 4010 | 2838 | 3041 | 2780 | 2843 |
| st | 4080 | 3995 | 4302 | 3995 | 4022 |
| statemate | 4001 | 1160 | 1262 | 1160 | 1722 |
| tarfind | 4033 | 1302 | 1468 | 1302 | 3184 |
| ud | 3999 | 3634 | 4020 | 3634 | 3634 |
| wikisort | 2779 | 1389 | 1533 | 1382 | 1686 |
| **Embench Speed/MHz** ↑ (ratio) | (1.000) | 1.32 | 1.20 | 1.33 | 1.21 |
| **CoreMark / MHz** ↑ | — | 3.57 | 3.14 | 3.57 | 3.57 |
| **Dhrystone 4mcu — DMIPS / MHz** ↑ | — | 1.95 | 1.78 | 1.96 | 1.61 |
| **Dhrystone v2.1 — DMIPS / MHz** ↑ | — | 1.93 | 1.76 | 1.94 | 1.60 |

#### SCB knob — observations from the data above

Going from `SCB=1` (zero-bubble taken branch) to `SCB=0` (one-bubble) at
`-O2` with `.rodata` in ROM costs:

| Aggregate | SCB=1 | SCB=0 | Δ |
|---|---:|---:|---:|
| Embench Speed Score | 1.32 | 1.20 | **−9 %** |
| CoreMark / MHz | 3.57 | 3.14 | **−12 %** |
| Dhrystone 4mcu / MHz | 1.95 | 1.78 | **−9 %** |
| Dhrystone v2.1 / MHz | 1.93 | 1.76 | **−9 %** |

The cost lands exactly where the knob's physics predicts: registering the
`inst_hrdata → inst_haddr` path inserts a bubble per taken branch. Three
data-grounded points worth highlighting:

- **`Branch taken` becomes the dominant stall.** Under `SCB=0`, the
  per-bench `target top stall cause` column shows `Branch taken` topping
  **18 of 22 Embench benches** — vs the `SCB=1` baseline where the top
  stall is spread across load-use, fetch-wait-state, DIV-multi-cycle, and
  Zcmp/Zcmt categories. IPC drops uniformly from ~0.9 (`SCB=1`) to
  ~0.65–0.7 (`SCB=0`) — the bubble-per-taken-branch is workload-independent
  in IPC terms, only weighted differently in absolute cycle count.

- **CoreMark pays more than Embench/Dhrystone** (12 % vs 9 %). CoreMark's
  hot loops have a higher dynamic branch density than Embench's mix or
  Dhrystone's call/return-dominated pattern, so it takes a proportionally
  larger `SCB=0` hit.

- **Two clean exceptions: `nettle-aes` (+1.9 %) and `nettle-sha256`
  (+1.4 %).** Both are already dominated by `Fetch wait state` under
  `SCB=1` (52 % AES, 36 % SHA) — i.e. fetch-bound, with the pipeline
  already stalled on fetch. Adding a branch bubble doesn't move the
  needle when the bubble was about to happen anyway. **Practical
  implication: the `SCB=0` cost is largely hidden by any fetch wait
  state your SoC actually has.** This table uses a zero-wait-state ROM;
  targets with Flash wait states or interconnect-induced latency will
  see a smaller `SCB=0` penalty than these numbers suggest.

#### `.rodata` layout — observations from the data above

Mirroring `.rodata` from ROM into SRAM at boot (`-DRODATA_TO_SRAM` build
flag + matching `crt0_rodata_sram.S` + `link_rodata_sram.ld`) at `-O2`
with `SCB=1` and newlib costs:

| Aggregate | `.rodata`→ROM | `.rodata`→SRAM | Δ |
|---|---:|---:|---:|
| Embench Speed Score | 1.32 | 1.33 | **+0.8 %** |
| CoreMark / MHz | 3.57 | 3.57 | **0 %** |
| Dhrystone 4mcu / MHz | 1.95 | 1.96 | **+0.4 %** |
| Dhrystone v2.1 / MHz | 1.93 | 1.94 | **+0.4 %** |

The aggregate Embench shift is essentially flat and CoreMark is
bit-identical, but the aggregate hides a sharply bimodal per-bench
distribution dominated by a single outlier. Four points worth
highlighting:

- **`nettle-aes` is the one big win (−12.2 % ms, IPC 0.80 → 0.91).**
  Its **9.7 kB** of S-box `.rodata` — by far the largest in the suite,
  3× any other bench — gets hammered every AES round. With `.rodata`
  in ROM, the instruction and data buses contend at the ROM port
  heavily enough that the prefetch buffer cannot fully absorb it.
  Moving `.rodata` to SRAM eliminates the contention, and the top
  stall cause stays `Fetch wait state` (62 % under SRAM, 51 % under
  ROM) — i.e. the contention manifested *as* fetch waits, which is
  the expected microarchitectural fingerprint of ROM-port competition
  reaching the fetch front-end. This is the prefetch buffer's ceiling
  on the current suite.

- **Every other bench is within ±2 %, and most are bit-identical.**
  Including benches with substantial linked `.rodata`: `wikisort`
  (3.6 kB, −0.5 %), `qrduino` (2.5 kB, 0 %), `coremark` (2.1 kB, 0 %),
  `huffbench` (2.0 kB, −0.1 %), `cubic` (1.7 kB, −0.3 %), `edn`
  (1.6 kB, −0.3 %), `matmult-int` (1.6 kB at 186 % of `.text`, 0 %).
  Static `.rodata` size is necessary but not sufficient for the
  prefetch to be overrun — what matters is access density per
  pipeline cycle, and only `nettle-aes`'s every-round S-box hammering
  clears that bar.

- **No bench regresses.** The startup-time `.rodata` copy loop's cost
  is below noise across all 22 + 3 workloads, including short-runtime
  benches like Dhrystone (which actually gain +0.4 % from reduced
  Proc_0 contention). The `.rodata`→SRAM build is therefore a
  no-measured-cost variant for workloads that don't benefit *and* a
  meaningful win for workloads that do — at the price of permanent
  SRAM footprint.

- **`slre`'s −2.0 % is the only other above-noise improvement.** Its
  `.rodata` is small (324 B), so the win isn't easily explained by
  raw size — likely a localised hot-loop access pattern that benefits
  from the contention removal. Below the threshold worth tuning for.

**The prefetch verdict.** Across 22 Embench benches + CoreMark + 2
Dhrystone variants — and across the full `.rodata` size spectrum
(0 B to 9.7 kB) — only one workload exposes the prefetch buffer's
ceiling. This is a positive design data point for the fetch unit:
the buffer is well sized and its drain/refill timing handles every
typical access pattern in the suite. The integrator recommendation
is correspondingly narrow (see §4.2): keep `.rodata` in ROM by
default; pay the SRAM footprint only for AES-S-box-class workloads
where the hot path hammers a sizable lookup table every iteration.

#### libc knob — observations from the data above

Switching from **newlib** to **newlib-nano** (`--specs=nano.specs`) at
`-O2` with `SCB=1` and `.rodata` in ROM costs:

| Aggregate | newlib | newlib-nano | Δ |
|---|---:|---:|---:|
| Embench Speed Score | 1.32 | 1.21 | **−8 %** |
| CoreMark / MHz | 3.57 | 3.57 | **0 %** |
| Dhrystone 4mcu / MHz | 1.95 | 1.61 | **−17 %** |
| Dhrystone v2.1 / MHz | 1.93 | 1.60 | **−17 %** |

The aggregate Embench shift hides a **bimodal** per-bench distribution:
nine benches are bit-identical to newlib (zero libc calls in their timed
body), and five take double-digit hits where their hot loops do call
libc. The Embench Speed Score under newlib-nano (1.21) happens to land
within rounding distance of the `SCB=0` score (1.20), making the libc
swap roughly comparable to losing single-cycle taken branches *on the
aggregate*. The two costs come from completely different mechanisms.

Five points worth highlighting:

- **Five "libc-hot" Embench benches dominate the aggregate.**
  `tarfind` (+145 %), `statemate` (+48 %), `wikisort` (+21 %),
  `huffbench` (+19 %), and `md5sum` (+18 %) account for nearly all of
  the score shift. Each of these has a hot path that calls
  `memcpy`/`memset`/`strcmp`/`strchr` (tarfind scans tar headers,
  md5sum digests a buffer, statemate manipulates state-vector
  bitfields, etc.). Replacing newlib's word-at-a-time implementations
  with newlib-nano's byte loops multiplies dynamic instruction count
  per call by ~4×, and the cost scales with how much of the timed body
  is spent inside those calls.

- **Nine benches are zero-delta.** `aha-mont64`, `crc32`, `edn`,
  `matmult-int`, `minver`, `nettle-aes`, `nsichneu`, `primecount`, and
  `ud` are bit-identical to newlib. Their inner loops are pure
  arithmetic / load-store / branch with no libc calls. Two more
  (`nbody` −0.1 %, `sglib-combined` −0.6 %) sit within measurement
  noise and effectively belong in this group. These eleven set the
  floor: when there's no libc in the timed body, the libc swap is
  a no-op.

- **The "Branch taken" microarchitectural signature.** Every Embench
  bench that takes a >5 % hit *also* shows its top stall cause
  flipping to `Branch taken` under newlib-nano (tarfind 87 %,
  statemate 56 %, wikisort 27 %, huffbench 31 %, md5sum/sha-256
  ~35–58 %). This is the same fingerprint Dhrystone shows: nano's
  byte loops are `load + compare + conditional branch per byte`,
  which doesn't change the pipeline's worst stall category but
  inflates its weight by ~4×. The signature is portable across
  workloads — if you swap libc and see a Branch-taken-dominated
  stall mix appear, you've found a libc call in your hot path.

- **CoreMark is genuinely libc-free in its timed body.** Cycle counts
  match newlib bit-identically. The linked binary contains nano's
  byte-oriented `memcpy`/`memset`/`strcpy` (we verified this from the
  ELF symbol sizes), but the timed iteration never calls them — only
  init/teardown and verification do.

- **Dhrystone is uniformly hit at −17 %.** Both v2.1 and 4mcu scoring
  conventions report the same delta. `Proc_0`'s hot path is
  `strcpy`/`strcmp` on `Str_1_Loc`/`Str_2_Loc` (plus `memcpy` on
  v2.1); byte-oriented implementations multiply both instruction
  count and branch density per call.

**Practical implication.** "Use newlib-nano" is not a free code-size
win on this core: any firmware whose hot path includes string
scanning, byte copies, or formatted I/O will pay a real cost. The
distribution observed here ranges from 0 % to +145 % per workload —
no single number summarises it. Two honest framings for an
integrator: (a) the Embench Speed Score drops by ~8 % on aggregate,
matching roughly the `SCB=0` penalty; (b) if your workload is
libc-heavy in its hot path (tarfind-class), expect costs comparable
to or larger than Dhrystone's −17 %. Quantify against your actual
firmware before assuming either extreme transfers.

### 4.2 Decision rules

**SCB — pick `=0` only when timing closure on the `inst_hrdata → inst_haddr` path is the
binding Fmax constraint** at your target frequency. The perf cost above is what you pay
for the Fmax headroom and scales with how branch-heavy the workload is. For most target
frequencies the `=1` default closes timing comfortably and there is no reason to flip it.

**`.rodata` layout — pick SRAM-mirrored only when** the workload's hot-path
`.rodata` access density is high enough to overrun the prefetch buffer's
contention absorption. The measured data above shows this is a tighter
criterion than "has lots of `.rodata`": only `nettle-aes`-class workloads
(large lookup table hammered every iteration — AES S-box, crypto
permutation table) actually clear the bar with a meaningful win (−12 %).
Workloads with substantial `.rodata` but moderate access density —
including the soft-FP coefficient table in `cubic`, the FIR coefficients
in `edn`, the matrix data in `matmult-int`, even CoreMark's lookup
tables — show no measurable improvement, because the prefetch absorbs
their access pattern. Hard constraints: the entire `.rodata` image must
fit in SRAM alongside `.data`/`.bss`/stack, and the startup-time copy
adds to boot latency. The startup overhead measured on Dhrystone-class
short-runtime benches is **below noise** (Dhrystone actually gains
+0.4 % from reduced `Proc_0` contention), so there is **no measured
downside** for picking this variant on workloads that don't benefit —
but it permanently costs SRAM footprint. For control-flow-bound or
compute-bound code, keep `.rodata` in ROM.

Reproduce with:

```bash
cd sim/rtl_sim/run
./run_benchmark -a -j 8 --rtl-config performance                 # baseline (SCB=1, .rodata→ROM)
# Variant A: SCB=0. Edit run_config.json default → SINGLE_CYCLE_BRANCH=0, re-run, diff.
# Variant B: .rodata→SRAM. Rebuild the firmware with -DRODATA_TO_SRAM, re-run, diff.
```


## 5. Per-Benchmark Detail

Per-benchmark Embench Speed Score against the M4 baseline. Use these to localise
regressions or to argue from individual workload characteristics; the aggregate scores
in §3 are derived from this table.

### 5.1 Per-benchmark Embench Speed Score (M4 baseline = 1.0)

Per-benchmark runtimes in **Time(ms)** for the M4 reference and each
persona, with the M4-anchored aggregate (geomean Speed Score over the 22 ratios) in
the summary row at the bottom.
Per-bench Speed Score for any row is `baseline_M4_ms / persona_ms` —
the reader can compute it directly from the cell values.

All persona columns at **`-O2`** (canonical Embench reporting level — see
§3.2 for `-Os / -O2 / -O3` sensitivity at the geomean level). The M4
reference (from `sim/rtl_sim/src-c/embench-iot/baseline-data/speed.json`,
generated on STM32F4-Discovery at its real clock with `CPU_MHZ` matched to
the chip's actual MHz) is in ms. aRVern's measurements are taken with
`CPU_MHZ=1` matching its 1 MHz test SoC clock — Embench's iteration scaling
(`LSF × CPU_MHZ`) makes the ratio `baseline_ms / aRVern_ms` a true per-MHz
performance comparison.

| Benchmark (run with `-O2`) | M4 reference (ms) | Light (ms) | Classic (ms) | Performance (ms) | Ultra (ms) |
|---|---:|---:|---:|---:|---:|
| aha-mont64 | 4004 | 5667 | 4671 | 4333 | 4333 |
| crc32 | 4010 | 6966 | 4353 | 3657 | 3657 |
| cubic | 3931 | 26853 | 28030 | 7199 | 7199 |
| edn | 4010 | 12203 | 3535 | 3457 | 3457 |
| huffbench | 4120 | 2577 | 2348 | 2248 | 2248 |
| matmult-int | 3985 | 8713 | 3551 | 3551 | 3551 |
| md5sum | 4002 | 2368 | 1935 | 1999 | 1883 |
| minver | 3998 | 13040 | 13121 | 4960 | 4960 |
| nbody | 2808 | 13847 | 14576 | 3482 | 3482 |
| nettle-aes | 4026 | 4846 | 4675 | 4137 | 4137 |
| nettle-sha256 | 3997 | 4953 | 2763 | 2745 | 2745 |
| nsichneu | 4001 | 3424 | 3013 | 3013 | 3013 |
| picojpeg | 4030 | 5385 | 3381 | 3406 | 3412 |
| primecount | 3834 | 3611 | 2657 | 2657 | 2657 |
| qrduino | 4253 | 4605 | 2999 | 2839 | 2879 |
| sglib-combined | 3981 | 2986 | 2694 | 2652 | 2624 |
| slre | 4010 | 2857 | 2878 | 2838 | 2837 |
| st | 4080 | 16955 | 17621 | 3995 | 4022 |
| statemate | 4001 | 1276 | 1186 | 1160 | 1160 |
| tarfind | 4033 | 3020 | 1316 | 1302 | 1302 |
| ud | 3999 | 6402 | 4153 | 3634 | 3634 |
| wikisort | 2779 | 3482 | 3428 | 1389 | 1385 |
| **Geomean Speed/MHz** ↑ (ratio) | (1.000) | 0.72 | 0.97 | 1.32 | 1.32 |

The summary row is a unitless ratio computed as
`geomean(baseline_M4_ms / persona_ms)` over the 22 per-bench ratios — *not*
an aggregate of the ms numbers above it.

**Important platform-vs-CPU caveat.** The M4 baseline was measured on
STM32F4-Discovery, whose code lives in Flash with ART (instruction
prefetch + cache) — meaning the M4 baseline includes Flash wait-state
penalties on branch-heavy / non-cache-friendly code. aRVern's test SoC
has zero-wait-state ROM/SRAM. So part of any speed advantage aRVern shows
reflects **memory architecture**, not pure CPU pipeline.


---

# Part II — Methodology

## 6. How Each Benchmark Works

### CoreMark — `CoreMark/MHz`

The industry-standard general-purpose CPU benchmark (EEMBC). Mixes
list/string processing, matrix manipulation, and state-machine logic.
Score is iterations/sec / MHz — a single scalar.

**Exercises:** integer ALU, memory access patterns, simple branching,
function-call overhead.
**Doesn't exercise:** floating point, vector ops, MMU, caches.

### Dhrystone — `DMIPS/MHz`

A classic synthetic benchmark with two variants in arvern:

- **`dhrystone_v2.1`** — the standard Dhrystone, faithful to the original
  upstream code. Tends to be sensitive to compiler optimisation tricks
  that can inline / simplify the synthetic workload.
- **`dhrystone_4mcu`** — modified for MCU-class targets (different `Number_Of_Runs`,
  no malloc, etc.). More representative of actual MCU workloads.

DMIPS/MHz is the cyclic-corrected score scaled to "VAX 11/780 DMIPS"
units (the historical reference machine).

**Note:** the `Str_1_Loc` / `Str_2_Loc` mismatch you may see at the end of
the Dhrystone log is an *expected* part of the Dhrystone self-check (the
benchmark is *supposed* to print the running values for visual inspection
and they're transient). The simulation reports PASS regardless of this
print.

### Embench-IoT — `Time(ms)`

22 small benchmarks chosen by the embench-iot team to be representative
of MCU workloads. Each one is timed in ms-per-iteration (lower is better).
aRVern's port uses a fixed 1 MHz reference clock so the ms-numbers are
also implicitly cycle counts (1 ms = 1000 cycles).

Embench's discriminating feature: each benchmark is *small* and targets one
specific code pattern, so a regression in (say) `embench_picojpeg` localises
to JPEG-style stream processing.

| Sub-benchmark | Stresses |
|---|---|
| aha-mont64 | 64-bit Montgomery multiplication (modular arithmetic) |
| crc32 | Bitwise XOR / shift |
| cubic | Cubic-equation solver (numerical) |
| edn | Stream / signal-processing primitives |
| huffbench | Huffman decompression |
| matmult-int | Integer matrix multiplication |
| md5sum | MD5 hashing |
| minver | Matrix inversion |
| nbody | N-body physics simulation |
| nettle-aes | AES encryption |
| nettle-sha256 | SHA-256 hashing |
| nsichneu | Large Petri-net state machine |
| picojpeg | Tiny JPEG decoder (stream processing) |
| primecount | Prime sieve |
| qrduino | QR-code generator |
| sglib-combined | Container library |
| slre | Regular-expression matcher |
| st | Statistics |
| statemate | State-machine model |
| tarfind | TAR archive search |
| ud | LU decomposition |
| wikisort | Merge-sort variant |

---


## 7. Score Extraction & Sensitivity Knobs

How scores are parsed from the simulator output, and the knobs that affect them: the
compressed-mode binary selection, the RTL configuration axes, and the compiler optimisation
level.

### 7.1 How scores are extracted

`./run_benchmark` parses the simulator's stdout for a numeric score
identified by a regex (`score_pattern` in `run_config.json`). For
example, CoreMark's entry:

```json
{
  "name": "coremark",
  "is_benchmark": true,
  "score_metric": "CoreMark/MHz",
  "score_pattern": "CoreMark\\s*Mhz\\s*:\\s*([0-9.]+)",
  ...
}
```

The first capture group is the score. The match runs against the test
log (`log/0/<name>-<mode>.log`).

`run_benchmark` then:

1. Prints the score with one line of context.
2. Saves the asphalt trace (per-cycle dispatched-instruction log) compressed
   with `zstandard` under
   `benchmark_traces/latest/trace_<test>_<mode>_<rtl-config>_<toolchain>_<variant>_<timestamp>.log.zst`.
3. Reports the binary size (text / rodata / data / bss) extracted from the
   ELF.

For automated comparisons (regression delta), the score, size, and trace are
all preserved — see §8.

---

### 7.2 Mode (std vs comp)

`./run_benchmark <name>` defaults to `--mode auto`, which reads
`C_EXTENSION` from `run_config.json` and picks:

| `C_EXTENSION` | Auto-picked mode | `-march` flavour |
|:--:|---|---|
| 0 | `std` | `rv32i[m]…` (no C) |
| ≥ 1 | `comp` | `rv32i[m]c…` (with C) |

Explicit `-m std` / `-m comp` overrides auto.

**Why this matters:** comp-mode binaries are smaller (~30 % code size
reduction), often slightly **faster** on cache-less cores because more
instructions fit in the same fetch window (i.e. less sensitive to wait states on the instruction bus). They can also be slightly
slower if a critical loop body that fit comfortably in std mode is now
split across more decode events (i.e. branch targets a std instruction which is not 32b aligned).

---

### 7.3 Sensitivity to RTL configuration knobs

The `rtl_config` entries in `run_config.json` select which extensions and unit
implementations are selected for the simulated core. What each knob changes at
the hardware / ISA level is listed below:

- **`M_EXTENSION = 0`** (no MUL/DIV) — `MUL`, `DIV`, `REM` (and their unsigned /
  high-half variants) are not implemented in hardware. The compiler emits soft
  library calls for `*`, `/`, `%`.
- **`M_EXTENSION = 1`** (Zmmul only) — Multiply is implemented in hardware;
  divide/remainder are not. The compiler emits soft library calls for `/` and `%`.
- **`MUL_TYPE`** — Selects the multiplier microarchitecture: 1-cycle (single-cycle),
  4-cycle (iterative), or 16-cycle (small radix). Sets the per-multiply latency
  every `MUL` / `MULH*` instruction sees.
- **`DIV_TYPE`** — Selects the divider microarchitecture: radix-8 (12-cycle),
  radix-4 (17-cycle), or radix-2 (33-cycle). Sets the per-divide latency every
  `DIV` / `REM` instruction sees.
- **`B_EXTENSION = 0`** (no Zbb / Zba / Zbs / Zbc) — Bit-manipulation
  instructions (count leading/trailing zeros, rotate, sign-extend, single-bit
  extract / set / clear / invert, carry-less multiply, shift-add) are not
  implemented. The compiler expands those idioms into multi-instruction
  sequences using the base ISA.
- **`C_EXTENSION = 0`** (no compressed) — 16-bit compressed instructions
  (Zca / Zcb / Zcmp / Zcmt) are not implemented; only 32-bit base-ISA encodings.
  Code is std-mode only, comp-mode binaries are unavailable, and cross-config
  comparisons must use the std-mode baseline.
- **`SINGLE_CYCLE_BRANCH = 0`** (one-bubble) — A register stage is inserted on
  the branch-target path, so each taken branch costs one extra cycle. Breaks the
  combinational `inst_hrdata → inst_haddr` loop, raising achievable Fmax. Only
  worth using when Fmax is the binding constraint.
- **`SINGLE_CYCLE_BRANCH = 1`** (zero-bubble — canonical default) — No
  register on the branch-target path; taken branches resolve in one cycle.
  Architecturally identical to `=0`; works with any conformant AHB-Lite fabric.
  Pure IPC ↔ Fmax trade-off.

The trace-filename convention encodes the active RTL config (`m2_c4_b4_mul1_div3_…`)
so a snapshot self-documents the configuration that produced it.

---


## 8. Trace Artefacts & Snapshot Workflow

What `run_benchmark` saves (compressed asphalt traces with embedded RTL/toolchain
metadata), and how to use `bench_snapshot` to capture a named reference point for
later comparison.

### 8.1 Trace artefacts

Every `./run_benchmark` call leaves:

```
benchmark_traces/latest/
└── trace_<test>_<mode>_m<M>_c<C>_b<B>_mul<MUL>_div<DIV>_<toolchain>_<opt>_<variant>_<timestamp>.log.zst
```

Decompress with `zstd -d` (or use the Python `zstandard` module). The zst file
is the **asphalt log** — one line per dispatched instruction (`cycle`,
`time(ns)`, `pc`, `instr`, `mnemonic`, `mem`, `mem_addr`, `mem_data`,
`tgt_reg`, `sz`, `br`, `trap`, `priv`, plus optional trailing annotations).
Full column-by-column spec, trailing-annotation catalogue, and snapshot
file layout (header block + decompressed payload) in
[`asphalt_trace_format.md`](asphalt_trace_format.md).

This is the canonical artefact for performance debugging. **Note that
stall-cause categorisation** — the `Branch taken (X %)` / `Fetch wait
state (Y %)` / `Load-use hazard (Z %)` percentages cited throughout
§§4–5 — **is not a column in the raw asphalt log**; it's derived during
preprocessing by `bin/benchmark_trace_tools/stats.py`, which classifies
each non-retiring cycle gap against the dispatching instruction's
context (taken/not-taken branch resolution, multi-cycle MUL/DIV, fetch
buffer drain, load-use, Zcmp/Zcmt sequencing, etc.). The full taxonomy
of categories is in [`asphalt_trace_format.md`](asphalt_trace_format.md).

The `bin/benchmark_trace_tools/` package provides:

| Tool | What it does |
|---|---|
| `bench_compare.py` | Compare two traces (or two snapshots) — diff instruction mix, branch behaviour, memory traffic |
| `bench_snapshot.py` | Take a "snapshot" of all benchmarks under the current config (lightweight: only PKL + manifest, no raw log) |
| `preprocess.py` | Pre-bake heavy stats (n-grams, dependency chains) for the viewer |
| `viewer/app.py` | Streamlit dashboard — interactive views: overview, instruction mix, branches, hot code, n-grams, branch-prediction analysis, memory access patterns, register dependencies, etc. |

The viewer is the recommended way to explore a single trace; `bench_compare`
is the recommended way to A/B two configs.

---

### 8.2 Snapshot comparison

To compare two RTL configurations cleanly:

```bash
# Config A: default
./run_benchmark -a -j 8
python3 ../bin/benchmark_trace_tools/bench_snapshot.py save \
    --name default_O3

# Edit run_config.json — e.g. flip SINGLE_CYCLE_BRANCH to 1
./run_benchmark -a -j 8
python3 ../bin/benchmark_trace_tools/bench_snapshot.py save \
    --name fastbr_O3

# Compare
python3 ../bin/benchmark_trace_tools/bench_compare.py \
    --snapshot1 default_O3 \
    --snapshot2 fastbr_O3
```

The snapshot manifest captures the RTL config that produced it (so old
snapshots remain interpretable even after RTL changes). Snapshots are
human-readable JSON + light PKL state, so they version-control well.

---


## See Also

- [`simulation_guide.md` §6](simulation_guide.md#6-benchmarks) — how to run a benchmark
- [`synthesis_guide.md` §6](synthesis_guide.md#6-rtl-config-sweep) — how to sweep synth across configs
- `bin/benchmark_trace_tools/viewer/README.md` — interactive viewer setup
- `sim/rtl_sim/src-c/dhrystone_4mcu/README.txt` — Dhrystone-specific notes
- `bench_compare.py --help` / `bench_snapshot.py --help` — CLI flags
