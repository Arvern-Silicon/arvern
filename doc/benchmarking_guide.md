<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Benchmarking &amp; Performance Methodology
  <br clear="all">
</h1>

---

## Table of Contents

**Part I — Results**

1. [Introduction](#1-introduction)
2. [Performance Results — Headline Speeds](#2-performance-results--headline-speeds)
3. [Performance Sensitivity Studies](#3-performance-sensitivity-studies)
4. [Per-Benchmark Detail](#4-per-benchmark-detail)

**Part II — Methodology**

5. [How Each Benchmark Works](#5-how-each-benchmark-works)
6. [Score Extraction & Sensitivity Knobs](#6-score-extraction--sensitivity-knobs)
7. [Trace Artefacts & Snapshot Workflow](#7-trace-artefacts--snapshot-workflow)

---

## 1. Introduction

This guide reports how the four bundled benchmarks (§1.1) perform on the four
reference personas (§1.2). Part I holds the results, starting with the headline
speeds in §2; every table in Part I has a reproduce recipe in
[§6.4](#64-reproducing-the-published-tables). Part II explains how each
benchmark works and how the scores are extracted. Synthesized **area** for the
same personas — per-module breakdown and the external-debug cost — is in
[`synthesis_guide.md` §2](synthesis_guide.md#2-area-results).

Terms used throughout: **SCB** = the `SINGLE_CYCLE_BRANCH` parameter (1 = zero-bubble
taken branch, 0 = one-bubble); **M4** = the Embench reference platform
(STM32F4-Discovery, Cortex-M4, `src-c/embench-iot/baseline-data/speed.json`), whose
per-benchmark times define Speed Score 1.0; **asphalt log** = the per-instruction
dispatch trace every run produces ([`asphalt_trace_format.md`](asphalt_trace_format.md)).

### 1.1 Benchmarks at a Glance

| Benchmark | Score metric | Source |
|---|---|---|
| **CoreMark** | CoreMark/MHz | EEMBC CoreMark, port under `sim/rtl_sim/src-c/coremark/arv/` |
| **Dhrystone v2.1** | DMIPS/MHz | Standard Dhrystone, `dhrystone_v2.1/` |
| **Dhrystone 4mcu** | DMIPS/MHz | Modified Dhrystone for MCU workloads, `dhrystone_4mcu/` |
| **Embench-IoT** (22 sub-benchmarks) | ms / iteration | `embench_*/` directories |

All bundled under `sim/rtl_sim/src-c/`. Each is a directory with its own startup,
its own `Makefile` (driven through `c2ihex.sh`), and its own oracle
(`src-c/<name>/<name>.v`).

---

### 1.2 aRVern Personas

The parameter space is large, so four reference configurations — the personas,
defined in `bin/rtl_sweep_configs.py:PERSONAS` — anchor every published area and
benchmark figure and make comparison with other cores possible:

| Parameter | **Light** | **Classic** | **Performance** | **Ultra** |
|---|:---:|:---:|:---:|:---:|
| `RV32E_EN` | 1 (RV32E) | 0 (RV32I) | 0 (RV32I) | 0 (RV32I) |
| `M_EXTENSION` | 1 (Zmmul) | 2 (M = mul+div) | 2 (M = mul+div) | 2 (M = mul+div) |
| `MUL_TYPE` | 3 (16-cycle) | 1 (1-cycle) | 1 (1-cycle) | 1 (1-cycle) |
| `DIV_TYPE` | — | 3 (radix-2, 33-cycle) | 1 (radix-8, 12-cycle) | 1 (radix-8, 12-cycle) |
| `B_EXTENSION` | 0 (none) | 1 (Zbb) | 4 (Zbb+Zba+Zbs+Zbc) | 4 (Zbb+Zba+Zbs+Zbc) |
| `C_EXTENSION` | 1 (Zca) | 1 (Zca) | 2 (Zca+Zcb) | 4 (Zca+Zcb+Zcmp+Zcmt) |
| `SU_MODE_EN` | 0 (M-only) | 0 (M-only) | 1 (M+S+U) | 1 (M+S+U) |
| `PMP_NR` | 0 (none) | 0 (none) | 4 entries | 8 entries |
| `DEBUG_EN` | 0 | 0 | 0 | 0 |
| `DM_TRIGGER_NR` | 0 | 0 | 0 | 0 |
| `ZICNTR_EN` | 0 | 1 | 1 | 1 |
| `ZIHPM_NR` | 0 | 0 | 0 | 4 |
| `CCSR_EN` | 0 | 0 | 0 | 0 |
| `SINGLE_CYCLE_BRANCH` | 1 | 1 | 1 | 1 |
| `ASYNC_RST_EN` | 1 | 1 | 1 | 1 |

Roles:

- **Light** — small CPU: RV32E + 16-cycle Zmmul + Zca, M-mode only (no S/U).
- **Classic** — mid-range CPU: RV32I + M (33-cycle divider) + Zbb + Zca, M-mode only,
  no PMP. Classic is exactly the `arvern.v` parameter default set.
- **Performance** — perf-pure compute target: the same engine as Ultra with no
  SoC-integration overhead (no Zihpm) and no UOP-sequencer-bearing extensions (no
  Zcmp / Zcmt); M+S+U with 4-entry PMP.
- **Ultra** — feature-rich target: full B + full C + Zicntr + Zihpm on the same perf
  engine as Performance; M+S+U with 8-entry PMP.

Each persona has a `-dbg` twin (`light-dbg` … `ultra-dbg`: `DEBUG_EN=1` with 0 / 2 /
4 / 8 Sdtrig triggers). They are synthesized ([`synthesis_guide.md` §2.3](synthesis_guide.md#23-debug-subsystem-area-cost))
but not benchmarked: external debug is performance-neutral.

> The personas are the configurations every number in §§2–4 and in
> [`synthesis_guide.md` §2](synthesis_guide.md#2-area-results) is measured on.
> **Any other parameter combination is equally supported**; an integrator who
> picks one runs their own synthesis and benchmark sweeps to characterise it.
> The simulation defaults in `run_config.json` (`C_EXTENSION=4`, `B_EXTENSION=4`,
> `SU_MODE_EN=1`, `PMP_NR=16`, `DEBUG_EN=1`, `CCSR_EN=1`, `ZIHPM_NR=1`) are a
> verification maximum, not a persona. What each parameter costs in area and
> speed is covered in [`integration_guide.md` §1](integration_guide.md#1-configuration-parameters)
> and [§6.3](#63-sensitivity-to-rtl-configuration-knobs).

## 2. Performance Results — Headline Speeds

### 2.1 -O2 canonical numbers

The headline numbers are measured at **`-O2`**, the optimisation level the
Embench, CoreMark and Dhrystone reporting conventions assume. §2.2 shows how each
persona responds to `-Os`, `-O2` and `-O3`.

| Metric | **Light** | **Classic** | **Performance** | **Ultra** |
|---|---:|---:|---:|---:|
| **CoreMark / MHz** ↑ (`-O2`) | 2.10 | 3.08 | 3.57 | 3.54 |
| **Dhrystone 4mcu — DMIPS / MHz** ↑ (`-O2`) | 1.63 | 1.81 | 1.95 | 1.95 |
| **Dhrystone v2.1 — DMIPS / MHz** ↑ (`-O2`) | 1.60 | 1.78 | 1.93 | 1.93 |
| **Embench-IoT — Speed/MHz** ↑ (M4 = 1.0; geomean over 22, `-O2`) | 0.72 | 1.25 | 1.32 | 1.32 |
| **Area — NAND2-equivalent kgates** | 32 | 52 | 69 | 82 |

All measurements: xPack `riscv-none-elf-gcc` **15.2.0** with newlib, comp-mode
binaries where C-ext present, zero-wait-state test SoC.

Area figures are a rounded copy of [`synthesis_guide.md` §2](synthesis_guide.md#2-area-results),
which is the authoritative home for absolute area and states the measurement basis.

Performance and Ultra share an identical perf engine and therefore isolate the **area cost of feature completeness while holding raw per-MHz perf nearly constant** (the Zcmp/Zcmt presence in Ultra costs a small amount on call-heavy benchmarks but generally wins on code size).

**A note on the Embench Speed Score.** The Embench Speed Score reported in the
tables is the geometric mean of 22 per-benchmark speed ratios against the M4 baseline.
As with any aggregate, individual workloads can deviate substantially from the geomean
— a single bottlenecked benchmark (16-cycle MUL on Light, soft-FP on every persona)
can pull the geomean down by a lot even when most workloads cluster
within ±20% of the central tendency. **Always check the per-benchmark detail in §4.1**
if your target workload doesn't match the "average" Embench profile.

Reproduce: [§6.4](#64-reproducing-the-published-tables).

### 2.2 Optimization sensitivity (4 personas × 3 -O levels)

The tables below give each persona's headline metrics at the three commonly
reported optimisation levels: `-Os` (code size), `-O2` (the canonical level of
§2.1) and `-O3` (compiler headroom). The level is selected with
`toolchain.build_config.OPTIMIZATION` in `run_config.json` (§6.3). To keep four
personas × three levels readable, only the geomean of each metric is shown; the
per-benchmark detail in §4.1 is at `-O2` only. Code size is not tabulated — every
snapshot stores it (`Size (bytes)`) and `bench_compare --attr text_size` compares
it (§7.2).

The persona columns are the §1.2 configurations. Light and Classic are M-mode
only (`SU_MODE_EN=0`); Performance and Ultra are M+S+U with PMP. The benchmarks
run entirely in M-mode and never execute `sret`, so `SU_MODE_EN` does not affect
the speed scores; it does affect area
([`synthesis_guide.md` §2.2](synthesis_guide.md#22-per-module-area-breakdown)).

#### Embench Speed Score (geomean over 22, M4 = 1.0; higher = faster than M4)

| Persona | `-Os` | `-O2` | `-O3` |
|---|---:|---:|---:|
| **Light** | 0.64 | 0.72 | 0.77 |
| **Classic** | 1.12 | 1.25 | 1.39 |
| **Performance** | 1.22 | 1.32 | 1.48 |
| **Ultra** | 1.22 | 1.32 | 1.49 |

#### CoreMark / MHz (higher = faster per MHz)

| Persona | `-Os` | `-O2` | `-O3` |
|---|---:|---:|---:|
| **Light** | 1.68 | 2.10 | 2.11 |
| **Classic** | 2.39 | 3.08 | 3.09 |
| **Performance** | 2.78 | 3.57 | 3.47 |
| **Ultra** | 2.75 | 3.54 | 3.48 |

#### Dhrystone 4mcu — DMIPS / MHz (higher = faster per MHz)

| Persona | `-Os` | `-O2` | `-O3` |
|---|---:|---:|---:|
| **Light** | 1.13 | 1.63 | 1.63 |
| **Classic** | 1.24 | 1.81 | 1.81 |
| **Performance** | 1.31 | 1.95 | 2.00 |
| **Ultra** | 1.28 | 1.95 | 2.00 |

#### Dhrystone v2.1 — DMIPS / MHz (higher = faster per MHz)

Both Dhrystone variants are reported because they exercise slightly different
code paths ([§5](#dhrystone--dmipsmhz)): `v2.1` is the upstream build, `4mcu`
the MCU port. They diverge mostly at `-Os`, where the v2.1 inlining patterns and
the 4mcu bump allocator interact differently with the compiler.

| Persona | `-Os` | `-O2` | `-O3` |
|---|---:|---:|---:|
| **Light** | 1.12 | 1.60 | 1.60 |
| **Classic** | 1.20 | 1.78 | 1.80 |
| **Performance** | 1.31 | 1.93 | 1.96 |
| **Ultra** | 1.27 | 1.93 | 1.96 |

**Reading the three levels.** `-Os` is what a size-bound firmware ships: the
smallest binary, some speed lost. `-O2` is the level Embench, CoreMark and
Dhrystone publications cite and most Cortex-M reference numbers use, so
cross-core comparisons should anchor on it. `-O3` shows the speed still
available when the build can afford the size growth from unrolling and
inlining. A narrow `-Os`↔`-O3` spread means the workload is compute-bound; a
wide one means it is sensitive to compiler heuristics (unrolling and inlining
decisions). When quoting a number elsewhere, always cite the level with it:
"Classic scores 1.25 on Embench Speed at `-O2`".

## 3. Performance Sensitivity Studies

Three independent knobs are measured on the Performance persona, where their
trade-offs matter most: branch latency (SCB), `.rodata` placement (ROM or SRAM)
and the C library (newlib or newlib-nano). Every result is relative to the
Performance baseline — `SCB=1`, `.rodata` in ROM, newlib, `-O2` — with all other
parameters held constant. The stall-cause percentages quoted below are the
heuristic attribution of [§7.1](#71-trace-artefacts), not measured pipeline
signals.

The three knobs:

- **SCB (`SINGLE_CYCLE_BRANCH`)**: `SCB=1` (the baseline) gives zero-bubble taken
  branches through the combinational `inst_hrdata → inst_haddr` loop, which bounds
  the clock period. `SCB=0` registers that path (one-bubble taken branch) for a
  shorter achievable clock period at the cost of IPC; the instruction-bus
  address phase never spans a wait state in either setting.
- **`.rodata` location** (`toolchain.build_config.RODATA_LOCATION`): `ROM` (the
  baseline) links `.rodata` next to `.text`, so the instruction and data buses can
  contend at the ROM port when a workload has heavy `.rodata` access (AES S-boxes,
  SHA constants, Montgomery tables, soft-FP coefficients). `SRAM` selects a
  startup-time copy of `.rodata` into SRAM (each Makefile picks
  `link_rodata_sram.ld` + `startup_rodata_sram.S`; Embench's `board.cfg` picks
  `crt0_rodata_sram.S`), trading SRAM footprint and boot time for eliminated bus
  contention.
- **C library** (`toolchain.build_config.LIBC`): `newlib` (the baseline: full ISO C,
  large soft-FP `printf`/`fwrite`, optimised `memcpy`/`memset`/`strcmp`) or
  `newlib-nano` (`--specs=nano.specs`), which shrinks `.text` substantially but
  replaces several hot string/memory routines with smaller, byte-oriented
  implementations.

| Benchmark | M4 reference (ms) | Performance baseline<br/>(SCB=1, `.rodata`→ROM, newlib,  ms) | Performance + SCB=0<br/>(`.rodata`→ROM, newlib, ms) | Performance baseline<br/>+ `.rodata`→SRAM (SCB=1, newlib, ms) | Performance baseline<br/>+ newlib-nano (SCB=1, `.rodata`→ROM, ms) |
|---|---:|---:|---:|---:|---:|
| aha-mont64 | 4004 | 4333 | 4671 | 4333 | 4333 |
| crc32 | 4010 | 3657 | 4353 | 3657 | 3657 |
| cubic | 3931 | 7199 | 7681 | 7180 | 7219 |
| edn | 4010 | 3457 | 3535 | 3448 | 3457 |
| huffbench | 4120 | 2248 | 2349 | 2246 | 2663 |
| matmult-int | 3985 | 3551 | 3551 | 3551 | 3551 |
| md5sum | 4002 | 1999 | 1935 | 1994 | 2353 |
| minver | 3998 | 4960 | 5720 | 4960 | 4960 |
| nbody | 2808 | 3482 | 3652 | 3474 | 3480 |
| nettle-aes | 4026 | 4137 | 4530 | 3633 | 4137 |
| nettle-sha256 | 3997 | 2745 | 2763 | 2744 | 2946 |
| nsichneu | 4001 | 3013 | 3013 | 3013 | 3013 |
| picojpeg | 4030 | 3406 | 3381 | 3404 | 3427 |
| primecount | 3834 | 2657 | 2657 | 2657 | 2657 |
| qrduino | 4253 | 2839 | 2999 | 2838 | 2873 |
| sglib-combined | 3981 | 2652 | 2694 | 2644 | 2635 |
| slre | 4010 | 2838 | 2876 | 2780 | 2843 |
| st | 4080 | 3995 | 4472 | 3995 | 4022 |
| statemate | 4001 | 1160 | 1178 | 1160 | 1722 |
| tarfind | 4033 | 1302 | 1313 | 1302 | 3184 |
| ud | 3999 | 3634 | 4348 | 3634 | 3634 |
| wikisort | 2779 | 1389 | 1605 | 1382 | 1686 |
| **Embench Speed/MHz** ↑ (ratio) | (1.000) | 1.32 | 1.20 | 1.33 | 1.21 |
| **CoreMark / MHz** ↑ | — | 3.57 | 3.14 | 3.57 | 3.57 |
| **Dhrystone 4mcu — DMIPS / MHz** ↑ | — | 1.95 | 1.78 | 1.96 | 1.61 |
| **Dhrystone v2.1 — DMIPS / MHz** ↑ | — | 1.93 | 1.76 | 1.94 | 1.60 |

Reproduce: [§6.4](#64-reproducing-the-published-tables).

### 3.1 SCB (`SINGLE_CYCLE_BRANCH`)

| Aggregate | SCB=1 | SCB=0 | Δ |
|---|---:|---:|---:|
| Embench Speed Score | 1.32 | 1.20 | **−9 %** |
| CoreMark / MHz | 3.57 | 3.14 | **−12 %** |
| Dhrystone 4mcu / MHz | 1.95 | 1.78 | **−9 %** |
| Dhrystone v2.1 / MHz | 1.93 | 1.76 | **−9 %** |

Registering the `inst_hrdata → inst_haddr` path inserts a bubble per taken branch:

- Under `SCB=0`, `Branch taken` is the top stall cause on 18 of 22 Embench benches,
  and IPC drops from ~0.9 to ~0.65–0.7 across the suite.
- CoreMark pays more (12 %) than Embench or Dhrystone (9 %): its hot loops have a
  higher dynamic branch density.
- `nettle-aes` (+1.9 %) and `nettle-sha256` (+1.4 %) barely move: both are already
  fetch-bound under `SCB=1` (`Fetch wait state` 52 % and 36 %), so the branch bubble
  overlaps a stall that was about to happen anyway. This table uses a zero-wait-state
  ROM; a target with Flash wait states or interconnect latency sees a smaller `SCB=0`
  penalty than these numbers.

**Decision rule.** Pick `SCB=0` only when the `inst_hrdata → inst_haddr` path is the
binding timing constraint at your target clock period. The cost above is what you pay
for the shorter period and scales with how branch-heavy the workload is.

### 3.2 `.rodata` layout

| Aggregate | `.rodata`→ROM | `.rodata`→SRAM | Δ |
|---|---:|---:|---:|
| Embench Speed Score | 1.32 | 1.33 | **+0.8 %** |
| CoreMark / MHz | 3.57 | 3.57 | **0 %** |
| Dhrystone 4mcu / MHz | 1.95 | 1.96 | **+0.4 %** |
| Dhrystone v2.1 / MHz | 1.93 | 1.94 | **+0.4 %** |

The aggregate is flat; the per-bench distribution is bimodal with one outlier:

- `nettle-aes` is the one big win (−12.2 % ms, IPC 0.80 → 0.91). Its 9.7 kB of S-box
  `.rodata` — 3× any other bench — is hammered every round; with `.rodata` in ROM the
  two buses contend at the ROM port faster than the prefetch buffer can absorb. The
  top stall cause is `Fetch wait state` in both builds (51 % under ROM, 62 % under
  SRAM): the contention manifests as fetch waits.
- Every other bench is within ±2 %, most bit-identical, including benches with
  substantial `.rodata`: `wikisort` (3.6 kB, −0.5 %), `qrduino` (2.5 kB, 0 %),
  `coremark` (2.1 kB, 0 %), `huffbench` (2.0 kB, −0.1 %), `cubic` (1.7 kB, −0.3 %),
  `edn` (1.6 kB, −0.3 %), `matmult-int` (1.6 kB at 197 % of `.text`, 0 %). What matters
  is access density per cycle, not static size. `slre` (−2.0 %, 324 B) is the only
  other above-noise change.
- No bench regresses: the startup copy loop is below noise even on short-runtime
  Dhrystone (which gains +0.4 % from reduced `Proc_0` contention).

**Decision rule.** Keep `.rodata` in ROM by default. Pick `SRAM` only for workloads
whose hot path hammers a sizeable lookup table every iteration (AES S-box, crypto
permutation tables); it costs permanent SRAM footprint (the whole `.rodata` image
must fit beside `.data`/`.bss`/stack) and boot latency, and shows no measured
downside otherwise.

### 3.3 libc

| Aggregate | newlib | newlib-nano | Δ |
|---|---:|---:|---:|
| Embench Speed Score | 1.32 | 1.21 | **−8 %** |
| CoreMark / MHz | 3.57 | 3.57 | **0 %** |
| Dhrystone 4mcu / MHz | 1.95 | 1.61 | **−17 %** |
| Dhrystone v2.1 / MHz | 1.93 | 1.60 | **−17 %** |

The aggregate hides a bimodal per-bench distribution:

- Five libc-hot benches dominate: `tarfind` (+145 %), `statemate` (+48 %), `wikisort`
  (+21 %), `huffbench` (+19 %), `md5sum` (+18 %). Their hot paths call
  `memcpy`/`memset`/`strcmp`/`strchr`; nano's byte loops multiply the dynamic
  instruction count per call by ~4×.
- Nine benches are bit-identical (`aha-mont64`, `crc32`, `edn`, `matmult-int`,
  `minver`, `nettle-aes`, `nsichneu`, `primecount`, `ud`) and two more are within
  noise (`nbody` −0.1 %, `sglib-combined` −0.6 %): no libc in the timed body, no cost.
- Every bench that loses more than 5 % also sees its top stall cause flip to
  `Branch taken` (tarfind 87 %, statemate 56 %, wikisort 27 %, huffbench 31 %,
  md5sum/sha-256 ~35–58 %): nano's `load + compare + branch per byte` loops. The
  same signature identifies a libc call in any hot path.
- CoreMark's timed iteration is libc-free (cycle counts match newlib exactly; the
  binary's nano `memcpy`/`memset`/`strcpy` run only in init, teardown and
  verification). Dhrystone is uniformly hit at −17 %: `Proc_0` is
  `strcpy`/`strcmp`-dominated (plus `memcpy` on v2.1).

**Decision rule.** newlib-nano is not a free code-size win on this core: firmware
whose hot path includes string scanning, byte copies or formatted I/O pays between 0 %
and +145 % per workload. Quantify against your actual firmware; on aggregate the
Embench cost (−8 %) happens to match the `SCB=0` penalty, but the mechanisms are
unrelated.

## 4. Per-Benchmark Detail

This section breaks the Embench aggregate of §2 down to its 22 benchmarks. Use
it to localise a regression or to reason from an individual workload's
characteristics.

### 4.1 Per-benchmark Embench Speed Score (M4 baseline = 1.0)

The table lists the runtime in **ms** of every benchmark on the M4 reference
and on each persona at `-O2` (§2.2 has the other optimisation levels at the
geomean level). A row's Speed Score is `M4_ms / persona_ms`; the summary row is
the geomean of those 22 ratios, not an aggregate of the ms values.

The M4 reference (`sim/rtl_sim/src-c/embench-iot/baseline-data/speed.json`) was
generated on an STM32F4-Discovery at its real clock, with `CPU_MHZ` set to the
chip's frequency. aRVern is measured with `CPU_MHZ=1` on its 1 MHz test SoC;
because Embench scales the iteration count by `CPU_MHZ`, the ratio is a per-MHz
comparison.

**Platform caveat.** The M4's code runs from Flash behind ST's ART accelerator
(prefetch plus cache), so its baseline includes Flash wait-state penalties on
branch-heavy or cache-unfriendly code, while aRVern's test SoC has zero-wait-state
ROM and SRAM. Part of any advantage aRVern shows is memory architecture, not
pipeline.

| Benchmark (run with `-O2`) | M4 reference (ms) | Light (ms) | Classic (ms) | Performance (ms) | Ultra (ms) |
|---|---:|---:|---:|---:|---:|
| aha-mont64 | 4004 | 5667 | 4671 | 4333 | 4333 |
| crc32 | 4010 | 6966 | 4353 | 3657 | 3657 |
| cubic | 3931 | 26853 | 7681 | 7199 | 7199 |
| edn | 4010 | 12203 | 3535 | 3457 | 3457 |
| huffbench | 4120 | 2577 | 2349 | 2248 | 2248 |
| matmult-int | 3985 | 8713 | 3551 | 3551 | 3551 |
| md5sum | 4002 | 2368 | 1935 | 1999 | 1883 |
| minver | 3998 | 13040 | 5720 | 4960 | 4960 |
| nbody | 2808 | 13847 | 3652 | 3482 | 3482 |
| nettle-aes | 4026 | 4846 | 4530 | 4137 | 4137 |
| nettle-sha256 | 3997 | 4953 | 2763 | 2745 | 2745 |
| nsichneu | 4001 | 3424 | 3013 | 3013 | 3013 |
| picojpeg | 4030 | 5385 | 3381 | 3406 | 3412 |
| primecount | 3834 | 3611 | 2657 | 2657 | 2657 |
| qrduino | 4253 | 4605 | 2999 | 2839 | 2879 |
| sglib-combined | 3981 | 2986 | 2694 | 2652 | 2624 |
| slre | 4010 | 2857 | 2876 | 2838 | 2837 |
| st | 4080 | 16955 | 4472 | 3995 | 4022 |
| statemate | 4001 | 1276 | 1178 | 1160 | 1160 |
| tarfind | 4033 | 3020 | 1313 | 1302 | 1302 |
| ud | 3999 | 6402 | 4348 | 3634 | 3634 |
| wikisort | 2779 | 3482 | 1605 | 1389 | 1385 |
| **Geomean Speed/MHz** ↑ (ratio) | (1.000) | 0.72 | 1.25 | 1.32 | 1.32 |

---

**Part II — Methodology**

## 5. How Each Benchmark Works

### CoreMark — `CoreMark/MHz`

EEMBC's general-purpose CPU benchmark mixes list and string processing, matrix
manipulation and state-machine logic; the score is iterations per second per
MHz, a single scalar.

**Exercises:** integer ALU, memory access patterns, simple branching,
function-call overhead.
**Doesn't exercise:** floating point, vector ops, MMU, caches.

### Dhrystone — `DMIPS/MHz`

Dhrystone is the classic synthetic benchmark; aRVern bundles two variants:

- **`dhrystone_v2.1`** — the standard Dhrystone, faithful to the original
  upstream code. Tends to be sensitive to compiler optimisation tricks
  that can inline / simplify the synthetic workload.
- **`dhrystone_4mcu`** — modified for MCU-class targets (different `Number_Of_Runs`,
  a trivial bump-allocator `emalloc` instead of newlib `malloc`, etc.). More
  representative of actual MCU workloads.

DMIPS/MHz is the cyclic-corrected score scaled to "VAX 11/780 DMIPS"
units (the historical reference machine).

**Note:** the `Str_1_Loc` / `Str_2_Loc` mismatch you may see at the end of
the Dhrystone log is an *expected* part of the Dhrystone self-check (the
benchmark is *supposed* to print the running values for visual inspection
and they're transient). The simulation reports PASS regardless of this
print.

### Embench-IoT — `Time(ms)`

Embench-IoT is a suite of 22 small benchmarks chosen to represent MCU
workloads, each timed in ms per iteration (lower is better). aRVern's port uses
a fixed 1 MHz reference clock, so the ms numbers are also cycle counts
(1 ms = 1000 cycles).

Embench's discriminating feature: each benchmark is *small* and targets one
specific code pattern, so a regression in (say) `embench_picojpeg` localises
to JPEG-style stream processing. The suite is described in
`src-c/embench-iot/doc/README.md`; the benches the studies above lean on are
`nettle-aes` (AES with a 9.7 kB S-box table), `nettle-sha256`, `tarfind` /
`statemate` / `wikisort` / `huffbench` / `md5sum` (libc-hot), and the soft-FP
group `cubic` / `minver` / `nbody` / `st`.

---

## 6. Score Extraction & Sensitivity Knobs

This section explains how scores are parsed from the simulator output and which
knobs affect them: the compressed-mode binary selection, the RTL configuration
axes and the compiler optimisation level.

### 6.1 How scores are extracted

`./run_benchmark` runs the test through `./run` with `-nodump` and
`-disable_ahb_check` (the AHB protocol checker is off because throughput is the point;
this and the trace destination are the only differences from `./run <benchmark>`),
then parses the simulator's stdout for a numeric score identified by a regex
(`score_pattern` in `run_config.json`). For example, CoreMark's entry:

```json
{
  "name": "coremark",
  "is_benchmark": true,
  "score_metric": "CoreMark/MHz",
  "score_pattern": "CoreMark per MHz\\s*:\\s*([\\d.]+)",
  ...
}
```

The first capture group is the score. The match runs against the test
log (`log/0/<name>-<mode>.log`).

`run_benchmark` then:

1. Prints the score with one line of context.
2. Saves the asphalt trace (the raw log is `asphalt_<benchmark>.log` in the run
   directory) compressed with `zstandard` under
   `benchmark_traces/latest/trace_<test>_<mode>_m<M>_c<C>_b<B>_mul<MUL>_div<DIV>_<toolchain>_<opt>_<variant>_<timestamp>.log.zst`.
3. Reports the binary size (text / rodata / data / bss) extracted from the
   ELF.

For automated comparisons (regression delta), the score, size, and trace are
all preserved — see §7.

---

### 6.2 Mode (std vs comp)

`./run_benchmark <name>` defaults to `--mode auto`, which reads
`C_EXTENSION` from `run_config.json` and picks:

| `C_EXTENSION` | Auto-picked mode | `-march` flavour |
|:--:|---|---|
| 0 | `std` | `rv32i[m]…` (no C) |
| ≥ 1 | `comp` | `rv32i[m]c…` (with C) |

Explicit `-m std` / `-m comp` overrides auto.

Comp-mode binaries are about 30 % smaller and usually slightly faster on a
cache-less core, because more instructions fit in each fetch word and the code
is less sensitive to instruction-bus wait states. They can also be slightly
slower when a hot loop's branch targets land on 32-bit instructions that are
not word-aligned, which splits them across two fetches.

---

### 6.3 Sensitivity to RTL configuration knobs

The `rtl_config` entries in `run_config.json` select the extensions and unit
implementations of the simulated core; `toolchain.build_config` selects the
firmware-side axes (`OPTIMIZATION`, `LIBC`, `RODATA_LOCATION`). What each RTL
knob changes:

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
  combinational `inst_hrdata → inst_haddr` loop, shortening the achievable clock
  period. Only worth using when that loop is the binding timing constraint.
- **`SINGLE_CYCLE_BRANCH = 1`** (zero-bubble — the default) — No
  register on the branch-target path; taken branches resolve in one cycle.
  Architecturally identical to `=0`; works with any conformant AHB-Lite fabric.
  Pure IPC ↔ clock-period trade-off.

The trace-filename convention encodes the active RTL config (`m2_c4_b4_mul1_div3_…`),
and the snapshot manifest records the persona or sweep index passed with
`--rtl-config`, so a snapshot self-documents the configuration that produced it.

### 6.4 Reproducing the published tables

All commands run from `sim/rtl_sim/run/` unless noted. `./run_benchmark` builds the
persona's RTL itself through `--rtl-config`; the firmware knobs are edited in
`run_config.json` `toolchain.build_config`.

| Table | `run_config.json` knob(s) | Command | Snapshot |
|---|---|---|---|
| §2.1, §4.1 (per persona, `-O2`) | `OPTIMIZATION = "-O2"` | `./run_benchmark -a -j 8 --rtl-config <persona>` then `./benchmark_trace_snapshot <persona>_scb1_O2_xpacks` | `<persona>_scb1_O2_xpacks` |
| §2.2 (`-Os` / `-O3` columns) | `OPTIMIZATION = "-Os"` or `"-O3"` | same, snapshot `<persona>_scb1_Os_xpacks` / `_O3_xpacks` | `<persona>_scb1_O{s,3}_xpacks` |
| §3.1 SCB=0 column | `SINGLE_CYCLE_BRANCH` default `0` | `./run_benchmark -a -j 8 --rtl-config performance` | `performance_scb0_O2_xpacks` |
| §3.2 `.rodata`→SRAM column | `RODATA_LOCATION = "SRAM"` | same | `performance_scb1_O2_rodata-sram_xpacks` |
| §3.3 newlib-nano column | `LIBC = "newlib-nano"` | same | `performance_scb1_O2_newlib-nano_xpacks` |
| §2.1 area row | — | `cd synthesis/synopsys && ./run_syn -rtl_config light,classic,performance,ultra` (per-config results under `results_sweep/persona_<name>/`) | — |

`./run_lint --sweep-mode personas` lints the same four configurations. Compare a
fresh run against a stored snapshot with `bench_compare` (§7.2).

---

## 7. Trace Artefacts & Snapshot Workflow

This section describes what `run_benchmark` saves (compressed asphalt traces
with the RTL and toolchain metadata embedded), how the trace tools are invoked,
and how to capture a named reference point for later comparison.

### 7.1 Trace artefacts

Every `./run_benchmark` call leaves:

```
benchmark_traces/latest/
└── trace_<test>_<mode>_m<M>_c<C>_b<B>_mul<MUL>_div<DIV>_<toolchain>_<opt>_<variant>_<timestamp>.log.zst
```

Decompress with `zstd -d` (or use the Python `zstandard` module). The zst file
is the **asphalt log** — one line per dispatched instruction, with the column
spec, trailing-annotation catalogue and snapshot file layout in
[`asphalt_trace_format.md`](asphalt_trace_format.md).

This is the canonical artefact for performance debugging. **Stall-cause
categorisation** — the `Branch taken (X %)` / `Fetch wait state (Y %)` /
`Load-use hazard (Z %)` percentages cited throughout §§3–4 — **is not a column
in the raw asphalt log**. It is a heuristic computed during preprocessing by
`bin/benchmark_trace_tools/stats.py`: the cycle gap before each dispatched
instruction is attributed to the category of the *preceding* instruction, and
whatever is left unattributed is labelled `Fetch wait state` (the residual).
Treat the percentages as attributions, not measured pipeline signals — a bench
with no division in its hot loop can still report `DIV multi-cycle` cycles when
a divide happens to precede a stall. The ten categories:

| Category | Attributed when the preceding instruction is |
|---|---|
| `Load-use hazard` | a load |
| `MUL multi-cycle` | a multiply |
| `DIV multi-cycle` | a divide / remainder |
| `Memory wait state` | a store |
| `Branch taken` | a taken conditional branch |
| `Branch not-taken` | a not-taken conditional branch |
| `Jump (JAL/JALR)` | an unconditional jump |
| `Zcmp/Zcmt multi-cycle` | a `CM.*` push/pop/table-jump |
| `CSR/System` | a CSR or system instruction |
| `Fetch wait state` | none of the above (residual) |

**Tools.** The `bin/benchmark_trace_tools/` modules are a package with relative
imports, so they are run through the wrappers in `sim/rtl_sim/run/` or as
`PYTHONPATH=../bin python3 -m benchmark_trace_tools.<module>`:

| Invocation | What it does |
|---|---|
| `./run_benchmark [name] [-a] [-j N] [-m auto\|std\|comp] [--rtl-config N\|persona] [--dump] [<./run flags>]` | Build, run, extract the score, save the trace (§6.1). Trailing `./run` variant flags pass through |
| `./benchmark_trace_snapshot [<name> [--desc TEXT] [--persona NAME] [--force] [--update -y]]` | Snapshot all benchmarks under the current config into `benchmark_traces/snapshots/<name>/` (manifest + `.stats.pkl`, no raw log); with no argument, list the existing snapshots |
| `PYTHONPATH=../bin python3 -m benchmark_trace_tools.bench_compare [snap ...] [--attr score\|text_size\|total_size\|ipc\|branch_miss] [--suite embench]` | Tabulate one attribute per benchmark across the named snapshots and `latest/`; with `--suite embench` adds the Embench Speed Score and GSD (geometric standard deviation) row. No snapshot lists them; one snapshot compares it against `latest/` |
| `./benchmark_trace_viewer [--no-preprocess] [--workers N] [--summary]` | Preprocess new/stale traces (`preprocess.py`: IPC, stall causes, n-grams, dependency chains into `.stats.pkl`) and open the Streamlit dashboard — instruction mix, branches, hot code, memory access patterns, register dependencies. Uses `~/arvern_env` if present |

The viewer is the recommended way to explore a single trace; `bench_compare`
is the recommended way to A/B two configs. Python dependencies per tier are in
[`simulation_guide.md` §1.3](simulation_guide.md#13-python-libraries).

---

### 7.2 Snapshot comparison

To compare two RTL configurations cleanly, for example `SCB=1` against `SCB=0` on
the Performance persona:

```bash
# Config A: SCB=1 (run_config.json default)
./run_benchmark -a -j 8 --rtl-config performance
./benchmark_trace_snapshot performance_scb1_O2_xpacks --desc "Performance, SCB=1, -O2"

# Config B: edit run_config.json — SINGLE_CYCLE_BRANCH default 0
./run_benchmark -a -j 8 --rtl-config performance
./benchmark_trace_snapshot performance_scb0_O2_xpacks --desc "Performance, SCB=0, -O2"

# Compare
PYTHONPATH=../bin python3 -m benchmark_trace_tools.bench_compare \
    performance_scb1_O2_xpacks performance_scb0_O2_xpacks --attr ipc --suite embench
```

The snapshot manifest captures the RTL config that produced it, including the
persona or index passed with `--rtl-config`, so old snapshots remain interpretable
after RTL changes. Snapshots are human-readable JSON + light PKL state, so they
version-control well.

---

## See Also

- [`simulation_guide.md` §6](simulation_guide.md#6-benchmarks) — how to run a benchmark
- [`synthesis_guide.md` §8](synthesis_guide.md#8-rtl-config-sweep) — how to sweep synth across configs
- `bin/benchmark_trace_tools/viewer/README.md` — interactive viewer setup
- `sim/rtl_sim/src-c/dhrystone_4mcu/README.txt` — Dhrystone-specific notes
- `./benchmark_trace_snapshot --help` / `python3 -m benchmark_trace_tools.bench_compare --help` — CLI flags
