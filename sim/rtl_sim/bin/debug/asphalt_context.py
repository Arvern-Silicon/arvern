#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    asphalt_context.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Extract N instructions around a trap / MRET / cycle / PC anchor in asphalt.log.
#----------------------------------------------------------------------------

"""
asphalt_context.py — Show N instructions before/after a specific point in an
asphalt.log execution trace.

Usage:
    python3 asphalt_context.py [asphalt.log] --trap 3
    python3 asphalt_context.py [asphalt.log] --mret 2
    python3 asphalt_context.py [asphalt.log] --cycle 425
    python3 asphalt_context.py [asphalt.log] --pc 0x20000030
    python3 asphalt_context.py [asphalt.log] --pc 0x20000030 --nth 3
    python3 asphalt_context.py [asphalt.log] --cycle 425 --before 10 --after 5

Defaults: --before 8 --after 4
"""

import re
import sys
import argparse
import os


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_asphalt(path):
    """Parse an asphalt.log and return a list of field dicts (with '_raw' line)."""
    records = []
    with open(path, 'r') as fh:
        for raw in fh:
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


# ---------------------------------------------------------------------------
# Anchor finders
# ---------------------------------------------------------------------------

def find_trap_anchor(records, nth):
    """Return index of the nth trap event (IRQ/exception, not MRET/SRET)."""
    count = 0
    for i, r in enumerate(records):
        trap = r['trap']
        if trap != '-' and not trap.startswith('MRET') and not trap.startswith('SRET'):
            count += 1
            if count == nth:
                return i
    return None


def find_mret_anchor(records, nth):
    """Return index of the nth MRET/SRET event."""
    count = 0
    for i, r in enumerate(records):
        trap = r['trap']
        if trap.startswith('MRET') or trap.startswith('SRET'):
            count += 1
            if count == nth:
                return i
    return None


def find_cycle_anchor(records, target_cycle):
    """Return index of the record whose cycle is closest to target_cycle."""
    best_idx = None
    best_dist = None
    for i, r in enumerate(records):
        dist = abs(r['cycle'] - target_cycle)
        if best_dist is None or dist < best_dist:
            best_dist = dist
            best_idx = i
    return best_idx


def find_pc_anchor(records, target_pc, nth):
    """Return index of the nth occurrence of target_pc."""
    # Normalize both sides to lowercase hex for comparison
    target_norm = target_pc.lower()
    count = 0
    for i, r in enumerate(records):
        if r['pc'].lower() == target_norm:
            count += 1
            if count == nth:
                return i
    return None


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

def print_context(records, anchor_idx, before, after):
    """Print context lines around anchor_idx with >>> prefix on anchor line."""
    total = len(records)
    start = max(0, anchor_idx - before)
    end   = min(total - 1, anchor_idx + after)

    # Leading separator
    if start > 0:
        skipped = start
        print(f"--- ({skipped} instructions skipped) ---")

    for i in range(start, end + 1):
        raw = records[i]['_raw'].rstrip('\n')
        if i == anchor_idx:
            print(f">>> {raw}")
        else:
            print(f"    {raw}")

    # Trailing separator
    if end < total - 1:
        skipped = total - 1 - end
        print(f"--- ({skipped} instructions skipped) ---")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Show context around a specific point in an asphalt.log trace.'
    )
    parser.add_argument('logfile', nargs='?', default='asphalt.log',
                        help='Path to asphalt.log (default: ./asphalt.log)')

    # Anchor selection (mutually exclusive)
    anchor_group = parser.add_mutually_exclusive_group(required=True)
    anchor_group.add_argument('--trap', type=int, metavar='N',
                              help='Anchor on the Nth trap event (IRQ/exception)')
    anchor_group.add_argument('--mret', type=int, metavar='N',
                              help='Anchor on the Nth MRET/SRET event')
    anchor_group.add_argument('--cycle', type=int, metavar='CYCLE',
                              help='Anchor on the instruction closest to CYCLE')
    anchor_group.add_argument('--pc', metavar='ADDR',
                              help='Anchor on the first (or --nth) occurrence of this PC')

    parser.add_argument('--nth', type=int, default=1, metavar='N',
                        help='Which occurrence to use with --pc (default: 1)')
    parser.add_argument('--before', type=int, default=8, metavar='N',
                        help='Instructions to show before anchor (default: 8)')
    parser.add_argument('--after', type=int, default=4, metavar='N',
                        help='Instructions to show after anchor (default: 4)')

    args = parser.parse_args()

    if not os.path.isfile(args.logfile):
        print(f"Error: file not found: {args.logfile}", file=sys.stderr)
        sys.exit(1)

    records = parse_asphalt(args.logfile)
    if not records:
        print(f"No data records found in {args.logfile}", file=sys.stderr)
        sys.exit(1)

    # Locate anchor
    anchor_idx = None

    if args.trap is not None:
        anchor_idx = find_trap_anchor(records, args.trap)
        if anchor_idx is None:
            print(f"Error: trap event #{args.trap} not found in {args.logfile}",
                  file=sys.stderr)
            sys.exit(1)
        r = records[anchor_idx]
        print(f"Anchor: trap #{args.trap}  cycle={r['cycle']}  {r['trap']}  at {r['pc']}\n")

    elif args.mret is not None:
        anchor_idx = find_mret_anchor(records, args.mret)
        if anchor_idx is None:
            print(f"Error: MRET/SRET event #{args.mret} not found in {args.logfile}",
                  file=sys.stderr)
            sys.exit(1)
        r = records[anchor_idx]
        print(f"Anchor: mret #{args.mret}  cycle={r['cycle']}  {r['trap']}  at {r['pc']}\n")

    elif args.cycle is not None:
        anchor_idx = find_cycle_anchor(records, args.cycle)
        if anchor_idx is None:
            print(f"Error: no records found in {args.logfile}", file=sys.stderr)
            sys.exit(1)
        r = records[anchor_idx]
        print(f"Anchor: closest to cycle {args.cycle}  -> cycle={r['cycle']}  at {r['pc']}\n")

    elif args.pc is not None:
        anchor_idx = find_pc_anchor(records, args.pc, args.nth)
        if anchor_idx is None:
            print(f"Error: PC {args.pc} (occurrence #{args.nth}) not found in {args.logfile}",
                  file=sys.stderr)
            sys.exit(1)
        r = records[anchor_idx]
        print(f"Anchor: pc={args.pc} occurrence #{args.nth}  cycle={r['cycle']}\n")

    print_context(records, anchor_idx, args.before, args.after)


if __name__ == '__main__':
    main()
