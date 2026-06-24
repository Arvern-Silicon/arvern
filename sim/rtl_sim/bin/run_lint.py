#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    run_lint.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Verilator lint driver for the arvern RTL with parameterization sweep.
#----------------------------------------------------------------------------

"""
run_lint.py - Verilator lint driver for arvern, with a parameterization sweep.

Verilator-lint half of the arvern RTL parameterization sweep: for each
configuration it builds and runs `verilator --lint-only`. The configuration
SET (default / corners / ofat / xprod, plus the parameter-interdependency
analysis behind xprod) is the single source of truth in
`bin/rtl_sweep_configs.py`, shared verbatim with the -rtl_sweep regression
in `bin/test_config.py` so the lint sweep and the simulation sweep are, by
construction, identical. See that module's header for the full coverage
argument.
"""

import argparse
import os
import re
import shlex
import subprocess
import sys

from rtl_sweep_configs import (RtlSweepConfigError, SWEEP_MODES, cfg_str,
                               generate_configs, load_rtl_config)


MSG_RE = re.compile(r"%(Warning|Error)")


def extract_extra(argv):
    """Peel -e/--extra and its value out of argv *before* argparse, so an
    option-like value (e.g. `-e --timing`) is taken verbatim instead of
    argparse mistaking it for a flag. Supports `-e V`, `--extra V`,
    `-e=V`, `--extra=V`; multiple occurrences are space-joined. Returns
    (extra_str, cleaned_argv)."""
    extras, out, i = [], [], 0
    while i < len(argv):
        tok = argv[i]
        if tok in ("-e", "--extra"):
            if i + 1 >= len(argv):
                sys.exit("Error: argument -e/--extra: expected one argument")
            extras.append(argv[i + 1])
            i += 2
        elif tok.startswith("-e=") or tok.startswith("--extra="):
            extras.append(tok.split("=", 1)[1])
            i += 1
        else:
            out.append(tok)
            i += 1
    return " ".join(extras), out


def build_verilator_cmd(top, waivers, extra, filelist, gargs=None):
    cmd = ["verilator", "--lint-only", "-Wall", "-Wpedantic", "--top", top]
    if waivers:
        cmd.append(waivers)
    cmd += shlex.split(extra) if extra else []
    cmd += gargs or []
    cmd += ["-f", filelist]
    return cmd


def _params_or_exit(path):
    """load_rtl_config with the shared module's exception turned into the
    same clean `Error: ...` + nonzero exit run_lint always produced."""
    try:
        return load_rtl_config(path)
    except RtlSweepConfigError as e:
        sys.exit(f"Error: {e}")


def run_sweep(args, params):
    try:
        order, configs = generate_configs(params, args.sweep_mode)
    except RtlSweepConfigError as e:
        sys.exit(f"Error: {e}")
    if not configs:
        sys.exit(f"Error: no configs generated (mode={args.sweep_mode})")
    ncfg = len(configs)
    print(f"Parameterization sweep: mode={args.sweep_mode}, {ncfg} config(s)")
    print("(full cross-product is infeasible; corners exercise every "
          "parameter-gated")
    print(" generate in both polarities, ofat covers per-tier values, xprod "
          "covers")
    print(" the muldiv interdependency gap -- see run_lint.py header)\n")

    npass = nfail = 0
    failed = []
    for idx, (label, d) in enumerate(configs, 1):
        gargs = [f"-G{k}={d[k]}" for k in order]
        cmd = build_verilator_cmd(args.top, args.waivers, args.extra,
                                   args.filelist, gargs)
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode == 0:
            npass += 1
            print(f"  [{idx:2d}/{ncfg:2d}] PASS  {label}")
        else:
            nfail += 1
            failed.append((label, cfg_str(d, order)))
            print(f"  [{idx:2d}/{ncfg:2d}] FAIL  {label}")
            lines = sorted({ln for ln in (proc.stdout + proc.stderr).splitlines()
                            if MSG_RE.search(ln)})
            for ln in lines:
                print(f"         {ln}")

    print()
    print(" ======================================================")
    print(f"|  SWEEP SUMMARY: {npass} passed, {nfail} failed (of {ncfg})")
    print(" ======================================================")
    if nfail:
        print("Failed configs:")
        for label, params_str in failed:
            print(f"  - {label}  ({params_str})")
        print("\n✗ Lint sweep FAILED")
        return 1
    print(f"\n✓ Lint sweep PASSED (all {ncfg} configs lint-clean)")
    return 0


def run_plain(args):
    # Lint the AS-BUILT configuration by default: arvern.v's module-
    # declared defaults are feature-lean (NMI_EN=0, ZICNTR_EN=0, ZIHPM_NR=0,
    # minimal B/C) and are NEVER the config runsim/synthesis build -- those
    # build run_config.json's rtl_config defaults. So apply the run_config
    # defaults as -G overrides unless --rtl-defaults asks for the bare
    # module-declaration config explicitly.
    gargs = None
    if not args.rtl_defaults and os.path.isfile(args.config):
        params = _params_or_exit(args.config)
        order = list(params.keys())
        gargs = [f"-G{k}={params[k]['default']}" for k in order]
        src = "as-built (run_config.json rtl_config defaults)"
    elif args.rtl_defaults:
        src = "RTL module-declaration defaults (--rtl-defaults)"
    else:
        print(f"Warning: {args.config} not found; linting bare RTL "
              "module-declaration defaults")
        src = "RTL module-declaration defaults (run_config.json absent)"
    print(f"Config: {src}\n")
    cmd = build_verilator_cmd(args.top, args.waivers, args.extra,
                              args.filelist, gargs)
    if args.verbose:
        print("Running:", " ".join(shlex.quote(c) for c in cmd), "\n")
    rc = subprocess.run(cmd).returncode
    print()
    if rc == 0:
        print("✓ Lint check PASSED")
    else:
        print(f"✗ Lint check FAILED (exit code: {rc})")
    print()
    return rc


def main():
    ap = argparse.ArgumentParser(
        description="Run Verilator lint on arvern, optionally across a "
                    "parameterization sweep.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples:\n"
               "  run_lint                       # as-built config "
               "(run_config.json rtl_config defaults)\n"
               "  run_lint --rtl-defaults        # bare arvern.v module "
               "defaults (old behavior)\n"
               "  run_lint --sweep               # full sweep (all modes)\n"
               "  run_lint --sweep-mode corners  # LO/HI corners (fastest)\n"
               "  run_lint --sweep-mode xprod    # just the muldiv x-products\n"
               "  run_lint -n arvern           # no waivers\n"
               "  run_lint -e '--timing'         # extra verilator flags\n")
    ap.add_argument("top", nargs="?", default="arvern",
                    help="top-level module (default: arvern)")
    ap.add_argument("-f", "--filelist",
                    default="../../../rtl/verilog/filelist.f",
                    help="filelist (default: ../../../rtl/verilog/filelist.f)")
    ap.add_argument("-w", "--waivers", default="waivers.vlt",
                    help="waivers file (default: waivers.vlt)")
    ap.add_argument("-n", "--no-waivers", action="store_true",
                    help="ignore waivers file")
    ap.add_argument("-e", "--extra", default="",
                    help="additional Verilator flags (quoted string)")
    ap.add_argument("-s", "--sweep", action="store_true",
                    help="lint across the parameterization sweep")
    ap.add_argument("--sweep-mode", default=None,
                    choices=list(SWEEP_MODES),
                    help="sweep coverage (implies --sweep; default: all)")
    ap.add_argument("--config", default="run_config.json",
                    help="rtl_config source (default: run_config.json)")
    ap.add_argument("--rtl-defaults", action="store_true",
                    help="plain run: lint the bare arvern.v module-"
                         "declaration defaults instead of the as-built "
                         "run_config.json config")
    ap.add_argument("-v", "--verbose", action="store_true")

    # -e/--extra value may itself look like an option (`-e --timing`);
    # peel it out before argparse so it is taken verbatim.
    extra_str, clean_argv = extract_extra(sys.argv[1:])
    args = ap.parse_args(clean_argv)
    args.extra = extra_str

    sweep = args.sweep or args.sweep_mode is not None
    if args.sweep_mode is None:
        args.sweep_mode = "all"

    if not os.path.isfile(args.filelist):
        sys.exit(f"Error: Filelist not found: {args.filelist}")

    # Flatten the source filelist once; reuse the result for the plain run
    # and every sweep config (the RTL set is identical across configs --
    # parameters vary via -G). Matches the submit_sim.f / submit_syn.tcl
    # pattern of the sim and synth flows.
    flatten = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "flatten_filelist.py")
    flat_filelist = "./submit_lint.f"
    subprocess.run([sys.executable, flatten, args.filelist, flat_filelist],
                   check=True)
    args.filelist = flat_filelist

    if args.no_waivers or not os.path.isfile(args.waivers):
        if not args.no_waivers and not os.path.isfile(args.waivers):
            print(f"Warning: Waivers file not found: {args.waivers} "
                  "(continuing without waivers)")
        args.waivers = None

    print()
    print(" ======================================================")
    print(f"|         LINT:          {args.top}")
    print(" ======================================================")
    print()
    if args.verbose:
        print("Configuration:")
        print(f"  Top module: {args.top}")
        print(f"  Filelist:   {args.filelist}")
        print(f"  Waivers:    {args.waivers or '<none>'}")
        print(f"  Extra flags: {args.extra or '<none>'}")
        print(f"  Sweep:      {args.sweep_mode if sweep else '<off>'}")
        print()

    if sweep:
        params = _params_or_exit(args.config)
        sys.exit(run_sweep(args, params))
    sys.exit(run_plain(args))


if __name__ == "__main__":
    main()
