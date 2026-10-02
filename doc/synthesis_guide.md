<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Synthesis Guide
  <br clear="all">
</h1>

---

## Table of Contents

**Part I — Results**

1. [Introduction](#1-introduction)
2. [Area Results](#2-area-results)

**Part II — Methodology**

3. [Flow Overview](#3-flow-overview)
4. [Quick Start](#4-quick-start)
5. [Library Flavor (`LIB_FLAVOR`)](#5-library-flavor-lib_flavor)
6. [Constraints](#6-constraints)
7. [DFT Insertion](#7-dft-insertion)
8. [RTL-Config Sweep](#8-rtl-config-sweep)
9. [Closing Timing — Critical Paths](#9-closing-timing--critical-paths)
10. [Waivers](#10-waivers)
11. [Output Files](#11-output-files)
12. [Beyond Synthesis (P&R notes)](#12-beyond-synthesis-pr-notes)
13. [Lint Flows](#13-lint-flows)

---

## 1. Introduction

This guide walks through the bundled Synopsys Design Compiler flow under
`synthesis/synopsys/`, the technology-library plug-in mechanism (`LIB_FLAVOR`),
constraints, DFT, the RTL-config sweep, tips for closing timing on the two
parameter axes that matter most for clock frequency (`SINGLE_CYCLE_BRANCH`,
`MUL_TYPE`), and the two lint flows that share the sweep set.

It targets **ASIC and FPGA implementers**. For SoC integration (ports, IRQ,
AHB) see [`integration_guide.md`](integration_guide.md).

**Part I** (§2) reports the synthesized **area** results for the four reference
personas; **Part II** (§§3–13) is the synthesis flow itself — how those numbers
are produced and how to close timing. The persona parameter vectors are defined
once in [`benchmarking_guide.md` §1.2](benchmarking_guide.md#12-arvern-personas)
— the sibling guide that reports benchmark **speed** on the same personas — and
are not duplicated here.

---

## 2. Area Results

Synthesized area for the four reference personas, plus per-module breakdown (with
scan insertion enabled). This is the single home for absolute area numbers; the
dials in §9.3 describe *relative* effects, and the benchmark / IPC results for the
same personas live in [`benchmarking_guide.md`](benchmarking_guide.md).

**Measurement basis.** Every number in this section comes from the same library, the
same constraints and the same flow for every persona — `compile_ultra -scan
-no_autoungroup` followed by `optimize_netlist -area`, scan inserted — and is reported in
kGates (NAND2 equivalents of the library's smallest NAND2 cell). The absolute values
are library-dependent; the ratios between personas and between rows are the point.

### 2.1 Per-persona headline

Headline area summary for the four reference personas:

| Persona | Total area | Flop count |
|---|---:|---:|
| **Light** | 32.0 kGates | ~1,520 |
| **Classic** | 51.5 kGates | ~2,180 |
| **Performance** | 69.1 kGates | ~2,600 |
| **Ultra** | 81.6 kGates | ~3,160 |

`Performance` and `Ultra` include PMP (4 and 8 entries); `Light` and `Classic` do not.

### 2.2 Per-module area breakdown

Per-module area for each persona, populated by
`./run_syn -rtl_config light,classic,performance,ultra` (see [§8](#8-rtl-config-sweep)).
Area is reported in **kGates (NAND2-equivalent)**, with scan insertion enabled during synthesis.

|  |                                                    **Light** |                                                 **Classic** |                                              **Performance** |                                                    **Ultra** |
|---|---:|---:|---:|---:|
| **Configuration** | <i>RV32E<br/>no debug<br/>Zmmul (16c)<br/>M-only<br/>Zca<br/>no PMP<br/><br/></i> | <i>RV32I<br/>no debug<br/>1c MUL + 33c DIV<br/>M-only<br/>Zca<br/>Zbb<br/>Zicntr<br/>no PMP</i> | <i>RV32I<br/>no debug<br/>1c MUL + 12c DIV<br/>M+S+U<br/>Zca + Zcb<br/>full B<br/>Zicntr<br/>PMP ×4</i> | <i>RV32I<br/>no debug<br/>1c MUL + 12c DIV<br/>M+S+U<br/>full C<br/>full B<br/>Zicntr + Zihpm×4<br/>PMP ×8</i> |
| Integer Register File | 10.1 | 19.5 | 19.5 | 19.6 |
| ALU<br/>*(incl. enabled B-ext sub-extensions)* | 1.4 | 2.6 | 6.8 | 6.8 |
| MUL / DIV<br/>*(M-extension, when present)* | 2.1 | 7.7 | 11.0 | 10.7 |
| Instruction Decode<br/>*(unified RV32I/E + C)* | 5.4 | 5.6 | 5.9 | 6.1 |
| Instruction Fetch<br/>*(prefetch buffer; PMP fetch checker when `PMP_NR > 0`)* | 4.3 | 4.3 | 6.7 | 8.7 |
| Load/Store Unit<br/>*(PMP load/store checker when `PMP_NR > 0`)* | 1.7 | 1.7 | 3.9 | 6.2 |
| CSR core<br/>*(mtraps + ids + decode + read-mux, incl. Smrnmi; S-mode bank and PMP CSRs when present)* | 6.8 | 6.9 | 12.0 | 14.2 |
| CSR Zicntr<br/>*(cycle / instret + U-mode shadows)* | 0.0 | 3.1 | 3.2 | 3.2 |
| CSR Zihpm<br/>*(mhpmcounter3–N + event selectors)* | 0.0 | 0.0 | 0.0 | 4.7 |
| UOP Sequencer<br/>*(Zcmp / Zcmt, when present)* | 0.0 | 0.0 | 0.0 | 1.1 |
| **Total (aRVern)** | **32.0** | **51.5** | **69.1** | **81.6** |
| Sequential cells (flop count) | ~1,520 | ~2,180 | ~2,600 | ~3,160 |

> **Note:** kGate area is a synthesis-only estimate. Different target nodes and/or synthesis tools will give different results.

> All numbers in this section are for the default **asynchronous** reset
> (`ASYNC_RST_EN=1`); the synchronous-reset saving is a row of §2.4, its trade-offs are
> in §9.3.

### 2.3 Debug subsystem area cost

External debug is off in all four base personas (`DEBUG_EN=0`; every debug-module row in
§2.2 reads 0). Each persona has a `<persona>-dbg` twin — identical in every other parameter
but with `DEBUG_EN=1` and a trigger count on a **0 / 2 / 4 / 8** ladder — so the debug cost
is simply `<persona>-dbg` − `<persona>`. Light-dbg carries **no** triggers, so its whole
delta is the `DEBUG_EN=1` interface; the incremental delta across the trigger-bearing tiers
gives the cost of one Sdtrig mcontrol6 trigger.

| Debug feature | Area cost |
|---|---:|
| **External debug** (`DEBUG_EN=1`) — DM core + DMI/APB slave + SBA master + hart debug CSRs | **~4.3 kGates** |
| **Each Sdtrig HW trigger** (one `DM_TRIGGER_NR` increment) | **~1.0 kGates** |

The `-dbg` twins (kGates, same basis as §2.2):

| Persona | Triggers (`DM_TRIGGER_NR`) | Base | `-dbg` total | Δ debug |
|---|---:|---:|---:|---:|
| Light | 0 | 32.0 | 36.3 | 4.3 |
| Classic | 2 | 51.5 | 58.2 | 6.7 |
| Performance | 4 | 69.1 | 77.7 | 8.6 |
| Ultra | 8 | 81.6 | 94.6 | 13.0 |

- **`DEBUG_EN=1` = 4.3 kGates** = Δ(Light) — 0 triggers, so the entire delta is the
  DM/DMI/SBA/CSR interface (composition below). Δ(Light) is the *clean* read: light-dbg's
  non-debug module rows match the base persona within noise.
- **Per trigger ≈ 1.0 kGates** — the "Debug Triggers" module row alone gives
  0.98 (Classic) / 0.97 (Performance) / 0.98 (Ultra) kGates per trigger, the flattest read
  (it excludes the interface). The per-trigger cost is architectural: `tdata2` (32 flops)
  plus the two 32-bit equal/NAPOT address comparators (execute + load/store paths).

Composition of the `DEBUG_EN=1` interface, from the light-dbg per-module report (the extra
~0.6 kGates over the debug-module subtotal is debug logic that lands in the *existing*
modules — chiefly the abstract-access GPR port the DM adds to the register file for
frozen-hart access, plus the debug-mode / issue-stall gating in decode and the CSR read path):

| Component | kGates |
|---|---:|
| Debug Module core | 1.6 |
| Debug SBA (System Bus Access master) | 1.3 |
| Debug CSRs (hart-side `dcsr` / `dpc`) | 0.8 |
| **Debug modules subtotal** | **3.7** |
| Core-side debug logic (regfile abstract-access port + decode / CSR gating) | ~0.6 |
| **Total (`DEBUG_EN=1` = Δ Light)** | **~4.3** |

A debug build with the tier's trigger file runs 12–16 % over the base persona (Light
+13 %, Classic +13 %, Performance +12 %, Ultra +16 %). §2.4 gives the same two costs
measured on the minimal and the full configuration.

> Two design choices keep the interface small: DMI `PRDATA` is driven combinationally (no
> response register), and `dpc` is captured directly at debug entry (no entry-PC shadow
> register).

### 2.4 Feature cost

What each configuration parameter costs, measured two ways because feature costs are
**not additive**: a feature added to a minimal core and the same feature removed from a
full one do not cost the same gates (the PMP checkers scale with S-mode, the Zcb
sign/zero-extend ops share the Zbb datapath, the S-mode CSR bank grows with Zicntr, a
divider is cheaper next to a single-cycle multiplier). The two columns bracket the real
cost of a feature in your own configuration:

- **+ on Light** — the `light` persona with this one feature added (or one implementation
  choice changed); sweep set `ofat-light` (`rtl_sweep_configs.py:OFAT_LIGHT`).
- **− from Full** — the feature-rich `run_config.json` default build with this one feature
  removed (or changed); the `ofat:` entries of the standard sweep set.

Same library and constraints as §2.1; kGates, NAND2-equivalent, scan inserted. A `—`
means the step does not exist from that end (the feature is already at that value in
the base). "Lands in" names the `report.area_analysis.txt` module rows that carry the
delta.

| Feature step | + on Light | − from Full | Lands in |
|---|---:|---:|---|
| RV32I register file (`RV32E_EN` 0, vs RV32E) | +9.2 | +9.1 | Integer Register File |
| Zmmul multiplier (`M_EXTENSION` 1, vs none) | +2.4 | +5.7 | MUL / DIV |
| Divider, radix-2 / 33 cycles (`M_EXTENSION` 2, `DIV_TYPE` 3, vs Zmmul) | +1.4 | +1.9 | MUL / DIV |
| Divider radix-4 / 17 cycles (`DIV_TYPE` 2, vs radix-2) | +1.0 | +1.3 | MUL / DIV |
| Divider radix-8 / 12 cycles (`DIV_TYPE` 1, vs radix-2) | +3.3 | +3.4 | MUL / DIV |
| Multiplier 4-cycle (`MUL_TYPE` 2, vs 16-cycle) | +1.1 | +1.2 | MUL / DIV |
| Multiplier single-cycle (`MUL_TYPE` 1, vs 16-cycle) | +3.6 | +4.1 | MUL / DIV |
| Zbb (`B_EXTENSION` 1) | +1.1 | +1.4 | ALU |
| + Zba (`B_EXTENSION` 2) | +0.7 | +0.7 | ALU |
| + Zbs (`B_EXTENSION` 3) | +0.4 | +0.2 | ALU |
| + Zbc (`B_EXTENSION` 4) | +3.4 | +3.1 | ALU |
| Zca (`C_EXTENSION` 1, vs no compressed) | +1.9 | +1.8 | Instruction Decode, Instruction Fetch |
| + Zcb (`C_EXTENSION` 2) | +0.0 | +0.1 | Instruction Decode |
| + Zcmp (`C_EXTENSION` 3) | +1.2 | +1.1 | UOP Sequencer, Instruction Decode |
| + Zcmt (`C_EXTENSION` 4) | +0.9 | +1.1 | UOP Sequencer |
| S + U modes (`SU_MODE_EN` 1) | +3.3 | +3.7 | CSR core |
| PMP 4 entries, M-only core (`PMP_NR` 4) | +6.2 | — | Instruction Fetch, Load/Store Unit, CSR core |
| PMP 8 entries, M-only core | +11.9 | — | same |
| PMP 16 entries, M-only core | +23.2 | — | same |
| PMP 4 entries with S + U | +6.4 | +6.5 | same |
| PMP 8 entries with S + U | +12.0 | +12.3 | same |
| PMP 16 entries with S + U | +23.6 | +23.7 | same |
| Zicntr (`ZICNTR_EN` 1) | +3.4 | +2.9 | CSR Zicntr |
| Zihpm, 1 counter (`ZIHPM_NR` 1) | +1.1 | +1.2 | CSR Zihpm |
| Zihpm, 4 counters | +4.6 | +5.0 | CSR Zihpm |
| Zihpm, 8 counters | +9.1 | +9.8 | CSR Zihpm |
| External debug, no triggers (`DEBUG_EN` 1) | +4.4 | — | Debug Module core, Debug SBA, Debug CSRs |
| + 1 Sdtrig trigger (`DM_TRIGGER_NR` 1) | +1.3 | +1.4 | Debug Triggers |
| + 2 Sdtrig triggers | +2.1 | +2.5 | Debug Triggers |
| + 4 Sdtrig triggers | +4.1 | +4.3 | Debug Triggers |
| + 8 Sdtrig triggers | +8.6 | +8.7 | Debug Triggers |
| Custom CSR interface (`CCSR_EN` 1) | +0.0 | +0.2 | CSR core |
| One-bubble branch (`SINGLE_CYCLE_BRANCH` 0) | -1.3 | -1.1 | Instruction Fetch, Instruction Decode |
| Synchronous reset (`ASYNC_RST_EN` 0) | -2.1 | -4.6 | every module (smaller flops) |

Where the two columns differ, the gap is the interaction. The multiplier is the clearest
case: adding Zmmul costs +2.4 kGates on Light (whose `MUL_TYPE` is the 16-cycle
implementation) but +5.7 removing it from Full (single-cycle) — the extension and the
implementation choice are separate rows for that reason. PMP is the opposite: 4 entries
cost +6.2 on an M-only core and +6.4 with S+U, so the Smepmp/S-mode logic is a small part
of it and the entry count dominates (+5.7 per additional four entries). The external-debug
interface has no "− from Full" value because the default build carries four triggers, so
removing `DEBUG_EN` alone is not a one-factor step; §2.3 measures it from the persona
ladder instead.

The sum of the "+ on Light" column does not reproduce a persona total, and is not meant
to: Ultra is Light plus sixteen of these steps, whose light-side costs add up to 82.3
kGates against a measured 81.6 — close here (−0.7), but nothing guarantees it, and the
divider and PMP rows show how far a single interaction can move. To size a configuration that is neither a persona nor a
one-step neighbour of one, synthesize it (§8, `-rtl_config`).

Reproduce: `./run_syn_d -rtl_config light,<ofat-light labels…>` for the left column
(labels from `./run_syn -list_configs` or `rtl_sweep_configs.py:OFAT_LIGHT`, e.g.
`ofat-light:SU_MODE_EN=1.PMP_NR=4`), the `ofat:` indices of the sweep set for the right
column; `doc_area_tables.py --features` renders this table from `results_sweep/`.

---

## 3. Flow Overview

The synthesis flow lives under `synthesis/synopsys/` and is built around
`dc_shell` (Synopsys Design Compiler):

```
run_syn ─▶ dc_shell-t -f synthesis.tcl
                    │
                    ├─▶ library.tcl           (technology library, gated by LIB_FLAVOR)
                    ├─▶ read.tcl              (RTL files + analyze)
                    ├─▶ constraints.tcl       (clock + path groups)
                    ├─▶ constraints_ports.tcl (per-port I/O delays)
                    ├─▶ compile_ultra         (with optional scan + DFT)
                    └─▶ report_*.tcl          (timing / area / RTL-config reports)
```

`read.tcl` itself is hand-maintained, but the two inputs that vary per config
are **auto-generated** and sourced by it during elaboration:

- `rtl_params.tcl` — the RTL parameter values, generated by `gen_rtl_params.py`
  from `sim/rtl_sim/run/run_config.json`.
- `submit_syn.tcl` — the RTL source-file list, generated by
  `flatten_filelist.py --format tcl` from `rtl/verilog/filelist.f`.

So the synth config tracks the same parameters — and the same RTL file list —
that the sim regression uses. (If `rtl_params.tcl` is absent, `read.tcl` falls
back to elaborating with the module-declaration default parameters and prints a
hint to run `gen_rtl_params.py`.)

A run creates the `WORK/` design library and the `alib-52/` cache next to the scripts
(both gitignored) and **wipes `./results/`** at its start; copy anything you want to keep
before re-running.

---

## 4. Quick Start

### Prerequisites

The repository ships only the library template
`synthesis/synopsys/libraries/setup_lib_example.tcl`; the default flavor file
`setup_lib_default.tcl` is intentionally absent, because it names your technology. Create
it for your environment before the first run:

```bash
cd synthesis/synopsys
cp libraries/setup_lib_example.tcl libraries/setup_lib_default.tcl
$EDITOR libraries/setup_lib_default.tcl    # .db paths, library names, opcons, period
```

Naming it `setup_lib_default.tcl` makes it the default; any other
`setup_<flavor>.tcl` is selected with `-lib <flavor>` (§5). Without a flavor file
`./run_syn` stops with "Unknown library flavor".

### Commands

```bash
cd synthesis/synopsys

./run_syn                                        # default flavor (lib_default), config from run_config.json
./run_syn -lib lib_a                             # target your own library flavor "lib_a"
./run_syn -lib lib_b -i                          # interactive — leaves dc_shell open
./run_syn -rtl_config classic                    # one persona (or a sweep index)
./run_syn -rtl_config light,classic,performance,ultra   # several — snapshot per config
./run_syn -rtl_config ultra -with_sync_reset     # same persona, ASYNC_RST_EN forced to 0
./run_syn -lib lib_c -rtl_sweep                  # sweep every RTL config
```

Results land in `./results/` (single config) or `./results_sweep/` (multi-config and
sweep runs).

| Flag | Meaning |
|---|---|
| `-lib <flavor>` | Library flavor: sources `libraries/setup_<flavor>.tcl` (default `lib_default`) |
| `-i` / `-noquit` / `--interactive` | Keep `dc_shell` open after synthesis |
| `-rtl_config N\|NAME[,…]` | Synthesize one or more sweep configs, by 1-based index, persona name (`light`, `classic`, `performance`, `ultra`, `<persona>-dbg`) or feature-cost name (`ofat-light:<label>`, §2.4), mixed freely. One entry writes `./results/`; several snapshot to `./results_sweep/persona_<name>/` or `./results_sweep/<NN>_<label>/` |
| `-rtl_sweep` | Every config in the shared sweep set (§8) |
| `-with_sync_reset` | Force `ASYNC_RST_EN=0` on top of the selected config (§9.3) |
| `-list_configs` | Print the sweep numbering (`gen_rtl_params.py --list-configs`) and exit |

---

## 5. Library Flavor (`LIB_FLAVOR`)

The `LIB_FLAVOR` mechanism keeps the synthesis flow technology-agnostic — the
top-level scripts never reference a specific library.

### How it works

`./run_syn -lib <flavor>` exports `LIB_FLAVOR=<flavor>`. The `library.tcl`
script reads the env var and sources `./libraries/setup_<flavor>.tcl`:

```tcl
if {[info exists ::env(LIB_FLAVOR)]} {
    set LIB_FLAVOR $::env(LIB_FLAVOR)
} else {
    set LIB_FLAVOR "lib_default"
}
source "./libraries/setup_${LIB_FLAVOR}.tcl"
```

### What a setup file does

A setup file is a `namespace eval <flavor> { … }` block of `variable` declarations —
`library.tcl` extracts the variables from that namespace after sourcing the file, so flat
`set` lines do not work. The shape, from `setup_lib_example.tcl`:

```tcl
namespace eval lib_example {
    variable LIB_WC_FILE   "<worst-case library>.db"
    variable LIB_WC_NAME   "<worst-case library name>"
    variable LIB_BC_FILE   "<best-case library>.db"
    variable LIB_BC_NAME   "<best-case library name>"
    variable LIB_WC_OPCON  "<worst-case operating condition>"
    variable LIB_BC_OPCON  "<best-case operating condition>"
    variable LIB_WIRE_LOAD "<wire-load model>"
    variable NAND2_NAME    "<smallest NAND2 cell>"
    variable CLOCK_PERIOD  <target clock period in ns>
}
```

| Variable | Meaning |
|---|---|
| `LIB_WC_FILE` / `LIB_BC_FILE` | Worst-case / best-case `.db` file(s); become `target_library` / `link_library`. `LIB_WC_FILE` may be a Tcl list (multi-Vt) |
| `LIB_WC_NAME` / `LIB_BC_NAME` | Worst-case / best-case library logical name |
| `LIB_WC_OPCON` / `LIB_BC_OPCON` | Operating condition names within the library |
| `LIB_WIRE_LOAD` | Wire-load model |
| `NAND2_NAME` | NAND2 cell name (used for gate-count equivalent reporting) |
| `CLOCK_PERIOD` | Target clock period (overrides `constraints.tcl`'s built-in default) |

`synthesis.tcl` consumes these:

```tcl
set_operating_conditions -max $LIB_WC_OPCON -max_library $LIB_WC_NAME \
                         -min $LIB_BC_OPCON -min_library $LIB_BC_NAME
set_wire_load_mode top
set_wire_load_model -name $LIB_WIRE_LOAD -max -library $LIB_WC_NAME
```

### Adding a new technology

```bash
cp ./libraries/setup_lib_example.tcl ./libraries/setup_my_flavor.tcl
$EDITOR ./libraries/setup_my_flavor.tcl    # set lib names, opcons, period
./run_syn -lib my_flavor
```

Foundry `.db` files are typically symlinked into `./libraries/` to avoid
duplicating multi-GB library data across projects. A `.gitignore` rule
covers the symlinks.

---

## 6. Constraints

### Clock

`constraints.tcl` creates the single core clock from `hclk_i`:

```tcl
create_clock -name "hclk" -period "$CLOCK_PERIOD" \
             -waveform "0 [expr $CLOCK_PERIOD/2]" [get_ports hclk_i]
```

`CLOCK_PERIOD` is set by the library setup file (§5), which `library.tcl` applies before
`constraints.tcl` runs; `constraints.tcl` falls back to its own built-in default only when
the flavor file sets none. Set it in the flavor file.

### Path groups

`constraints.tcl` defines path groups for clear reporting:

| Group | Paths |
|---|---|
| `REGIN` | All inputs (except `hclk_i`) → first flop |
| `REGOUT` | Last flop → all outputs |
| `FEEDTHROUGH_INST2INST` | Instruction bus inputs → instruction bus outputs (the single-cycle branch path) |
| `FEEDTHROUGH_DATA2INST` | Data bus inputs → instruction bus outputs (`data_hready_i` → `inst_haddr_o`: a data-bus stall releasing a fetch) |
| `FEEDTHROUGH_OTHER` | Every other input → output combinational path |

`FEEDTHROUGH_INST2INST` is the **critical path of the design** when
`SINGLE_CYCLE_BRANCH = 1`; `FEEDTHROUGH_DATA2INST` is the next tightest. Use them to
focus optimisation effort.

### Port I/O delays

`constraints_ports.tcl` sets per-port `set_input_delay` and `set_output_delay` as a
fraction of `CLOCK_PERIOD`: inputs at 50–55 % (instruction bus 50 %, data bus 55 %),
AHB outputs at 30 %, CCSR 30–60 %, DMI 50 % in / 40 % out, and the synchronous reset at
40 %. Adjust these to match your fabric's actual timing budget.

## 7. DFT Insertion

DFT is **enabled by default** (`WITH_DFT = 1` in `synthesis.tcl`). It uses a
3-chain multiplexed scan style:

```tcl
set_dft_signal -view existing_dft -type ScanClock -port hclk_i    -timing [list 45 55]
# hresetn_i (and dbgresetn_i on DEBUG_EN=1 builds) is declared as an async
# DFT Reset ONLY when ASYNC_RST_EN=1:
if {$RTL_PARAM_ASYNC_RST_EN} {
    set_dft_signal -view existing_dft -type Reset -port hresetn_i -active 0
    if {$RTL_PARAM_DEBUG_EN} {
        set_dft_signal -view existing_dft -type Reset -port dbgresetn_i -active 0
    }
}

set_dft_insertion_configuration -preserve_design_name true
set_scan_configuration -style multiplexed_flip_flop
set_scan_configuration -clock_mixing mix_clocks
set_scan_configuration -chain_count 3
```

The reset declaration is **reset-style-aware**: `hresetn_i` (and `dbgresetn_i` when
`DEBUG_EN=1`) is an asynchronous control only when `ASYNC_RST_EN=1`, so it's declared as a
DFT `Reset` (held inactive during scan shift) only then. Under synchronous reset it's an ordinary
data-path signal the scan mux bypasses during shift, so declaring it as an async
Reset would be wrong — and tends to leave a few stray async-reset cells in an
otherwise-synchronous netlist (catch them with `check_reset_style_pt.tcl`).

### To use a different DFT style

| Want | Edit |
|---|---|
| More / fewer chains | `-chain_count N` |
| Different scan style | `-style …` |
| Add `scan_enable` / `scan_mode` ports | Uncomment the commented `set_dft_signal` lines (they're in the template) |
| Disable DFT entirely | Set `WITH_DFT = 0` at the top of `synthesis.tcl` |

The flow writes a test protocol (`results/<DESIGN_NAME>.spf`) for ATPG.

---

## 8. RTL-Config Sweep

`./run_syn -rtl_sweep` runs synthesis across **every config** in the shared
sweep set defined by `bin/rtl_sweep_configs.py` (the same set used by
`./run_lint --sweep` and `./run_all -rtl_sweep`).

Per-config outputs land in `./results_sweep/<NN>_<label>/` with the
configuration snapshotted into `rtl_params.tcl`. The final summary line
per config:

```
Config  1: WNS=<slack> TNS=<slack> gates=<k> warn=<n> err=<n> waive=<n> - RV32E_EN=0, M_EXTENSION=2, ...
```

| Field | Meaning |
|---|---|
| `WNS` | Worst Negative Slack (post-DFT) |
| `TNS` | Total Negative Slack |
| `gates` | NAND2-equivalent gate count |
| `warn` / `err` | Counts of dc_shell messages |
| `waive` | Of those warnings, how many matched `waivers.txt` |

### Selective sweep

`./run_syn -rtl_config 1,4,15` runs only those configs and snapshots them to
`results_sweep/<NN>_<label>/`. Persona names are accepted in place of indices, mixed
freely (`-rtl_config 14,light,ultra-dbg`); a persona snapshots to
`results_sweep/persona_<name>/`. A **single** entry (`-rtl_config 4` or
`-rtl_config classic`) writes `./results/` instead, like a plain run.

### Mapping config indices to features

`./run_syn -list_configs` prints the (idx, label) map (identical to
`./run_all -rtl_sweep`'s mapping).

---

## 9. Closing Timing — Critical Paths

The two parameter axes that dominate the achievable clock frequency:

### 9.1 `SINGLE_CYCLE_BRANCH`

| Value | Effect on clock frequency | Effect on IPC |
|---|---|---|
| `1` (default) | Lower — `inst_hrdata → branch decode → inst_haddr` is combinational | zero-bubble taken branch |
| `0` | **Higher** — registered branch target | one bubble per taken branch |

Both options produce architecturally correct behaviour with any conformant AHB-Lite
consumer: the instruction-bus address phase never spans a wait state in either setting
([`memory_and_ahb.md` §6](memory_and_ahb.md#6-wait-states)).
The choice is a pure frequency/IPC trade-off — pick `=0` if you're frequency-bound, `=1`
if you're IPC-bound.

The critical path with `=1` is the `FEEDTHROUGH_INST2INST` group (see §6).
You can inspect it specifically with:

```tcl
report_timing -group FEEDTHROUGH_INST2INST -delay max -path full -max_paths 10
```

### 9.2 `MUL_TYPE` (and `DIV_TYPE`)

| `MUL_TYPE` | Cycles | Effect on clock frequency | Area |
|---:|---:|---|---|
| 1 | 1 | Lowest (whole 32×32 in one cycle) | Largest — §2.4 |
| 2 | 4 | Medium | Medium |
| 3 | 16 | Highest | Smallest |

If `MUL_TYPE = 1` is the binding path the `-rtl_sweep` flow automates the exploration of different  `MUL_TYPE` values.

### 9.3 Other dials

| Parameter | Effect |
|---|---|
| `B_EXTENSION` (esp. `>= 4`, the Zbc CLMUL tree) | Adds ALU depth on the EX path; area in [§2.4](#24-feature-cost) |
| `C_EXTENSION = 4` (Zcmp + Zcmt) | Adds the UOP sequencer and its CSR (`jvt`); no impact on the main critical path; area in §2.4 |
| `ZIHPM_NR` | No timing impact (64-bit counters are registered); area per counter in §2.4 |
| `ASYNC_RST_EN = 0` (sync reset) | Smaller flops (no async clear/preset port), saving in §2.4. Trade-offs: sync reset needs a running clock during reset assertion and turns `hresetn_i` into a *timed* high-fanout net (constrained in `constraints_ports.tcl`); async (`= 1`, default) is false-path'd in STA but needs an external reset-deassertion synchronizer. See §9.5. |

### 9.5 `arv_dff` register primitive — flatten before compile

Every flop in the design is an instance of the `arv_dff` or `arv_dff_sinit` register
primitive (reset style selected by `ARST_EN`; see the reset-architecture notes). `arv_dff`'s
body is `else if (en_i) q_o <= d_i`, i.e. an enabled flop. Everything below applies to
both primitives: the `ungroup` filter is `ref_name =~ arv_dff*`.

**The gotcha — and it only bites with `-no_autoungroup`:** this IP flow runs
`compile_ultra -no_autoungroup` so the real `arv_*` module boundaries survive for
the per-module area report ([§2.2](#22-per-module-area-breakdown)), DFT, and ECO. With autoungroup off, if the
`arv_dff` wrappers are *also* left intact (or only ungrouped *during* compile via
`set_ungroup … true`), DC maps each to the larger **native load-enable scan cell**
before it sees the surrounding context — ~1900 oversized flops, **≈+4–5% area at
identical timing**. The flop *count* is unchanged; the cells are just bigger.

**The fix (in `synthesis.tcl`, already in the flow):** `ungroup -flatten` all
`arv_dff` instances immediately after `read.tcl`, *before* constraints and
`compile_ultra`. Optimizing fully flat logic from the first pass lets DC pick the best cell per flop from the whole
library.

**When the explicit ungroup is (and isn't) needed.** It matters *only* because we
keep `-no_autoungroup`. Measured 2×2 (Ultra persona, async reset; the relative deltas
between the four flows are the point):

| `arv_dff` | `compile_ultra` | Area |
|---|---|---:|
| not ungrouped | `-no_autoungroup` | 70.2 kGates |
| **ungrouped** (this flow) | `-no_autoungroup` | **66.8 kGates** |
| not ungrouped | autoungroup | 66.4 kGates |
| ungrouped | autoungroup | 67.0 kGates |

If you let `compile_ultra` autoungroup (drop `-no_autoungroup`), it dissolves
`arv_dff` on its own and the explicit ungroup is redundant — area is ~the same.
The catch is autoungroup is non-deterministic about which *other* small `arv_*`
blocks it flattens too, which drops rows from the [§2.2](#22-per-module-area-breakdown) per-module breakdown. This
flow deliberately takes the 0.5 kGates (~0.7%) over the autoungroup minimum to
keep a predictable hierarchy.

---

## 10. Waivers

`waivers.txt` carries one extended-regex pattern per line. Any `Warning:`
line in `synthesis.log` matching a pattern is rewritten with a `[WAIVED]`
prefix and counted separately in the per-config summary (`waive=N`).

Format:

```
# This is a comment
^Warning:.*MV-201 Clock signal.*hclk_i.*
^Warning:.*UID-401 Reset signal.*hresetn_i.*
# Inline ' #notes' are stripped:
^Warning:.*SVR-3  # known DFT pattern in some older library kits
```

`build_waiver_pattern` (in `run_syn`) joins all patterns with `|` and applies
them after dc_shell finishes. Idempotent — re-running doesn't double-tag.

**Discipline:** only waive warnings you've understood and decided are
non-blocking. Treat the un-waived warning count as a per-config gate.

---

## 11. Output Files

After a single-config run, `./results/` contains:

| File | What |
|---|---|
| `<DESIGN>.gate.v` | Mapped gate-level Verilog netlist |
| `<DESIGN>.ddc` | Saved DC database (for re-loading in dc_shell) |
| `<DESIGN>.svf` | Set verification format (for formal equivalence) |
| `<DESIGN>.spf` | Test protocol (for ATPG / DFT) |
| `report.timing` | `check_timing` output |
| `report.check_timing_pre` | `check_timing` before compile |
| `report.paths.max.<GROUP>` | 200 worst setup paths per path group (`FEEDTHROUGH_INST2INST`, `FEEDTHROUGH_DATA2INST`, `FEEDTHROUGH_OTHER`, `REGIN`, `REGOUT`, `hclk`) |
| `report.full_paths.max.<GROUP>` | Full path detail for the top 5 per group |
| `report.paths.min` / `report.full_paths.min` | Hold paths, same two levels of detail |
| `report.timing_analysis.txt` | Per-group WNS/TNS summary — what `run_syn` parses for its summary line |
| `report.area` / `report.full_area` | Cell area (flat + hierarchical), with NAND2 equivalent appended |
| `report.area_analysis.txt` | Per-module kGates breakdown — the source of §2's tables and of the `gates=` field |
| `report.refs` | `report_reference` (instance map by cell type) |
| `report.constraints` | Constraint violations |
| `report.check` | `check_design` output (from `read.tcl`) |
| `report.dft_*` | DFT reports (scan configuration, chains, coverage, violations) |
| `synthesis.log` | Full dc_shell log (with `[WAIVED]` annotations) |
| `rtl_params.tcl` | Snapshot of the RTL parameters that built this netlist |

The `submit_syn.tcl` file (generated by `flatten_filelist.py --format tcl`)
sits in the working dir for inspection — same role as `submit_sim.f` in the
sim flow.

---

## 12. Beyond Synthesis (P&R notes)

The bundled flow stops at the gate-level netlist. For real tape-out you'll
hand off to a place-and-route flow (Innovus, ICC2, Genus + Innovus,
OpenROAD…). A few arvern-specific notes for that hand-off:

- **Single clock domain.** No CDC at the core boundary except the externally-
  required reset synchroniser and any optional `nmi_i` / `irq_platform_i`
  synchronisers in the SoC wrapper. No internal CDC analysis needed.
- **Clock gating.** `hclk_en_o` is the WFI clock-enable signal. Drive the SoC's ICG
  cell from `hclk_en_o | ~hresetn_i` — the reset term is mandatory for a
  synchronous-reset build (a sleeping hart must still see a clock edge to reset) and
  harmless otherwise; see
  [`integration_guide.md` §2.1](integration_guide.md#21-clock-enable-hclk_en_o), the
  single home of the ICG rule. Place the ICG just outside the core.
- **Scan chains.** Three chains by default. The P&R flow should route scan
  using the scan-architect tool of choice (DC's chain decisions are advisory).
- **Reset.** Async-assert / sync-deassert; the SoC supplies the synchroniser. In the DC
  flow `hresetn_i` (and `dbgresetn_i`) are false-pathed when `ASYNC_RST_EN=1` and timed
  as inputs at 40 % of the period when `ASYNC_RST_EN=0` (`constraints_ports.tcl`);
  reset-tree balancing is a P&R task.
- **`mvendorid` / `marchid` / `mimpid`.** Core-owned constants, not
  integrator-modifiable. The chip identity — including its revision — goes in
  the DTM's `IDCODE` (see [`integration_guide.md` §1](integration_guide.md#1-configuration-parameters),
  "Core identity registers").

---

## 13. Lint Flows

Two lint flows share the sweep set and numbering of §8 (`gen_rtl_params.py
--list-configs` prints it); both are gates on every persona.

**Verilator lint** — `sim/rtl_sim/run/run_lint` (`verilator --lint-only`):

| Flag | Meaning |
|---|---|
| `--sweep` | Lint every config in the sweep set |
| `--sweep-mode {all,corners,ofat,xprod,default,personas,coverage}` | Choose the sweep subset (`personas` = the four personas and their `-dbg` twins) |
| `--rtl-defaults` | Lint the module-declaration default parameters |
| `-e '<flags>'` | Extra Verilator flags |

Waivers live in `sim/rtl_sim/run/waivers.vlt`. Details in
[`simulation_guide.md` §5](simulation_guide.md#5-linting).

**VC Static signoff lint** — `lint/vc_static/run_vclint`:

| Flag | Meaning |
|---|---|
| `-rtl_config <idx\|persona>` | One config, by sweep index or persona name |
| `-rtl_sweep` | Every config in the sweep set |
| `-lang` | Add the LANGUAGE_CHECK ruleset — run it with `-j 1`; that checker deadlocks with `-j > 1` |
| `-top`, `-raw`, `-no_params`, `-i` | Top module override, raw (unfiltered) report, no parameter overrides, interactive shell |

Rules are in `rules.tcl`, waivers in `waivers.tcl`, results under
`lint/vc_static/results/` (single) or `results_sweep/` (sweep). The full option list is
in `lint/vc_static/README.md`.

One VC Static rule that Verilator and Icarus do not enforce: a wire must be declared before
the instance or `assign` that reads it.

---

## See Also

- [`benchmarking_guide.md`](benchmarking_guide.md) — benchmark speeds (CoreMark / Dhrystone / Embench) and IPC sensitivity for the same reference config tiers
- [`integration_guide.md`](integration_guide.md) — what the synthesised netlist's ports do
- [`simulation_guide.md`](simulation_guide.md) — the shared `bin/rtl_sweep_configs.py` configuration set
- `lint/vc_static/README.md` — VC Static flow reference
- `synthesis/synopsys/synthesis.tcl` — the top-level flow
- `synthesis/synopsys/libraries/setup_lib_example.tcl` — template for adding a new library
