#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    rtl_sweep_configs.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Single source of truth for the arvern RTL parameterization sweep configurations.
#----------------------------------------------------------------------------

"""
rtl_sweep_configs.py - the arvern RTL parameterization sweep set.

SINGLE SOURCE OF TRUTH for "which RTL parameter configurations to exercise".
Consumed by both:
  * bin/run_lint.py          (Verilator lint per config)
  * bin/test_config.py       (-rtl_sweep regression per config)

so the lint sweep and the simulation sweep are, by construction, the same
set of configurations. The hand-maintained per-parameter "enable" subkey in
run_config.json's rtl_config is therefore obsolete: configs are derived
algorithmically from each parameter's `allowed`/`default`, not from a
manually curated flag.

================================================================================
PARAMETERIZATION COVERAGE ARGUMENT
================================================================================
The full RTL parameter cross-product is infeasible (~2.9M points). Failures
across parameterizations are almost entirely *parameter-gated generate /
conditional* code (a signal unused-when-off, undriven-when-on, a width
mismatch in a tier-selected datapath, or -- for simulation -- a feature only
reachable in a particular tier). That space is covered by three construction
strategies, in increasing specificity:

  corners : every sweepable param at min(allowed) (LO) and at max(allowed)
            (HI). Exercises every parameter-gated generate in *both*
            polarities and the dominant all-off / all-on cross modes.

  ofat    : One-Factor-At-A-Time -- each param swept through every allowed
            value with all *other* params at their run_config default.
            Covers mid-tier values the corners miss and, because the
            "others" sit at the feature-rich default, transitively covers
            many feature-pair interactions (e.g. ofat:M_EXTENSION=0 carries
            default C_EXTENSION=4 -> "Zcb present, MUL_EN=0").

  xprod   : Targeted cross-products that NEITHER ofat (others=default) NOR
            the two homogeneous corners reach. Derived from the actual
            nested-generate structure (see the XPROD table comments), not
            guessed. The muldiv-cluster entries were each bug-sensitive
            proven (an isolating width-probe fails ONLY that one config).

  all     : default + corners + ofat + xprod, de-duplicated (recommended;
            this is the sweep the design must pass for tapeout, and the set
            -rtl_sweep regresses).

Single source of truth for the per-parameter `allowed`/`default` is
run_config.json's `rtl_config` (same file runsim and the synthesis param
generator read). MVENDORID is excluded: its `allowed` is the empty
free-valued sentinel and its value is a Verilog string literal that is a
lint-neutral constant kept at the design default (it is still emitted at
its default into the generated parameterization file for simulation, just
never swept).
================================================================================
"""

import json

# ---------------------------------------------------------------------------
# Targeted cross-product table (the parameter-interdependency analysis).
# Each entry: (label_suffix, {PARAM: value, ...}); unspecified params take
# their run_config default. Every entry cites the RTL anchor it exercises.
# ---------------------------------------------------------------------------
# run_config defaults are M_EXTENSION=2, MUL_TYPE=1, DIV_TYPE=3. ofat pins
# every *other* param at default, so ofat:MUL_TYPE=v always carries DIV_TYPE=3
# and ofat:DIV_TYPE=v always carries MUL_TYPE=1; neither homogeneous corner is
# a mixed (MUL,DIV) point. The genuinely-unreached interdependency region is
# therefore exactly {MUL_TYPE in 2,3} x {DIV_TYPE in 1,2} (both NON-default
# simultaneously), plus the Zmmul branch (M=1) with a non-default multiplier.
XPROD = [
    # Zmmul (M_EXTENSION=1 -> MUL_EN=1, DIV_EN=0) with a NON-default
    # multiplier microarch. Reaches arv_alu.v:554 WITH_MULDIV with DIV_EN=0
    # and MUL_4C_EN/MUL_16C_EN=1 -- ofat only sweeps MUL_TYPE with M=2.
    ("M1-MUL2",      {"M_EXTENSION": 1, "MUL_TYPE": 2}),
    ("M1-MUL3",      {"M_EXTENSION": 1, "MUL_TYPE": 3}),
    # Full 2x2 of non-default multiplier x non-default divider microarch at
    # M=2 (default): every distinct (MUL_*C_EN, DIV_*C_EN) elaboration pair
    # that ofat (one factor at default) and the homogeneous corners miss.
    ("M2-MUL2-DIV1", {"MUL_TYPE": 2, "DIV_TYPE": 1}),
    ("M2-MUL2-DIV2", {"MUL_TYPE": 2, "DIV_TYPE": 2}),
    ("M2-MUL3-DIV1", {"MUL_TYPE": 3, "DIV_TYPE": 1}),
    ("M2-MUL3-DIV2", {"MUL_TYPE": 3, "DIV_TYPE": 2}),
    # uop sequencer ACTIVE with Zcmt DISABLED, under the RV32E-narrowed
    # regfile. arvern.v:592 `if (UOP_EN)` instantiates arv_uop_sequencer
    # only for C>=3; inside it arv_uop_sequencer.v:298 `if (ZCMT_EN)` gates
    # the table-jump state (C>=4). C_EXTENSION==3 is therefore the ONLY
    # value with the sequencer present but its WITH_ZMT branch taken false;
    # crossing it with RV32E_EN=1 also exercises the RV32E_MODE branch of
    # arv_int_registers ({ex,wb}_reg_dest_sel_1hot[31:16] dead). ofat:C=3
    # carries RV32I; ofat:RV32E_EN=1 carries default C=4 (Zcmt on);
    # corner-HI is RV32E_EN=1,C=4 -- none reach this point.
    ("RVE-C3",       {"RV32E_EN": 1, "C_EXTENSION": 3}),
    # Split counter-CSR ownership stress: arv_csr_cntr (ZICNTR) owns
    # mcounteren/mcountinhibit[2:0], arv_csr_hpm (ZIHPM_NR) owns [10:3] and
    # decodes the same write-enable independently. ZICNTR_EN=0 with
    # ZIHPM_NR=8 = cntr side absent, hpm side at max width -- ofat:ZICNTR=0
    # carries ZIHPM=1, ofat:ZIHPM=8 carries ZICNTR=1, and the corners are
    # both-off / both-on; none hit the half-present split.
    ("ZICNTR0-HPM8", {"ZICNTR_EN": 0, "ZIHPM_NR": 8}),
    # Sparse-config INSURANCE -- no single generate anchor (unlike the
    # entries above; this one does NOT cite line numbers and is not
    # bug-sensitive-proof-tested). Full M+C datapath with every auxiliary
    # subsystem stripped: catches signals undriven only when the whole
    # CSR/counter/NMI/custom cluster is absent while the datapath still
    # sources events/traps into it -- a config no ofat (others=rich) nor
    # either homogeneous corner (corner-LO also strips M+C) ever visits.
    ("IMC-lean",     {"B_EXTENSION": 0, "ZICNTR_EN": 0,
                      "ZIHPM_NR": 0, "CCSR_EN": 0}),
    # External debug present on the SMALLEST core. DEBUG_EN auto-sweeps via
    # corners/ofat, but because its run_config default is 1, every ofat:X=v
    # already carries debug-ON-with-rich-defaults and corner-HI is debug+all-max;
    # the one debug x features point NOTHING reaches is debug ON while every
    # surrounding feature is stripped (corner-LO/-RVE both have debug OFF). This
    # exercises the full DM/DMI/SBA/debug-CSR cluster (arv_debug_dm.v,
    # arv_debug_sba.v, arv_csr_debug.v + the id_excp_ebreak_nodbg debug-entry
    # path) against the RV32E 16-register file (abstract GPR access into
    # arv_int_registers RV32E_MODE), with NO multi-cycle MUL/DIV/UOP to halt-drain
    # and M-only dcsr.prv (SU_MODE_EN=0) -- the lean-cluster insurance analogue of
    # IMC-lean, but for the debug subsystem. = corner-LO-RVE + DEBUG_EN=1.
    ("DEBUG-lean",   {"DEBUG_EN": 1, "DM_TRIGGER_NR": 1, "RV32E_EN": 1, "M_EXTENSION": 0,
                      "C_EXTENSION": 0, "B_EXTENSION": 0, "SU_MODE_EN": 0, "ZICNTR_EN": 0, "ZIHPM_NR": 0,
                      "CCSR_EN": 0}),
]

# ---------------------------------------------------------------------------
# Named "persona" configurations — the four advertised reference
# integration profiles. Each persona names every sweepable param
# explicitly (does NOT inherit from run_config defaults) so the persona
# yields identical RTL regardless of what the json default happens to be
# at any point in time. Consumed via `--sweep-mode personas` (focused PPA
# workflow) and via the `-rtl_config <name>` resolver (runsim.py /
# gen_rtl_params.py).
#
# Personas are also included in the `all` sweep set, so every routine
# regression / lint / synth -rtl_sweep run exercises all four — keeping
# the advertised configurations from silently breaking under parameter
# rename, allowed-list change, or default drift.
# ---------------------------------------------------------------------------
PERSONAS = [
    # "Light" — smallest viable usable CPU: RV32E + Zmmul (slow mul, no
    # divider) + Zca (cheap compressed for code size), no B-ext, no
    # counters, no custom CSR, **M-mode only** (SU_MODE_EN=0: S+U gated
    # out — sret traps as illegal, the S-mode CSRs and mideleg/medeleg/
    # mcounteren/menvcfg are absent (illegal-instruction), mstatus.MPP
    # forced to M).
    ("light", dict(
        ASYNC_RST_EN=1,
        RV32E_EN=1, M_EXTENSION=1, MUL_TYPE=3, DIV_TYPE=3,
        B_EXTENSION=0, C_EXTENSION=1,
        SU_MODE_EN=0, DEBUG_EN=0, DM_TRIGGER_NR=0, ZICNTR_EN=0, ZIHPM_NR=0, CCSR_EN=0,
        PMP_NR=0,
        SINGLE_CYCLE_BRANCH=1,
    )),
    # "Classic" — well-balanced MCU baseline: RV32I + full M (single-cycle
    # multiplier, radix-2 divider) + Zbb + Zca + Zicntr, **M-mode only**.
    # The confident default-choice config integrators reach for when no
    # specific constraint dominates — the "smart middle" of the ladder.
    #
    # M-only deliberately: S+U without PMP is trap delegation, not isolation,
    # so privilege modes and containment arrive together at "performance".
    # The area that buys goes into a divider instead, which an MCU baseline
    # wants far more than privilege modes it cannot enforce.
    ("classic", dict(
        ASYNC_RST_EN=1,
        RV32E_EN=0, M_EXTENSION=2, MUL_TYPE=1, DIV_TYPE=3,
        B_EXTENSION=1, C_EXTENSION=1,
        SU_MODE_EN=0, DEBUG_EN=0, DM_TRIGGER_NR=0, ZICNTR_EN=1, ZIHPM_NR=0, CCSR_EN=0,
        PMP_NR=0,
        SINGLE_CYCLE_BRANCH=1,
    )),
    # "Performance" — perf-pure compute target: RV32IM + 1-cycle MUL +
    # fastest divider (radix-8, 12-cycle) + full B (Zbb/Zba/Zbs/Zbc) +
    # Zca+Zcb (compressed base + byte/half-word memops, c.mul, c.zext/sext;
    # all decode-only, no UOP sequencer) + Zicntr. NO Zcmp/Zcmt (those
    # carry a UOP sequencer with real area cost), no Zihpm, no
    # CCSR — every knob set to maximise per-MHz throughput, nothing for
    # SoC integration features. Compare against Ultra to isolate the
    # area + code-size cost of feature-completeness while holding the
    # perf engine constant.
    ("performance", dict(
        ASYNC_RST_EN=1,
        RV32E_EN=0, M_EXTENSION=2, MUL_TYPE=1, DIV_TYPE=1,
        B_EXTENSION=4, C_EXTENSION=2,
        SU_MODE_EN=1, DEBUG_EN=0, DM_TRIGGER_NR=0, ZICNTR_EN=1, ZIHPM_NR=0, CCSR_EN=0,
        PMP_NR=4,
        SINGLE_CYCLE_BRANCH=1,
    )),
    # "Ultra" — feature-complete tape-out target: everything Performance
    # has + full C (Zca/Zcb/Zcmp/Zcmt for code density) and Zihpm for
    # production telemetry. CCSR left
    # OFF (aRVern-specific opt-in extension; integrators turn it on when
    # they have a use). Same perf engine as Performance (1-cycle MUL,
    # radix-8 DIV, full B) so the Ultra↔Performance comparison answers
    # "what does the SoC-integration feature load cost in gates and code
    # size?" without confusing perf and feature axes. External debug is
    # kept on the orthogonal axis: the debug-inclusive build is the
    # "ultra-dbg" twin below (DEBUG_EN=1 + full 8-trigger Sdtrig file).
    ("ultra", dict(
        ASYNC_RST_EN=1,
        RV32E_EN=0, M_EXTENSION=2, MUL_TYPE=1, DIV_TYPE=1,
        B_EXTENSION=4, C_EXTENSION=4,
        SU_MODE_EN=1, DEBUG_EN=0, DM_TRIGGER_NR=0, ZICNTR_EN=1, ZIHPM_NR=4, CCSR_EN=0,
        PMP_NR=8,
        SINGLE_CYCLE_BRANCH=1,
    )),
]

# ---------------------------------------------------------------------------
# Debug-enabled twins of the four base personas. The base personas above are
# deliberately debug-FREE (the smallest RTL for their tier); each twin below is
# the SAME configuration with DEBUG_EN=1 and a tier-appropriate Sdtrig trigger
# count, named "<persona>-dbg". This keeps external debug ORTHOGONAL to the four
# tiers: diffing "<persona>" against "<persona>-dbg" isolates the per-tier PPA
# cost of the Sdext DM/DMI/SBA + hart-side debug CSRs (+ Sdtrig triggers) with
# every other knob held constant.
#
# Derived from the base dicts (copied, not re-typed) so a twin can never silently
# drift from its base under a later parameter edit; because it copies the base's
# full dict, each twin still names every sweepable param explicitly -- the same
# frozen-config guarantee the base personas carry.
# A 0/2/4/8 ladder across the tiers: minimal -> full, which also spreads
# DM_TRIGGER_NR sweep coverage (4 is otherwise only reached via ofat).
_PERSONA_DBG_TRIGGERS = {
    "light":       0,   # minimal debug: run-control + abstract GPR/CSR access, no HW triggers
    "classic":     2,   # a small mcontrol6 trigger file, typical for an MCU
    "performance": 4,   # mid trigger file for a compute core with real HW breakpoints
    "ultra":       8,   # feature-complete: the full 8-trigger file
}
PERSONAS += [
    (f"{base}-dbg", dict(cfg, DEBUG_EN=1, DM_TRIGGER_NR=_PERSONA_DBG_TRIGGERS[base]))
    for base, cfg in list(PERSONAS)
]

# ---------------------------------------------------------------------------
# COVERAGE_CONFIGS -- verification-only builds, deliberately NOT personas.
#
# PERSONAS above is an integrator-facing product ladder; entries here are not
# products, they exist to elaborate as much RTL as possible in one simulation.
# They are therefore excluded from -rtl_sweep and reachable only by name via
# -rtl_config <name>, which is what run_cov uses for its third pass.
#
# Unlike a persona, an entry here lists only the DELTA from the run_config.json
# defaults; everything unnamed keeps its default.
#
# "maxcov": every COUNT knob at maximum (more elaborated instances = strictly
# more live RTL), plus the multiplier/divider implementations the default build
# does NOT elaborate. MUL_TYPE/DIV_TYPE select mutually exclusive generate
# branches, so a single build can never cover them all -- but run_cov merges
# this pass with the two default-config passes, and the union then covers both
# the shipping single-cycle multiplier / radix-2 divider (passes 1-2) and the
# multi-cycle multiplier / radix-8 divider (this pass). Picking the defaults
# here instead would just re-cover what passes 1-2 already did.
#
# Note the remaining variants (MUL_TYPE=2, DIV_TYPE=2) are still uncovered by
# any pass; a second entry would be needed to close them.
# The three entries below are designed as a SET: run together they span every
# place the RTL has mutually exclusive implementations, so no pass needs the
# shipping default config at all. What each one uniquely contributes:
#
#   MUL_TYPE   1 / 2 / 3   three separate generate branches; no build has two
#   DIV_TYPE   3 / 2 / 1   likewise
#   counts     max / mid / absent -- "absent" matters because the tie-off arms
#              for unimplemented slots (arv_debug_trigger.v:402) only elaborate
#              when slots are missing, so a max-only suite would never see them
#   SCB        1 / 1 / 0   at SCB=0 the mux select at arv_fetch.v:411 becomes
#              id_pc_o[1] and BOTH arms are live; at SCB=1 it is constant-true
#              and the second arm is structurally unreachable (see :408-410)
#   ARST       1 / 1 / 0   sync vs async reset in arv_dff
#
# Random delays go on cov_stress only. The wait-state edge case documented in
# CLAUDE.md ("inst-bus address phase not held across wait states") is specific
# to SINGLE_CYCLE_BRANCH=1, so the stressed pass keeps SCB=1; cov_alt's extra
# reachable arm is instruction-alignment driven, not timing driven, and needs
# no randomisation.
#
# Every entry keeps ALL features enabled (SU/DEBUG/NMI/CCSR/ZICNTR, C=4, B=4,
# M=2) so the full test suite runs in all three. Deliberately NOT covered here:
# SU_MODE_EN=0, M_EXTENSION=0/1, C_EXTENSION=0 and RV32E_EN=1 gate 12 tests
# between them, but those builds REMOVE logic rather than adding it, so they
# buy little coverage for a full pass each -- they stay with -rtl_sweep.
COVERAGE_CONFIGS = [
    ("cov_max", dict(
        MUL_TYPE=1, DIV_TYPE=3,          # the shipping multiplier / divider
        DM_TRIGGER_NR=8, ZIHPM_NR=8,     # counts at maximum: most instances live
        SINGLE_CYCLE_BRANCH=1, ASYNC_RST_EN=1,
    )),
    ("cov_stress", dict(
        MUL_TYPE=2, DIV_TYPE=2,          # 4-cycle multiplier, radix-4 divider
        DM_TRIGGER_NR=2, ZIHPM_NR=4,     # mid counts: some slots present, some tied off
        SINGLE_CYCLE_BRANCH=1, ASYNC_RST_EN=1,
    )),
    ("cov_alt", dict(
        MUL_TYPE=3, DIV_TYPE=1,          # 16-cycle multiplier, radix-8 divider
        DM_TRIGGER_NR=0, ZIHPM_NR=0,     # absent: exercises the tie-off arms
        SINGLE_CYCLE_BRANCH=0, ASYNC_RST_EN=0,
    )),
]


SWEEP_MODES = ("all", "corners", "ofat", "xprod", "default", "personas", "coverage",
               "ofat-light")

# OFAT_LIGHT -- feature-cost measurement set: the `light` persona with ONE feature
# added (or one implementation choice changed) per entry. The `ofat` mode gives the
# same one-factor view from the opposite end (the feature-rich run_config default
# with one feature removed); the two bracket a feature's cost, which is not
# additive between them (PMP scales with S-mode, Zcb shares the Zbb datapath, ...).
#
# Reachable only by `--sweep-mode ofat-light` or by name via -rtl_config
# (`ofat-light:<label>`); deliberately NOT part of `all`, so the regression /
# lint / synthesis -rtl_sweep counts are unchanged.
#
# Entries are (label, overrides-on-top-of-light). A feature whose parameter is
# dead without an enabler carries the enabler in the same entry (DIV_TYPE needs
# M_EXTENSION=2, DM_TRIGGER_NR needs DEBUG_EN=1); the enabler's own entry is the
# reference for it.
OFAT_LIGHT = [
    ("RV32E_EN=0",              dict(RV32E_EN=0)),
    ("M_EXTENSION=0",           dict(M_EXTENSION=0)),
    ("M_EXTENSION=2",           dict(M_EXTENSION=2)),                 # adds the radix-2 divider (DIV_TYPE=3)
    ("M_EXTENSION=2.DIV_TYPE=2",dict(M_EXTENSION=2, DIV_TYPE=2)),
    ("M_EXTENSION=2.DIV_TYPE=1",dict(M_EXTENSION=2, DIV_TYPE=1)),
    ("MUL_TYPE=2",              dict(MUL_TYPE=2)),
    ("MUL_TYPE=1",              dict(MUL_TYPE=1)),
    ("B_EXTENSION=1",           dict(B_EXTENSION=1)),
    ("B_EXTENSION=2",           dict(B_EXTENSION=2)),
    ("B_EXTENSION=3",           dict(B_EXTENSION=3)),
    ("B_EXTENSION=4",           dict(B_EXTENSION=4)),
    ("C_EXTENSION=0",           dict(C_EXTENSION=0)),
    ("C_EXTENSION=2",           dict(C_EXTENSION=2)),
    ("C_EXTENSION=3",           dict(C_EXTENSION=3)),
    ("C_EXTENSION=4",           dict(C_EXTENSION=4)),
    ("SU_MODE_EN=1",            dict(SU_MODE_EN=1)),
    ("PMP_NR=4",                dict(PMP_NR=4)),                       # PMP on an M-only core
    ("PMP_NR=8",                dict(PMP_NR=8)),
    ("PMP_NR=16",               dict(PMP_NR=16)),
    ("SU_MODE_EN=1.PMP_NR=4",   dict(SU_MODE_EN=1, PMP_NR=4)),        # PMP with S/U (MML rules live)
    ("SU_MODE_EN=1.PMP_NR=8",   dict(SU_MODE_EN=1, PMP_NR=8)),
    ("SU_MODE_EN=1.PMP_NR=16",  dict(SU_MODE_EN=1, PMP_NR=16)),
    ("ZICNTR_EN=1",             dict(ZICNTR_EN=1)),
    ("ZIHPM_NR=1",              dict(ZIHPM_NR=1)),
    ("ZIHPM_NR=4",              dict(ZIHPM_NR=4)),
    ("ZIHPM_NR=8",              dict(ZIHPM_NR=8)),
    ("DEBUG_EN=1",              dict(DEBUG_EN=1)),
    ("DEBUG_EN=1.DM_TRIGGER_NR=1", dict(DEBUG_EN=1, DM_TRIGGER_NR=1)),
    ("DEBUG_EN=1.DM_TRIGGER_NR=2", dict(DEBUG_EN=1, DM_TRIGGER_NR=2)),
    ("DEBUG_EN=1.DM_TRIGGER_NR=4", dict(DEBUG_EN=1, DM_TRIGGER_NR=4)),
    ("DEBUG_EN=1.DM_TRIGGER_NR=8", dict(DEBUG_EN=1, DM_TRIGGER_NR=8)),
    ("CCSR_EN=1",               dict(CCSR_EN=1)),
    ("SINGLE_CYCLE_BRANCH=0",   dict(SINGLE_CYCLE_BRANCH=0)),
    ("ASYNC_RST_EN=0",          dict(ASYNC_RST_EN=0)),
]


# Legend printed before the sweep list by `-list_configs` on every wrapper
# (./run, ./run_all, ./run_syn, ./run_syn_d). Header lines start with '#'
# so the same output is still machine-parseable: awk -F'\t' '$1==N' skips
# them naturally.
SWEEP_SET_LEGEND = """\
# RTL sweep set (1-based; same numbering shared by all sweep entry points:
#   ./run -list_configs   ./run_all -rtl_sweep / -rtl_config N
#   ./run_syn -list_configs  ./run_syn -rtl_sweep / -rtl_config N
#   run_lint --sweep)
#
#   default        every param at its run_config.json default
#   corner-LO      every param at min(allowed)       -- smallest RV32I build
#   corner-HI      every param at max(allowed)       -- largest build
#   corner-LO-RVE  corner-LO + RV32E_EN=1            -- smallest RV32E build
#   ofat:P=v       param P=v, others at default      -- one-factor-at-a-time;
#                                                      covers each allowed value
#                                                      of every sweepable param
#                                                      against the feature-rich
#                                                      default
#   xprod:NAME     targeted cross-product            -- combinations the corners
#                                                      and ofat alone cannot
#                                                      reach (see XPROD table
#                                                      in bin/rtl_sweep_configs.py
#                                                      for per-entry rationale)
#   persona:NAME   marketing/publication reference   -- named integration
#                                                      profile (light / classic /
#                                                      performance / ultra, each
#                                                      debug-free, plus a debug-
#                                                      enabled "<name>-dbg" twin),
#                                                      also included in the
#                                                      `all` sweep set so every
#                                                      regression / lint / synth
#                                                      run exercises them. Pick
#                                                      one in isolation via
#                                                      --sweep-mode personas
#                                                      or -rtl_config <name>.
#"""


def print_sweep_list(configs, with_legend=True, file=None):
    """Print the sweep list as '<idx>\\t<label>' lines, optionally preceded by
    the legend explaining default/corner/ofat/xprod categories. configs is the
    list returned by generate_configs()[1]."""
    import sys
    if file is None:
        file = sys.stdout
    if with_legend:
        print(SWEEP_SET_LEGEND, file=file)
    for i, (label, _vals) in enumerate(configs, 1):
        print(f"{i}\t{label}", file=file)


class RtlSweepConfigError(ValueError):
    """Raised on a malformed rtl_config / sweep request. Callers decide how
    to surface it (run_lint -> clean sys.exit; runsim -> propagate)."""


def sweepable_params(rtl_config):
    """Filter a parsed run_config.json `rtl_config` dict down to the
    sweepable parameters: integer-valued with a finite `allowed` list.
    Excludes free-valued params (empty/missing `allowed`, e.g. MVENDORID) --
    they are fixed at default and emitted but never swept. This is the one
    place that decides "what is sweepable", shared by the lint sweep
    (load_rtl_config) and the -rtl_sweep regression (test_config)."""
    params = {}
    for name, info in rtl_config.items():
        allowed = info.get("allowed")
        if not allowed:                       # [] or missing -> free-valued
            continue
        if not all(isinstance(v, int) for v in allowed):
            continue
        params[name] = {"default": info["default"], "allowed": list(allowed)}
    return params


def load_rtl_config(config_path):
    """Read run_config.json and return its sweepable params (see
    sweepable_params)."""
    try:
        with open(config_path) as f:
            cfg = json.load(f)
    except FileNotFoundError:
        raise RtlSweepConfigError(f"config not found: {config_path}")
    except json.JSONDecodeError as e:
        raise RtlSweepConfigError(f"invalid JSON in {config_path}: {e}")
    return sweepable_params(cfg.get("rtl_config", {}))


def cfg_str(d, order):
    return ",".join(f"{k}={d[k]}" for k in order)


def generate_configs(params, mode="all"):
    """Return (order, [(label, {param: value}), ...]) for the requested
    sweep mode, de-duplicated. Every config lists ALL sweepable params
    explicitly so corners are true corners and ofat/xprod pin every other
    param at its default."""
    if mode not in SWEEP_MODES:
        raise RtlSweepConfigError(
            f"unknown sweep mode '{mode}' (expected one of {SWEEP_MODES})")
    order = list(params.keys())
    default = {k: params[k]["default"] for k in order}
    seen, out = set(), []

    def add(label, d, allow_duplicate=False):
        key = cfg_str(d, order)
        if key in seen and not allow_duplicate:
            return
        seen.add(key)
        out.append((label, dict(d)))

    if mode in ("all", "default"):
        add("default", dict(default))

    if mode in ("all", "corners"):
        lo = {k: min(params[k]["allowed"]) for k in order}
        hi = {k: max(params[k]["allowed"]) for k in order}
        add("corner-LO(all-min)", lo)
        add("corner-HI(all-max)", hi)
        # Smallest possible RTL: corner-LO with RV32E_EN pinned to 1 so the
        # regfile narrows to x0-x15 (RV32E). Every other param stays at
        # min(allowed) -- B/M/C/NMI/Zicntr/Zihpm/CCSR all off. Distinct from
        # plain corner-LO (RV32E_EN=0) and from any ofat:RV32E_EN=1 entry
        # (which carries the FEATURE-RICH default for every other param).
        add("corner-LO-RVE(all-min,RV32E_EN=1)", dict(lo, RV32E_EN=1))

    if mode in ("all", "ofat"):
        for k in order:
            for v in params[k]["allowed"]:
                d = dict(default)
                d[k] = v
                add(f"ofat:{k}={v}", d)

    if mode in ("all", "xprod"):
        for suffix, overrides in XPROD:
            d = dict(default)
            for k, v in overrides.items():
                if k not in d:
                    raise RtlSweepConfigError(
                        f"xprod entry '{suffix}' names unknown param '{k}'")
                if v not in params[k]["allowed"]:
                    raise RtlSweepConfigError(
                        f"xprod '{suffix}' {k}={v} not in allowed "
                        f"{params[k]['allowed']}")
                d[k] = v
            add(f"xprod:{suffix}", d)

    # Personas are part of the `all` sweep set so every regression /
    # lint / synth -rtl_sweep run also exercises the four advertised
    # reference configurations. Keeping them in `all` ensures the
    # PERSONAS table can never silently break (a parameter rename or
    # allowed-list change would fail the next sweep, not the next
    # publication). They are still selectable on their own via
    # `--sweep-mode personas` for the focused PPA-numbers workflow.
    # Every persona must name every sweepable param so the persona is
    # fully frozen regardless of run_config's default drift.
    #
    # allow_duplicate=True: emit personas under their persona label even
    # when the parameter vector happens to match an earlier-added entry
    # (Ultra naturally coincides with `ofat:C_EXTENSION=4` when the
    # run_config.json defaults align with Ultra-minus-full-C, which is
    # the common case). Without this the persona would silently dedup
    # away and a broken persona definition wouldn't surface in regression
    # output under its own name. The tiny double-run cost is worth the
    # visibility guarantee.
    # "coverage" is reachable ONLY by explicit -rtl_config <name>; it is
    # deliberately not part of "all", so -rtl_sweep never runs these builds.
    if mode == "coverage":
        for label, overrides in COVERAGE_CONFIGS:
            d = dict(default)
            extra = [k for k in overrides if k not in d]
            if extra:
                raise RtlSweepConfigError(
                    f"coverage config '{label}' names unknown param(s): {extra}")
            for k, v in overrides.items():
                if v not in params[k]["allowed"]:
                    raise RtlSweepConfigError(
                        f"coverage config '{label}': {k}={v} not in allowed "
                        f"{params[k]['allowed']}")
                d[k] = v
            add(f"coverage:{label}", d, allow_duplicate=True)

    if mode == "ofat-light":
        base = dict(default)
        base.update(dict(PERSONAS)["light"])
        for label, overrides in OFAT_LIGHT:
            d = dict(base)
            for k, v in overrides.items():
                if k not in d:
                    raise RtlSweepConfigError(
                        f"ofat-light entry '{label}' names unknown param '{k}'")
                if v not in params[k]["allowed"]:
                    raise RtlSweepConfigError(
                        f"ofat-light '{label}' {k}={v} not in allowed "
                        f"{params[k]['allowed']}")
                d[k] = v
            add(f"ofat-light:{label}", d, allow_duplicate=True)

    if mode in ("all", "personas"):
        for label, overrides in PERSONAS:
            d = dict(default)
            unset = [k for k in order if k not in overrides]
            if unset:
                raise RtlSweepConfigError(
                    f"persona '{label}' is missing required param(s): {unset}")
            extra = [k for k in overrides if k not in d]
            if extra:
                raise RtlSweepConfigError(
                    f"persona '{label}' names unknown param(s): {extra}")
            for k, v in overrides.items():
                if v not in params[k]["allowed"]:
                    raise RtlSweepConfigError(
                        f"persona '{label}' {k}={v} not in allowed "
                        f"{params[k]['allowed']}")
                d[k] = v
            add(f"persona:{label}", d, allow_duplicate=True)

    return order, out


def resolve_persona(name, params):
    """Look up a persona by name and return (label, param_dict).

    Used by `-rtl_config <name>` resolvers in runsim.py and gen_rtl_params.py
    to pick a single persona directly (bypassing the sweep-mode iteration).
    Raises RtlSweepConfigError if the name isn't a known persona.
    """
    # Coverage-only configs are looked up first: they are not personas and are
    # intentionally absent from every sweep mode, so generate_configs() below
    # will never produce them.
    for cov_label, cov_overrides in COVERAGE_CONFIGS:
        if cov_label != name:
            continue
        extra = [k for k in cov_overrides if k not in params]
        if extra:
            raise RtlSweepConfigError(
                f"coverage config '{name}' names unknown param(s): {extra}")
        d = {k: params[k]["default"] for k in params}
        for k, v in cov_overrides.items():
            if v not in params[k]["allowed"]:
                raise RtlSweepConfigError(
                    f"coverage config '{name}': {k}={v} not in allowed "
                    f"{params[k]['allowed']}")
            d[k] = v
        return f"coverage:{name}", d

    if name.startswith("ofat-light:"):
        for cfg_label, cfg_dict in generate_configs(params, "ofat-light")[1]:
            if cfg_label == name:
                return cfg_label, cfg_dict
        raise RtlSweepConfigError(f"unknown ofat-light config '{name}'")

    known = [lbl for lbl, _ in PERSONAS] + [lbl for lbl, _ in COVERAGE_CONFIGS]
    if name not in known:
        raise RtlSweepConfigError(
            f"unknown persona '{name}' (known: {known})")
    for cfg_label, cfg_dict in generate_configs(params, "personas")[1]:
        if cfg_label == f"persona:{name}":
            return cfg_label, cfg_dict
    # Unreachable if generate_configs and PERSONAS stay in sync
    raise RtlSweepConfigError(f"persona '{name}' missing from generated set")
