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
    ("IMC-lean",     {"B_EXTENSION": 0, "NMI_EN": 0, "ZICNTR_EN": 0,
                      "ZIHPM_NR": 0, "CCSR_EN": 0}),
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
    # counters, no NMI, no custom CSR, **M-mode only** (SU_MODE_EN=0:
    # S+U gated out — sret/sfence.vma trap as illegal, S-mode CSRs RAZ/WI,
    # mideleg/medeleg WI, mstatus.MPP forced to M).
    ("light", dict(
        ASYNC_RST_EN=1,
        RV32E_EN=1, M_EXTENSION=1, MUL_TYPE=3, DIV_TYPE=3,
        B_EXTENSION=0, C_EXTENSION=1,
        NMI_EN=0, SU_MODE_EN=0, ZICNTR_EN=0, ZIHPM_NR=0, CCSR_EN=0,
        SINGLE_CYCLE_BRANCH=1,
    )),
    # "Classic" — well-balanced MCU baseline (matches the arvern.v
    # module-declaration defaults): RV32I + single-cycle Zmmul + Zbb + Zca +
    # Zicntr + M+S+U. The confident default-choice config integrators reach
    # for when no specific constraint dominates — the "smart middle" of the
    # ladder.
    ("classic", dict(
        ASYNC_RST_EN=1,
        RV32E_EN=0, M_EXTENSION=1, MUL_TYPE=1, DIV_TYPE=3,
        B_EXTENSION=1, C_EXTENSION=1,
        NMI_EN=0, SU_MODE_EN=1, ZICNTR_EN=1, ZIHPM_NR=0, CCSR_EN=0,
        SINGLE_CYCLE_BRANCH=1,
    )),
    # "Performance" — perf-pure compute target: RV32IM + 1-cycle MUL +
    # fastest divider (radix-8, 12-cycle) + full B (Zbb/Zba/Zbs/Zbc) +
    # Zca+Zcb (compressed base + byte/half-word memops, c.mul, c.zext/sext;
    # all decode-only, no UOP sequencer) + Zicntr. NO Zcmp/Zcmt (those
    # carry a UOP sequencer with real area cost), no NMI, no Zihpm, no
    # CCSR — every knob set to maximise per-MHz throughput, nothing for
    # SoC integration features. Compare against Ultra to isolate the
    # area + code-size cost of feature-completeness while holding the
    # perf engine constant.
    ("performance", dict(
        ASYNC_RST_EN=1,
        RV32E_EN=0, M_EXTENSION=2, MUL_TYPE=1, DIV_TYPE=1,
        B_EXTENSION=4, C_EXTENSION=2,
        NMI_EN=0, SU_MODE_EN=1, ZICNTR_EN=1, ZIHPM_NR=0, CCSR_EN=0,
        SINGLE_CYCLE_BRANCH=1,
    )),
    # "Ultra" — feature-complete tape-out target: everything Performance
    # has + full C (Zca/Zcb/Zcmp/Zcmt for code density), Smrnmi NMI for
    # safety-critical wakeup, Zihpm for production telemetry. CCSR left
    # OFF (aRVern-specific opt-in extension; integrators turn it on when
    # they have a use). Same perf engine as Performance (1-cycle MUL,
    # radix-8 DIV, full B) so the Ultra↔Performance comparison answers
    # "what does the SoC-integration feature load cost in gates and code
    # size?" without confusing perf and feature axes.
    ("ultra", dict(
        ASYNC_RST_EN=1,
        RV32E_EN=0, M_EXTENSION=2, MUL_TYPE=1, DIV_TYPE=1,
        B_EXTENSION=4, C_EXTENSION=4,
        NMI_EN=1, SU_MODE_EN=1, ZICNTR_EN=1, ZIHPM_NR=4, CCSR_EN=0,
        SINGLE_CYCLE_BRANCH=1,
    )),
]

SWEEP_MODES = ("all", "corners", "ofat", "xprod", "default", "personas")


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
#                                                      profile (light / standard /
#                                                      performance / ultra),
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
    known = [lbl for lbl, _ in PERSONAS]
    if name not in known:
        raise RtlSweepConfigError(
            f"unknown persona '{name}' (known: {known})")
    for cfg_label, cfg_dict in generate_configs(params, "personas")[1]:
        if cfg_label == f"persona:{name}":
            return cfg_label, cfg_dict
    # Unreachable if generate_configs and PERSONAS stay in sync
    raise RtlSweepConfigError(f"persona '{name}' missing from generated set")
