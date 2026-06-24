#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    app.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Streamlit entry point for the arvern benchmark trace viewer.
#----------------------------------------------------------------------------

"""
arvern Trace Viewer — Streamlit entry point.

Launch with:
    streamlit run app.py
or from the bin directory:
    streamlit run trace_viewer/app.py

Traces are discovered automatically from a configurable directory.
Run preprocess_traces.py first to build .stats.pkl caches for instant loading.
"""

import os
import re
import sys
import pickle
from typing import Optional

# Allow importing benchmark_trace_tools as a package
_BIN = os.path.join(os.path.dirname(__file__), '..', '..')
sys.path.insert(0, _BIN)

import streamlit as st

# ── Page config ────────────────────────────────────────────────────────────────
st.set_page_config(
    page_title='arvern Trace Viewer',
    page_icon='🔍',
    layout='wide',
    initial_sidebar_state='expanded',
)

from benchmark_trace_tools import parser as tp
from benchmark_trace_tools import stats  as ts
from benchmark_trace_tools.bench_utils import precompute_metrics

from views import overview, pipeline, instmix, branches, memory, registers
from views import hotcode, dependencies, ngrams, loops, compare, branch_pred
from views import snapshot_compare


# ── Filename parser ────────────────────────────────────────────────────────────

def _parse_trace(path: str):
    """Parse a trace filepath into structured components, or None on failure.

    Expected filename pattern:
        trace_{benchmark}_{mode}_{m#_c#_b#_mul#_div#}_{toolchain}_{opt}_{timing}_{date}_{time}
    """
    fname = os.path.basename(path)
    for sfx in ('.log.zst', '.log'):
        if fname.endswith(sfx):
            fname = fname[:-len(sfx)]
            break
    if not fname.startswith('trace_'):
        return None
    name = fname[len('trace_'):]

    # RTL config block: m{n}_c{n}_b{n}_mul{n}_div{n}
    m = re.search(r'(m\d+_c\d+_b\d+_mul\d+_div\d+)', name)
    if not m:
        return None

    rtl    = m.group(1)
    before = name[:m.start()].rstrip('_')
    after  = name[m.end():].lstrip('_')

    # before = "{benchmark}_{mode}"  (mode is the last token: comp or std)
    toks = before.rsplit('_', 1)
    if len(toks) == 2 and toks[1] in ('comp', 'std'):
        benchmark, mode = toks
    else:
        benchmark, mode = before, '?'

    # after = "{toolchain}_{opt}_{timing}_{date}_{time}"
    ta        = after.split('_')
    opt       = ta[1] if len(ta) > 1 else ''
    timing    = ta[2] if len(ta) > 2 else ''
    raw_date  = ta[3] if len(ta) > 3 else ''
    raw_time  = ta[4] if len(ta) > 4 else ''

    date_fmt = (f'{raw_date[:4]}-{raw_date[4:6]}-{raw_date[6:]}'
                if len(raw_date) == 8 else raw_date)
    time_fmt = (f'{raw_time[:2]}:{raw_time[2:4]}'
                if len(raw_time) >= 4 else raw_time)
    dt = f'{date_fmt} {time_fmt}'.strip()

    cached = os.path.exists(path + '.stats.pkl')

    return {
        'benchmark':   benchmark,
        'mode':        mode,
        'rtl':         rtl,
        'opt':         opt,
        'timing':      timing,
        'datetime':    dt,
        'short_label': f'{timing} — {dt}' if timing else dt,
        'cached':      cached,
    }


# ── Cascading trace selector ───────────────────────────────────────────────────

def _trace_selector(traces: list, prefix: str) -> Optional[str]:
    """Cascading sidebar selector. Returns selected path or None.

    Filters: Benchmark → Mode → Extensions → Optimization → final trace.
    Steps with a single option are shown as a caption (no dropdown noise).
    """
    if not traces:
        return None

    # Parse all traces; unparseable ones go into a fallback flat list
    parsed  = []
    fallback = []
    for _lbl, path in traces:
        info = _parse_trace(path)
        if info:
            parsed.append((path, info))
        else:
            fallback.append((_lbl, path))

    if not parsed:
        # No structured names — use plain selectbox
        labels = [lbl for lbl, _ in fallback]
        paths  = {lbl: p for lbl, p in fallback}
        sel    = st.sidebar.selectbox('Trace', labels, key=f'{prefix}_fallback')
        return paths.get(sel)

    # ── Step 1: Benchmark ──────────────────────────────────────────────────────
    benchmarks = sorted({p[1]['benchmark'] for p in parsed})
    if len(benchmarks) > 1:
        bench = st.sidebar.selectbox('Benchmark', benchmarks, key=f'{prefix}_bench')
    else:
        bench = benchmarks[0]
        st.sidebar.caption(f'Benchmark: **{bench}**')
    pool = [p for p in parsed if p[1]['benchmark'] == bench]

    # ── Step 2: Mode (comp / std) ──────────────────────────────────────────────
    modes = sorted({p[1]['mode'] for p in pool})
    if len(modes) > 1:
        mode = st.sidebar.selectbox('Mode', modes, key=f'{prefix}_mode')
        pool = [p for p in pool if p[1]['mode'] == mode]
    else:
        st.sidebar.caption(f'Mode: **{modes[0]}**')

    # ── Step 3: Extensions (Z* / RTL config) ──────────────────────────────────
    rtls = sorted({p[1]['rtl'] for p in pool})
    if len(rtls) > 1:
        rtl  = st.sidebar.selectbox('Extensions', rtls, key=f'{prefix}_rtl')
        pool = [p for p in pool if p[1]['rtl'] == rtl]
    else:
        st.sidebar.caption(f'Ext: **{rtls[0]}**')

    # ── Step 4: Optimization ───────────────────────────────────────────────────
    opts = sorted({p[1]['opt'] for p in pool})
    if len(opts) > 1:
        opt  = st.sidebar.selectbox('Optimization', opts, key=f'{prefix}_opt')
        pool = [p for p in pool if p[1]['opt'] == opt]
    else:
        st.sidebar.caption(f'Opt: **{opts[0]}**')

    if not pool:
        st.sidebar.warning('No matching traces.')
        return None

    # ── Step 5: Final trace (timing + datetime) ────────────────────────────────
    if len(pool) == 1:
        info  = pool[0][1]
        label = info['short_label'] + (' ✓' if info['cached'] else ' ⚠ no cache')
        st.sidebar.caption(f'→ {label}')
        return pool[0][0]

    final_labels = [
        p[1]['short_label'] + (' ✓' if p[1]['cached'] else ' ⚠') for p in pool
    ]
    paths_map = {lbl: p[0] for lbl, p in zip(final_labels, pool)}
    sel = st.sidebar.selectbox('Trace', final_labels, key=f'{prefix}_final')
    return paths_map.get(sel)


# ── Bundle loading ─────────────────────────────────────────────────────────────

def _compute_bundle(trace_path: str) -> dict:
    """Compute a full stats bundle from a trace file (no cache)."""
    td = tp.load(trace_path)
    df = td.df
    bundle = {
        'path':           trace_path,
        'filename':       os.path.basename(trace_path),
        'mtime':          os.path.getmtime(trace_path),
        'metadata':       td.metadata,
        'n_instructions': len(df),
        'pc_nunique':     int(df['pc'].nunique()),
        'mnem_nunique':   int(df['mnem_base'].nunique()),
        'pipeline':       ts.pipeline(td),
        'instmix':        ts.instmix(td),
        'branches':       ts.branches(td),
        'jumps':          ts.jumps(td),
        'memory':         ts.memory(td),
        'registers':      ts.registers(td),
        'dependencies':   ts.dependencies(td),
        'ngrams2':           ts.ngrams(td, n=2, top_k=50),
        'ngrams3':           ts.ngrams(td, n=3, top_k=50),
        'fusion_candidates': None,  # populated below
        'immediates':        ts.immediates(td),
        'loops':             ts.loops(td),
        'hotcode':           ts.hotcode(td, top_k=200),
        'branch_prediction': ts.branch_prediction(td),
    }
    bundle['fusion_candidates'] = ts.fusion_candidates(bundle['ngrams2'])
    bundle['_metrics'] = precompute_metrics(bundle)
    return bundle


@st.cache_data(show_spinner='Loading trace stats…')
def load_bundle(trace_path: str) -> dict:
    """Load a stats bundle from cache (.stats.pkl) or compute on-the-fly."""
    cp = trace_path + '.stats.pkl'
    if os.path.exists(cp):
        cache_mtime = os.path.getmtime(cp)
        trace_mtime = os.path.getmtime(trace_path)
        if cache_mtime >= trace_mtime:
            with open(cp, 'rb') as f:
                return pickle.load(f)
    return _compute_bundle(trace_path)


# ── Trace discovery ────────────────────────────────────────────────────────────

@st.cache_data(ttl=30)
def discover_traces(directory: str) -> list:
    """Return sorted list of (display_label, full_path) for all traces found."""
    latest = os.path.join(directory, 'latest')
    if not os.path.isdir(latest):
        return []
    results = []
    for root, _, files in os.walk(latest):
        for fname in sorted(files):
            if fname.endswith('.log.zst') or (
                    fname.endswith('.log') and not fname.endswith('.stats.pkl')):
                full = os.path.join(root, fname)
                label = os.path.basename(full)
                results.append((label, full))
    return results


# ── Sidebar ────────────────────────────────────────────────────────────────────

st.sidebar.title('arvern Trace Viewer')
st.sidebar.markdown('---')

# Traces directory (shared by both modes)
default_dir = os.path.normpath(os.path.join(_BIN, '..', 'run', 'benchmark_traces'))
traces_dir = st.sidebar.text_input('Traces directory', value=default_dir,
                                    key='traces_dir')

st.sidebar.markdown('---')

# ── Top-level mode selector ────────────────────────────────────────────────────
MODE_SNAPSHOT = 'Snapshot Compare'
MODE_TRACE    = 'Latest Trace Analysis'
MODE_COMPARE  = 'Latest Trace Compare'

mode = st.sidebar.radio('Mode', [MODE_SNAPSHOT, MODE_TRACE, MODE_COMPARE], key='mode')

st.sidebar.markdown('---')

# ── Snapshot Compare mode ──────────────────────────────────────────────────────
if mode == MODE_SNAPSHOT:
    with st.sidebar.expander('Preprocessing'):
        st.caption(
            'Run `preprocess_traces.py` to pre-build caches:\n\n'
            '```\npython3 -m benchmark_trace_tools.preprocess --dir ./benchmark_traces/latest\n```'
        )
        if st.button('Refresh', key='refresh_snap'):
            discover_traces.clear()
            st.rerun()

    snapshot_compare.render(traces_dir)
    st.stop()

# ── Shared: discover traces & preprocessing helper ────────────────────────────
traces = discover_traces(traces_dir)

if not traces:
    st.sidebar.warning('No traces found. Check directory.')

# Preprocessing helper
with st.sidebar.expander('Preprocessing'):
    st.caption(
        'Run `preprocess_traces.py` to pre-build caches for instant loading:\n\n'
        '```\npython3 -m benchmark_trace_tools.preprocess --dir ./benchmark_traces/latest\n```\n\n'
        'Traces marked ✓ already have a cache.'
    )
    if st.button('Refresh trace list', key='refresh_trace'):
        discover_traces.clear()
        st.rerun()

st.sidebar.markdown('---')

# ── No-bundle landing page ────────────────────────────────────────────────────
def _show_landing(title):
    st.title(f'arvern Trace Viewer — {title}')
    st.info(
        'Select a trace from the sidebar to get started.\n\n'
        'Run `preprocess_traces.py` once to build caches for instant loading.'
    )
    if traces:
        import pandas as pd
        st.subheader(f'Found {len(traces)} trace(s) in `{traces_dir}`')
        rows = []
        for _lbl, path in traces:
            info   = _parse_trace(path)
            cached = os.path.exists(path + '.stats.pkl')
            sz_kb  = os.path.getsize(path) / 1024
            if info:
                rows.append({
                    'benchmark':  info['benchmark'],
                    'mode':       info['mode'],
                    'extensions': info['rtl'],
                    'opt':        info['opt'],
                    'datetime':   info['datetime'],
                    'cached':     '✓' if cached else '—',
                    'size_kb':    f'{sz_kb:.0f}',
                })
            else:
                rows.append({
                    'benchmark':  os.path.basename(path),
                    'mode': '', 'extensions': '', 'opt': '', 'datetime': '',
                    'cached': '✓' if cached else '—',
                    'size_kb': f'{sz_kb:.0f}',
                })
        st.dataframe(pd.DataFrame(rows), width='stretch', hide_index=True)

# ── Latest Trace Compare mode ─────────────────────────────────────────────────
if mode == MODE_COMPARE:
    bundle_a = bundle_b = None

    st.sidebar.subheader(f'Trace A  ({len(traces)} available)')
    path_a = _trace_selector(traces, prefix='a')
    if path_a:
        with st.spinner('Loading trace A…'):
            bundle_a = load_bundle(path_a)

    st.sidebar.markdown('---')

    st.sidebar.subheader('Trace B')
    path_b = _trace_selector(traces, prefix='b')
    if path_b:
        with st.spinner('Loading trace B…'):
            bundle_b = load_bundle(path_b)

    if bundle_a is None or bundle_b is None:
        _show_landing('Latest Trace Compare')
        if bundle_a is None and bundle_b is None:
            st.warning('Select Trace A and Trace B from the sidebar.')
        elif bundle_a is None:
            st.warning('Select Trace A from the sidebar.')
        else:
            st.warning('Select Trace B from the sidebar.')
        st.stop()

    compare.render(bundle_a, bundle_b)
    st.stop()

# ── Latest Trace Analysis mode ────────────────────────────────────────────────
bundle_a = None

st.sidebar.subheader(f'Trace  ({len(traces)} available)')
path_a = _trace_selector(traces, prefix='a')
if path_a:
    with st.spinner('Loading trace…'):
        bundle_a = load_bundle(path_a)

if bundle_a is None:
    _show_landing('Latest Trace Analysis')
    st.stop()

# ── View tabs ─────────────────────────────────────────────────────────────────
TRACE_VIEWS = [
    'Overview',
    'Pipeline',
    'Inst Mix',
    'Branches',
    'Branch Pred',
    'Memory',
    'Registers',
    'Hot Code',
    'Dependencies',
    'N-grams',
    'Loops',
]
tabs = st.tabs(TRACE_VIEWS)

with tabs[0]:
    overview.render(bundle_a)
with tabs[1]:
    pipeline.render(bundle_a)
with tabs[2]:
    instmix.render(bundle_a)
with tabs[3]:
    branches.render(bundle_a)
with tabs[4]:
    branch_pred.render(bundle_a)
with tabs[5]:
    memory.render(bundle_a)
with tabs[6]:
    registers.render(bundle_a)
with tabs[7]:
    hotcode.render(bundle_a)
with tabs[8]:
    dependencies.render(bundle_a)
with tabs[9]:
    ngrams.render(bundle_a)
with tabs[10]:
    loops.render(bundle_a)
