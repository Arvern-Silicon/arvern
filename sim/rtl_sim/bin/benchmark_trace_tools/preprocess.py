#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    preprocess.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Pre-process raw trace data before downstream analysis.
#----------------------------------------------------------------------------

"""
Pre-compute arvern trace statistics and save to .stats.pkl cache files.

Run this once after saving new traces to make the Streamlit viewer load
instantly.  Re-run whenever new traces are added — only stale/new files
are reprocessed.

Usage (from sim/rtl_sim/run/):
    python3 -m benchmark_trace_tools.preprocess
    python3 -m benchmark_trace_tools.preprocess --dir ./benchmark_traces/latest
    python3 -m benchmark_trace_tools.preprocess --dir ~/arv_traces --force
    python3 -m benchmark_trace_tools.preprocess --dir ./benchmark_traces/latest --workers 4
"""

import argparse
import os
import pickle
import sys
import time

from . import parser as tp
from . import stats  as ts
from .bench_utils import precompute_metrics


# ── Cache filename convention ──────────────────────────────────────────────────

def cache_path(trace_path: str) -> str:
    """Return the .stats.pkl path for a given trace file."""
    return trace_path + '.stats.pkl'


def is_stale(trace_path: str) -> bool:
    """True if the cache does not exist or is older than the trace."""
    cp = cache_path(trace_path)
    if not os.path.exists(cp):
        return True
    return os.path.getmtime(trace_path) > os.path.getmtime(cp)


# ── Bundle computation ─────────────────────────────────────────────────────────

_STEPS = [
    ('Parsing trace',      None),      # special: handled separately
    ('Pipeline',           lambda td: ts.pipeline(td)),
    ('Instruction mix',    lambda td: ts.instmix(td)),
    ('Branches',           lambda td: ts.branches(td)),
    ('Jumps',              lambda td: ts.jumps(td)),
    ('Memory',             lambda td: ts.memory(td)),
    ('Registers',          lambda td: ts.registers(td)),
    ('Dependencies',       lambda td: ts.dependencies(td)),
    ('N-grams (2)',        lambda td: ts.ngrams(td, n=2, top_k=50)),
    ('N-grams (3)',        lambda td: ts.ngrams(td, n=3, top_k=50)),
    ('Immediates',         lambda td: ts.immediates(td)),
    ('Loops',              lambda td: ts.loops(td)),
    ('Hot code',           lambda td: ts.hotcode(td, top_k=200)),
    ('Branch prediction',  lambda td: ts.branch_prediction(td)),
    ('Fusion candidates',  None),      # special: uses ngrams2
    ('Metrics',            None),      # special: uses bundle
]


def compute_bundle(trace_path: str, progress=None) -> dict:
    """Parse a trace and compute all statistics.  Returns a stats bundle dict.

    Parameters
    ----------
    progress : callable, optional
        Called as progress(step_name) after each step completes.
    """
    def _tick(name):
        if progress:
            progress(name)

    td = tp.load(trace_path)
    df = td.df
    _tick('Parsing trace')

    bundle = {
        'path':           trace_path,
        'filename':       os.path.basename(trace_path),
        'mtime':          os.path.getmtime(trace_path),
        'metadata':       td.metadata,
        'n_instructions': len(df),
        'pc_nunique':     int(df['pc'].nunique()),
        'mnem_nunique':   int(df['mnem_base'].nunique()),
    }

    # Run each analysis step
    keys = [
        'pipeline', 'instmix', 'branches', 'jumps', 'memory',
        'registers', 'dependencies', 'ngrams2', 'ngrams3',
        'immediates', 'loops', 'hotcode', 'branch_prediction',
    ]
    for (step_name, fn), key in zip(_STEPS[1:14], keys):
        bundle[key] = fn(td)
        _tick(step_name)

    bundle['fusion_candidates'] = ts.fusion_candidates(bundle['ngrams2'])
    _tick('Fusion candidates')

    bundle['_metrics'] = precompute_metrics(bundle)
    _tick('Metrics')

    return bundle


# ── Per-file processing ────────────────────────────────────────────────────────

def process_one(trace_path: str, force: bool = False,
                verbose: bool = True, step_bar=None,
                progress_queue=None, worker_id: int = 0) -> bool:
    """Compute and cache stats for one trace.  Returns True if processed.

    Parameters
    ----------
    step_bar : tqdm bar, optional
        Nested progress bar to update after each analysis step (single-worker).
    progress_queue : multiprocessing.Queue, optional
        Queue to send (worker_id, step_index, step_name, filename) updates
        back to the main process (multi-worker).
    worker_id : int
        Worker identifier for progress_queue messages.
    """
    cp = cache_path(trace_path)
    fname = os.path.basename(trace_path)

    if not force and not is_stale(trace_path):
        if verbose:
            print(f'  skip   {fname}')
        if progress_queue is not None:
            progress_queue.put((worker_id, -1, 'skip', fname))
        return False

    t0 = time.time()
    try:
        step_idx = 0

        _sw = max(len(name) for name, _ in _STEPS)

        def _progress(step_name):
            nonlocal step_idx
            step_idx += 1
            if step_bar is not None:
                step_bar.set_description(f'  {step_name.ljust(_sw)}')
                step_bar.update(1)
            if progress_queue is not None:
                progress_queue.put((worker_id, step_idx, step_name, fname))

        if step_bar is not None:
            step_bar.reset(total=len(_STEPS))
            step_bar.set_description('  Starting')

        if progress_queue is not None:
            progress_queue.put((worker_id, 0, 'Starting', fname))

        bundle = compute_bundle(trace_path, progress=_progress)
        with open(cp, 'wb') as f:
            pickle.dump(bundle, f, protocol=5)
        elapsed = time.time() - t0
        size_kb = os.path.getsize(cp) / 1024
        if verbose:
            print(f'  done   {fname}  ({elapsed:.1f}s, cache {size_kb:.0f} KB)')
        if progress_queue is not None:
            progress_queue.put((worker_id, len(_STEPS), 'Done', fname))
        return True
    except Exception as e:
        print(f'  FAIL   {fname}: {e}', file=sys.stderr)
        if os.path.exists(cp):
            os.unlink(cp)
        if progress_queue is not None:
            progress_queue.put((worker_id, -2, f'FAIL: {e}', fname))
        return False


def _worker_fn(args_tuple):
    """Top-level worker function for multiprocessing (must be picklable)."""
    trace_path, force, progress_queue, worker_id = args_tuple
    return process_one(trace_path, force=force, verbose=False,
                       progress_queue=progress_queue, worker_id=worker_id)


# ── Directory scan ─────────────────────────────────────────────────────────────

def find_traces(directory: str) -> list:
    """Recursively find all .log and .log.zst trace files."""
    traces = []
    for root, _, files in os.walk(directory):
        for fname in sorted(files):
            if fname.endswith('.log.zst') or (fname.endswith('.log')
                                              and not fname.endswith('.stats.pkl')):
                traces.append(os.path.join(root, fname))
    return traces


# ── Summary ────────────────────────────────────────────────────────────────────

def _find_pkl_files(directory: str) -> list:
    """Recursively find all .stats.pkl files in a directory."""
    pkls = []
    for root, _, files in os.walk(directory):
        for fname in sorted(files):
            if fname.endswith('.stats.pkl'):
                pkls.append(os.path.join(root, fname))
    return pkls


def _bundle_to_row(bundle: dict, name: str) -> dict:
    """Extract summary row from a stats bundle."""
    pipe = bundle.get('pipeline', {})
    n_instr = pipe.get('total_instructions', bundle.get('n_instructions', 0))
    total_cyc = pipe.get('total_cycles', 0)
    ipc = pipe.get('ipc', 0)
    cpi = pipe.get('cpi', 0)
    stall_rate = pipe.get('stall_rate', 0)

    stalls_df = pipe.get('stalls_by_cause')
    if stalls_df is not None and not stalls_df.empty:
        top = stalls_df.loc[stalls_df['cycles'].idxmax()]
        top_stall = f"{top['cause']} ({top['pct']:.0f}%)"
    else:
        top_stall = '-'

    # Score from pre-computed metrics or metadata
    pm = bundle.get('_metrics', {})
    score_val = pm.get('score_value') if pm else None
    score_unit = pm.get('score_unit', '') if pm else ''
    if score_val is not None:
        score_str = f"{score_val:,.2f} {score_unit}".strip()
    else:
        score_str = '-'

    return {
        'name':       name,
        'instrs':     n_instr,
        'cycles':     total_cyc,
        'ipc':        ipc,
        'cpi':        cpi,
        'stall%':     stall_rate * 100,
        'top_stall':  top_stall,
        'score':      score_str,
    }


def _print_rows(rows: list):
    """Print a formatted summary table from a list of row dicts."""
    if not rows:
        return

    name_w  = max(len(r['name']) for r in rows)
    stall_w = max(len(r['top_stall']) for r in rows)
    score_w = max(len(r['score']) for r in rows)
    score_w = max(score_w, len('Score'))

    hdr = (f"  {'Trace':<{name_w}}  {'Score':>{score_w}}  {'Instrs':>10}  {'Cycles':>10}  "
           f"{'IPC':>6}  {'CPI':>6}  {'Stall%':>6}  {'Top stall cause':<{stall_w}}")
    sep = '  ' + '─' * (len(hdr) - 2)

    print(f'\n{sep}')
    print(hdr)
    print(sep)
    for r in sorted(rows, key=lambda x: x['name']):
        print(f"  {r['name']:<{name_w}}  {r['score']:>{score_w}}  {r['instrs']:>10,}  {r['cycles']:>10,}  "
              f"{r['ipc']:>6.3f}  {r['cpi']:>6.3f}  {r['stall%']:>5.1f}%  {r['top_stall']:<{stall_w}}")
    print(sep)


def _print_summary(traces: list):
    """Print summary table for trace files (looks up their .stats.pkl caches)."""
    rows = []
    for t in traces:
        cp = cache_path(t)
        if not os.path.exists(cp):
            continue
        try:
            with open(cp, 'rb') as f:
                bundle = pickle.load(f)
        except Exception:
            continue
        rows.append(_bundle_to_row(bundle, os.path.basename(t)))
    _print_rows(rows)


def _print_summary_from_pkl(pkl_files: list):
    """Print summary table directly from .stats.pkl files."""
    rows = []
    for cp in pkl_files:
        try:
            with open(cp, 'rb') as f:
                bundle = pickle.load(f)
        except Exception:
            continue
        # Derive a readable name: strip .stats.pkl (and .log.zst if present)
        name = os.path.basename(cp)
        for suffix in ('.stats.pkl', '.log.zst', '.log'):
            if name.endswith(suffix):
                name = name[:-len(suffix)]
        rows.append(_bundle_to_row(bundle, name))
    _print_rows(rows)


# ── Entry point ────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description='Pre-compute arvern trace statistics.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples (run from sim/rtl_sim/run/):
  python3 -m benchmark_trace_tools.preprocess
  python3 -m benchmark_trace_tools.preprocess --dir ./benchmark_traces/latest --workers 4
  python3 -m benchmark_trace_tools.preprocess --force
  python3 -m benchmark_trace_tools.preprocess --summary
  python3 -m benchmark_trace_tools.preprocess --summary --snap ref_std_O3
        """,
    )
    ap.add_argument('--dir',     default='../run/benchmark_traces/latest', metavar='DIR',
                    help='Directory to scan for traces (default: ../run/benchmark_traces/latest)')
    ap.add_argument('--force',   action='store_true',
                    help='Recompute even if cache is up to date')
    ap.add_argument('--workers', type=int, default=4, metavar='N',
                    help='Parallel workers for large trace sets (default: 4)')
    ap.add_argument('--summary', action='store_true',
                    help='Print summary table of cached traces and exit (no processing)')
    ap.add_argument('--snap',    default=None, metavar='NAME',
                    help='Snapshot name to use with --summary (e.g. ref_std_O3)')
    args = ap.parse_args()

    # --summary mode: just print the table and exit
    if args.summary:
        if args.snap:
            snap_dir = os.path.join(os.path.dirname(args.dir), 'snapshots', args.snap)
        else:
            snap_dir = args.dir
        pkl_files = _find_pkl_files(snap_dir)
        if not pkl_files:
            print(f'No cached stats found in {snap_dir}')
            return
        label = args.snap if args.snap else os.path.basename(os.path.realpath(snap_dir))
        print(f'Summary for: {label}  ({len(pkl_files)} traces)')
        _print_summary_from_pkl(pkl_files)
        return

    traces = find_traces(args.dir)
    if not traces:
        print(f'No trace files found in {args.dir}')
        return

    stale = [t for t in traces if is_stale(t)] if not args.force else traces
    print(f'Found {len(traces)} trace(s) in {args.dir} '
          f'({len(stale)} need processing)')

    if not stale and not args.force:
        print('All caches are up to date.')
        return

    # List files to be processed
    for t in stale:
        print(f'  → {os.path.basename(t)}')

    from tqdm import tqdm

    t_total = time.time()

    if args.workers > 1 and len(stale) > 2:
        import queue as queue_mod
        import multiprocessing as mp
        from concurrent.futures import ProcessPoolExecutor, as_completed

        progress_queue = mp.Manager().Queue()
        n_workers = min(args.workers, len(stale))
        n_steps = len(_STEPS)
        _STEP_WIDTH = max(len(name) for name, _ in _STEPS)

        # Global progress bar (position 0) + per-worker bars (positions 1..n)
        global_bar = tqdm(total=len(stale), unit='trace',
                          desc='Overall', position=0)
        worker_bars = {}
        for w in range(n_workers):
            worker_bars[w] = tqdm(
                total=n_steps, position=w + 1,
                bar_format=f'  W{w}: {{desc}}: {{bar}} {{n_fmt}}/{{total_fmt}}',
                desc='idle', leave=False,
            )

        def _drain_queue():
            """Drain all pending progress messages from the queue."""
            pad = lambda s: s.ljust(_STEP_WIDTH)
            while True:
                try:
                    wid, step_idx, step_name, fname = progress_queue.get_nowait()
                except queue_mod.Empty:
                    break
                short = fname[:50] + '…' if len(fname) > 50 else fname
                bar = worker_bars.get(wid)
                if bar is None:
                    continue
                if step_idx == 0:  # starting
                    bar.reset(total=n_steps)
                    bar.set_description(f'{pad(step_name)} {short}')
                elif step_idx > 0 and step_idx < n_steps:
                    bar.set_description(f'{pad(step_name)} {short}')
                    if step_idx > bar.n:
                        bar.update(step_idx - bar.n)

        # Submit only stale/forced traces, round-robin worker IDs
        work_items = [(t, args.force, progress_queue, i % n_workers)
                      for i, t in enumerate(stale)]

        n_done = 0
        with ProcessPoolExecutor(max_workers=n_workers) as ex:
            futures = {ex.submit(_worker_fn, item): item for item in work_items}

            for fut in as_completed(futures):
                _drain_queue()
                result = fut.result()
                n_done += result
                # Update the worker bar to show completion
                _, _, _, wid = futures[fut]
                bar = worker_bars.get(wid)
                short = os.path.basename(futures[fut][0])
                short = short[:50] + '…' if len(short) > 50 else short
                pad = lambda s: s.ljust(_STEP_WIDTH)
                if bar is not None:
                    if result:
                        bar.update(n_steps - bar.n)
                        bar.set_description(f'{pad("done")} {short}')
                    else:
                        bar.reset(total=n_steps)
                        bar.set_description(f'{pad("skip")} {short}')
                global_bar.update(1)

        _drain_queue()  # final drain
        for bar in worker_bars.values():
            bar.close()
        global_bar.close()
    else:
        n_done = 0
        file_bar = tqdm(stale, unit='trace', desc='Processing', position=0)
        step_bar = tqdm(total=len(_STEPS), desc='  Starting', position=1,
                        bar_format='  {desc}: {bar} {n_fmt}/{total_fmt}',
                        leave=False)
        for t in file_bar:
            file_bar.set_postfix_str(os.path.basename(t), refresh=True)
            result = process_one(t, force=args.force, verbose=False,
                                 step_bar=step_bar)
            n_done += result
        step_bar.close()
        file_bar.close()

    n_skip = len(traces) - len(stale)
    elapsed = time.time() - t_total
    print(f'\nDone: {n_done} processed, {n_skip} up-to-date  ({elapsed:.1f}s total)')

    # Print summary table of processed traces
    if n_done:
        _print_summary(stale)


if __name__ == '__main__':
    main()
