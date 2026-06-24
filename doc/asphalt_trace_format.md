<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Asphalt Trace Format
  <br clear="all">
</h1>

`asphalt.log` is aRVern's per-cycle dispatched-instruction trace — the
authoritative record of what the core *retired*, written by
`bench/verilog/probes_instructions.v` at every dispatch.

This document specifies the file format precisely enough for third-party
tools to parse it. For the *consumer* side — what to do with a trace
after a failing test — see
[`sim/rtl_sim/bin/debug/DEBUG_MANUAL.md`](../sim/rtl_sim/bin/debug/DEBUG_MANUAL.md).

---

## Table of Contents

1. [File at a Glance](#1-file-at-a-glance)
2. [Column Specification](#2-column-specification)
3. [Trailing Annotations](#3-trailing-annotations)
4. [Example Excerpt](#4-example-excerpt)
5. [Production and Suppression](#5-production-and-suppression)
6. [Compressed Snapshots](#6-compressed-snapshots)
7. [Consumer Tools](#7-consumer-tools)

---

## 1. File at a Glance

| Property | Value |
|---|---|
| Location (live run) | `sim/rtl_sim/run/asphalt.log` |
| Location (benchmark batch) | `sim/rtl_sim/run/asphalt_<benchmark>.log` |
| Location (snapshot archive) | `sim/rtl_sim/run/benchmark_traces/latest/trace_<test>_<mode>_<rtl-config>_<toolchain>_<variant>_<timestamp>.log.zst` |
| Encoding | ASCII, LF line endings |
| Granularity | one row per **dispatched** instruction (in program order) |
| Generator | [`bench/verilog/probes_instructions.v`](../bench/verilog/probes_instructions.v) |
| Suppressed by | `+define+NOTRACE` (regressions set this automatically) |

The trace is **stable across runs** with the same RTL config and binary
(modulo wait-state variants and IRQ injection seeds). Two passes through
the same test on the same seed produce identical traces — this is the
foundation of `asphalt_diff.py` regression bisection.

---

## 2. Column Specification

Each row is whitespace-separated with field widths set by the
`$fwrite` format strings in `probes_instructions.v`. Padding is `%-Nd`
(left-justified) so columns line up visually but tools should split on
runs of whitespace, not fixed offsets.

| # | Column | Format | Meaning |
|---|---|---|---|
| 1 | `cycle` | `%-12d` | Clock cycle at dispatch. |
| 2 | `time(ns)` | `%-12d` | `cycle × CLK_PERIOD_NS`. Convenience field — derivable from `cycle` and the testbench clock period. Default 100 MHz ⇒ 10 ns per cycle. |
| 3 | `pc` | `0x%08h` | Program counter of the dispatched instruction. |
| 4 | `instr` | `0x%08h` | Raw 32-bit instruction word (low 16 bits only meaningful when the instruction is 16-bit compressed — see `sz`). |
| 5 | `mnemonic` | `%-32s` | Decoded instruction string, left-padded to 32 chars. |
| 6 | `mem` | `%-4s` | Memory direction: `R` (load), `W` (store), or `-` (no memory op). |
| 7 | `mem_addr` | `0x%08h` / `-` | AHB address driven on the data bus. `-` when no memory op. |
| 8 | `mem_data` | `0x%08h` / `-` | Raw AHB bus word. Loads show the full 32-bit bus read — see `tgt_reg` (column 9) for the sign/zero-extended byte/half actually written to the register file. |
| 9 | `tgt_reg` | `%-20s` | Register effect: `x<n>=0x<val>` for loads / ALU writes, `[x<n>]=0x<val>` for the *source* of a store (where the bytes came from), or `-` if no register write occurred. |
| 10 | `sz` | `%-2d` | Instruction size in bytes: `2` for a compressed (Zca/Zcb/Zcmp/Zcmt) instruction, `4` for a standard 32-bit instruction. |
| 11 | `br` | `%-2s` | Branch outcome: `T` (taken), `N` (not-taken), `-` (non-branch). For Zcmt table jumps the outcome is on the parent `CM.JT`/`JALT`. |
| 12 | `trap` | `%-9s` | Trap / xRET marker: `-` if none, otherwise an exception cause name (e.g. `IF_FAULT`, `LD_MISALN`, `ECALL_M`), or `MRET` / `SRET` / `MNRET` on a privilege return. |
| 13 | `priv` | `%-4s` | Privilege mode at dispatch: `M`, `S`, or `U`. |

A row ends at the newline after column 13 or after any trailing
annotations described below.

---

## 3. Trailing Annotations

Optional `# …` annotations may appear after column 13. They are *additive
diagnostic context*; absence carries no information. Tools should ignore
unknown `# …` tokens. Known annotations:

| Annotation | When emitted | Example |
|---|---|---|
| `# rs1:x<n>=0x<val>  rs2:x<n>=0x<val>` | After any instruction that reads source register(s) — the forwarded value visible in decode at dispatch. `rs2` only when the instruction actually has a second source. | `# rs1:x12=0x0000000c` |
| `# <N> mem ops` | After a Zcmp `CM.PUSH`/`POP`/`POPRET`/`POPRETZ` or Zcmt `CM.JT`/`CM.JALT` — the count of hidden memory transactions that micro-op expansion produced. Hand-written parsers must account for this; the `asphalt_*` helpers already do. | `CM.POPRET {ra,s0-s2}, 16    ...  # 5 mem ops` |
| `# mepc=0x<val> mcause=0x<val>` | On a synchronous-exception entry — the `mepc` and `mcause` values latched at trap entry. | `# mepc=0x20000204 mcause=0x00000005` |
| `# kill:NMI` / `# kill:IRQ` | When a multi-cycle operation (MUL/DIV/UOP) was aborted before retirement because a higher-priority trap pre-empted it. | `# kill:IRQ` |
| `# csr:0x<addr>:=0x<val>` | After a CSR-write instruction — the address and value actually written. | `# csr:0x305:=0x20000040` |

Multiple annotations on the same row appear separated by two spaces, in
the order shown above (rs/mem-count first, trap-context last).

---

## 4. Example Excerpt

Raw output from a real CoreMark run (Light persona) — boot code,
unmodified:

```
2             2000          0x20000000  0x61002117  AUIPC x2,0x61002000               -     -           -           x2=0x81002000         4   -   -          M
3             3000          0x20000004  0x02c10113  ADDI x2,x2,44                     -     -           -           x2=0x8100202c         4   -   -          M     # rs1:x2=0x81002000
4             4000          0x20000008  0x00004517  AUIPC x10,0x4000                  -     -           -           x10=0x20004008        4   -   -          M
5             5000          0x2000000c  0x19050513  ADDI x10,x10,400                  -     -           -           x10=0x20004198        4   -   -          M     # rs1:x10=0x20004008
8             8000          0x20000018  0x00c00613  ADDI x12,x0,12                    -     -           -           x12=0x0000000c        4   -   -          M
9             9000          0x2000001c  0x2283ca11  C.BEQZ x12, 20                    -     -           -           -                     2   N   -          M     # rs1:x12=0x0000000c
```

Reading the last row: cycle 9, PC `0x2000001c`, a compressed `C.BEQZ`
(`sz=2`) that compares `x12 = 0x0000000c` against zero — non-zero, so
branch not taken (`br=N`), no register write (`tgt_reg=-`), no trap
(`trap=-`), executing in M-mode. The `# rs1:x12=0x0000000c` annotation
shows what the decoder actually read.

---

## 5. Production and Suppression

The trace is emitted by `bench/verilog/probes_instructions.v` whenever
`NOTRACE` is **not** defined. Production conditions:

| Scenario | Trace produced? | Notes |
|---|---|---|
| `./run <testname>` | yes | Plain run keeps `asphalt.log` in `sim/rtl_sim/run/`. |
| `./run <testname> -nodump` | yes | `-nodump` only suppresses the VCD. The asphalt trace is independent. |
| `./run_all` (regression) | **no** | Regressions set `+define+NOTRACE` to avoid multi-MB log files × hundreds of tests. |
| `./run_benchmark <name>` | yes | Single-benchmark runs explicitly enable the trace (`SIMULATION_NOTRACE=0` in `store_benchmark.py`) so it can be snapshotted. |
| `./run_benchmark --all` | yes | Per-benchmark traces land at `sim/rtl_sim/run/asphalt_<benchmark>.log` (each worker sets its own `SIMULATION_TRACE_DEST`). |
| `+define+NOTRACE` set manually | no | Hard kill of trace generation, regardless of other env. |

The trace is written incrementally during simulation and flushed at
`$finish` — partial traces from `Ctrl+C` runs are valid prefix views.

---

## 6. Compressed Snapshots

Trace files saved through `bench_snapshot.py` or the benchmark-trace
pipeline are **zstd-compressed** and prepended with a YAML-ish metadata
header. The filename pattern is:

```
trace_<test>_<mode>_<rtl-config>_<toolchain>_<variant>_<timestamp>.log.zst
```

Example:

```
trace_coremark_comp_m1_c1_b0_mul3_xpacks_O3_nominal_20260601_104010.log.zst
       │       │    │                  │      │   │        │
       │       │    │                  │      │   │        └ YYYYMMDD_HHMMSS
       │       │    │                  │      │   └ wait-state / IRQ variant
       │       │    │                  │      └ -O level
       │       │    │                  └ toolchain profile
       │       │    └ RTL-config signature (m=M_EXTENSION, c=C_EXTENSION, b=B_EXTENSION, mul=MUL_TYPE [, div=DIV_TYPE])
       │       └ mode (`std` / `comp`)
       └ test name
```

The decompressed payload starts with a `# ...` metadata block (RTL params,
toolchain version, score, size, host info), then a blank line, then the
trace rows specified above. Tools that handle both raw and snapshot
files: drop everything from the start of file up to and including the
first all-blank line, then parse the rest as plain rows.

---

## 7. Consumer Tools

In-tree helpers that already parse this format correctly (Zcmp multi-mem
caveat, clock-period auto-detect, snapshot header skip):

| Script | Purpose |
|---|---|
| `sim/rtl_sim/bin/debug/asphalt_summary.py` | Trace stats: trap/MRET counts, livelock detection — the first thing to run on any failure. |
| `sim/rtl_sim/bin/debug/asphalt_context.py` | N instructions around a trap / MRET / cycle / PC anchor. |
| `sim/rtl_sim/bin/debug/asphalt_diff.py` | First PC divergence between two runs — the regression bisection workhorse. |
| `sim/rtl_sim/bin/debug/asphalt_perf_diff.py` | Per-instruction cycle delta between two runs whose PC sequence is identical — answers "where do the extra cycles go" when comparing linker layouts, bus topologies, or libc swaps. Complements `asphalt_diff.py`. |
| `sim/rtl_sim/bin/debug/asphalt_annotate.py` | Fuse the firmware trace with VCD signal values per dispatch cycle. |
| `sim/rtl_sim/bin/benchmark_trace_tools/preprocess.py` | Reads compressed snapshots, extracts pipeline statistics (IPC, stall causes, branch behaviour) into `.stats.pkl` bundles consumed by `bench_compare` and the Streamlit viewer. |
| `sim/rtl_sim/bin/benchmark_trace_tools/save_trace.py` | Wrap an `asphalt.log` with RTL-config / build metadata and serialize it to a compact `.log.zst` (zstd) for archival or as a regression baseline. |

Use these in preference to ad-hoc `grep | awk` pipelines — the Zcmp
`# <N> mem ops` annotation in particular is easy to mis-handle.

If you need to write a new consumer, import from
`sim/rtl_sim/bin/benchmark_trace_tools/parser.py` rather than
re-implementing the column / annotation / snapshot rules above. It is the
canonical parser (`asphalt.log` / `.log.zst` → `TraceData` / pandas
`DataFrame`) used by every script in the table, so any future format
extension lands there first.

---

## See Also

- [`sim/rtl_sim/bin/debug/DEBUG_MANUAL.md`](../sim/rtl_sim/bin/debug/DEBUG_MANUAL.md) — full debug-tool reference; how to triage a failing test using the trace + VCD together.
- [`simulation_guide.md` §8](simulation_guide.md#8-waveforms-and-debugging) — quick overview of artefacts and debug helpers.
- [`verification_guide.md`](verification_guide.md) — test taxonomy, the `x31` sync mechanism, registering tests.
- [`characterization_guide.md` §8](characterization_guide.md#8-trace-artefacts--snapshot-workflow) — how the snapshot pipeline uses these traces.
- [`bench/verilog/probes_instructions.v`](../bench/verilog/probes_instructions.v) — the generator (canonical source of truth).
