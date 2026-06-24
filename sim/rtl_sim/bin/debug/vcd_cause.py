#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    vcd_cause.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Recursive driver tree (cause_tree.json) for a signal at a given cycle.
#----------------------------------------------------------------------------

"""
Show a signal's value and all its defined causes at a given cycle/time,
recursively to a configurable depth.

The cause tree is read from cause_tree.json (same directory as this script,
or a file specified via --config).

Usage:
  python3 vcd_cause.py tb_arvern.vcd trap_taken --cycle 412
  python3 vcd_cause.py tb_arvern.vcd irq_detect --cycle 570
  python3 vcd_cause.py tb_arvern.vcd trap_taken --cycle 412 --depth 2
  python3 vcd_cause.py tb_arvern.vcd trap_taken --cycle 412 --config my_cause_tree.json
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from vcd_trace import VCDParser, detect_clk_period, ticks_to_cycle


# ─── Value helpers ────────────────────────────────────────────────────────────

def bin_to_display(bstr, width):
    """Format a binary string for display."""
    if width == 1:
        return bstr
    if any(c in bstr for c in 'xzXZ'):
        return bstr
    val = int(bstr, 2)
    hex_digits = (width + 3) // 4
    return f'0x{val:0{hex_digits}X}'


# ─── Snapshot helper ──────────────────────────────────────────────────────────

def get_values_at_tick(vcd_parser, vids, tick):
    """
    Return a dict {vid: value_str} representing signal values at `tick`.
    Streams from t=0 up to tick, keeping the last seen value for each vid.
    """
    current = {}
    for _, snap in vcd_parser.stream_changes(vids, t_start=0, t_end=tick):
        current.update(snap)
    return current


# ─── Recursive cause printer ──────────────────────────────────────────────────

def print_causes(vcd_parser, sig_name, tick, cause_tree, depth, max_depth,
                 indent=0, visited=None):
    """
    Recursively print signal value and its causes at `tick`.

    Parameters
    ----------
    sig_name   : leaf name of the signal to look up
    tick       : VCD timestamp
    cause_tree : dict loaded from cause_tree.json
    depth      : current recursion depth (starts at 0 for the root signal)
    max_depth  : maximum recursion depth (--depth argument)
    indent     : current indentation level (in spaces, 2 per level)
    visited    : set of signal names already printed (avoid infinite loops)
    """
    if visited is None:
        visited = set()

    prefix = '  ' * indent

    # Resolve signal in VCD
    matches = vcd_parser.find_signals([sig_name])
    if matches:
        full_name, vid, width = matches[0]
        vals = get_values_at_tick(vcd_parser, [vid], tick)
        raw  = vals.get(vid, 'x')
        disp = bin_to_display(raw, width)
        path_str = f'[{full_name}]'
    else:
        full_name = None
        vid       = None
        width     = 1
        disp      = '?'
        path_str  = '[not in VCD]'

    # Padding for alignment
    name_col = 28
    padded_name = sig_name.ljust(name_col - indent * 2)
    print(f'{prefix}{padded_name} = {disp:<5}  {path_str}')

    # Look up in cause tree
    key = sig_name.lower()
    entry = cause_tree.get(key)

    if entry and depth < max_depth:
        desc = entry.get('desc', '')
        if desc:
            print(f'{prefix}  desc: {desc}')

        causes = entry.get('causes', [])
        if causes and sig_name not in visited:
            visited.add(sig_name)
            for cause in causes:
                print_causes(vcd_parser, cause, tick, cause_tree,
                             depth + 1, max_depth,
                             indent + 1, visited)


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description='Show a signal and its causes at a given cycle.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument('vcd',    help='Path to VCD file')
    ap.add_argument('signal', help='Signal name pattern')
    ap.add_argument('--cycle',      type=int, metavar='N',
                    help='Cycle number to inspect')
    ap.add_argument('--tick',       type=int, metavar='N',
                    help='Raw tick to inspect (overrides --cycle)')
    ap.add_argument('--clk-period', type=int, metavar='N',
                    help='Clock period in ticks (auto-detected if omitted)')
    ap.add_argument('--depth',      type=int, default=1, metavar='N',
                    help='Recursion depth (default: 1 = signal + direct causes)')
    ap.add_argument('--config',     metavar='FILE',
                    help='Path to cause tree JSON (default: cause_tree.json next to this script)')
    args = ap.parse_args()

    # Load cause tree
    if args.config:
        config_path = args.config
    else:
        config_path = os.path.join(os.path.dirname(__file__), 'cause_tree.json')

    cause_tree = {}
    if os.path.exists(config_path):
        with open(config_path) as f:
            raw = json.load(f)
        # Normalize keys to lowercase for case-insensitive lookup
        cause_tree = {k.lower(): v for k, v in raw.items()}
    else:
        print(f'Warning: cause tree config not found: {config_path}', file=sys.stderr)

    vcd_parser = VCDParser(args.vcd)

    # Clock period
    clk_period = args.clk_period
    if clk_period is None:
        clk_period = detect_clk_period(vcd_parser)
        if clk_period:
            print(f'# Auto-detected clock period: {clk_period} ticks ({vcd_parser.timescale})',
                  file=sys.stderr)

    # Determine tick
    if args.tick is not None:
        tick = args.tick
        cycle_label = ticks_to_cycle(tick, clk_period)
    elif args.cycle is not None:
        if not clk_period:
            ap.error('--cycle requires a clock period; use --clk-period or ensure hclk is in the VCD')
        tick = args.cycle * clk_period
        cycle_label = args.cycle
    else:
        ap.error('Specify --cycle N or --tick N')

    print(f'\nSignal causes at cycle {cycle_label} (tick {tick}):\n')
    print_causes(vcd_parser, args.signal, tick, cause_tree,
                 depth=0, max_depth=args.depth)
    print()
    return 0


if __name__ == '__main__':
    sys.exit(main())
