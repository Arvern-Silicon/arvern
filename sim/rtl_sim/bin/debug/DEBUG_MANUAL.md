# arvern Debug Tools Manual

Reference for the trace (`asphalt.log`) and waveform (`tb_arvern.vcd`) analysis
scripts in `sim/rtl_sim/bin/debug/`. All commands assume you are in
`sim/rtl_sim/run/` after a test run, i.e. with `asphalt.log` and `tb_arvern.vcd`
present in the current directory. Scripts are reached as `../bin/debug/<name>.py`.

For an AI agent: prefer these scripts to hand-rolled grep/awk on the trace or
custom VCD parsers — they handle Zcmp multi-memory lines, livelock heuristics,
clock-period auto-detection, and hierarchical signal-name resolution.

---

## Quick-Start Workflow

```
1. Run failing test:       ./run <test> -seed <N>
2. Summarize trace:        python3 ../bin/debug/asphalt_summary.py
3. Locate the event:       python3 ../bin/debug/asphalt_context.py --trap 3
4. Check VCD signals:      python3 ../bin/debug/vcd_find.py tb_arvern.vcd trap_taken --rise
5. Correlate:              python3 ../bin/debug/asphalt_annotate.py asphalt.log tb_arvern.vcd irq_detect trap_pending_o trap_taken --cycles 400:600
6. Drill into causes:      python3 ../bin/debug/vcd_cause.py tb_arvern.vcd trap_taken --cycle 412 --depth 2
7. Open in GTKWave:        python3 ../bin/debug/vcd_gtkwave.py tb_arvern.vcd irq_software_i trap_pending_o trap_taken irq_suppress_post_mret --cycles 400:600 --out debug.gtkw && gtkwave debug.gtkw
```

---

## Tool Reference

### asphalt_summary.py — Trace Overview

Print statistics for an entire execution trace: trap count, MRET count,
livelock detection (repeated PC windows), final cycle.

```
python3 ../bin/debug/asphalt_summary.py [asphalt.log]
python3 ../bin/debug/asphalt_summary.py asphalt.log --traps-only
python3 ../bin/debug/asphalt_summary.py asphalt.log --livelock-threshold 50
```

**When to use**: First step after any failure.  Shows immediately if the right
number of traps/MRETs occurred, and flags a livelock when a PC window repeats
≥100 times (tunable with `--livelock-threshold`).

**Output example**:
```
# asphalt.log  (82 instructions,  last cycle: 580)

Trap events (3):
  #1  cycle=140    IRQ:MSW   at 0x200000a0
  #2  cycle=272    IRQ:MSW   at 0x200000a0
  #3  cycle=425    IRQ:MSW   at 0x200000a0

MRET/SRET events (3):
  #1  cycle=246    MRET      at 0x200000fc
  ...

LIVELOCK DETECTED: PC window 0x20000026-0x2000002c repeated 127 times
```

---

### asphalt_context.py — Context Around an Event

Show N instructions before and after a specific anchor point in the trace.
Anchors: Nth trap event, Nth MRET, closest cycle number, or Nth occurrence
of a PC address.

```
python3 ../bin/debug/asphalt_context.py --trap 3             # context around 3rd trap
python3 ../bin/debug/asphalt_context.py --mret 2             # context around 2nd MRET
python3 ../bin/debug/asphalt_context.py --cycle 425          # closest to cycle 425
python3 ../bin/debug/asphalt_context.py --pc 0x200000a0      # first occurrence of PC
python3 ../bin/debug/asphalt_context.py --pc 0x200000a0 --nth 3   # third occurrence
python3 ../bin/debug/asphalt_context.py --trap 3 --before 15 --after 10
```

Default window: 8 lines before, 4 after.  The anchor line is prefixed with `>>>`.

**When to use**: Once `asphalt_summary` shows the wrong trap/MRET count, use
this to see exactly what the processor was doing before and after the event.

---

### asphalt_diff.py — Compare Two Traces

Find where two runs first diverge (by PC sequence by default).  Useful for
comparing a passing run vs a failing run.

```
python3 ../bin/debug/asphalt_diff.py pass.log fail.log
python3 ../bin/debug/asphalt_diff.py pass.log fail.log --field all   # compare all fields
python3 ../bin/debug/asphalt_diff.py pass.log fail.log --show 10     # show 10 lines after divergence
```

Fields: `pc` (default), `mnemonic`, `instr`, `trap`, `br`, or `all`.

**When to use**: When you have a known-good run (e.g., seed=0 passes) and
a failing seed.  Saves both `.log` files with `-seed`, then diff them to
pinpoint exactly where the two executions part ways.

**Tip**: Save traces with:
```bash
./run <test> -seed 0 && cp asphalt.log pass.log
./run <test> -seed 1781569746 && cp asphalt.log fail.log
python3 ../bin/debug/asphalt_diff.py pass.log fail.log
```

---

### asphalt_perf_diff.py — Cycle-Delta Diff Between Two Runs

Aligns two traces (`log_a` = reference, `log_b` = compared) at a chosen
anchor and computes per-instruction cycle deltas from there. Complements
`asphalt_diff.py` (functional first-divergence) by attributing the *timing*
difference to instructions, mnemonics, memory targets, and PCs — including
a branch-target alignment-flip rollup that auto-detects whether the
slowdown is an alignment artifact.

```
# Same symbol addresses in both binaries:
python3 ../bin/debug/asphalt_perf_diff.py ref.log cmp.log --anchor 0x20000690

# Different addresses -- supply per-trace PCs:
python3 ../bin/debug/asphalt_perf_diff.py ref.log cmp.log \
    --anchor-a 0x20000690 --anchor-b 0x200006c0

# Easiest: let nm resolve "main" from each ELF:
python3 ../bin/debug/asphalt_perf_diff.py ref.log cmp.log \
    --elf-a ref.elf --elf-b cmp.elf --anchor-sym main
```

**Output sections**:
- Aggregate cycle delta (sum + percentage; positive = log_b slower than log_a)
- Top-N mnemonics by extra cycles (with per-instr average)
- Top-N memory targets by slave bucket (ROM / SRAM_X / SRAM_NX / periph / PLIC)
- R / W / `-` (load / store / ALU) breakdown
- Top-N PCs with `PC_a`, `PC_b`, their mod-4 alignment, and a flip column
- **Alignment-flip rollup**: aggregates across ALL nonzero-delta PCs into
  `4-4`, `4->2`, `2->4`, `2-2` buckets

**When to use**: When two binaries with identical `.text` (or text shifted
by a fixed offset, e.g. different `.rodata` location or different libc) run
at different speeds and you want to know *where* the cycles went. The
alignment-flip rollup is the killer feature — a net positive delta
concentrated in the `4->2` bucket is a smoking gun for branch-target
misalignment caused by a non-multiple-of-4 `.text` shift in the compared
binary.

**Trace prerequisites**: both traces must have an *identical PC sequence*
after the anchor (modulo a constant PC offset derived from the anchor
delta). PC mismatches after that are reported and stop the alignment.

---

### asphalt_annotate.py — Fuse Trace + VCD

Print each asphalt.log line (abbreviated) with VCD signal values appended at
the dispatch cycle for that instruction.

```
python3 ../bin/debug/asphalt_annotate.py asphalt.log tb_arvern.vcd \
    irq_detect irq_suppress_post_mret trap_pending_o trap_taken \
    --cycles 400:600

python3 ../bin/debug/asphalt_annotate.py asphalt.log tb_arvern.vcd \
    irq_software_i mstatus_mie trap_pending_o trap_taken \
    --traps-only                    # only lines with trap != "-"
```

**When to use**: The definitive correlation tool.  When you know *which* cycles
are wrong (from `asphalt_summary`/`asphalt_context`) and want to see exactly
which control signals were set at each instruction dispatch.  Ideal for
IRQ-related bugs where the interaction between firmware and hardware matters.

**Note on clock period**: Auto-detected from `hclk` signal.  Override with
`--clk-period 10000` if detection fails.

---

### vcd_trace.py — Signal Table from VCD

Display a table of signal values over a cycle range, one row per change.

```
python3 ../bin/debug/vcd_trace.py tb_arvern.vcd irq_software trap_taken --cycles 550:700
python3 ../bin/debug/vcd_trace.py tb_arvern.vcd mstatus_mie --transitions
python3 ../bin/debug/vcd_trace.py tb_arvern.vcd --list           # list all signals
python3 ../bin/debug/vcd_trace.py tb_arvern.vcd --grep trap      # search signal names
python3 ../bin/debug/vcd_trace.py tb_arvern.vcd irq_software_i mstatus_mie irq_detect \
    trap_pending_o trap_taken irq_suppress_post_mret \
    --cycles 540:640 --clk-period 10000
```

**When to use**: Precise signal timeline.  After `asphalt_annotate` identifies
the suspicious cycle window, use this to see every signal change within it.

---

### vcd_find.py — Find Signal Transitions

Find all timestamps where a signal rises, falls, or equals a value.

```
python3 ../bin/debug/vcd_find.py tb_arvern.vcd trap_taken --rise
python3 ../bin/debug/vcd_find.py tb_arvern.vcd irq_software_i --rise --cycles 500:700
python3 ../bin/debug/vcd_find.py tb_arvern.vcd mstatus_mie --fall
python3 ../bin/debug/vcd_find.py tb_arvern.vcd mhpmcounter3 --value 0x4
```

**When to use**: Quick sanity check on event counts.  E.g., "did `trap_taken`
really rise 4 times?" — if it only shows 3 rising edges, something is wrong.
Also useful to find the exact cycle a signal first reaches a value.

---

### vcd_cause.py — Cause Tree at a Cycle

Show a signal's value and all its defined driver signals at a given cycle,
recursively to a configurable depth.  The signal dependency graph is defined
in `cause_tree.json`.

```
python3 ../bin/debug/vcd_cause.py tb_arvern.vcd trap_taken --cycle 412
python3 ../bin/debug/vcd_cause.py tb_arvern.vcd irq_detect --cycle 570
python3 ../bin/debug/vcd_cause.py tb_arvern.vcd trap_taken --cycle 412 --depth 2
python3 ../bin/debug/vcd_cause.py tb_arvern.vcd trap_taken --cycle 412 --config my_cause_tree.json
```

**When to use**: After finding a suspicious cycle with `vcd_find`, use this to
immediately see the full causal chain without manually listing every signal in
`vcd_trace`.  E.g., if `trap_taken=0` at cycle 412 but should be 1, check
`trap_pending_o` and `trap_drained` automatically.

**Extending cause_tree.json**: Add new signals as needed:
```json
"my_signal": {
  "desc": "human-readable formula",
  "causes": ["driver1", "driver2"]
}
```

Currently defined signals: `trap_taken`, `trap_drained`, `pipeline_drained_for_irq`,
`pipeline_drained_for_id`, `irq_detect`, `trap_pending_o`, `irq_suppress_post_mret`,
`irq_suppress_clr`, `trap_stall_o`, `trap_stall_raw`, `wb_ldst_ready_o`, `ex_ldst_ready_o`.

---

### vcd_gtkwave.py — Generate GTKWave Save File

Generate a `.gtkw` save file pre-zoomed to a cycle range with specified signals.

```
python3 ../bin/debug/vcd_gtkwave.py tb_arvern.vcd \
    irq_software_i mstatus_mie irq_detect trap_pending_o trap_taken irq_suppress_post_mret \
    --cycles 400:600 --out irq_debug.gtkw
gtkwave irq_debug.gtkw

python3 ../bin/debug/vcd_gtkwave.py tb_arvern.vcd --from-file signals.txt --cycles 400:600 --out debug.gtkw
```

**When to use**: When you need interactive waveform browsing (GTKWave).  The
generated file opens directly at the right zoom level with the relevant signals
pre-loaded — no manual signal dragging.

**signals.txt format** (one per line, `#` = comment):
```
irq_software_i
# trap signals
trap_pending_o
trap_taken
```

---

## Common Debug Scenarios

### Scenario: Wrong IRQ count / livelock

```bash
# 1. How many traps/MRETs?
python3 ../bin/debug/asphalt_summary.py

# 2. See what happened around last trap
python3 ../bin/debug/asphalt_context.py --trap 3 --before 20

# 3. Count trap_taken edges in VCD (should match trap count in asphalt)
python3 ../bin/debug/vcd_find.py tb_arvern.vcd trap_taken --rise

# 4. If counts differ: check the cycle before the discrepancy
python3 ../bin/debug/vcd_cause.py tb_arvern.vcd trap_pending_o --cycle 412 --depth 2

# 5. Full picture at suspicious cycle range
python3 ../bin/debug/asphalt_annotate.py asphalt.log tb_arvern.vcd \
    irq_software_i irq_detect irq_suppress_post_mret trap_pending_o trap_taken \
    --cycles 400:450
```

**Root cause found in this session (seed 1781569746)**:  `trap_taken` is purely
combinatorial (`trap_pending_o & trap_drained`).  At the cycle when
`trap_pending_o` first goes high, `trap_drained` is momentarily 1, causing a
delta-cycle glitch (0→1→0 within one timestep) invisible in the VCD.  The
testbench `@(posedge trap_taken)` fires on this glitch and double-counts.
**Fix**: sample `trap_taken` at `@(posedge free_clk)` in the ACTIVE region
(not `@(posedge trap_taken)`), which only sees settled values.

### Scenario: Two runs diverge (seed-dependent failure)

```bash
./run <test> -seed 0 -nodump && cp asphalt.log pass.log
./run <test> -seed 1234 -nodump && cp asphalt.log fail.log
python3 ../bin/debug/asphalt_diff.py pass.log fail.log
# Find first PC divergence, then:
python3 ../bin/debug/asphalt_context.py fail.log --cycle <diverge_cycle> --before 20
```

### Scenario: Pipeline stall / never drains

```bash
python3 ../bin/debug/vcd_cause.py tb_arvern.vcd pipeline_drained_for_irq --cycle <N> --depth 2
# Shows ex_alu_ready, ex_ldst_ready, etc. to find which stage is stuck
```

---

## Artefact Locations

After a test run, both `tb_arvern.vcd` and `asphalt.log` are left in
`sim/rtl_sim/run/`.

- Do **not** pass `-nodump` when you need VCD analysis (regressions set
  `SIMULATION_NODUMP=1` automatically, so VCD is suppressed there).
- The asphalt trace is suppressed by the `NOTRACE` define (also set by
  regressions to avoid multi-MB log files); a normal single-test run leaves
  it in place.

### asphalt.log column format

Canonical spec lives in [`doc/asphalt_trace_format.md`](../../../doc/asphalt_trace_format.md)
(all 13 columns, trailing annotations, snapshot header layout). Read it
before writing any custom parser — the `asphalt_*` scripts in this
directory already handle every edge case (Zcmp `# <N> mem ops`, trap
annotations, snapshot-vs-raw header skip).

---

## Clock Period

The VCD timescale is `100ps`.  The default clock is 100 MHz → period = `10000`
ticks.  All scripts auto-detect the clock period from the `hclk` signal; you
only need `--clk-period 10000` if auto-detection fails.
