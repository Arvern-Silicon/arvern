#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    bench_compare.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Compare two benchmark trace snapshots side-by-side.
#----------------------------------------------------------------------------

"""bench_compare — Compare benchmark results across snapshots and latest traces.

Usage (run from sim/rtl_sim/run/):
    ../bin/bench_compare                            # list available snapshots
    ../bin/bench_compare snap_a                     # snap_a vs latest
    ../bin/bench_compare snap_a snap_b              # snap_a, snap_b, + latest
    ../bin/bench_compare snap_a --attr ipc          # compare IPC
    ../bin/bench_compare snap_a --suite embench     # embench only (Speed Score)
"""

import argparse
import math
import sys
from pathlib import Path

from .bench_utils import (
    ATTR_LABELS, ATTR_HIGHER_IS_BETTER,
    detect_suite, embench_speed_score, extract_metric,
    gsd_interpretation,
    list_snapshots, load_latest_bundles, load_snapshot_bundles,
    score_higher_is_better,
)

DEFAULT_TRACES_DIR = Path(__file__).resolve().parent.parent.parent / 'run' / 'benchmark_traces'
ATTR_CHOICES = list(ATTR_LABELS.keys())


def _geomean(vals):
    v = [x for x in vals if x is not None and x > 0]
    return math.exp(sum(math.log(x) for x in v) / len(v)) if v else None


def _fmt_val(v, attr):
    if v is None:
        return '—'
    if attr == 'ipc':
        return f'{v:.3f}'
    if attr == 'branch_miss':
        return f'{v:.2f}%'
    if attr in ('text_size', 'total_size'):
        return f'{int(v):,}'
    return f'{v:.5g}'


def _fmt_delta(val, ref, hib):
    if val is None or ref is None or ref == 0:
        return ''
    pct  = (val - ref) / abs(ref) * 100
    sign = '+' if pct > 0 else ''
    if hib is True:
        arrow = '↑' if pct > 0 else '↓'
    elif hib is False:
        arrow = '↑' if pct < 0 else '↓'
    else:
        arrow = ''
    return f'{sign}{pct:.1f}% {arrow}'.strip()


def main():
    ap = argparse.ArgumentParser(
        description='Compare benchmark results across snapshots.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Attributes: {', '.join(ATTR_CHOICES)}

Examples (run from sim/rtl_sim/run/):
  ../bin/bench_compare                              # list snapshots
  ../bin/bench_compare snap_a                       # snap_a vs latest
  ../bin/bench_compare snap_a snap_b                # snap_a, snap_b, latest
  ../bin/bench_compare snap_a --attr ipc            # compare IPC
  ../bin/bench_compare snap_a --suite embench       # embench only — bottom row is
                                                    #   Speed Score (geomean of
                                                    #   baseline_ms/target_ms vs M4)
                                                    #   + GSD, per Embench spec
""",
    )
    ap.add_argument('snapshots', nargs='*', metavar='SNAPSHOT',
                    help='Snapshot names to compare (omit to list available)')
    ap.add_argument('--attr',  choices=ATTR_CHOICES, default='score',
                    metavar='ATTR',
                    help=f'Attribute ({", ".join(ATTR_CHOICES)}, default: score)')
    ap.add_argument('--suite', default=None,
                    help='Filter by suite prefix (embench, coremark, dhrystone…)')
    ap.add_argument('--dir',   default=str(DEFAULT_TRACES_DIR), metavar='DIR',
                    help='Traces directory (default: %(default)s)')
    args = ap.parse_args()

    traces_dir  = Path(args.dir)
    available   = list_snapshots(traces_dir)
    avail_names = {n for n, _ in available}

    # ── List mode ──────────────────────────────────────────────────────────────
    if not args.snapshots:
        if not available:
            print(f'No snapshots found in {traces_dir / "snapshots"}')
            print('Create one with:  bench_snapshot <name>')
        else:
            print(f'Available snapshot names:')
            for name, mf in available:
                if mf.get('_virtual'):
                    print(f'  {name:30s}  (embench reference platform, '
                          f'{mf["_n"]} benchmarks)')
                else:
                    n_bm   = len(mf.get('benchmarks', []))
                    ts     = mf.get('timestamp', '')
                    commit = mf.get('git', {}).get('commit', '')
                    desc   = mf.get('description', '')
                    print(f'  {name:30s}  {ts}  {commit:8s}  {n_bm:2d} benchmarks'
                          + (f'  {desc}' if desc else ''))
            print(f'\nUsage: bench_compare [snapshot…] '
                  f'[--attr {"| ".join(ATTR_CHOICES)}]')
        return

    # ── Validate snapshots ─────────────────────────────────────────────────────
    for sn in args.snapshots:
        if sn not in avail_names:
            sys.exit(f'error: snapshot "{sn}" not found')

    snap_root = traces_dir / 'snapshots'

    # ── Load data ──────────────────────────────────────────────────────────────
    columns = {}   # label → {test: bundle}
    for sn in args.snapshots:
        columns[sn] = load_snapshot_bundles(sn, snap_root / sn)
    columns['latest'] = load_latest_bundles(traces_dir)

    col_names = list(columns.keys())
    baseline  = col_names[0]

    # Collect benchmark names, apply suite filter
    all_tests = set()
    for bundles in columns.values():
        all_tests |= bundles.keys()
    if args.suite:
        all_tests = {t for t in all_tests if detect_suite(t) == args.suite}
    tests = sorted(all_tests)

    if not tests:
        print(f'No benchmarks found'
              + (f' for suite "{args.suite}"' if args.suite else ''))
        return

    # ── Determine higher-is-better ─────────────────────────────────────────────
    attr = args.attr
    hib  = ATTR_HIGHER_IS_BETTER.get(attr)
    if hib is None and attr == 'score':
        for bundles in columns.values():
            for b in bundles.values():
                hib = score_higher_is_better(b)
                if hib is not None:
                    break
            if hib is not None:
                break

    # Warn if mixing score units
    if attr == 'score':
        from .bench_utils import parse_score
        units = set()
        for bundles in columns.values():
            for b in bundles.values():
                _, u = parse_score(b.get('metadata', {})
                                    .get('benchmark', {})
                                    .get('Score', ''))
                if u:
                    units.add(u)
        if len(units) > 1:
            print(f'Warning: mixed score units ({", ".join(sorted(units))}) '
                  f'— filter with --suite to compare within one suite\n')

    # ── Render table ───────────────────────────────────────────────────────────
    BW = 32    # benchmark column
    CW = 14    # data columns
    DW = 18    # delta column

    header = f'{"Benchmark":<{BW}}'
    for c in col_names:
        header += f'  {c:>{CW}}'
    header += f'  {"Δ latest/"+baseline:>{DW}}'
    sep = '─' * len(header)

    print()
    print(header)
    print(sep)

    all_vals = {c: [] for c in col_names}

    for test in tests:
        row  = f'{test:<{BW}}'
        vals = {}
        for c, bundles in columns.items():
            v, _ = extract_metric(bundles.get(test), attr)
            vals[c] = v
            row += f'  {_fmt_val(v, attr):>{CW}}'
            if v is not None:
                all_vals[c].append(v)
        row += f'  {_fmt_delta(vals.get("latest"), vals.get(baseline), hib):>{DW}}'
        print(row)

    # Aggregation row(s).
    #
    # When ANY displayed test is Embench AND we're showing per-bench raw
    # scores (Time(ms)), replace the unitless "geomean of ms" row -- which is
    # mathematically valid but NOT the metric Embench publishes -- with the
    # canonical Speed Score: per-bench ratio R_b = baseline_ms / target_ms
    # against the M4 reference (speed.json), aggregated by geomean, with GSD
    # reported alongside so the reader knows whether the score is statistically
    # meaningful. By definition this is exactly 1.000 for M4-vs-M4 and >1
    # means faster than M4 per MHz.
    #
    # In mixed-suite views (embench + coremark + dhrystone displayed together)
    # the Speed Score still aggregates ONLY the embench rows; CoreMark/DMIPS
    # rate scores aren't ratio-able against an Embench Time(ms) baseline and
    # are silently skipped by embench_speed_score(). Non-embench-only views
    # (no embench rows at all, or non-score attributes) keep the legacy raw
    # geomean since there's no canonical normalization for those.
    print(sep)
    any_embench = bool(attr == 'score' and tests
                       and any(detect_suite(t) == 'embench' for t in tests))
    n_max = 0

    if any_embench:
        scores  = {c: embench_speed_score(columns[c]) for c in col_names}
        n_max   = max((sc[2] for sc in scores.values()), default=0)
        ss_hib  = True   # Geomean Score: higher = faster than M4
        ss_label  = f'— Geomean Score (vs M4, n={n_max}) —'
        gsd_label = '— Geomean Standard Deviation (vs M4) —'
        label_w   = max(BW, len(ss_label), len(gsd_label))
        ss_row    = f'{ss_label:<{label_w}}'
        gsd_row   = f'{gsd_label:<{label_w}}'
        # GSD-row Δ slot doubles as a plain-language interpretation hint:
        # the value isn't a comparison-against-baseline -- the latest column's
        # GSD lives on its own. Use the widest GSD across columns as the
        # signal source (most cautious interpretation wins).
        latest_gsd = scores.get('latest', (None, None, 0))[1]
        for c in col_names:
            ss, gsd, _n = scores[c]
            ss_row  += f'  {(f"{ss:.3f}"  if ss  is not None else "—"):>{CW}}'
            gsd_row += f'  {(f"{gsd:.3f}" if gsd is not None else "—"):>{CW}}'
        ss_row  += f'  {_fmt_delta(scores.get("latest", (None,))[0], scores.get(baseline, (None,))[0], ss_hib):>{DW}}'
        gsd_row += f'  {gsd_interpretation(latest_gsd):>{DW}}'
        print(ss_row)
        print(gsd_row)
    else:
        gm     = {c: _geomean(all_vals[c]) for c in col_names}
        gm_row = f'{"Geomean":<{BW}}'
        for c in col_names:
            gm_row += f'  {_fmt_val(gm[c], attr):>{CW}}'
        gm_row += f'  {_fmt_delta(gm.get("latest"), gm.get(baseline), hib):>{DW}}'
        print(gm_row)
    print()

    hib_str = ('higher is better' if hib is True
               else 'lower is better' if hib is False
               else 'no direction info')
    print(f'Attribute: {ATTR_LABELS[attr]}  ({hib_str})')
    if any_embench:
        print(f'Geomean Score = geomean(M4_baseline_ms / target_ms) over {n_max} '
              'Embench benchmarks (higher = faster than Cortex-M4).')
        print('Geomean Standard Deviation bands: ≤1.20 tight  |  ≤1.50 moderate  |  '
              '≤2.00 wide  |  >2.00 very wide.  Per Embench convention, GSD>1.30 '
              'means the per-benchmark detail is more informative than the geomean.')
    if hib is not None:
        print('↑ = improvement   ↓ = regression')
    print()


if __name__ == '__main__':
    main()
