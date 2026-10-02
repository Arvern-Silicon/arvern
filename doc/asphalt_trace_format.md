<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Asphalt Trace Format
  <br clear="all">
</h1>

> *Other architectures pave with tarmac, we use asphalt.*

This document specifies the two simulation trace files precisely enough for
third-party tools to parse them:

- **`asphalt.log`** (§1–§7) — aRVern's per-instruction dispatch trace, the
  authoritative record of what the core *retired*, written by
  `bench/verilog/probes_instructions.v`.
- **`pitstop.log`** (§8) — the companion external-debug event trace, written by
  `bench/verilog/probes_debug.v`, which fills the gap `asphalt.log` leaves while
  the hart is halted.

For the *consumer* side — what to do with a trace after a failing test — see
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
8. [Companion Debug Trace (`pitstop.log`)](#8-companion-debug-trace-pitstoplog)

---

## 1. File at a Glance

| Property | Value |
|---|---|
| Location (live run) | `sim/rtl_sim/run/asphalt.log` — a relative symlink into `run/WORK/tmp*/`; the next `runsim.py` invocation deletes that directory, so copy the file out (`cp -L`) before the next run (`mv` moves only the link) |
| Location (benchmark batch) | `sim/rtl_sim/run/asphalt_<benchmark>.log` |
| Location (snapshot archive) | `sim/rtl_sim/run/benchmark_traces/latest/trace_<test>_<mode>_<rtl-config>_<toolchain>_<variant>_<timestamp>.log.zst` |
| Encoding | ASCII, LF line endings |
| Granularity | one row per **dispatched** instruction. Rows are written as each instruction completes (a load/store when its data phase ends, anything else at the next dispatch or register write), so under wait states file order can differ from dispatch order — sort by column 1 when order matters |
| Generator | [`bench/verilog/probes_instructions.v`](../bench/verilog/probes_instructions.v) |
| Suppressed by | `SIMULATION_NOTRACE=1` in the environment (`./run_all` exports it), which the scripts turn into `+define+NOTRACE` — see §5 |

The trace is **stable across runs** with the same RTL config and binary
(modulo wait-state variants and IRQ injection seeds). Two passes through
the same test on the same seed produce identical traces — this is the
foundation of `asphalt_diff.py` regression bisection.

---

## 2. Column Specification

**Parsing contract:**

1. Skip every line whose first non-blank character is `#`. The file begins
   with a `#` comment header ending in the column legend, and a `# wfi-end: …`
   line (§3) can appear on its own inside the body.
2. Columns are separated by **two or more** spaces; the mnemonic column
   contains single spaces (`ADDI x2,x2,44`, `CM.PUSH {ra, s0-s11}, -112`).
   Split on `re.split(r'\s{2,}', line)`, never on single whitespace or fixed
   offsets.
3. A trap marker (`EXC:`/`IRQ:`/`NMI` in column 12) and its `# mepc= mcause=` /
   `# kill:` annotations sit on the **first instruction dispatched after the
   trap** (the handler entry), not on the faulting or interrupted instruction;
   `mepc` in the annotation names that instruction. `MRET`/`SRET`/`MNRET` mark
   the xRET instruction's own row.

Field widths are set by the `$fwrite` format strings in `probes_instructions.v`;
padding is `%-Nd` (left-justified) so columns line up visually.

| # | Column | Format | Meaning |
|---|---|---|---|
| 1 | `cycle` | `%-12d` | Clock cycle at dispatch. |
| 2 | `time(ns)` | `%-12d` | `cycle × CLK_PERIOD_NS`. Convenience field — derivable from `cycle` and the testbench clock period. Default 1 MHz ⇒ 1000 ns per cycle. |
| 3 | `pc` | `0x%08h` | Program counter of the dispatched instruction. |
| 4 | `instr` | `0x%08h` | Raw 32-bit instruction word (low 16 bits only meaningful when the instruction is 16-bit compressed — see `sz`). |
| 5 | `mnemonic` | `%-32s` | Decoded instruction string, left-padded to 32 chars. Contains single spaces. |
| 6 | `mem` | `%-4s` | Memory direction: `R` (load), `W` (store), or `-` (no memory op). |
| 7 | `mem_addr` | `0x%08h` / `-` | AHB address driven on the data bus. `-` when no memory op. |
| 8 | `mem_data` | `0x%08h` / `-` | Raw AHB bus word. Loads show the full 32-bit bus read — see `tgt_reg` (column 9) for the sign/zero-extended byte/half actually written to the register file. For a sub-word store this is the lane-replicated `hwdata` word. |
| 9 | `tgt_reg` | `%-20s` | Register effect: `x<n>=0x<val>` for loads / ALU writes, `[x<n>]=0x<val>` for the *source* of a store, printed at the store width (2 / 4 / 8 hex digits for SB / SH / SW), or `-` if no register write occurred. |
| 10 | `sz` | `%-2d` | Instruction size in bytes: `2` for a compressed (Zca/Zcb/Zcmp/Zcmt) instruction, `4` for a standard 32-bit instruction. |
| 11 | `br` | `%-2s` | Branch outcome: `T` (taken) / `N` (not-taken) for **conditional** branches only; unconditional jumps, including `CM.JT`/`CM.JALT`, print `-`. |
| 12 | `trap` | `%-9s` | Trap / xRET marker (placement: contract rule 3). `-` if none; else an exception `EXC:IADM` `EXC:IACF` `EXC:ILLI` `EXC:EBRK` `EXC:LDAM` `EXC:LDAF` `EXC:STAM` `EXC:STAF` `EXC:ECALL` (one string for ECALL from any mode) or `EXC:????` for a cause the probe does not name (e.g. the Smdbltrp double-trap cause 16); an interrupt `IRQ:SSW` `IRQ:MSW` `IRQ:STMR` `IRQ:MTMR` `IRQ:SEXT` `IRQ:MEXT` `IRQ:Pnn` (platform, nn = 16..31); `NMI`; or `MRET` / `SRET` / `MNRET` on a privilege return. |
| 13 | `priv` | `%-4s` | Privilege mode at dispatch: `M`, `S`, or `U` (`?` for a reserved encoding). |

A row ends at the newline after column 13 or after any trailing
annotations described below.

---

## 3. Trailing Annotations

Optional `# …` annotations may appear after column 13. They are *additive
diagnostic context*; absence carries no information. Tools should ignore
unknown `# …` tokens. The annotation set and its order differ between
non-load/store rows and load/store rows.

**Non-load/store rows**, in emission order:

| Annotation | When emitted | Example |
|---|---|---|
| `# <N> mem ops` | After a Zcmp `CM.PUSH`/`POP`/`POPRET`/`POPRETZ` or Zcmt `CM.JT`/`CM.JALT` — the count of hidden memory transactions that micro-op expansion produced. Hand-written parsers must account for this; the `asphalt_*` helpers already do. | `CM.POPRET {ra, s0-s2}, 16   …   # 4 mem ops` |
| `# kill:NMI` / `# kill:IRQ` | On the handler-entry row (contract rule 3) when the trap aborted a multi-cycle operation (MUL/DIV/UOP) before retirement. | `# kill:IRQ` |
| `# csr:0x<addr>:=0x<val>` | After any Zicsr instruction (reads included) once its write value has been captured — the value is what the CSR datapath would write, which for a `csrr` equals the current value. | `# csr:0x305:=0x20000040` |
| `# rs1:x<n>=0x<val>  rs2:x<n>=0x<val>` | The forwarded source value(s) visible in decode at dispatch. `rs1`/`rs2` are omitted when the source is `x0` or the format has no such operand (LUI/AUIPC/JAL/CSR-immediate); `rs2:` carries no leading `#`. | `# rs1:x12=0x0000000c` |
| `# mepc=0x<val> mcause=0x<val>` | On the handler-entry row of every exception or interrupt (not NMI) — the `mepc` and `mcause` latched at trap entry. | `# mepc=0x20000204 mcause=0x00000005` |

**Load/store rows** carry only `# mepc=… mcause=…` then `# kill:…`; their
operands are visible in `mem_addr` / `tgt_reg`, so they never carry rs
annotations.

**Whole-line annotation.** `# wfi-end: <N> cycles (resume at cycle <M>)` is
written on its own line after every WFI row — the only direct measure of a WFI
sleep's length. Consumers skip it under contract rule 1.

Multiple annotations on the same row are separated by two spaces.

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
`NOTRACE` is **not** defined. The user-facing switch is the environment
variable `SIMULATION_NOTRACE`, which the scripts translate into the define.
Production conditions:

| Scenario | Trace produced? | Notes |
|---|---|---|
| `./run <testname>` | yes | Plain run keeps `asphalt.log` in `sim/rtl_sim/run/`. |
| `./run <testname> -nodump` | yes | `-nodump` only suppresses the VCD. The asphalt trace is independent. |
| `./run <testname> -rtl_config N` | yes | Single-config reproduction keeps VCD and trace. |
| `./run … -j N` with `N > 1` | **no** | The runner sets `SIMULATION_NOTRACE=1` for parallel runs. |
| `./run … -rtl_sweep`, `./run_all -rtl_sweep` | **no** | Same. |
| `./run_all` (regression) | **no** | `run_all` exports `SIMULATION_NOTRACE=1` to avoid multi-MB log files × hundreds of tests. |
| `./run_benchmark <name>` | yes | Single-benchmark runs explicitly enable the trace (`SIMULATION_NOTRACE=0` in `store_benchmark.py`) so it can be snapshotted. |
| `./run_benchmark -a` | yes | Per-benchmark traces land at `sim/rtl_sim/run/asphalt_<benchmark>.log` (each worker sets its own `SIMULATION_TRACE_DEST`). |
| `SIMULATION_NOTRACE=1` set by hand | no | An explicit `SIMULATION_NOTRACE=0` re-enables the trace even under `-j N`. |

`SIMULATION_TRACE_DEST=<path>` relocates the trace at the end of the run.

The trace is written incrementally during simulation and flushed at
`$finish` — partial traces from `Ctrl+C` runs are valid prefix views. The
flushed last row uses a reduced format (`tgt_reg` padded `%-15s`, no rs / csr /
trap annotations), so the final row of a trace can look truncated.

---

## 6. Compressed Snapshots

Trace files saved by `save_trace.py` (called by `run_benchmark`) are
**zstd-compressed** and prepended with a `#` metadata header. The filename
pattern is:

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
toolchain, score, size, host info), followed by the writer's own `#` legend,
then the trace rows specified above. There is no blank separator line. Tools
that handle both raw and snapshot files apply contract rule 1: skip every line
that is empty or starts with `#` — metadata block, legend and in-body
`# wfi-end:` lines alike — and parse the rest.

---

## 7. Consumer Tools

In-tree helpers that already parse this format correctly (two-space split,
`#`-line skip, Zcmp multi-mem caveat, clock-period auto-detect):

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
pandas loader (`asphalt.log` / `.log.zst` → `TraceData` / `DataFrame`) behind
the benchmark pipeline (`preprocess`, `stats`, the viewer), and accepts every
column-12 value including `NMI` and `MNRET` and the `[x<n>]=0x…` store source.
The `asphalt_*.py` debug tools use a lighter inline splitter of their own.

---

## 8. Companion Debug Trace (`pitstop.log`)

`asphalt.log` records *dispatched instructions* — so it goes **silent
whenever the hart is halted in Debug Mode**. A frozen hart dispatches
nothing, which means the exact window where the Debug Module is busy
(halting, poking GPRs/CSRs, running System Bus Access, resuming) leaves no
trace, and `asphalt_annotate.py` has no dispatch rows to hang VCD values on.

`pitstop.log` is the companion trace that fills that gap: one
cycle-stamped line per **external-debug event**, written by
[`bench/verilog/probes_debug.v`](../bench/verilog/probes_debug.v). Its
`cycle` column shares the **same basis** as `asphalt.log` (same clock, same
free-running counter), so the two can be merged by cycle into a single
time-ordered story of an external-debug session.

### 8.1 File at a Glance

| Property | Value |
|---|---|
| Location (live run) | written to the simulation working directory, then symlinked into `sim/rtl_sim/run/` next to `asphalt.log` (when tracing is enabled — same `NOTRACE` switch, so regressions suppress both); same lifetime as `asphalt.log` (§1) |
| Encoding | ASCII, LF line endings; starts with a `#` header — skip `#` lines |
| Granularity | one row per external-debug event (DMI transaction, SBA transfer, or Debug-Mode transition) |
| Generator | [`bench/verilog/probes_debug.v`](../bench/verilog/probes_debug.v) |
| Suppressed by | `SIMULATION_NOTRACE=1` (same switch as `asphalt.log`; regressions set it) |
| Present only when | the probe is instantiated in the testbench; the `DBG` (hart-side) rows additionally require `DEBUG_EN=1` |

### 8.2 How the Probe Reaches the Core (portability)

`probes_debug.v` is an **RTL-side observer**: it reads core signals by
cross-module reference rooted at the `` `ARV_CPU_INST `` macro (default
`dut` — the *same* knob `probes_instructions.v` uses). A different
testbench hierarchy just overrides the root:

```
+define+ARV_CPU_INST=my_soc.u_cpu
```

The core's `DEBUG_EN` is passed straight through as a module parameter
(`probes_debug #(.DEBUG_EN(DEBUG_EN))`), keeping probe and core in lockstep:

- **Boundary sources (`DMI`, `SBA`)** tap always-present top-level ports
  (the DMI/APB slave bus and the data-AHB `data_hmaster_o` tag), so they
  compile and run in **every** configuration — they are simply silent when
  no debug traffic occurs.
- **Ground-truth source (`DBG`)** reaches into the hart-side debug logic,
  which only exists at `DEBUG_EN=1`. Those reach-ins sit inside a
  `generate if (DEBUG_EN)` block, so at `DEBUG_EN=0` the pruned hierarchy
  is never referenced and the build stays clean.

### 8.3 Row Format

Every row is `cycle`, then a three-letter **source tag**, then a
source-specific payload. Whitespace-separated; split on runs of whitespace,
not fixed offsets.

| Source | Meaning | Payload format |
|---|---|---|
| `DMI` | A completed DMI/APB transaction — the debugger's conversation with the DM. Logged when `PSEL & PENABLE & PREADY` (register index = `PADDR[8:2]`). | `WR`\|`RD` `<regname>` `= 0x<value>` `[# <decode>]` |
| `SBA` | A System Bus Access transfer on the data AHB bus (tagged by `data_hmaster_o=1`). Reported at data-phase completion, so it reflects wait states. | `WR`\|`RD` `[0x<addr>] = 0x<data>  sz=<bytes>  OKAY`\|`ERROR` |
| `DBG` | Hart-side Debug-Mode transition (ground truth; `DEBUG_EN=1` only). `ENTER` is written once `dpc` has been captured, which can be later than the entry edge. | `ENTER Debug Mode  cause=<name>  dpc=0x<val>` / `EXIT  Debug Mode  (resume)` |

`<regname>` is the decoded DMI register: `data0` (0x04), `dmcontrol`
(0x10), `dmstatus` (0x11), `hartinfo` (0x12), `abstractcs` (0x16),
`command` (0x17), `abstauto` (0x18), `sbcs` (0x38), `sbaddress0` (0x39),
`sbdata0` (0x3c); an unrecognised index prints as `reg[0x<nn>]`.

**DMI decode notes** (the `# …` tail, additive — ignore unknown tokens):

| Register | Note |
|---|---|
| `dmcontrol` (write) | `# halt=<b> resume=<b> ndmreset=<b> dmactive=<b> ackhavereset=<b>` |
| `dmstatus` | `# allhalted=<b> allrunning=<b> allhavereset=<b> allresumeack=<b>` |
| `abstractcs` | `# busy=<b> cmderr=<n>` |
| `command` (write) | `# AccessReg wr=<b> x<n> aarsize=<n>` (GPR) / `# AccessReg wr=<b> csr=0x<addr> aarsize=<n>` (CSR) / `# cmdtype=<n>` (non-Access-Register) |
| `sbcs` | `# sberror=<n> sbbusy=<b>` |

**`DBG` cause names** (from `dcsr.cause`): `1`=`ebreak`, `2`=`trigger`,
`3`=`haltreq`, `4`=`step`, `5`=`resethaltreq`, `6`=`group`; any other value
prints as its number.

### 8.4 Example Excerpt

A halt → abstract access → SBA → resume session over the UART DTM
(`debug_dtm_uart`, abridged):

```
        3478  DMI  WR dmcontrol  = 0x80000001   # halt=1 resume=0 ndmreset=0 dmactive=1 ackhavereset=0
        3480  DBG  ENTER Debug Mode  cause=haltreq  dpc=0x20000038
        4445  DMI  RD dmstatus   = 0x000003a3   # allhalted=1 allrunning=0 allhavereset=0 allresumeack=0
        5412  DMI  WR command    = 0x00221012   # AccessReg wr=0 x18 aarsize=2
        6379  DMI  RD abstractcs = 0x00000001   # busy=0 cmderr=0
        7346  DMI  RD data0      = 0xa5a5a5a5
        9280  DMI  WR command    = 0x00231014   # AccessReg wr=1 x20 aarsize=2
       17983  DMI  WR sbaddress0 = 0x80004020
       18950  DMI  WR sbdata0    = 0x5ba00001
       18951  SBA  WR [0x80004020] = 0x5ba00001  sz=4  OKAY
       21852  SBA  RD [0x80004020] = 0x5ba00001  sz=4  OKAY
       25719  DMI  WR dmcontrol  = 0x40000001   # halt=0 resume=1 ndmreset=0 dmactive=1 ackhavereset=0
       25720  DBG  EXIT  Debug Mode  (resume)
```

Reading it: at cycle 3478 the debugger sets `dmcontrol.haltreq`; two cycles
later the hart enters Debug Mode with `dcsr.cause = haltreq` and
`dpc = 0x20000038` (the frozen PC). It then abstract-reads `x18`
(`0xa5a5a5a5`), abstract-writes `x20`, and SBA-writes then reads back
`0x5ba00001` at `0x80004020`. At cycle 25719 `resumereq` drops it out of
Debug Mode — after which `asphalt.log` picks the instruction stream back up.

### 8.5 Merging with `asphalt.log`

Because both files count cycles identically, a merged view is a
cycle-ordered interleave of the two. The `DMI`/`SBA`/`DBG` rows slot into
the `asphalt.log` gap that opens between the last pre-halt dispatch and the
first post-resume dispatch — turning a blank stretch into the readable
account above.

`asphalt_context.py` and `asphalt_summary.py` do this automatically: they
locate `pitstop.log` alongside the resolved `asphalt.log` target (the
run script also symlinks it into `sim/rtl_sim/run/` next to `asphalt.log`)
and, respectively, **interleave** the events into the printed window
(prefixed `#`, in cycle order) and summarise them (a *Debug activity* line
plus the halt-enter/resume events with `dcsr.cause`). Pass
`--no-debug-events` to either tool to suppress the merge. Shared discovery
and parsing live in `sim/rtl_sim/bin/debug/pitstop.py`.

---

## See Also

- [`sim/rtl_sim/bin/debug/DEBUG_MANUAL.md`](../sim/rtl_sim/bin/debug/DEBUG_MANUAL.md) — full debug-tool reference; how to triage a failing test using the trace + VCD together.
- [`simulation_guide.md` §8](simulation_guide.md#8-waveforms-and-debugging) — quick overview of artefacts and debug helpers.
- [`verification_guide.md`](verification_guide.md) — test taxonomy, the `x31` sync mechanism, registering tests.
- [`benchmarking_guide.md` §7](benchmarking_guide.md#7-trace-artefacts--snapshot-workflow) — how the snapshot pipeline uses these traces.
- [`bench/verilog/probes_instructions.v`](../bench/verilog/probes_instructions.v) — the generator (canonical source of truth).
