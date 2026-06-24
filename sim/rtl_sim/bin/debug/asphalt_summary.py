#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    asphalt_summary.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Aggregate stats from asphalt.log (trap counts, MRET counts, livelock heuristics).
#----------------------------------------------------------------------------

"""
asphalt_summary.py — Summarize an asphalt.log execution trace.

Usage:
    python3 asphalt_summary.py [asphalt.log]
    python3 asphalt_summary.py asphalt.log --livelock-threshold 50
    python3 asphalt_summary.py asphalt.log --traps-only
"""

import re
import sys
import argparse
import os
from collections import deque


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_asphalt(path):
    """Parse an asphalt.log and return a list of field dicts plus the raw lines."""
    records = []
    with open(path, 'r') as fh:
        for raw in fh:
            line = raw.rstrip('\n')
            if not line or line.lstrip().startswith('#'):
                continue
            # Split on 2+ whitespace to handle variable-width mnemonic
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
# Analysis helpers
# ---------------------------------------------------------------------------

def collect_traps(records):
    """Return list of records where trap field is not '-'."""
    return [r for r in records if r['trap'] != '-' and not r['trap'].startswith('MRET') and not r['trap'].startswith('SRET')]


def collect_mrets(records):
    """Return list of records where trap field is MRET or SRET."""
    return [r for r in records if r['trap'].startswith('MRET') or r['trap'].startswith('SRET')]


def detect_livelock(records, threshold):
    """
    Scan for a repeating PC window (up to 8 PCs) that repeats more than
    `threshold` consecutive times.

    Returns (detected, window_pcs, repeat_count, start_cycle, end_cycle)
    or (False, ...) if none found.
    """
    if not records:
        return False, [], 0, 0, 0

    MAX_WINDOW = 8

    # Try increasing window sizes from 1 to MAX_WINDOW
    for window_size in range(1, MAX_WINDOW + 1):
        count = 0
        start_idx = 0
        i = window_size  # start checking from second window occurrence

        while i + window_size <= len(records):
            # Compare current window to previous window
            prev_window = [records[i - window_size + k]['pc'] for k in range(window_size)]
            curr_window = [records[i + k]['pc'] for k in range(window_size)]

            if prev_window == curr_window:
                if count == 0:
                    start_idx = i - window_size
                count += 1
                i += window_size
            else:
                if count >= threshold:
                    # Found a livelock
                    end_idx = i - 1
                    window_pcs = [records[start_idx + k]['pc'] for k in range(window_size)]
                    start_cycle = records[start_idx]['cycle']
                    end_cycle = records[end_idx]['cycle']
                    return True, window_pcs, count, start_cycle, end_cycle
                count = 0
                i += 1

        # Check at end of file
        if count >= threshold:
            end_idx = len(records) - 1
            window_pcs = [records[start_idx + k]['pc'] for k in range(window_size)]
            start_cycle = records[start_idx]['cycle']
            end_cycle = records[end_idx]['cycle']
            return True, window_pcs, count, start_cycle, end_cycle

    return False, [], 0, 0, 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Summarize an asphalt.log execution trace.'
    )
    parser.add_argument('logfile', nargs='?', default='asphalt.log',
                        help='Path to asphalt.log (default: ./asphalt.log)')
    parser.add_argument('--livelock-threshold', type=int, default=100,
                        metavar='N',
                        help='Consecutive PC-window repetitions before declaring livelock (default: 100)')
    parser.add_argument('--traps-only', action='store_true',
                        help='Only show trap events table, skip MRET and livelock sections')
    args = parser.parse_args()

    if not os.path.isfile(args.logfile):
        print(f"Error: file not found: {args.logfile}", file=sys.stderr)
        sys.exit(1)

    records = parse_asphalt(args.logfile)
    if not records:
        print(f"No data records found in {args.logfile}", file=sys.stderr)
        sys.exit(1)

    last_cycle = records[-1]['cycle']
    n_instr    = len(records)

    print(f"\n# {args.logfile}  ({n_instr} instructions,  last cycle: {last_cycle})\n")

    # --- Trap events ---
    traps = collect_traps(records)
    if traps:
        print(f"Trap events ({len(traps)}):")
        for idx, r in enumerate(traps, 1):
            print(f"  #{idx:<3d} cycle={r['cycle']:<8d} {r['trap']:<12s} at {r['pc']}")
    else:
        print("No trap events.")

    if args.traps_only:
        return

    print()

    # --- MRET/SRET events ---
    mrets = collect_mrets(records)
    if mrets:
        print(f"MRET/SRET events ({len(mrets)}):")
        for idx, r in enumerate(mrets, 1):
            print(f"  #{idx:<3d} cycle={r['cycle']:<8d} {r['trap']:<10s} at {r['pc']}")
    else:
        print("No MRET/SRET events.")

    print()

    # --- Livelock detection ---
    detected, window_pcs, repeat_count, start_cycle, end_cycle = detect_livelock(
        records, args.livelock_threshold
    )
    if detected:
        pc_range = window_pcs[0] if len(window_pcs) == 1 else f"{window_pcs[0]}..{window_pcs[-1]}"
        print(f"LIVELOCK DETECTED: PC {pc_range} repeated {repeat_count}x  "
              f"(cycles {start_cycle}..{end_cycle})")
    else:
        print("No livelock detected.")

    print()


if __name__ == '__main__':
    main()
