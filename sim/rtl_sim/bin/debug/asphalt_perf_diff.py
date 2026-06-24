#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    asphalt_perf_diff.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Per-instruction cycle delta between two asphalt.log runs of the same
# firmware. Complements asphalt_diff.py (which finds first PC divergence) by
# computing where extra cycles accumulate when the PC sequence is identical
# but timing differs (e.g. linker layout, bus topology, libc swap).
#----------------------------------------------------------------------------

"""
asphalt_perf_diff.py — Compare two asphalt.log runs cycle-by-cycle.

Aligns the two traces (log_a = reference, log_b = compared) at a chosen
anchor PC and computes per-instruction cycle deltas from that point onward.
Useful when you want to know *where* the extra cycles go between two
binaries with identical .text (or .text shifted by a fixed offset, e.g.
different .rodata location, different libc, different linker layout).

Three ways to anchor:
    --anchor 0xPC                                # same address in both binaries
    --anchor-a 0xPC_A --anchor-b 0xPC_B          # different addresses
    --elf-a a.elf --elf-b b.elf --anchor-sym SYM # resolve symbol -> PC via nm

When the two anchors differ, a constant PC offset is derived from the
anchor delta and applied to align log_a's PC sequence onto log_b's
(useful when a linker change shifted all of .text by a fixed amount).
PC mismatches after that are reported and stop the alignment.

Reports include:
    - Aggregate cycle delta + total
    - Top mnemonics, memory-op categories, slave targets by extra cycles
    - Top PCs by extra cycles, annotated with branch-target alignment
      flips (4-byte vs 2-byte aligned PCs across the two binaries) so you
      can spot whether the slowdown is alignment-related
    - Alignment-flip rollup (4-4, 4->2, 2->4, 2-2 buckets) across ALL
      contributing PCs

Examples:
    # Same symbol addresses in both binaries -- use single anchor:
    python3 asphalt_perf_diff.py ref.log cmp.log --anchor 0x20000690

    # Different symbol addresses -- resolve "main" from each ELF:
    python3 asphalt_perf_diff.py ref.log cmp.log \\
        --elf-a ref.elf --elf-b cmp.elf --anchor-sym main

    # Equivalent if you know the addresses:
    python3 asphalt_perf_diff.py ref.log cmp.log \\
        --anchor-a 0x20000690 --anchor-b 0x200006c0
"""

import argparse
import os
import re
import subprocess
import sys
from collections import defaultdict


def find_symbol_in_elf(elf_path, sym_name, toolchain_prefix='riscv-none-elf'):
    """Resolve a symbol name to its '0xHEX' PC via toolchain nm.

    Returns the lowercase '0xHEX' address string, or None if either the
    nm binary is missing or the symbol is not present (as 'T' or 't').
    """
    try:
        out = subprocess.check_output([f'{toolchain_prefix}-nm', elf_path],
                                      text=True, stderr=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] in ('T', 't') and parts[2] == sym_name:
            return '0x' + parts[0].lower()
    return None


def alignment_flip(v1_pc, v3_pc):
    """Classify the branch-target alignment shift between two PCs.

    Returns one of: '4-4', '4->2', '2->4', '2-2', or 'odd' for anything
    that isn't a clean halfword pair.
    """
    a1, a3 = v1_pc & 3, v3_pc & 3
    if (a1, a3) == (0, 0): return '4-4'
    if (a1, a3) == (0, 2): return '4->2'
    if (a1, a3) == (2, 0): return '2->4'
    if (a1, a3) == (2, 2): return '2-2'
    return 'odd'


def parse_asphalt(path, max_records=None):
    """Parse asphalt.log into a list of compact tuples (cycle, pc, mnemonic, mem, mem_addr).

    Returns lists instead of dicts so the memory footprint of 700K-line traces
    stays reasonable. max_records caps loading for quick smoke tests.
    """
    cycles, pcs, mnemonics, mems, addrs = [], [], [], [], []
    n = 0
    with open(path, 'r') as fh:
        for raw in fh:
            line = raw.rstrip('\n')
            if not line or line.lstrip().startswith('#'):
                continue
            fields = re.split(r'\s{2,}', line.strip())
            if len(fields) < 13:
                continue
            try:
                cyc = int(fields[0])
            except ValueError:
                continue
            cycles.append(cyc)
            pcs.append(fields[2])
            mnemonics.append(fields[4])
            mems.append(fields[5])
            addrs.append(fields[6])
            n += 1
            if max_records and n >= max_records:
                break
    return cycles, pcs, mnemonics, mems, addrs


def find_anchor(pcs, anchor_pc):
    """Return the index of the first occurrence of anchor_pc, or None."""
    target = anchor_pc.lower()
    for i, pc in enumerate(pcs):
        if pc.lower() == target:
            return i
    return None


def classify_addr(addr):
    """Map a mem_addr to a slave bucket using the testbench's address map.

    See bench/verilog/ahb_decoder.v:
        ROM      : 0x20000000..0x20001FFF (8 KB)
        SRAM_X   : 0x80000000..0x80001FFF (8 KB)
        SRAM_NX  : 0x81000000..0x81001FFF (8 KB)
        peripherals + PLIC at 0x10040000+, 0x0C000000+
    """
    if addr in ('-', '', '0x00000000'):
        return 'none'
    try:
        a = int(addr, 16)
    except ValueError:
        return 'unknown'
    if 0x20000000 <= a < 0x20002000: return 'ROM'
    if 0x80000000 <= a < 0x80002000: return 'SRAM_X'
    if 0x81000000 <= a < 0x81002000: return 'SRAM_NX'
    if 0x10040000 <= a < 0x10043000: return 'periph'
    if 0x0C000000 <= a < 0x0C400000: return 'PLIC'
    return 'other'


def main():
    ap = argparse.ArgumentParser(description='Cycle-delta diff between two asphalt.log runs.',
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('log_a', help='First (reference) asphalt.log')
    ap.add_argument('log_b', help='Second (compared) asphalt.log; cycle deltas are b - a.')
    ap.add_argument('--anchor', default=None,
                    help='Anchor PC (hex; e.g. 0x200006be) used in BOTH traces. Use this when both binaries have the same symbol layout. If symbol addresses differ between the two builds (e.g. linker-script changes shift main()), use --anchor-a / --anchor-b instead.')
    ap.add_argument('--anchor-a', default=None,
                    help='Anchor PC for log_a. Overrides --anchor. Pair with --anchor-b. Find via: riscv-none-elf-nm <a.elf> | grep " T <symbol>$".')
    ap.add_argument('--anchor-b', default=None,
                    help='Anchor PC for log_b. Overrides --anchor. Pair with --anchor-a.')
    ap.add_argument('--elf-a', default=None,
                    help='Path to log_a\'s ELF file. Used with --anchor-sym to resolve the symbol\'s PC.')
    ap.add_argument('--elf-b', default=None,
                    help='Path to log_b\'s ELF file. Used with --anchor-sym.')
    ap.add_argument('--anchor-sym', default=None,
                    help='Symbol name to anchor at (e.g. "main"). Requires --elf-a and --elf-b; resolves to per-trace PCs via nm.')
    ap.add_argument('--toolchain-prefix', default='riscv-none-elf',
                    help='Toolchain prefix used for nm when resolving --anchor-sym. Default: riscv-none-elf.')
    ap.add_argument('--top', type=int, default=20,
                    help='Top-N rows per category in the report. Default: 20.')
    ap.add_argument('--max-records', type=int, default=None,
                    help='Cap the number of records loaded per trace (smoke test).')
    ap.add_argument('--max-mismatch', type=int, default=10,
                    help='Stop after this many PC mismatches between aligned traces. Default: 10.')
    args = ap.parse_args()

    if not os.path.isfile(args.log_a) or not os.path.isfile(args.log_b):
        sys.exit(f'ERROR: input file missing')

    # ----- parse both traces -----
    print(f'Parsing {args.log_a} ...', file=sys.stderr)
    ca, pa, ma, mea, mha = parse_asphalt(args.log_a, args.max_records)
    print(f'  -> {len(ca):,} records', file=sys.stderr)
    print(f'Parsing {args.log_b} ...', file=sys.stderr)
    cb, pb, mb, meb, mhb = parse_asphalt(args.log_b, args.max_records)
    print(f'  -> {len(cb):,} records', file=sys.stderr)

    # ----- find anchor (symbol-name | per-trace PCs | shared PC | none) -----
    if args.anchor_sym:
        if not (args.elf_a and args.elf_b):
            sys.exit('ERROR: --anchor-sym requires both --elf-a and --elf-b')
        anchor_a = find_symbol_in_elf(args.elf_a, args.anchor_sym, args.toolchain_prefix)
        anchor_b = find_symbol_in_elf(args.elf_b, args.anchor_sym, args.toolchain_prefix)
        if not anchor_a:
            sys.exit(f'ERROR: symbol "{args.anchor_sym}" not found (or {args.toolchain_prefix}-nm not on PATH) in {args.elf_a}')
        if not anchor_b:
            sys.exit(f'ERROR: symbol "{args.anchor_sym}" not found (or {args.toolchain_prefix}-nm not on PATH) in {args.elf_b}')
        print(f'Anchor symbol "{args.anchor_sym}" -> log_a@{anchor_a}, log_b@{anchor_b}',
              file=sys.stderr)
    elif args.anchor_a or args.anchor_b:
        if not (args.anchor_a and args.anchor_b):
            sys.exit('ERROR: --anchor-a and --anchor-b must be supplied together '
                     '(use --anchor when both traces share the same symbol address)')
        anchor_a, anchor_b = args.anchor_a, args.anchor_b
    elif args.anchor:
        anchor_a = anchor_b = args.anchor
    else:
        anchor_a = anchor_b = None

    if anchor_a:
        ia = find_anchor(pa, anchor_a)
        ib = find_anchor(pb, anchor_b) if anchor_b else None
        if ia is None:
            sys.exit(f'ERROR: anchor PC {anchor_a} not found in log_a')
        if ib is None:
            sys.exit(f'ERROR: anchor PC {anchor_b} not found in log_b')
        same_label = '(same)' if anchor_a == anchor_b else '(per-trace)'
        print(f'Anchor {same_label}: log_a@{anchor_a} idx={ia} cyc={ca[ia]}  '
              f'log_b@{anchor_b} idx={ib} cyc={cb[ib]}', file=sys.stderr)
    else:
        ia = ib = 0

    # ----- walk in lock-step, computing per-instruction delta -----
    na = len(ca) - ia
    nb = len(cb) - ib
    n  = min(na, nb)

    # Constant-offset alignment: when the two binaries differ only by an
    # in-.text shift (e.g. v3 has a larger crt0), the offset between any
    # corresponding PCs is constant and equal to (anchor_b - anchor_a).
    pc_offset = 0
    if anchor_a and anchor_b and anchor_a != anchor_b:
        try:
            pc_offset = int(anchor_b, 16) - int(anchor_a, 16)
        except ValueError:
            pass
    if pc_offset:
        print(f'PC offset (b - a) derived from anchors: {pc_offset:+#x}', file=sys.stderr)

    mismatches = 0
    last_cyc_a = ca[ia]
    last_cyc_b = cb[ib]

    # per-bucket extra-cycle accumulators
    by_mnem    = defaultdict(int)
    by_memop   = defaultdict(int)
    by_slave   = defaultdict(int)
    by_pc      = defaultdict(int)
    # also counts (for averaging)
    cnt_mnem   = defaultdict(int)
    cnt_slave  = defaultdict(int)
    cnt_pc     = defaultdict(int)

    total_extra = 0
    aligned_n   = 0

    for k in range(1, n):
        pa_pc = pa[ia + k]
        pb_pc = pb[ib + k]
        # Apply the constant PC offset before comparing (no-op when offset=0)
        pa_eff = pa_pc if not pc_offset else f'0x{(int(pa_pc, 16) + pc_offset) & 0xFFFFFFFF:08x}'
        if pa_eff != pb_pc:
            mismatches += 1
            if mismatches >= args.max_mismatch:
                print(f'\nWARNING: too many PC mismatches ({mismatches}); '
                      f'stopping alignment at instr index {k} '
                      f'(a={pa_pc} a_shifted={pa_eff}, b={pb_pc})', file=sys.stderr)
                break
            continue

        dt_a = ca[ia + k] - last_cyc_a
        dt_b = cb[ib + k] - last_cyc_b
        extra = dt_b - dt_a
        last_cyc_a = ca[ia + k]
        last_cyc_b = cb[ib + k]

        total_extra += extra
        aligned_n   += 1

        if extra != 0:
            # only bucket the contributing instructions to keep the output tight
            mnemonic = ma[ia + k].split()[0] if ma[ia + k] else '-'
            mop      = mea[ia + k]            # R, W, or -
            slave    = classify_addr(mha[ia + k])

            by_mnem[mnemonic]    += extra
            by_memop[mop]        += extra
            by_slave[slave]      += extra
            by_pc[pa_pc]         += extra
            cnt_mnem[mnemonic]   += 1
            cnt_slave[slave]     += 1
            cnt_pc[pa_pc]        += 1

    # ----- report -----
    total_a = ca[ia + aligned_n] - ca[ia] if aligned_n > 0 else 0
    total_b = cb[ib + aligned_n] - cb[ib] if aligned_n > 0 else 0

    print()
    print('='*78)
    print('Aligned-window summary (from anchor onward)')
    print('='*78)
    print(f'  Aligned instructions: {aligned_n:>10,}')
    print(f'  PC mismatches seen:   {mismatches:>10,}')
    print(f'  log_a cycle span:     {total_a:>10,}  ({args.log_a})')
    print(f'  log_b cycle span:     {total_b:>10,}  ({args.log_b})')
    delta = total_b - total_a
    pct = 100.0 * delta / total_a if total_a else 0
    print(f'  Delta (b - a):        {delta:>+10,}  ({pct:+.2f} %)')
    print(f'  Cumulative extras (only nonzero-delta instrs): {total_extra:>+10,}')

    def print_table(title, accum, counts=None, n=args.top):
        print()
        print('-'*78)
        print(title)
        print('-'*78)
        items = sorted(accum.items(), key=lambda kv: -abs(kv[1]))[:n]
        col_w = max((len(str(k)) for k, _ in items), default=10)
        for k, v in items:
            extra = f'avg={v/counts[k]:+.2f}c/instr  cnt={counts[k]:,}' if counts and counts.get(k) else ''
            print(f'  {str(k):<{col_w}}  {v:>+10,} cycles   {extra}')

    print_table(f'Top {args.top} mnemonics by extra cycles (only nonzero-delta instrs)',
                by_mnem, cnt_mnem)
    print_table(f'Top {args.top} memory targets by extra cycles',
                by_slave, cnt_slave)
    print()
    print('-'*78)
    print('Memory-op buckets (R = load, W = store, - = ALU/branch/no memory)')
    print('-'*78)
    for k in ('R', 'W', '-'):
        v = by_memop.get(k, 0)
        print(f'  {k:<3}  {v:>+10,} cycles')

    # ----- per-PC table with alignment-flip annotation -----
    print()
    print('-'*100)
    print(f'Top {args.top} PCs by |extra cycles|  (with branch-target alignment flips)')
    print('-'*100)
    print(f'  {"PC_a":<12} {"PC_b":<12} {"a%4":>4} {"b%4":>4} {"flip":<6} '
          f'{"cycles":>10} {"count":>6} {"avg":>8}')
    items = sorted(by_pc.items(), key=lambda kv: -abs(kv[1]))[:args.top]
    for pa_pc, cycles in items:
        pc_a = int(pa_pc, 16)
        pc_b = (pc_a + pc_offset) & 0xFFFFFFFF
        cls = alignment_flip(pc_a, pc_b)
        cnt = cnt_pc[pa_pc]
        avg = cycles / cnt if cnt else 0
        print(f'  0x{pc_a:08x}  0x{pc_b:08x}  {pc_a & 3:>4} {pc_b & 3:>4} {cls:<6} '
              f'{cycles:>+10,} {cnt:>6,} {avg:>+8.2f}')

    # ----- alignment-flip rollup across ALL nonzero-delta PCs -----
    flip_cyc = defaultdict(int)
    flip_cnt = defaultdict(int)
    flip_pcs = defaultdict(int)
    for pa_pc, cycles in by_pc.items():
        pc_a = int(pa_pc, 16)
        pc_b = (pc_a + pc_offset) & 0xFFFFFFFF
        cls = alignment_flip(pc_a, pc_b)
        flip_cyc[cls] += cycles
        flip_cnt[cls] += cnt_pc[pa_pc]
        flip_pcs[cls] += 1

    print()
    print('-'*78)
    print('Branch-target alignment-flip summary (all nonzero-delta PCs)')
    print('-'*78)
    print(f'  {"flip":<8} {"cycles":>10} {"PCs":>8} {"instrs":>10} {"avg":>10}')
    for cls in ('4-4', '4->2', '2->4', '2-2', 'odd'):
        cyc = flip_cyc.get(cls, 0)
        cnt = flip_cnt.get(cls, 0)
        n_pcs = flip_pcs.get(cls, 0)
        if cyc == 0 and cnt == 0:
            continue
        avg = cyc / cnt if cnt else 0
        print(f'  {cls:<8} {cyc:>+10,} {n_pcs:>8,} {cnt:>10,} {avg:>+10.2f}')

    print()
    print('Reading the flip column (a = log_a, b = log_b):')
    print('  "4-4"  = PC_a mod 4 == 0  and  PC_b mod 4 == 0   (4-byte aligned in BOTH; no flip)')
    print('  "4->2" = PC_a was 4-byte aligned, PC_b is 2-byte aligned only   (FAST -> SLOW)')
    print('  "2->4" = PC_a was 2-byte aligned, PC_b is 4-byte aligned        (SLOW -> FAST)')
    print('  "2-2"  = both 2-byte aligned only   (SLOW in both; no flip)')
    print('A net positive delta concentrated in 4->2 rows is a smoking gun for an')
    print('alignment artifact -- log_b\'s build shifted .text by an odd halfword amount,')
    print('flipping every taken-branch target by 2 bytes.')


if __name__ == '__main__':
    main()
