#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    vcd_find.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Find every rising/falling edge or value match for a signal in a VCD.
#----------------------------------------------------------------------------

"""
Find timestamps / cycle numbers where a VCD signal matches a condition.

Conditions:
  --rise         : signal transitions 0→1
  --fall         : signal transitions 1→0
  --value V      : signal equals V (binary or hex with 0x prefix)
  --posedge      : alias for --rise
  --negedge      : alias for --fall

Usage (from sim/rtl_sim/run/):
  python3 ../bin/debug/vcd_find.py tb_arvern.vcd trap_taken --rise
  python3 ../bin/debug/vcd_find.py tb_arvern.vcd irq_software_i --rise --cycles 500:700
  python3 ../bin/debug/vcd_find.py tb_arvern.vcd mstatus_mie --fall --rise
"""

import argparse
import sys
from vcd_trace import VCDParser, detect_clk_period, ticks_to_cycle


def parse_value(vstr):
    """Parse a value string to a binary string for comparison."""
    vstr = vstr.strip()
    if vstr.startswith('0x') or vstr.startswith('0X'):
        ival = int(vstr, 16)
        return bin(ival)[2:]
    if vstr.startswith('0b') or vstr.startswith('0B'):
        return vstr[2:]
    # Try plain decimal
    try:
        return bin(int(vstr))[2:]
    except ValueError:
        return vstr  # treat as raw binary string


def main():
    ap = argparse.ArgumentParser(
        description='Find timestamps where a VCD signal meets a condition.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument('vcd',    help='Path to VCD file')
    ap.add_argument('signal', help='Signal name pattern')
    ap.add_argument('--rise',    '--posedge', action='store_true', help='Find rising edges')
    ap.add_argument('--fall',    '--negedge', action='store_true', help='Find falling edges')
    ap.add_argument('--value',   metavar='V', help='Find when signal equals V')
    ap.add_argument('--cycles',  metavar='START:END', help='Restrict to cycle range')
    ap.add_argument('--ticks',   metavar='START:END', help='Restrict to tick range')
    ap.add_argument('--clk-period', type=int, metavar='N',
                    help='Clock period in ticks (auto-detected if omitted)')
    ap.add_argument('--limit', type=int, default=200, metavar='N',
                    help='Max matches to print (default: 200)')
    args = ap.parse_args()

    vcd_parser = VCDParser(args.vcd)
    sigs = vcd_parser.find_signals([args.signal])
    if not sigs:
        print(f'No signal matching "{args.signal}"', file=sys.stderr)
        return 1

    full_name, vid, width = sigs[0]
    if len(sigs) > 1:
        print(f'# Multiple matches; using first: {full_name}', file=sys.stderr)

    clk_period = args.clk_period or detect_clk_period(vcd_parser)
    if clk_period:
        print(f'# Clock period: {clk_period} ticks', file=sys.stderr)

    t_start, t_end = 0, None
    if args.ticks:
        parts = args.ticks.split(':')
        t_start = int(parts[0]) if parts[0] else 0
        t_end   = int(parts[1]) if len(parts) > 1 and parts[1] else None
    elif args.cycles and clk_period:
        parts = args.cycles.split(':')
        t_start = int(parts[0]) * clk_period if parts[0] else 0
        t_end   = int(parts[1]) * clk_period if len(parts) > 1 and parts[1] else None

    target_val = parse_value(args.value) if args.value else None

    prev_val = None
    count = 0
    print(f'# Signal: {full_name}  (width={width})')
    print(f'{"Cycle":>8}  {"Tick":>12}  {"Prev":>12}  {"New":>12}')
    print('-' * 52)

    for t, snap in vcd_parser.stream_changes([vid], t_start=t_start, t_end=t_end):
        new_val = snap.get(vid)
        if new_val is None:
            continue

        match = False
        if args.rise and prev_val == '0' and new_val == '1':
            match = True
        if args.fall and prev_val == '1' and new_val == '0':
            match = True
        if target_val is not None:
            # Normalize both to int for comparison
            try:
                nv_int = int(new_val, 2) if all(c in '01' for c in new_val) else None
                tv_int = int(target_val, 2) if all(c in '01' for c in target_val) else None
                if nv_int is not None and tv_int is not None and nv_int == tv_int:
                    match = True
                elif new_val == target_val:
                    match = True
            except Exception:
                if new_val == target_val:
                    match = True

        if match:
            cycle = ticks_to_cycle(t, clk_period)
            pv = prev_val if prev_val is not None else '-'
            print(f'{cycle:>8}  {t:>12}  {pv:>12}  {new_val:>12}')
            count += 1
            if count >= args.limit:
                print(f'# (limit {args.limit} reached)')
                break

        prev_val = new_val

    print('-' * 52)
    print(f'# Total matches: {count}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
