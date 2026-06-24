#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    asphalt_diff.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Show the first PC divergence between two asphalt.log runs.
#----------------------------------------------------------------------------

"""
asphalt_diff.py — Compare two asphalt.log files and report the first divergence.

Usage:
    python3 asphalt_diff.py file1.log file2.log
    python3 asphalt_diff.py file1.log file2.log --show 10
    python3 asphalt_diff.py file1.log file2.log --field pc
    python3 asphalt_diff.py file1.log file2.log --field mnemonic
    python3 asphalt_diff.py file1.log file2.log --field all

Default: --field pc  (compare PC sequences, ignoring cycle timing differences)
"""

import re
import sys
import argparse
import os


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

FIELD_NAMES = ['cycle', 'pc', 'instr', 'mnemonic', 'mem', 'mem_addr',
               'mem_data', 'tgt_reg', 'sz', 'br', 'trap', 'priv']


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
# Comparison helpers
# ---------------------------------------------------------------------------

# Fields that participate in 'all' comparison (every meaningful field)
ALL_CMP_FIELDS = ['cycle', 'pc', 'instr', 'mnemonic', 'mem', 'mem_addr',
                  'mem_data', 'tgt_reg', 'sz', 'br', 'trap', 'priv']

# Fields compared in default 'pc' mode
PC_CMP_FIELDS = ['pc']


def records_equal(r1, r2, cmp_fields):
    """Return True if all cmp_fields match between the two records."""
    for f in cmp_fields:
        v1 = r1[f] if f != 'cycle' else r1[f]
        v2 = r2[f] if f != 'cycle' else r2[f]
        if str(v1).lower() != str(v2).lower():
            return False
    return True


def format_record(r, label, instr_num):
    """Format a single record for diff output."""
    parts = [
        f"cycle={r['cycle']}",
        f"pc={r['pc']}",
        f"{r['mnemonic']}",
        f"br={r['br']}",
    ]
    if r['trap'] != '-':
        parts.append(f"trap={r['trap']}")
    if r['mem'] != '-':
        parts.append(f"mem={r['mem']}@{r['mem_addr']}={r['mem_data']}")
    return f"  {label}[{instr_num}]: " + "  ".join(parts)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Compare two asphalt.log files and report the first divergence.'
    )
    parser.add_argument('file1', help='First asphalt.log')
    parser.add_argument('file2', help='Second asphalt.log')
    parser.add_argument('--show', type=int, default=5, metavar='N',
                        help='Number of post-divergence lines to show per file (default: 5)')
    parser.add_argument('--field', default='pc',
                        metavar='FIELD',
                        help=('Field(s) to compare: pc, mnemonic, instr, trap, br, '
                              'or "all" to compare every field (default: pc)'))

    args = parser.parse_args()

    for path in (args.file1, args.file2):
        if not os.path.isfile(path):
            print(f"Error: file not found: {path}", file=sys.stderr)
            sys.exit(1)

    recs1 = parse_asphalt(args.file1)
    recs2 = parse_asphalt(args.file2)

    # Determine comparison fields
    field_arg = args.field.strip().lower()
    if field_arg == 'all':
        cmp_fields = ALL_CMP_FIELDS
    elif field_arg in FIELD_NAMES:
        cmp_fields = [field_arg]
    else:
        print(f"Error: unknown field '{args.field}'. "
              f"Valid choices: {', '.join(FIELD_NAMES + ['all'])}",
              file=sys.stderr)
        sys.exit(1)

    # Walk both instruction streams in lock-step
    n_agree   = 0
    diverge   = None
    min_len   = min(len(recs1), len(recs2))

    for i in range(min_len):
        if records_equal(recs1[i], recs2[i], cmp_fields):
            n_agree += 1
        else:
            diverge = i
            break

    # Check for length mismatch after one file ends
    if diverge is None and len(recs1) != len(recs2):
        diverge = min_len  # one file is longer

    if diverge is None:
        print(f"Files are identical ({n_agree} instructions).")
        return

    print(f"Files agree for {n_agree} instructions.")
    print(f"DIVERGE at instruction #{n_agree + 1}:")

    # Show the diverging instruction from each file (if it exists)
    for label, recs, path in ((os.path.basename(args.file1), recs1, args.file1),
                               (os.path.basename(args.file2), recs2, args.file2)):
        if diverge < len(recs):
            print(format_record(recs[diverge], label, diverge + 1))
        else:
            print(f"  {label}: (end of file at instruction #{len(recs)})")

    # Show N following lines from each file
    if args.show > 0:
        print(f"\nFollowing {args.show} lines (file1 / file2):")
        for j in range(1, args.show + 1):
            idx = diverge + j
            line1 = (format_record(recs1[idx], os.path.basename(args.file1), idx + 1)
                     if idx < len(recs1) else
                     f"  {os.path.basename(args.file1)}[{idx + 1}]: (end of file)")
            line2 = (format_record(recs2[idx], os.path.basename(args.file2), idx + 1)
                     if idx < len(recs2) else
                     f"  {os.path.basename(args.file2)}[{idx + 1}]: (end of file)")
            print(line1)
            print(line2)
            # Stop early if both files exhausted
            if idx >= len(recs1) - 1 and idx >= len(recs2) - 1:
                break


if __name__ == '__main__':
    main()
