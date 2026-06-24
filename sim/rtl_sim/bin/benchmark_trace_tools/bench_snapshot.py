#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    bench_snapshot.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Capture a benchmark trace snapshot for later regression comparison.
#----------------------------------------------------------------------------

"""bench_snapshot — Save, update, or list named snapshots of trace statistics.

Usage (from sim/rtl_sim/run/):
    ../bin/bench_snapshot                          # list existing snapshots
    ../bin/bench_snapshot <name>
    ../bin/bench_snapshot before_branch_pred --desc "Before branch predictor"
    ../bin/bench_snapshot v1 --dir ./benchmark_traces --force
    ../bin/bench_snapshot v1 --update              # update existing snapshot
"""

import argparse
import json
import pickle
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from .bench_utils import list_snapshots
from .save_trace import _RTL_DESC, _RTL_ORDER, read_march_info, read_toolchain_version

DEFAULT_TRACES_DIR = Path(__file__).resolve().parent.parent.parent / 'run' / 'benchmark_traces'


def _read_arv_params(path: str = './arv_parameterization.v') -> dict:
    """Parse arv_parameterization.v and return {PARAM: <translated value or int>}.

    Values are translated through save_trace._RTL_DESC when a mapping exists,
    otherwise the raw integer / hex string is returned. Used to backfill any
    RTL fields the pickle metadata doesn't already carry.
    """
    out = {}
    try:
        with open(path) as f:
            for line in f:
                m = re.match(r'\s*parameter\s+(\w+)\s*=\s*(?:32\'h([0-9A-Fa-f]+)|(\d+))', line)
                if not m:
                    continue
                name = m.group(1)
                if m.group(2) is not None:                       # hex literal (e.g. MVENDORID)
                    out[name] = f"0x{m.group(2).upper()}"
                else:
                    val = int(m.group(3))
                    desc = _RTL_DESC.get(name, {})
                    out[name] = desc.get(val, val)
    except FileNotFoundError:
        pass
    return out


def _toolchain_block(march_info: dict, tc_version: str) -> dict:
    """Compact toolchain dict for the manifest."""
    return {
        'version':      tc_version,
        'march_std':    march_info.get('MARCH_STD',  ''),
        'march_comp':   march_info.get('MARCH_COMP', ''),
        'mabi':         march_info.get('MABI',       ''),
        'optimization': march_info.get('TC_OPT',     ''),
        'profile':      march_info.get('CROSS',      '').rstrip('-').split('/')[-1] if march_info.get('CROSS') else '',
    }


def _infer_persona(name: str) -> str:
    """Best-effort: 'classic_scb1_O3_xpacks' -> 'classic'. Empty if no match."""
    for persona in ('light', 'classic', 'performance', 'ultra'):
        if name.lower().startswith(persona + '_') or name.lower() == persona:
            return persona
    return ''


def _git_info() -> dict:
    info = {}
    try:
        info['commit'] = subprocess.check_output(
            ['git', 'rev-parse', '--short', 'HEAD'],
            stderr=subprocess.DEVNULL, text=True).strip()
        info['branch'] = subprocess.check_output(
            ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
            stderr=subprocess.DEVNULL, text=True).strip()
        info['message'] = subprocess.check_output(
            ['git', 'log', '-1', '--pretty=%s'],
            stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        pass
    return info


def _latest_per_test(traces_dir: Path) -> dict:
    """Return {test_name: pkl_path} keeping the most recent pkl per test."""
    latest = {}   # test -> (mtime, path)
    for pkl in sorted((traces_dir / 'latest').glob('*.stats.pkl')):
        try:
            with open(pkl, 'rb') as f:
                b = pickle.load(f)
            test  = b.get('metadata', {}).get('Test', '')
            mtime = b.get('mtime', 0)
            if test and (test not in latest or mtime > latest[test][0]):
                latest[test] = (mtime, pkl)
        except Exception as e:
            print(f'  warning: {pkl.name}: {e}', file=sys.stderr)
    return {t: p for t, (_, p) in latest.items()}


def _update_snapshot(snap_dir: Path, traces_dir: Path, yes: bool = False):
    """Update an existing snapshot with newer files from the traces directory."""
    if not snap_dir.is_dir():
        sys.exit(f'error: snapshot not found: {snap_dir}')

    # Collect current snapshot pkl files
    snap_pkls = {p.name: p for p in snap_dir.glob('*.stats.pkl')}
    if not snap_pkls:
        sys.exit(f'error: no .stats.pkl files in snapshot: {snap_dir}')

    # Find matching files in traces/latest directory with newer mtime
    updates = []   # list of (filename, snap_path, traces_path)
    latest_dir = traces_dir / 'latest'
    for name, snap_pkl in sorted(snap_pkls.items()):
        traces_pkl = latest_dir / name
        if not traces_pkl.exists():
            continue
        if traces_pkl.stat().st_mtime > snap_pkl.stat().st_mtime:
            updates.append((name, snap_pkl, traces_pkl))

    if not updates:
        print(f'Snapshot "{snap_dir.name}" is up to date — no newer files found.')
        return

    # Show what would be updated
    print(f'Found {len(updates)} file(s) to update in snapshot '
          f'"{snap_dir.name}":\n')
    for name, snap_pkl, traces_pkl in updates:
        snap_time   = datetime.fromtimestamp(snap_pkl.stat().st_mtime)
        traces_time = datetime.fromtimestamp(traces_pkl.stat().st_mtime)
        print(f'  {name}')
        print(f'    snapshot: {snap_time:%Y-%m-%d %H:%M:%S}')
        print(f'    traces:   {traces_time:%Y-%m-%d %H:%M:%S}')

    # Ask for confirmation
    if not yes:
        print()
        answer = input('Proceed with update? [y/N] ').strip().lower()
        if answer not in ('y', 'yes'):
            print('Aborted.')
            return

    # Perform the update
    print()
    for name, _snap_pkl, traces_pkl in updates:
        shutil.copy2(traces_pkl, snap_dir / name)
        print(f'  updated {name}')

    # Update manifest timestamp
    manifest_path = snap_dir / 'manifest.json'
    if manifest_path.exists():
        try:
            with open(manifest_path) as f:
                manifest = json.load(f)
        except Exception:
            manifest = {}
    else:
        manifest = {}
    manifest['updated'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    manifest['git']     = _git_info()
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f'\nSnapshot "{snap_dir.name}" updated ({len(updates)} file(s)).')


def main():
    ap = argparse.ArgumentParser(
        description='Save, update, or list named snapshots of trace statistics.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
How it works:
  Snapshots capture pre-computed trace statistics (.stats.pkl files) from
  benchmark_traces/latest/ into a named directory under benchmark_traces/snapshots/.

  When creating a snapshot, if multiple PKL files exist for the same test
  (e.g. coremark run at different times or with different configs), only the
  most recent one is kept (based on the trace file modification time stored
  inside the PKL metadata). So 155 PKL files covering 25 distinct tests
  will produce a snapshot with 25 files.

  Snapshots are lightweight — only PKL files and a manifest.json are stored,
  not the raw trace logs. Git commit, branch, and message are captured
  automatically for traceability.

  Use --update to refresh an existing snapshot with newer files from latest/
  without recreating it from scratch.

Modes:
  (no name)          List existing snapshots
  <name>             Create a new snapshot from latest/
  <name> --update    Update an existing snapshot with newer files

Examples (run from sim/rtl_sim/run/):
  ./benchmark_trace_snapshot                            # list snapshots
  ./benchmark_trace_snapshot before_branch_pred
  ./benchmark_trace_snapshot after_split_cache --desc "After split I/D cache"
  ./benchmark_trace_snapshot v1 --force                 # overwrite existing
  ./benchmark_trace_snapshot v1 --update                # refresh with newer files
  ./benchmark_trace_snapshot v1 --update -y             # skip confirmation
""",
    )
    ap.add_argument('name',     nargs='?', default=None,
                    help='Snapshot name (omit to list existing snapshots)')
    ap.add_argument('--desc',   default='', metavar='TEXT',
                    help='Human-readable description')
    ap.add_argument('--persona', default='', metavar='NAME',
                    help='Persona tag (light/classic/performance/ultra) — '
                         'inferred from the snapshot name if not provided')
    ap.add_argument('--dir',    default=str(DEFAULT_TRACES_DIR), metavar='DIR',
                    help='Traces directory (default: %(default)s)')
    ap.add_argument('--force',  action='store_true',
                    help='Overwrite existing snapshot')
    ap.add_argument('--update', action='store_true',
                    help='Update existing snapshot with newer files from traces')
    ap.add_argument('-y', '--yes', action='store_true',
                    help='Skip confirmation prompt (for --update)')
    args = ap.parse_args()

    traces_dir = Path(args.dir)
    if not traces_dir.is_dir():
        sys.exit(f'error: traces directory not found: {traces_dir}')

    # ── List mode (no name given) ─────────────────────────────────────────────
    if args.name is None:
        snapshots = list_snapshots(traces_dir)
        # Filter out virtual entries (e.g. embench baseline)
        snapshots = [(n, m) for n, m in snapshots if not m.get('_virtual')]
        if not snapshots:
            print('No snapshots found.')
            return
        print(f'Snapshots in {traces_dir / "snapshots"}:\n')
        for name, manifest in snapshots:
            desc = manifest.get('description', '')
            ts   = manifest.get('timestamp', '')
            n_bm = len(manifest.get('benchmarks', []))
            line = f'  {name:<24s}'
            if n_bm:
                line += f'  ({n_bm} benchmarks)'
            if ts:
                line += f'  [{ts}]'
            if desc:
                line += f'  {desc}'
            print(line)
        print()
        ap.print_usage()
        return

    snap_dir = traces_dir / 'snapshots' / args.name

    # ── Update mode ───────────────────────────────────────────────────────────
    if args.update:
        _update_snapshot(snap_dir, traces_dir, yes=args.yes)
        return

    # ── Create mode ───────────────────────────────────────────────────────────
    if snap_dir.exists() and not args.force:
        sys.exit(
            f'error: snapshot "{args.name}" already exists '
            f'(use --force to overwrite, or --update to refresh)')

    selected = _latest_per_test(traces_dir)
    if not selected:
        sys.exit(f'error: no .stats.pkl files found in {traces_dir / "latest"}')

    snap_dir.mkdir(parents=True, exist_ok=True)

    # Copy pkl files and collect RTL config from the first one
    print(f'Creating snapshot "{args.name}" ({len(selected)} benchmarks)')
    rtl_config = {}
    for test, src in sorted(selected.items()):
        shutil.copy2(src, snap_dir / src.name)
        print(f'  {test}')
        if not rtl_config:
            try:
                with open(src, 'rb') as f:
                    rtl_config = pickle.load(f).get('metadata', {}).get('rtl', {})
            except Exception:
                pass

    # Backfill any RTL fields the pickle metadata didn't carry by parsing
    # arv_parameterization.v (the source of truth for this run). Pickle values
    # win where present so we don't clobber existing translations.
    full_rtl = _read_arv_params()
    for k, v in full_rtl.items():
        rtl_config.setdefault(k, v)
    # Reorder rtl_config to match _RTL_ORDER for stable JSON output.
    ordered_rtl = {k: rtl_config[k] for k in _RTL_ORDER if k in rtl_config}
    for k, v in rtl_config.items():                              # any extra keys (forward-compat)
        ordered_rtl.setdefault(k, v)

    # Read toolchain context (compiler version + -march/-mabi/-O level).
    march_info = read_march_info()
    tc_version = read_toolchain_version(march_info)
    toolchain  = _toolchain_block(march_info, tc_version)

    # Write manifest
    git  = _git_info()
    persona = getattr(args, 'persona', '') or _infer_persona(args.name)
    manifest = {
        'name':        args.name,
        'persona':     persona,
        'description': args.desc,
        'timestamp':   datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'git':         git,
        'rtl':         ordered_rtl,
        'toolchain':   toolchain,
        'benchmarks':  sorted(selected.keys()),
    }
    with open(snap_dir / 'manifest.json', 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f'\nSnapshot saved: {snap_dir}')
    if args.desc:
        print(f'Description:    {args.desc}')
    if git.get('commit'):
        print(f'Git:            {git["branch"]}@{git["commit"]}  '
              f'{git.get("message", "")}')


if __name__ == '__main__':
    main()
