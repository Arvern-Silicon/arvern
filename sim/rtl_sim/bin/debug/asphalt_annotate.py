#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    asphalt_annotate.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Fuse the asphalt.log firmware trace with VCD signal values at each dispatch cycle.
#----------------------------------------------------------------------------

"""
Merge asphalt.log instruction trace with VCD signal values at each dispatch cycle.

For each instruction in the requested cycle range, the original asphalt.log columns
are printed (abbreviated) with the signal values appended after a '|' separator.
Signal values are shown as hex for buses, 0/1 for 1-bit signals.

Usage:
  python3 asphalt_annotate.py asphalt.log tb_arvern.vcd signal1 signal2 ... [options]
  python3 asphalt_annotate.py asphalt.log tb_arvern.vcd irq_software_i \\
      mstatus_mie trap_pending_o trap_taken --cycles 400:600
  python3 asphalt_annotate.py asphalt.log tb_arvern.vcd irq_detect \\
      irq_suppress_post_mret --cycles 540:640 --clk-period 10000
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from vcd_trace import VCDParser, detect_clk_period


# ─── Asphalt log parser ───────────────────────────────────────────────────────

def parse_asphalt(path):
    """Parse asphalt.log; return list of record dicts."""
    records = []
    with open(path) as f:
        for raw in f:
            line = raw.rstrip('\n')
            if not line or line.lstrip().startswith('#'):
                continue
            fields = re.split(r'\s{2,}', line.strip())
            if len(fields) < 13:
                continue
            try:
                rec = {
                    'cycle':    int(fields[0]),
                    'time_ns':  fields[1],
                    'pc':       fields[2],
                    'instr':    fields[3],
                    'mnemonic': fields[4],
                    'mem':      fields[5],
                    'mem_addr': fields[6],
                    'mem_data': fields[7],
                    'tgt_reg':  fields[8],
                    'sz':       fields[9],
                    'br':       fields[10],
                    'trap':     fields[11],
                    'priv':     fields[12],
                    '_raw':     raw,
                }
            except (ValueError, IndexError):
                continue
            records.append(rec)
    return records


# ─── Value helpers ────────────────────────────────────────────────────────────

def bin_to_hex(bstr, width):
    if any(c in bstr for c in 'xzXZ'):
        return bstr
    val = int(bstr, 2)
    hex_digits = (width + 3) // 4
    return f'0x{val:0{hex_digits}X}'


def format_val(bstr, width):
    if width == 1:
        return bstr
    return bin_to_hex(bstr, width)


# ─── VCD signal pre-loader ────────────────────────────────────────────────────

def load_signal_timeline(vcd_parser, sigs, t_start, t_end):
    """
    Stream the VCD once over [t_start, t_end] and build a timeline dict.

    Returns
    -------
    timeline : list of (timestamp, {vid: value_str})  — sorted by timestamp
    last_before : dict {vid: value_str} — last value seen before t_start
    """
    vids = [vid for _, vid, _ in sigs]

    # First pass: collect last value before t_start for each vid
    last_before = {}
    for t, snap in vcd_parser.stream_changes(vids, t_start=0, t_end=t_start):
        last_before.update(snap)

    # Second pass: collect all changes in range
    timeline = []
    for t, snap in vcd_parser.stream_changes(vids, t_start=t_start, t_end=t_end):
        timeline.append((t, snap))

    return timeline, last_before


def lookup_at_tick(timeline, last_before, tick):
    """
    Return {vid: value_str} at the given tick using the pre-loaded timeline.
    Uses the last-seen value at or before tick.
    """
    current = dict(last_before)
    for t, snap in timeline:
        if t > tick:
            break
        current.update(snap)
    return current


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description='Annotate asphalt.log with VCD signal values at each dispatch cycle.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument('asphalt_log', help='Path to asphalt.log')
    ap.add_argument('vcd',         help='Path to VCD file')
    ap.add_argument('signals',     nargs='+', help='Signal name patterns')
    ap.add_argument('--cycles',    metavar='START:END',
                    help='Cycle range to show (default: all)')
    ap.add_argument('--clk-period', type=int, metavar='N',
                    help='Clock period in ticks (auto-detected if omitted)')
    ap.add_argument('--traps-only', action='store_true',
                    help='Only show lines where the trap column is not "-"')
    args = ap.parse_args()

    # Parse asphalt log
    records = parse_asphalt(args.asphalt_log)
    if not records:
        print(f'No records found in {args.asphalt_log}', file=sys.stderr)
        return 1

    # VCD setup
    vcd_parser = VCDParser(args.vcd)

    clk_period = args.clk_period
    if clk_period is None:
        clk_period = detect_clk_period(vcd_parser)
        if clk_period:
            print(f'# Auto-detected clock period: {clk_period} ticks ({vcd_parser.timescale})',
                  file=sys.stderr)

    if not clk_period:
        print('Error: could not determine clock period. Use --clk-period.', file=sys.stderr)
        return 1

    # Cycle range filter
    cyc_start, cyc_end = None, None
    if args.cycles:
        parts = args.cycles.split(':')
        cyc_start = int(parts[0]) if parts[0] else None
        cyc_end   = int(parts[1]) if len(parts) > 1 and parts[1] else None

    # Filter records to the requested cycle range
    filtered = []
    for rec in records:
        c = rec['cycle']
        if cyc_start is not None and c < cyc_start:
            continue
        if cyc_end is not None and c > cyc_end:
            continue
        if args.traps_only and rec['trap'] == '-':
            continue
        filtered.append(rec)

    if not filtered:
        print('No matching records.', file=sys.stderr)
        return 0

    # Resolve signals
    sigs = vcd_parser.find_signals(args.signals)
    if not sigs:
        print('No signals found.', file=sys.stderr)
        return 1

    leaf_names = [s[0].split('.')[-1] for s in sigs]
    widths     = [s[2] for s in sigs]
    vids       = [s[1] for s in sigs]

    # Tick range for VCD streaming
    first_cycle = filtered[0]['cycle']
    last_cycle  = filtered[-1]['cycle']
    t_start_vcd = first_cycle * clk_period
    t_end_vcd   = last_cycle  * clk_period + clk_period

    # Pre-load signal timeline once
    timeline, last_before = load_signal_timeline(
        vcd_parser, sigs, t_start_vcd, t_end_vcd
    )

    # Build a cumulative state dict for O(1) per-instruction lookup
    # We walk timeline entries once in order while iterating records.
    timeline_idx = 0
    current_vals = dict(last_before)

    def advance_to(tick):
        nonlocal timeline_idx
        while timeline_idx < len(timeline) and timeline[timeline_idx][0] <= tick:
            current_vals.update(timeline[timeline_idx][1])
            timeline_idx += 1

    # Column widths for display
    mnemonic_w = max((len(r['mnemonic']) for r in filtered), default=24)
    mnemonic_w = max(mnemonic_w, 24)
    trap_w     = max((len(r['trap']) for r in filtered), default=8)
    trap_w     = max(trap_w, 8)

    # Signal column widths
    sig_col_widths = []
    for i, (leaf, w) in enumerate(zip(leaf_names, widths)):
        if w > 1:
            hex_w = (w + 3) // 4 + 2  # 0xNN
            sig_col_widths.append(max(len(leaf), hex_w, 4))
        else:
            sig_col_widths.append(max(len(leaf), 4))

    # Header
    hdr_left  = f"{'cycle':>6}  {'pc':<12}  {'mnemonic':<{mnemonic_w}}  {'trap':<{trap_w}}"
    hdr_sigs  = '  '.join(n.ljust(sig_col_widths[i]) for i, n in enumerate(leaf_names))
    sep_len   = len(hdr_left) + 3 + len(hdr_sigs)
    print(f'{hdr_left}  | {hdr_sigs}')
    print('-' * sep_len)

    for rec in filtered:
        cycle = rec['cycle']
        tick  = cycle * clk_period

        # Advance cumulative state to this tick
        advance_to(tick)

        # Format signal values
        sig_vals = []
        for i, (vid, w) in enumerate(zip(vids, widths)):
            raw = current_vals.get(vid, 'x')
            sig_vals.append(format_val(raw, w).ljust(sig_col_widths[i]))

        left = (f"{cycle:>6}  {rec['pc']:<12}  "
                f"{rec['mnemonic']:<{mnemonic_w}}  "
                f"{rec['trap']:<{trap_w}}")
        print(f'{left}  | {"  ".join(sig_vals)}')

    print('-' * sep_len)
    return 0


if __name__ == '__main__':
    sys.exit(main())
