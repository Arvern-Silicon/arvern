#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    snapshot_compare.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: compare against a stored snapshot.
#----------------------------------------------------------------------------

"""Snapshot Compare view — compare benchmark metrics across named snapshots."""

import math

import numpy as np
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
import streamlit as st

from benchmark_trace_tools.bench_utils import (
    ATTR_LABELS, ATTR_HIGHER_IS_BETTER,
    detect_suite, extract_metric, geomean_ratio,
    gsd_interpretation,
    list_snapshots, load_latest_bundles, load_snapshot_bundles,
    score_higher_is_better,
)

from pathlib import Path

_LATEST = 'latest'

# Padding / border CSS for the HTML-rendered Snapshot Compare table -- pandas
# Styler's default to_html() output is bare, so without this the table looks
# noticeably plainer than the surrounding st.dataframe tabs. Scoped to a
# class only Snapshot Compare emits (`arv-snapcmp`) so it can't leak into any
# other view's tables.
_TABLE_BASE_CSS = """
<style>
.arv-snapcmp table { border-collapse: collapse; font-size: 0.92rem; }
.arv-snapcmp th, .arv-snapcmp td { padding: 6px 12px; border-bottom: 1px solid rgba(128,128,128,0.18); white-space: nowrap; }
.arv-snapcmp th { text-align: left; font-weight: 600; background-color: rgba(128,128,128,0.08); }
.arv-snapcmp tr:hover td { background-color: rgba(128,128,128,0.06); }
</style>
"""


def _copyable_table(df, label: str = 'Copy as text'):
    """Show a dataframe as plain text inside an expander for easy copy-paste."""
    with st.expander(label):
        st.code(df.to_string(index=False), language=None)


# ── Cached loaders ─────────────────────────────────────────────────────────────

@st.cache_data(ttl=60, show_spinner='Loading snapshot…')
def _load_snapshot(snap_name: str, snap_dir_str: str) -> dict:
    return load_snapshot_bundles(snap_name, Path(snap_dir_str))


@st.cache_data(ttl=30, show_spinner='Loading latest traces…')
def _load_latest(traces_dir_str: str) -> dict:
    return load_latest_bundles(Path(traces_dir_str))


# ── Helpers ────────────────────────────────────────────────────────────────────

def _geomean(vals):
    v = [x for x in vals if x is not None and x > 0]
    return math.exp(sum(math.log(x) for x in v) / len(v)) if v else None


def _target_ipc(bundle):
    """Target column's IPC for one bench (None if bundle/data missing)."""
    if bundle is None:
        return None
    return bundle.get('pipeline', {}).get('ipc')


def _top_stall_cause(bundle):
    """Highest-cycles stall cause for one bench as 'Cause (pct%)'.

    Returns '' when the bundle has no `pipeline.stalls_by_cause` (e.g. the
    virtual `embench_baseline` M4 bundle, which carries only published ms
    numbers), or when every recorded cause has zero cycles (synthetic /
    unstall-able trace).
    """
    if bundle is None:
        return ''
    sbc = bundle.get('pipeline', {}).get('stalls_by_cause')
    if sbc is None or not hasattr(sbc, 'iloc') or sbc.empty:
        return ''
    top = sbc.loc[sbc['cycles'].idxmax()]
    if top['cycles'] <= 0:
        return ''
    return f"{top['cause']} ({top['pct']:.0f}%)"


def _gsd(vals):
    """Geometric Standard Deviation of a list of positive values.

    Same formula as Embench's `compute_geosd()` and the ratio-based version
    in `bench_utils.embench_speed_score()`, but applied to raw values rather
    than to M4-anchored ratios. Used for the per-column "Standard Deviation"
    cell in the snapshot-compare table: it's a scale-free spread measure
    (multiplicative factor), independent of unit, so e.g. a column of bench
    ms values yields a number that says "typical bench runtime lands within
    [GM/GSD, GM*GSD]" — directly comparable across columns even when their
    geomeans differ by an order of magnitude.
    """
    v = [x for x in vals if x is not None and x > 0]
    n = len(v)
    if n < 2:
        return None
    gm = math.exp(sum(math.log(x) for x in v) / n)
    lnsize = sum(math.log(x / gm) ** 2 for x in v)
    return math.exp(math.sqrt(lnsize / n))


def _fmt_val(v, attr):
    if v is None:
        return '—'
    if attr == 'ipc':
        return f'{v:.3f}'
    if attr == 'branch_miss':
        return f'{v:.2f}'
    if attr in ('text_size', 'total_size'):
        return f'{int(v):,}'
    return f'{v:.5g}'


def _delta_str(val, ref, hib):
    """Return formatted delta string with arrow, or '—'."""
    if val is None or ref is None or ref == 0:
        return '—'
    pct  = (val - ref) / abs(ref) * 100
    if abs(pct) < 0.05:   # rounds to 0.0% — no arrow, no colour
        return '0.0%'
    sign = '+' if pct > 0 else ''
    if hib is True:
        arrow = '↑' if pct > 0 else '↓'
    elif hib is False:
        arrow = '↑' if pct < 0 else '↓'
    else:
        arrow = ''
    return f'{sign}{pct:.1f}% {arrow}'.strip()


def _highlight_delta(val):
    """Pandas Styler: colour delta column green/red based on arrow."""
    s = str(val)
    if '↑' in s:
        return 'color: green; font-weight: bold'
    if '↓' in s:
        return 'color: #cc0000; font-weight: bold'
    return ''


def _style_ratio_and_diag(row):
    """Row-wise styler for the ratio + diagnostics columns.

    Ratio column:
      * Per-bench rows: green when ratio > 1 (target faster than ref),
        red when < 1 (slower). No styling on `—` / blank / unparseable.
      * Score row (summary): same green/red rule + bold + 1.25em font-size
        (the table's headline number).
      * Standard Deviation row (summary): bold, NO color. The cell carries
        a GSD value which is a multiplicative spread measure, not a
        direction-bearing ratio.

    Target IPC column on the SD row only:
      * Italic + muted grey for the plain-language spread interpretation
        that lives there (e.g. "very wide -- caution"). Splitting the
        GSD value + interpretation across the two adjacent cells lets the
        sometimes-long hint fit without widening the ratio column.

    Returns a list of CSS strings aligned with `row.index`. Cells not
    explicitly styled get '' (transparent).
    """
    styles = [''] * len(row)
    idx = {col: i for i, col in enumerate(row.index)}

    bench    = str(row.get('Benchmark', ''))
    is_score = bench.startswith('—') and 'Score' in bench
    is_sd    = bench.startswith('—') and 'Standard Deviation' in bench

    # Ratio column ───────────────────────────────────────────────────────
    if 'ratio' in idx:
        val = str(row.get('ratio', '')).strip()
        if val and val != '—':
            if is_sd:
                # GSD has no "better" direction; bold for emphasis, no colour.
                styles[idx['ratio']] = 'font-weight: bold'
            else:
                try:
                    v = float(val.split()[0])
                except (ValueError, IndexError):
                    v = None
                if v is not None:
                    parts = []
                    if v > 1.0:
                        parts.append('color: green')
                    elif v < 1.0:
                        parts.append('color: #cc0000')
                    if is_score:
                        parts.append('font-weight: bold')
                        parts.append('font-size: 1.5em')
                    styles[idx['ratio']] = '; '.join(parts)

    # Target IPC column on SD row carries the interpretation text.
    if is_sd and 'target IPC' in idx:
        ipc_val = str(row.get('target IPC', '')).strip()
        if ipc_val:
            styles[idx['target IPC']] = 'font-style: italic; color: #666666'

    return styles


def _hib_for_bundle(bundle, attr: str):
    """Return higher-is-better for a specific bundle+attribute combination."""
    hib = ATTR_HIGHER_IS_BETTER.get(attr)
    if hib is None and attr == 'score' and bundle is not None:
        hib = score_higher_is_better(bundle)
    return hib


def _load_bundles(name: str, snap_root: Path, latest_bundles: dict) -> dict:
    """Load bundles for a snapshot name or 'latest'."""
    if name == _LATEST:
        return latest_bundles
    return _load_snapshot(name, str(snap_root / name))


# ── Branch Statistics helper ───────────────────────────────────────────────────

def _render_branch_stats(br_tests, all_options, snap_root, latest_bundles,
                         load_bundles_fn):
    """Aggregate branch-by-mnemonic statistics across all tests in a snapshot."""

    @st.fragment
    def _br_fragment():
        br_snap = st.selectbox('Snapshot', all_options, key='br_snap')
        snap_bundles = load_bundles_fn(br_snap, snap_root, latest_bundles)

        # Collect per-test branch-by-mnemonic tables
        all_rows = []
        summary_rows = []
        for test in br_tests:
            br = snap_bundles.get(test, {}).get('branches', {})
            by_mnem = br.get('by_mnem', pd.DataFrame())
            if by_mnem.empty:
                continue
            tmp = by_mnem.copy()
            tmp['test'] = test
            all_rows.append(tmp)

            total   = int(tmp['count'].sum()) if 'count' in tmp.columns else 0
            taken   = int(tmp['taken'].sum()) if 'taken' in tmp.columns else 0
            fwd     = int(tmp['forward'].sum()) if 'forward' in tmp.columns else 0
            bwd     = int(tmp['backward'].sum()) if 'backward' in tmp.columns else 0
            summary_rows.append({
                'Test':      test,
                'Branches':  total,
                'Taken %':   round(taken / total * 100, 1) if total else 0,
                'Forward %': round(fwd / total * 100, 1) if total else 0,
                'Backward %': round(bwd / total * 100, 1) if total else 0,
            })

        if not all_rows:
            st.info('No branch data available for the selected snapshot.')
            return

        combined = pd.concat(all_rows, ignore_index=True)

        # Fixed mnemonic order: alphabetical so it stays stable across snapshots
        mnem_order = sorted(combined['mnem_base'].unique())
        combined['mnem_base'] = pd.Categorical(
            combined['mnem_base'], categories=mnem_order, ordered=True,
        )
        combined = combined.sort_values('mnem_base')

        # ── Summary table with averages ──────────────────────────────────
        st.subheader('Per-Test Branch Summary')
        st.caption(
            'High-level branch statistics for each test. '
            'The average row shows the mean across all tests.'
        )
        summary_df = pd.DataFrame(summary_rows)
        avg_row = {
            'Test':       '— Average —',
            'Branches':   int(summary_df['Branches'].mean()),
            'Taken %':    round(summary_df['Taken %'].mean(), 1),
            'Forward %':  round(summary_df['Forward %'].mean(), 1),
            'Backward %': round(summary_df['Backward %'].mean(), 1),
        }
        summary_df = pd.concat([summary_df, pd.DataFrame([avg_row])],
                               ignore_index=True)
        st.dataframe(summary_df, hide_index=True, width='stretch')
        _copyable_table(summary_df, 'Copy branch summary as text')

        st.markdown('---')

        # ── Grouped bar: branch count by mnemonic across tests ───────────
        st.subheader('Branch Count by Mnemonic (all tests)')
        st.caption(
            'Total branch count per mnemonic for each test. '
            'Shows which branch instructions dominate and how usage varies.'
        )
        fig1 = px.bar(
            combined, x='mnem_base', y='count', color='test',
            barmode='group',
            labels={'mnem_base': 'Mnemonic', 'count': 'Count', 'test': 'Test'},
        )
        fig1.update_layout(
            legend=dict(orientation='h', y=-0.2, yanchor='top'),
            height=450,
        )
        st.plotly_chart(fig1)

        st.markdown('---')

        # ── Taken % by mnemonic with variability ─────────────────────────
        st.subheader('Taken % by Mnemonic (variability across tests)')
        st.caption(
            'Each dot is one test. Shows how the taken percentage for each '
            'mnemonic varies across tests. Low spread = consistent behavior.'
        )
        if 'taken_pct' not in combined.columns and 'taken' in combined.columns:
            combined['taken_pct'] = np.where(
                combined['count'] > 0,
                combined['taken'] / combined['count'] * 100,
                0,
            )
        fig2 = px.strip(
            combined, x='mnem_base', y='taken_pct', color='test',
            labels={'mnem_base': 'Mnemonic', 'taken_pct': 'Taken %', 'test': 'Test'},
            category_orders={'mnem_base': mnem_order},
        )
        # Add vertical separators and mean/std bands per mnemonic
        mnemonics = mnem_order
        for i, mnem in enumerate(mnemonics):
            # Vertical separator between groups
            if i < len(mnemonics) - 1:
                fig2.add_vline(
                    x=i + 0.5, line_width=1, line_dash='dot',
                    line_color='lightgrey',
                )
            # Mean line and ±1 std band
            vals = combined.loc[combined['mnem_base'] == mnem, 'taken_pct']
            if len(vals) > 1:
                m = vals.mean()
                s = vals.std()
                hw = 0.35  # half-width of the line segment
                # ±1 std shaded band
                fig2.add_shape(
                    type='rect',
                    xref='x', x0=i - hw, x1=i + hw,
                    y0=max(m - s, 0), y1=min(m + s, 100),
                    fillcolor='rgba(100,100,100,0.10)',
                    line_width=0,
                )
                # Mean line
                fig2.add_shape(
                    type='line',
                    xref='x', x0=i - hw, x1=i + hw,
                    y0=m, y1=m,
                    line=dict(color='rgba(80,80,80,0.6)', width=2, dash='dash'),
                )
        fig2.update_layout(
            legend=dict(orientation='h', y=-0.2, yanchor='top'),
            height=450,
            xaxis=dict(categoryorder='array', categoryarray=mnemonics),
        )
        st.plotly_chart(fig2)

        st.markdown('---')

        # ── Aggregate table: per-mnemonic avg ± std ──────────────────────
        st.subheader('Per-Mnemonic Averages (across all tests)')
        st.caption(
            'Mean and standard deviation of count and taken % for each mnemonic '
            'across all tests in the snapshot.\n\n'
            '**Mean** gives the typical value across tests — useful for comparing '
            'mnemonics and understanding overall behavior. '
            '**Std (standard deviation)** measures how much a value varies between '
            'tests — a low std means the mnemonic behaves consistently regardless '
            'of the workload, while a high std indicates the value is workload-dependent. '
            'For example, a mnemonic with *Taken % mean = 60* and *std = 5* is '
            'consistently biased toward taken across all tests, making it a good '
            'candidate for static prediction. One with *mean = 50* and *std = 30* '
            'swings wildly between tests, so only a dynamic predictor can handle it well.'
        )
        agg_cols = {}
        if 'count' in combined.columns:
            agg_cols['count'] = ['mean', 'std']
        if 'taken_pct' in combined.columns:
            agg_cols['taken_pct'] = ['mean', 'std']
        elif 'taken' in combined.columns:
            combined['taken_pct'] = np.where(
                combined['count'] > 0,
                combined['taken'] / combined['count'] * 100, 0)
            agg_cols['taken_pct'] = ['mean', 'std']

        if agg_cols:
            agg = combined.groupby('mnem_base', observed=True).agg(agg_cols).round(1)
            agg.columns = [f'{c}_{s}' for c, s in agg.columns]
            agg = agg.sort_values('count_mean', ascending=False).reset_index()
            agg.columns = ['Mnemonic', 'Count (mean)', 'Count (std)',
                           'Taken % (mean)', 'Taken % (std)']
            st.dataframe(agg, hide_index=True, width='stretch')
            _copyable_table(agg, 'Copy per-mnemonic averages as text')

    _br_fragment()


# ── Main render ────────────────────────────────────────────────────────────────

def render(traces_dir: str):
    st.title('Snapshot Compare')

    traces_path    = Path(traces_dir)
    available      = list_snapshots(traces_path)
    latest_bundles = _load_latest(traces_dir)
    snap_root      = traces_path / 'snapshots'

    if not available:
        st.info(
            f'No snapshots found in `{traces_path / "snapshots"}`.\n\n'
            'Create one from the run directory with:\n'
            '```\n../bin/bench_snapshot <name> --desc "description"\n```'
        )
        return

    snap_names = [name for name, _ in available]
    manifests  = {name: mf for name, mf in available}

    # All selectable options: snapshots + latest
    all_options = snap_names + [_LATEST]

    # ── Determine which optional tabs should be shown ────────────────────────
    bp_tests = [
        t for t in latest_bundles
        if not latest_bundles[t].get('branch_prediction', {})
               .get('size_sweep', pd.DataFrame()).empty
    ]
    br_tests = [
        t for t in latest_bundles
        if not latest_bundles[t].get('branches', {})
               .get('by_mnem', pd.DataFrame()).empty
    ]
    jmp_tests = [
        t for t in latest_bundles
        if latest_bundles[t].get('jumps', {}).get('jalr_total', 0) > 0
    ]
    pl_tests = [
        t for t in latest_bundles
        if not latest_bundles[t].get('pipeline', {})
               .get('stalls_by_cause', pd.DataFrame()).empty
    ]

    # ── Tabs ──────────────────────────────────────────────────────────────────
    tab_labels = ['Score Table']
    if br_tests:
        tab_labels.append('Branch Statistics')
    if jmp_tests:
        tab_labels.append('Jump Analysis')
    if pl_tests:
        tab_labels.append('Pipeline Stalls')
    if bp_tests:
        tab_labels.append('Branch Prediction')
    tabs = st.tabs(tab_labels)

    # ── Tab 1: Score Table ────────────────────────────────────────────────────
    with tabs[0]:
        col1, col2, col3, col4 = st.columns([2, 2, 2, 2])

        with col1:
            ref_default = 0
            ref_name = st.selectbox(
                'Reference',
                all_options,
                index=ref_default,
                help='Baseline to compare against.',
            )

        with col2:
            tgt_default = all_options.index(_LATEST)
            tgt_name = st.selectbox(
                'Target',
                all_options,
                index=tgt_default,
                help='Snapshot or latest traces to evaluate.',
            )

        with col3:
            attr = st.selectbox(
                'Attribute',
                list(ATTR_LABELS.keys()),
                format_func=lambda k: ATTR_LABELS[k],
            )

        with col4:
            suites_avail = sorted({detect_suite(t) for t in latest_bundles})
            suite        = st.selectbox('Suite filter', ['all'] + suites_avail)

        if ref_name == tgt_name:
            st.info('Reference and target are the same — select different snapshots.')
            return

        # Extra columns (plain values, no Δ)
        extra_options = [n for n in all_options if n not in (ref_name, tgt_name)]
        extra_names   = st.multiselect(
            'Extra columns',
            extra_options,
            default=[],
            help='Additional snapshots shown as plain value columns for visual comparison.',
        )

        # ── Load data ─────────────────────────────────────────────────────────
        ref_bundles = _load_bundles(ref_name, snap_root, latest_bundles)
        tgt_bundles = _load_bundles(tgt_name, snap_root, latest_bundles)
        extra_bundles = {
            name: _load_bundles(name, snap_root, latest_bundles)
            for name in extra_names
        }

        # Collect tests and apply suite filter
        all_tests = set(ref_bundles.keys()) | set(tgt_bundles.keys())
        if suite != 'all':
            all_tests = {t for t in all_tests if detect_suite(t) == suite}
        tests = sorted(all_tests)

        if not tests:
            st.warning(f'No benchmarks found for suite "{suite}".')
        else:
            # ── Build DataFrame ───────────────────────────────────────────────
            #
            # Decide upfront whether the table will carry the extra "Geomean
            # (vs M4)" column -- happens when we're showing raw scores AND
            # at least one Embench row is present. Per-bench rows get a blank
            # cell in that column (no per-bench aggregation to compute); the
            # Score / Standard Deviation summary rows fill it with the
            # M4-anchored Speed Score and ratio-GSD respectively.
            has_embench = bool(attr == 'score'
                               and any(detect_suite(t) == 'embench' for t in tests))
            # The delta-geomean column is anchored to the currently-selected
            # reference (ref_name), not hard-wired to M4. When the user
            # leaves the default `embench_baseline` selected as ref, the
            # column carries the canonical M4 Speed Score; when they pick
            # any other snapshot as ref, it becomes "geomean of ref vs each
            # target column", which is just as useful for snapshot-vs-snapshot
            # cross-comparison (silicon vs golden run, before vs after a
            # config change, etc.). The exact reference is named in the
            # caption beneath the table.
            GM_COL  = 'ratio'
            IPC_COL = 'target IPC'
            TS_COL  = 'target top stall cause'
            # Per-bench diagnostic columns ride alongside the comparison
            # columns whenever we have score-mode embench data. They report
            # what the TARGET column saw -- the ref column is typically the
            # virtual `embench_baseline` snapshot which carries no pipeline
            # data, and adding a second pair of columns for ref would just
            # produce 22 empty cells. Summary rows leave both blank (top
            # stall cause has no meaningful aggregate; weighted IPC is
            # defensible but not requested).
            show_diag = has_embench

            rows          = []
            ref_gm_v      = []
            tgt_gm_v      = []
            extra_gm_v    = {name: [] for name in extra_names}
            gm_hib        = False

            for test in tests:
                ref_b = ref_bundles.get(test)
                tgt_b = tgt_bundles.get(test)
                ref_v, _ = extract_metric(ref_b, attr)
                tgt_v, _ = extract_metric(tgt_b, attr)
                row_hib = _hib_for_bundle(ref_b or tgt_b, attr)
                row = {
                    'Benchmark': test,
                    ref_name:    _fmt_val(ref_v, attr),
                }
                for name in extra_names:
                    ex_v, _ = extract_metric(extra_bundles[name].get(test), attr)
                    row[name] = _fmt_val(ex_v, attr)
                    if detect_suite(test) == 'embench' and ex_v is not None:
                        extra_gm_v[name].append(ex_v)
                row[tgt_name] = _fmt_val(tgt_v, attr)
                row['Δ']      = _delta_str(tgt_v, ref_v, row_hib)
                # Per-bench delta-geomean = ref_ms / tgt_ms, i.e. "how many times
                # faster than ref is tgt on THIS bench" (higher = better, mirrors
                # the Score row's aggregate). Only meaningful for ms-based scores
                # (skipped silently if either side is missing, non-positive, or a
                # non-ms unit like CoreMark/MHz / DMIPS/MHz).
                if has_embench:
                    _, ref_unit = extract_metric(ref_b, 'score')
                    _, tgt_unit = extract_metric(tgt_b, 'score')
                    if (ref_v is not None and ref_v > 0
                            and tgt_v is not None and tgt_v > 0
                            and (not ref_unit or ref_unit == 'Time(ms)')
                            and (not tgt_unit or tgt_unit == 'Time(ms)')):
                        row[GM_COL] = f'{ref_v / tgt_v:.3f}'
                    else:
                        row[GM_COL] = '—'
                if show_diag:
                    ipc = _target_ipc(tgt_b)
                    row[IPC_COL] = f'{ipc:.3f}' if ipc is not None else '—'
                    row[TS_COL]  = _top_stall_cause(tgt_b) or '—'
                rows.append(row)
                if detect_suite(test) == 'embench':
                    if ref_v is not None:
                        ref_gm_v.append(ref_v)
                    if tgt_v is not None:
                        tgt_gm_v.append(tgt_v)

            # Aggregation row(s).
            #
            # When ANY displayed test is Embench AND we're showing raw scores,
            # the bottom two rows are split: the main per-column cells carry
            # raw-ms aggregates (geomean and GSD of bench ms per column,
            # scale-free / unit-comparable across columns), and the extra
            # "Geomean (vs M4)" column carries the M4-anchored ratio numbers
            # (Embench Speed Score and ratio GSD -- what Embench publishes for
            # cross-platform comparison). That way the table tells two stories
            # at once: how each snapshot looks on its own (ms summary), and
            # how it stacks up against the M4 reference (ratio summary).
            #
            # In mixed-suite views (embench + coremark + dhrystone displayed
            # together) the summary rows still aggregate ONLY the embench rows
            # -- matches the long-standing convention here, and Speed Score has
            # no meaning for CoreMark/DMIPS rate scores. Non-score attributes
            # (ipc, branch_miss, sizes) keep the legacy single raw-geomean row.
            if has_embench:
                # Per-column raw-ms geomean + GSD (scale-free spread of the
                # column's own bench ms values).
                ref_gm  = _geomean(ref_gm_v)
                tgt_gm  = _geomean(tgt_gm_v)
                ref_gsd_ms = _gsd(ref_gm_v)
                tgt_gsd_ms = _gsd(tgt_gm_v)
                extra_gm   = {name: _geomean(extra_gm_v[name]) for name in extra_names}
                extra_gsd_ms = {name: _gsd(extra_gm_v[name]) for name in extra_names}

                # Per-column ratio aggregates (geomean + GSD) anchored to the
                # currently-selected reference snapshot. By construction the
                # ref column reads 1.000 / 1.000 (ref vs itself); the tgt and
                # extras columns read ref_geomean / column_geomean. When ref
                # is `embench_baseline`, this collapses to the canonical M4
                # Speed Score; for any other ref, it's the generalized "how
                # much faster than ref" score.
                ref_ss, ref_gsd, ref_n = geomean_ratio(ref_bundles, ref_bundles)
                tgt_ss, tgt_gsd, tgt_n = geomean_ratio(tgt_bundles, ref_bundles)
                extra_ss = {
                    name: geomean_ratio(extra_bundles[name], ref_bundles)
                    for name in extra_names
                }
                # Highest contributing-bench count across the displayed
                # columns; surfaced in the caption rather than in the row
                # label so the table reader knows the aggregation breadth.
                n_max = max([ref_n, tgt_n,
                             *[v[2] for v in extra_ss.values()]], default=0)

                # Score row: geomean of bench ms per column. Δ cell shows the
                # percent change of those geomeans (ms: lower is better, ↑ on
                # improvement) -- a familiar additive view of the same trend
                # the multiplicative `ratio` column conveys.
                score_row = {
                    'Benchmark': '— Score —',
                    ref_name:    _fmt_val(ref_gm, attr) if ref_gm is not None else '—',
                }
                for name in extra_names:
                    score_row[name] = _fmt_val(extra_gm[name], attr) if extra_gm[name] is not None else '—'
                score_row[tgt_name] = _fmt_val(tgt_gm, attr) if tgt_gm is not None else '—'
                score_row['Δ']      = _delta_str(tgt_gm, ref_gm, False)   # ms: lower-is-better
                score_row[GM_COL]   = f'{tgt_ss:.3f}' if tgt_ss is not None else '—'
                if show_diag:
                    score_row[IPC_COL] = ''
                    score_row[TS_COL]  = ''
                rows.append(score_row)

                # Standard Deviation row: per-column GSD-of-ms (scale-free,
                # interpretable across columns regardless of their geomean
                # magnitude). Δ cell is BLANK (no meaningful "Δ of GSD" to
                # show). The delta-geomean column carries the ratio-anchored
                # GSD plus the plain-language spread hint next to its number,
                # so value and interpretation read together.
                sd_row = {
                    'Benchmark': '— Standard Deviation —',
                    ref_name:    f'{ref_gsd_ms:.3f}' if ref_gsd_ms is not None else '—',
                }
                for name in extra_names:
                    v = extra_gsd_ms[name]
                    sd_row[name] = f'{v:.3f}' if v is not None else '—'
                sd_row[tgt_name] = f'{tgt_gsd_ms:.3f}' if tgt_gsd_ms is not None else '—'
                sd_row['Δ']      = ''
                # Split the ratio-GSD across two cells so the (sometimes
                # long) interpretation string has room without forcing the
                # ratio column wider: bare GSD number in the ratio cell, the
                # plain-language spread hint in the (otherwise-blank-for-this-
                # row) target-IPC cell. The two read as one expression to
                # anyone scanning the row label "— Standard Deviation —".
                sd_hint = gsd_interpretation(tgt_gsd) if tgt_gsd is not None else ''
                sd_row[GM_COL] = f'{tgt_gsd:.3f}' if tgt_gsd is not None else '—'
                if show_diag:
                    sd_row[IPC_COL] = sd_hint   # spread interpretation lives here
                    sd_row[TS_COL]  = ''
                rows.append(sd_row)
            else:
                # Legacy raw-value geomean -- still meaningful for ipc, branch_miss,
                # sizes, or any non-Embench score-attribute view.
                ref_gm = _geomean(ref_gm_v)
                tgt_gm = _geomean(tgt_gm_v)
                if ref_gm is None and tgt_gm is None:
                    gm_hib = None
                gm_row = {
                    'Benchmark': '— Geomean —',
                    ref_name:    _fmt_val(ref_gm, attr),
                }
                for name in extra_names:
                    gm_row[name] = _fmt_val(_geomean(extra_gm_v[name]), attr)
                gm_row[tgt_name] = _fmt_val(tgt_gm, attr)
                gm_row['Δ']      = _delta_str(tgt_gm, ref_gm, gm_hib)
                rows.append(gm_row)

            df = pd.DataFrame(rows)

            # ── Render table ──────────────────────────────────────────────────
            caption = f'**{ATTR_LABELS[attr]}**  —  ↑ improvement  ↓ regression'
            if has_embench:
                n_note = f' (n={n_max} benches)' if n_max else ''
                caption += (f'  |  Main columns: per-bench ms (Score row = geomean of those ms; '
                            f'Standard Deviation row = GSD of those ms).'
                            f'  |  **{GM_COL}** column: per-bench `ref_ms / column_ms` vs `{ref_name}` — '
                            f'higher = faster than `{ref_name}`. Score row = geomean of those ratios{n_note}; '
                            f'Standard Deviation row = GSD over those ratios.'
                            f'  |  **{IPC_COL}** / **{TS_COL}**: per-bench diagnostics for '
                            f'the target column (`{tgt_name}`).')
            elif ref_gm_v:
                caption += '  |  Geomean over Embench tests only'
            caption += f'  |  Δ = **{tgt_name}** vs **{ref_name}**'
            st.caption(caption)

            styled = df.style.map(_highlight_delta, subset=['Δ'])
            if GM_COL in df.columns:
                # One row-wise styler handles the ratio column's per-bench
                # green/red + Score-row bold/enlarge + SD-row bold-no-colour,
                # plus the SD-row interpretation in the target-IPC cell.
                styled = styled.apply(_style_ratio_and_diag, axis=1)

            # Render via st.markdown rather than st.dataframe so the full
            # CSS subset (font-size, font-style, padding) is honoured --
            # st.dataframe's virtualized data-grid renderer silently drops
            # everything except color, background-color, and font-weight,
            # so the Score-row 1.5em emphasis and SD-row italic hint would
            # otherwise vanish. Trade-off: lose click-to-sort and scroll
            # virtualization on this one table; both negligible at ~25 rows.
            # `_TABLE_BASE_CSS` adds the cell padding / border styling that
            # st.dataframe applies by default so the rendered table doesn't
            # look out-of-place next to the other tabs that still use
            # st.dataframe.
            styled = styled.hide(axis='index')
            table_html = (
                _TABLE_BASE_CSS
                + '<div class="arv-snapcmp" style="overflow-x:auto;">'
                + styled.to_html(escape=False)
                + '</div>'
            )
            st.markdown(table_html, unsafe_allow_html=True)
            _copyable_table(df, 'Copy score table as text')

    # ── Tab: Branch Statistics ────────────────────────────────────────────────
    if br_tests:
        _tab_idx_br = tab_labels.index('Branch Statistics')
        with tabs[_tab_idx_br]:
            _render_branch_stats(br_tests, all_options, snap_root, latest_bundles,
                                 _load_bundles)

    # ── Tab: Jump Analysis ──────────────────────────────────────────────────────
    if jmp_tests:
        _tab_idx_jmp = tab_labels.index('Jump Analysis')
        with tabs[_tab_idx_jmp]:
            @st.fragment
            def _jmp_fragment():
                jmp_snap = st.selectbox('Snapshot', all_options, key='jmp_snap')
                snap_bundles = _load_bundles(jmp_snap, snap_root, latest_bundles)

                # ── Per-test JALR summary table ───────────────────────────────
                st.subheader('Per-Test JALR Summary')
                st.caption(
                    'JALR statistics for each test. '
                    '**Late-source %** is the percentage of JALRs where the immediately '
                    'preceding instruction writes the target register (RAW hazard — potential '
                    'pipeline stall). **Indirect call %** shows JALR calls vs total calls '
                    '(JAL + JALR).'
                )
                summary_rows = []
                for test in sorted(jmp_tests):
                    jmp = snap_bundles.get(test, {}).get('jumps', {})
                    if not jmp:
                        continue
                    cr = jmp.get('call_return_ratio', {})
                    summary_rows.append({
                        'Test':             test,
                        'JALR':             jmp.get('jalr_total', 0),
                        'JAL':              jmp.get('jal_total', 0),
                        'Calls':            cr.get('call', 0),
                        'Returns':          cr.get('return', 0),
                        'Other':            cr.get('other', 0),
                        'Indirect call %':  jmp.get('indirect_call_pct', 0),
                        'Late-source %':    jmp.get('jalr_late_source_pct', 0),
                    })

                if not summary_rows:
                    st.info('No JALR data available for the selected snapshot.')
                    return

                summary_df = pd.DataFrame(summary_rows)

                # Add average row
                num_cols = ['JALR', 'JAL', 'Calls', 'Returns', 'Other',
                            'Indirect call %', 'Late-source %']
                avg_row = {'Test': '— Average —'}
                for col in num_cols:
                    avg_row[col] = round(summary_df[col].mean(), 1)
                summary_df = pd.concat([summary_df, pd.DataFrame([avg_row])],
                                       ignore_index=True)
                st.dataframe(summary_df, hide_index=True, width='stretch')
                _copyable_table(summary_df, 'Copy JALR summary as text')

                st.markdown('---')

                # ── JALR rs1 register distribution across tests ───────────────
                st.subheader('JALR Target Register (rs1) Distribution')
                st.caption(
                    'Which registers are used as JALR jump targets across all tests. '
                    'Returns typically use x1 (ra). Indirect calls through other registers '
                    '(e.g., t0, t1) are harder to predict and may benefit from a BTB.'
                )
                all_rs1_rows = []
                for test in sorted(jmp_tests):
                    jmp = snap_bundles.get(test, {}).get('jumps', {})
                    rs1_freq = jmp.get('jalr_rs1_freq', pd.DataFrame())
                    if rs1_freq.empty:
                        continue
                    tmp = rs1_freq[['name', 'count', 'pct']].copy()
                    tmp['test'] = test
                    all_rs1_rows.append(tmp)

                if all_rs1_rows:
                    combined_rs1 = pd.concat(all_rs1_rows, ignore_index=True)

                    # Aggregate: total count per register across all tests
                    agg_rs1 = (combined_rs1.groupby('name', as_index=False)['count']
                               .sum()
                               .sort_values('count', ascending=False))
                    total = agg_rs1['count'].sum()
                    agg_rs1['pct'] = (agg_rs1['count'] / total * 100).round(1)

                    col_tbl, col_chart = st.columns([1, 2])
                    with col_tbl:
                        agg_rs1.columns = ['Register', 'Count', '%']
                        st.dataframe(agg_rs1, hide_index=True, width='stretch')
                    with col_chart:
                        fig_rs1 = px.bar(
                            agg_rs1, x='Register', y='%',
                            labels={'%': 'Percentage', 'Register': 'Register'},
                        )
                        fig_rs1.update_layout(height=350, showlegend=False)
                        st.plotly_chart(fig_rs1)

                    st.markdown('---')

                    # Per-test register heatmap
                    st.subheader('JALR rs1 Usage by Test')
                    st.caption(
                        'Percentage of JALRs using each register as rs1, per test. '
                        'Helps identify which benchmarks rely on indirect jumps through '
                        'non-standard registers.'
                    )
                    pivot = combined_rs1.pivot_table(
                        index='test', columns='name', values='pct',
                        fill_value=0, aggfunc='sum',
                    )
                    # Order columns by total usage
                    col_order = agg_rs1['Register'].tolist()
                    pivot = pivot.reindex(columns=[c for c in col_order if c in pivot.columns])

                    fig_heat = px.imshow(
                        pivot.values,
                        x=pivot.columns.tolist(),
                        y=pivot.index.tolist(),
                        labels=dict(x='Register', y='Test', color='%'),
                        color_continuous_scale='Blues',
                        aspect='auto',
                    )
                    fig_heat.update_layout(height=max(300, 30 * len(pivot)))
                    st.plotly_chart(fig_heat)

                    _copyable_table(
                        pivot.reset_index().rename(columns={'test': 'Test'}),
                        'Copy rs1 heatmap as text',
                    )

                st.markdown('---')

                # ── JALR rs1 transition matrix ──────────────────────────────
                st.subheader('JALR rs1 Register Transitions')
                st.caption(
                    'How often one JALR base register is followed by another '
                    '(consecutive JALRs). Strong diagonal = same register repeated '
                    '(e.g. always returning via ra). Off-diagonal entries reveal '
                    'indirect call patterns.'
                )
                all_trans_rows = []
                for test in sorted(jmp_tests):
                    jmp = snap_bundles.get(test, {}).get('jumps', {})
                    trans = jmp.get('jalr_rs1_transition', pd.DataFrame())
                    if trans.empty:
                        continue
                    cols = ['from_reg', 'to_reg', 'count']
                    # Include late_count if available (requires pkl regeneration)
                    if 'late_count' in trans.columns:
                        cols.append('late_count')
                    tmp = trans[cols].copy()
                    tmp['test'] = test
                    if 'late_count' not in tmp.columns:
                        tmp['late_count'] = 0
                    all_trans_rows.append(tmp)

                if all_trans_rows:
                    trans_combined = pd.concat(all_trans_rows, ignore_index=True)

                    # Aggregate across all tests
                    trans_agg = (trans_combined
                                 .groupby(['from_reg', 'to_reg'], as_index=False)
                                 [['count', 'late_count']].sum()
                                 .sort_values('count', ascending=False))
                    trans_agg['late_pct'] = (
                        trans_agg['late_count'] / trans_agg['count'] * 100
                    ).round(1)

                    # Build pivot tables for heatmap (count and late %)
                    trans_pivot = trans_agg.pivot_table(
                        index='from_reg', columns='to_reg', values='count',
                        fill_value=0, aggfunc='sum',
                    )
                    late_pivot = trans_agg.pivot_table(
                        index='from_reg', columns='to_reg', values='late_pct',
                        fill_value=0, aggfunc='sum',
                    )
                    # Order by total usage (rows and columns)
                    row_order = trans_agg.groupby('from_reg')['count'].sum().sort_values(ascending=False).index.tolist()
                    col_order = trans_agg.groupby('to_reg')['count'].sum().sort_values(ascending=False).index.tolist()
                    # Combine to get a consistent order
                    all_regs = []
                    for r in row_order + col_order:
                        if r not in all_regs:
                            all_regs.append(r)
                    trans_pivot = trans_pivot.reindex(
                        index=[r for r in all_regs if r in trans_pivot.index],
                        columns=[r for r in all_regs if r in trans_pivot.columns],
                        fill_value=0,
                    )
                    late_pivot = late_pivot.reindex(
                        index=trans_pivot.index,
                        columns=trans_pivot.columns,
                        fill_value=0,
                    )

                    col_tbl, col_heat = st.columns([1, 2])
                    with col_tbl:
                        trans_display = trans_agg[['from_reg', 'to_reg', 'count', 'late_pct']].copy()
                        trans_display.columns = ['From', 'To', 'Count', 'Late %']
                        st.dataframe(trans_display, hide_index=True, width='stretch')
                        _copyable_table(trans_display, 'Copy transition table as text')
                    with col_heat:
                        # Build text annotations: count (late%)
                        trans_values = trans_pivot.values
                        late_values = late_pivot.values
                        trans_text = []
                        for r_idx in range(len(trans_values)):
                            row_text = []
                            for c_idx in range(len(trans_values[r_idx])):
                                cnt = int(trans_values[r_idx][c_idx])
                                lp = late_values[r_idx][c_idx]
                                if cnt == 0:
                                    row_text.append('')
                                elif lp > 0:
                                    row_text.append(f'{cnt} ({lp:.0f}%)')
                                else:
                                    row_text.append(str(cnt))
                            trans_text.append(row_text)
                        fig_trans = px.imshow(
                            trans_values,
                            x=trans_pivot.columns.tolist(),
                            y=trans_pivot.index.tolist(),
                            labels=dict(x='To register', y='From register', color='Count'),
                            color_continuous_scale='Blues',
                            aspect='auto',
                            text_auto=False,
                        )
                        fig_trans.update_traces(
                            text=trans_text,
                            texttemplate='%{text}',
                            textfont=dict(size=11),
                        )
                        fig_trans.update_layout(
                            height=max(350, 50 * len(trans_pivot)),
                        )
                        st.plotly_chart(fig_trans)

                st.markdown('---')

                # ── Late-source % bar chart ───────────────────────────────────
                st.subheader('JALR Late-Source % by Test')
                st.caption(
                    'Percentage of JALRs where the immediately preceding instruction '
                    'writes the target register. Higher values indicate more RAW hazards '
                    'on the JALR critical path — a key metric for timing optimization.'
                )
                late_df = pd.DataFrame([
                    {'Test': r['Test'], 'Late-source %': r['Late-source %']}
                    for r in summary_rows
                ]).sort_values('Late-source %', ascending=False)

                fig_late = px.bar(
                    late_df, x='Test', y='Late-source %',
                    labels={'Late-source %': 'Late-source %', 'Test': ''},
                )
                avg_late = late_df['Late-source %'].mean()
                fig_late.add_hline(
                    y=avg_late, line_dash='dash', line_color='crimson',
                    annotation_text=f'avg: {avg_late:.1f}%',
                    annotation_position='top right',
                )
                fig_late.update_layout(height=400, xaxis_tickangle=-45)
                st.plotly_chart(fig_late)

                st.markdown('---')

                # ── Shadow register analysis ──────────────────────────────────
                st.subheader('Shadow Register Analysis')
                st.caption(
                    'Analyzes JALR rs1 register switching behavior to guide shadow '
                    'register design decisions. **Switch rate** is the percentage of '
                    'consecutive JALRs that use a different rs1. **Shadow register hit '
                    'rate** simulates an LRU cache of N shadow registers — a hit means '
                    'the JALR target register was already cached and available without '
                    'a register file read. **Effective hit rate** counts shadow misses '
                    'that coincide with a late-source RAW hazard as free — the pipeline '
                    'is already stalling, so the shadow update has no extra cost.'
                )

                # Per-test switch rate + shadow hit rates
                shadow_rows = []
                sweep_lines = []
                for test in sorted(jmp_tests):
                    jmp = snap_bundles.get(test, {}).get('jumps', {})
                    if not jmp:
                        continue
                    switch_rate = jmp.get('jalr_rs1_switch_rate', 0)
                    sweep = jmp.get('jalr_shadow_hit_sweep', pd.DataFrame())
                    run_info = jmp.get('jalr_rs1_run_length', {})

                    row = {
                        'Test':          test,
                        'Switch rate %': switch_rate,
                        'Run (median)':  run_info.get('median', 0),
                        'Run (mean)':    run_info.get('mean', 0),
                        'Run (max)':     run_info.get('max', 0),
                    }
                    if not sweep.empty:
                        has_eff = 'effective_hit_rate' in sweep.columns
                        for _, sr in sweep.iterrows():
                            n = int(sr['shadow_regs'])
                            row[f'{n}-reg hit %'] = sr['hit_rate']
                            if has_eff:
                                row[f'{n}-reg eff %'] = sr['effective_hit_rate']
                            sweep_lines.append({
                                'test':        test,
                                'shadow_regs': n,
                                'hit_rate':    sr['hit_rate'],
                                'effective_hit_rate': sr.get('effective_hit_rate', sr['hit_rate']),
                            })
                    shadow_rows.append(row)

                if shadow_rows:
                    shadow_df = pd.DataFrame(shadow_rows)

                    # Add average row
                    avg_row = {'Test': '— Average —'}
                    for col in shadow_df.columns:
                        if col != 'Test':
                            avg_row[col] = round(shadow_df[col].mean(), 1)
                    shadow_df = pd.concat(
                        [shadow_df, pd.DataFrame([avg_row])], ignore_index=True,
                    )
                    st.dataframe(shadow_df, hide_index=True, width='stretch')
                    _copyable_table(shadow_df, 'Copy shadow register analysis as text')

                    st.markdown('---')

                    # Shadow register hit rate sweep chart
                    if sweep_lines:
                        st.subheader('Shadow Register Hit Rate Sweep')
                        st.caption(
                            'Each line is one benchmark. The X-axis shows the number of '
                            'LRU shadow registers, the Y-axis shows the hit rate. '
                            'If the curve flattens at 1-2 registers, a single shadow '
                            'register is sufficient. If it keeps climbing, more are needed. '
                            'Solid lines show raw hit rate; dotted lines show effective hit rate '
                            '(misses masked by a late-source RAW stall count as free).'
                        )
                        sweep_df = pd.DataFrame(sweep_lines)

                        fig_sweep = go.Figure()

                        has_eff_sweep = 'effective_hit_rate' in sweep_df.columns

                        # Compute averages for bold overlay
                        avg_sweep = (sweep_df.groupby('shadow_regs', as_index=False)
                                     ['hit_rate'].mean())
                        if has_eff_sweep:
                            avg_eff = (sweep_df.groupby('shadow_regs', as_index=False)
                                       ['effective_hit_rate'].mean())

                        for test in sorted(sweep_df['test'].unique()):
                            tdf = sweep_df[sweep_df['test'] == test]
                            fig_sweep.add_trace(go.Scatter(
                                x=tdf['shadow_regs'], y=tdf['hit_rate'],
                                mode='lines+markers', name=test,
                                opacity=0.3, line=dict(width=1),
                                marker=dict(size=5),
                                legendgroup=test,
                            ))
                            if has_eff_sweep:
                                fig_sweep.add_trace(go.Scatter(
                                    x=tdf['shadow_regs'], y=tdf['effective_hit_rate'],
                                    mode='lines+markers', name=f'{test} (eff)',
                                    opacity=0.3, line=dict(width=1, dash='dot'),
                                    marker=dict(size=5, symbol='diamond'),
                                    legendgroup=test, showlegend=False,
                                ))

                        fig_sweep.add_trace(go.Scatter(
                            x=avg_sweep['shadow_regs'], y=avg_sweep['hit_rate'],
                            mode='lines+markers', name='Average hit rate',
                            line=dict(width=4, color='crimson'),
                            marker=dict(size=10, color='crimson'),
                        ))
                        if has_eff_sweep:
                            fig_sweep.add_trace(go.Scatter(
                                x=avg_eff['shadow_regs'], y=avg_eff['effective_hit_rate'],
                                mode='lines+markers', name='Average effective rate',
                                line=dict(width=4, color='royalblue', dash='dot'),
                                marker=dict(size=10, color='royalblue', symbol='diamond'),
                            ))

                        fig_sweep.update_layout(
                            xaxis_title='Shadow registers (LRU)',
                            yaxis_title='Hit rate %',
                            xaxis=dict(
                                tickvals=[1, 2, 4, 8],
                                ticktext=['1', '2', '4', '8'],
                            ),
                            yaxis=dict(range=[0, 105]),
                            height=450,
                            legend=dict(
                                orientation='v',
                                x=1.02, xanchor='left',
                                y=1, yanchor='top',
                            ),
                            margin=dict(r=200),
                        )
                        st.plotly_chart(fig_sweep)

                st.markdown('---')

                # ── Run length histograms ─────────────────────────────────────
                st.subheader('JALR rs1 Run Length Distribution')
                st.caption(
                    'How many consecutive JALRs use the same rs1 register before '
                    'switching. Long runs mean a single shadow register stays valid '
                    'for many JALRs. Short runs (length 1) indicate frequent switching.'
                )

                # Collect aggregated run length histograms across tests
                all_rl_rows = []
                for test in sorted(jmp_tests):
                    jmp = snap_bundles.get(test, {}).get('jumps', {})
                    rl_info = jmp.get('jalr_rs1_run_length', {})
                    rl_hist = rl_info.get('hist', pd.DataFrame())
                    if rl_hist.empty:
                        continue
                    # Normalize column names (handle both old and new pkl formats)
                    hist = rl_hist.copy()
                    cols = list(hist.columns)
                    if len(cols) == 2:
                        hist.columns = ['length', 'count']
                    tmp = hist[['length', 'count']].copy()
                    tmp['test'] = test
                    all_rl_rows.append(tmp)

                if all_rl_rows:
                    rl_combined = pd.concat(all_rl_rows, ignore_index=True)

                    # Aggregated histogram: sum across all tests
                    rl_agg = (rl_combined.groupby('length', as_index=False)['count']
                              .sum()
                              .sort_values('length'))

                    fig_rl = px.bar(
                        rl_agg, x='length', y='count',
                        labels={'length': 'Run length (consecutive same rs1)',
                                'count': 'Occurrences'},
                    )
                    fig_rl.update_layout(height=350)
                    st.plotly_chart(fig_rl)
                    _copyable_table(rl_agg.rename(columns={
                        'length': 'Run length', 'count': 'Occurrences',
                    }), 'Copy aggregated run lengths as text')

                    st.markdown('---')

                    # ── Per-register run length distribution ───────────────────
                    st.subheader('Run Length Distribution by Register')
                    st.caption(
                        'Same analysis but split by register. Reveals if e.g. x1 (ra) '
                        'has long runs (returns) while t0 has short runs (indirect calls). '
                        'This helps decide whether to use a dedicated shadow for ra vs '
                        'a small LRU for the rest.'
                    )

                    all_per_reg_rows = []
                    for test in sorted(jmp_tests):
                        jmp = snap_bundles.get(test, {}).get('jumps', {})
                        by_reg = jmp.get('jalr_rs1_run_length_by_reg', pd.DataFrame())
                        if by_reg.empty:
                            continue
                        all_per_reg_rows.append(by_reg)

                    if all_per_reg_rows:
                        per_reg_combined = pd.concat(all_per_reg_rows, ignore_index=True)

                        # Aggregate across all tests: sum counts per (register, length)
                        per_reg_agg = (per_reg_combined
                                       .groupby(['register', 'length'], as_index=False)
                                       ['count'].sum()
                                       .sort_values(['register', 'length']))

                        # One subplot per register (only registers with data)
                        regs_with_data = sorted(per_reg_agg['register'].unique(),
                                                key=lambda r: -per_reg_agg[
                                                    per_reg_agg['register'] == r
                                                ]['count'].sum())

                        # Summary table: per-register run length stats
                        reg_summary_rows = []
                        for reg in regs_with_data:
                            rdf = per_reg_agg[per_reg_agg['register'] == reg]
                            # Expand to individual run lengths for stats
                            expanded = rdf['length'].repeat(rdf['count'])
                            reg_summary_rows.append({
                                'Register':    reg,
                                'Runs':        int(rdf['count'].sum()),
                                'Min':         int(expanded.min()),
                                'Max':         int(expanded.max()),
                                'Median':      round(float(expanded.median()), 1),
                                'Mean':        round(float(expanded.mean()), 1),
                            })
                        reg_summary_df = pd.DataFrame(reg_summary_rows)
                        st.dataframe(reg_summary_df, hide_index=True, width='stretch')
                        _copyable_table(reg_summary_df,
                                        'Copy per-register run length summary as text')

                        # Bar chart per register
                        fig_per_reg = px.bar(
                            per_reg_agg, x='length', y='count',
                            color='register', facet_col='register',
                            facet_col_wrap=min(4, len(regs_with_data)),
                            labels={'length': 'Run length', 'count': 'Occurrences',
                                    'register': 'Register'},
                            category_orders={'register': regs_with_data},
                        )
                        fig_per_reg.update_layout(
                            height=300 * max(1, (len(regs_with_data) + 3) // 4),
                            showlegend=False,
                        )
                        fig_per_reg.for_each_annotation(
                            lambda a: a.update(text=a.text.split('=')[-1])
                        )
                        st.plotly_chart(fig_per_reg)

            _jmp_fragment()

    # ── Tab: Pipeline Stalls ──────────────────────────────────────────────────
    if pl_tests:
        _tab_idx_pl = tab_labels.index('Pipeline Stalls')
        with tabs[_tab_idx_pl]:
            @st.fragment
            def _pl_fragment():
                pl_snap = st.selectbox('Snapshot', all_options, key='pl_snap')
                snap_bundles = _load_bundles(pl_snap, snap_root, latest_bundles)

                # ── Per-test pipeline summary ─────────────────────────────────
                st.subheader('Per-Test Pipeline Summary')
                st.caption(
                    'CPI (Cycles Per Instruction), IPC, and stall rate for each test. '
                    'Lower CPI and stall rate indicate better pipeline utilization.'
                )
                summary_rows = []
                stall_rows = []
                for test in sorted(pl_tests):
                    pl = snap_bundles.get(test, {}).get('pipeline', {})
                    if not pl:
                        continue
                    summary_rows.append({
                        'Test':       test,
                        'CPI':        pl.get('cpi', 0),
                        'IPC':        pl.get('ipc', 0),
                        'Stall rate': pl.get('stall_rate', 0),
                    })
                    # Collect stall breakdowns
                    sbc = pl.get('stalls_by_cause', pd.DataFrame())
                    if not sbc.empty:
                        for _, row in sbc.iterrows():
                            stall_rows.append({
                                'test':   test,
                                'cause':  row['cause'],
                                'cycles': row['cycles'],
                                'pct':    row['pct'],
                            })

                if not summary_rows:
                    st.info('No pipeline data available for the selected snapshot.')
                    return

                summary_df = pd.DataFrame(summary_rows)
                avg_row = {
                    'Test':       '— Average —',
                    'CPI':        round(summary_df['CPI'].mean(), 3),
                    'IPC':        round(summary_df['IPC'].mean(), 3),
                    'Stall rate': round(summary_df['Stall rate'].mean(), 3),
                }
                summary_with_avg = pd.concat(
                    [summary_df, pd.DataFrame([avg_row])], ignore_index=True,
                )
                st.dataframe(summary_with_avg, hide_index=True, width='stretch')
                _copyable_table(summary_with_avg, 'Copy pipeline summary as text')

                st.markdown('---')

                # ── Stall breakdown across tests ──────────────────────────────
                if stall_rows:
                    stall_df = pd.DataFrame(stall_rows)

                    st.subheader('Stall Breakdown by Cause')
                    st.caption(
                        'Distribution of stall cycles by cause for each test. '
                        'Identifies which pipeline hazards dominate across workloads.'
                    )

                    # Stacked bar chart: stall cycles per cause per test
                    fig_stall = px.bar(
                        stall_df[stall_df['cycles'] > 0],
                        x='test', y='cycles', color='cause',
                        barmode='stack',
                        labels={'test': '', 'cycles': 'Stall cycles', 'cause': 'Cause'},
                    )
                    fig_stall.update_layout(
                        height=450, xaxis_tickangle=-45,
                        legend=dict(orientation='h', y=-0.3, yanchor='top'),
                    )
                    st.plotly_chart(fig_stall)

                    st.markdown('---')

                    # Percentage view: stall cause as % of total stalls per test
                    st.subheader('Stall Cause Distribution (%)')
                    st.caption(
                        'Each bar shows 100% of stall cycles for a test, split by cause. '
                        'Useful for comparing the relative importance of each stall cause '
                        'across different workloads.'
                    )
                    fig_stall_pct = px.bar(
                        stall_df[stall_df['pct'] > 0],
                        x='test', y='pct', color='cause',
                        barmode='stack',
                        labels={'test': '', 'pct': 'Stall %', 'cause': 'Cause'},
                    )
                    fig_stall_pct.update_layout(
                        height=450, xaxis_tickangle=-45,
                        legend=dict(orientation='h', y=-0.3, yanchor='top'),
                    )
                    st.plotly_chart(fig_stall_pct)

                    st.markdown('---')

                    # Aggregate table: average stall % per cause across all tests
                    st.subheader('Average Stall Cause (across all tests)')
                    st.caption(
                        'Mean and standard deviation of each stall cause percentage '
                        'across all tests. Causes with high mean and low std are '
                        'consistent bottlenecks worth optimizing.'
                    )
                    agg_stall = (stall_df.groupby('cause', as_index=False)
                                 .agg(cycles_mean=('cycles', 'mean'),
                                      cycles_std=('cycles', 'std'),
                                      pct_mean=('pct', 'mean'),
                                      pct_std=('pct', 'std'))
                                 .round(1)
                                 .sort_values('pct_mean', ascending=False))
                    agg_stall.columns = ['Cause', 'Cycles (mean)', 'Cycles (std)',
                                         '% (mean)', '% (std)']
                    st.dataframe(agg_stall, hide_index=True, width='stretch')
                    _copyable_table(agg_stall, 'Copy stall averages as text')

            _pl_fragment()

    # ── Tab: Branch Prediction ─────────────────────────────────────────────────
    if bp_tests:
        _SCHEME_LABELS = {
            'bimodal_1bit': '1-bit bimodal',
            'bimodal_2bit': '2-bit bimodal',
            'gshare':       'GShare',
            'micro_tage':   'Micro-TAGE',
            'tournament':   'Tournament',
        }

        # Discover available micro-TAGE and tournament variants from data
        _UTAGE_VARIANTS = []
        _TOURNAMENT_VARIANTS = []
        for t in bp_tests:
            sweep = latest_bundles.get(t, {}).get('branch_prediction', {}).get('size_sweep', pd.DataFrame())
            if not sweep.empty:
                for s in sweep['scheme'].unique():
                    if s.startswith('micro_tage_') and s not in _UTAGE_VARIANTS:
                        _UTAGE_VARIANTS.append(s)
                    elif s.startswith('tournament_') and s not in _TOURNAMENT_VARIANTS:
                        _TOURNAMENT_VARIANTS.append(s)
                break  # all tests have the same variants

        def _utage_label(s):
            """Format micro_tage_B32T8w6 → 'B32 T8 w6'."""
            return s.replace('micro_tage_', '').replace('B', 'B').replace('T', ' T').replace('w', ' w')

        def _tournament_label(s):
            """Format tournament_64 → '64 entries'."""
            return s.replace('tournament_', '') + ' entries'

        _tab_idx_bp = tab_labels.index('Branch Prediction')
        with tabs[_tab_idx_bp]:
            @st.fragment
            def _bp_fragment():
                bp_col1, bp_col2, bp_col3 = st.columns([2, 3, 1])
                with bp_col1:
                    bp_snap = st.selectbox('Snapshot', all_options, key='bp_snap')
                with bp_col2:
                    bp_family = st.radio(
                        'Scheme',
                        list(_SCHEME_LABELS.keys()),
                        format_func=lambda k: _SCHEME_LABELS[k],
                        horizontal=True,
                        key='bp_scheme',
                    )
                with bp_col3:
                    show_avg = st.checkbox('Show average', key='bp_avg')

                # Determine if this is a multi-variant family
                is_multi = (
                    (bp_family == 'micro_tage' and _UTAGE_VARIANTS) or
                    (bp_family == 'tournament' and _TOURNAMENT_VARIANTS)
                )

                variants: list   = []
                var_labels: dict = {}
                bp_scheme        = bp_family

                if is_multi:
                    if bp_family == 'micro_tage':
                        variants = _UTAGE_VARIANTS
                        var_labels = {v: _utage_label(v) for v in variants}
                    else:
                        variants = _TOURNAMENT_VARIANTS
                        var_labels = {v: _tournament_label(v) for v in variants}
                    display_label = _SCHEME_LABELS[bp_family]
                else:
                    display_label = _SCHEME_LABELS[bp_family]

                fig_bp = go.Figure()
                snap_bundles = _load_bundles(bp_snap, snap_root, latest_bundles)

                avg_accum = {}
                x_labels: list = []

                if is_multi:
                    # ── Multi-variant chart: X = variant label ────────────────
                    # Prepend BTFN as baseline anchor
                    x_labels = ['BTFN'] + [var_labels[v] for v in variants]

                    for test in bp_tests:
                        bp = snap_bundles.get(test, {}).get('branch_prediction', {})
                        sweep = bp.get('size_sweep', pd.DataFrame())
                        if sweep.empty:
                            continue
                        # Get BTFN value (table_bits=0 for first variant)
                        btfn_row = sweep[(sweep['scheme'] == variants[0]) & (sweep['table_bits'] == 0)]
                        btfn_val = float(btfn_row['mispredict_pct'].iloc[0]) if not btfn_row.empty else None
                        y_vals = [btfn_val]
                        for v in variants:
                            row = sweep[(sweep['scheme'] == v) & (sweep['table_bits'] != 0)]
                            val = float(row['mispredict_pct'].iloc[0]) if not row.empty else None
                            y_vals.append(val)
                        if all(v is None for v in y_vals):
                            continue
                        trace_kw = {}
                        if show_avg:
                            trace_kw['opacity'] = 0.25
                            trace_kw['line']    = dict(width=1)
                            trace_kw['marker']  = dict(size=4)
                        fig_bp.add_trace(go.Scatter(
                            x=x_labels, y=y_vals,
                            mode='lines+markers', name=test,
                            **trace_kw,
                        ))
                        for i, val in enumerate(y_vals):
                            if val is not None:
                                avg_accum.setdefault(x_labels[i], []).append(val)

                    if show_avg and avg_accum:
                        avg_x = [l for l in x_labels if l in avg_accum]
                        avg_y = [sum(avg_accum[l]) / len(avg_accum[l]) for l in avg_x]
                        fig_bp.add_trace(go.Scatter(
                            x=avg_x, y=avg_y,
                            mode='lines+markers', name='Average',
                            line=dict(width=5, color='crimson', dash='solid'),
                            marker=dict(size=10, color='crimson'),
                        ))

                    fig_bp.update_layout(
                        xaxis_title='Variant',
                        yaxis_title='Misprediction %',
                        title=f'{display_label} — {bp_snap}',
                        legend=dict(
                            orientation='v',
                            x=1.02, xanchor='left',
                            y=1,    yanchor='top',
                        ),
                        margin=dict(t=40, r=200),
                        height=500,
                        xaxis=dict(type='category'),
                    )
                else:
                    # ── Single-scheme chart: X = table_bits ──────────────────
                    bp_scheme = bp_family
                    for test in bp_tests:
                        bp = snap_bundles.get(test, {}).get('branch_prediction', {})
                        sweep = bp.get('size_sweep', pd.DataFrame())
                        if sweep.empty:
                            continue
                        rows_scheme = sweep[sweep['scheme'] == bp_scheme]
                        if rows_scheme.empty:
                            continue
                        trace_kw = {}
                        if show_avg:
                            trace_kw['opacity'] = 0.25
                            trace_kw['line']    = dict(width=1)
                            trace_kw['marker']  = dict(size=4)
                        fig_bp.add_trace(go.Scatter(
                            x=rows_scheme['table_bits'],
                            y=rows_scheme['mispredict_pct'],
                            mode='lines+markers', name=test,
                            **trace_kw,
                        ))
                        for _, row in rows_scheme.iterrows():
                            avg_accum.setdefault(row['table_bits'], []).append(row['mispredict_pct'])

                    if show_avg and avg_accum:
                        avg_bits = sorted(avg_accum.keys())
                        avg_vals = [sum(avg_accum[b]) / len(avg_accum[b]) for b in avg_bits]
                        fig_bp.add_trace(go.Scatter(
                            x=avg_bits, y=avg_vals,
                            mode='lines+markers', name='Average',
                            line=dict(width=5, color='crimson', dash='solid'),
                            marker=dict(size=10, color='crimson'),
                        ))

                    fig_bp.update_layout(
                        xaxis_title='Table index bits (N)',
                        yaxis_title='Misprediction %',
                        title=f'{display_label} — {bp_snap}',
                        legend=dict(
                            orientation='v',
                            x=1.02, xanchor='left',
                            y=1,    yanchor='top',
                        ),
                        margin=dict(t=40, r=200),
                        height=500,
                    )
                    fig_bp.update_xaxes(
                        tickvals=[0, 2, 3, 4, 5, 6, 7, 8, 10, 12],
                        ticktext=['BTFN', '2b (4)', '3b (8)', '4b (16)', '5b (32)', '6b (64)',
                                  '7b (128)', '8b (256)', '10b (1024)', '12b (4096)'],
                    )

                st.plotly_chart(fig_bp)

                # ── Text summary table ────────────────────────────────────────
                if avg_accum:
                    if is_multi:
                        col_keys   = [l for l in x_labels if l in avg_accum]
                        col_labels = {l: l for l in col_keys}
                    else:
                        _TICK_LABELS = {
                            0: 'BTFN', 2: '4', 3: '8', 4: '16', 5: '32',
                            6: '64', 7: '128', 8: '256', 10: '1K', 12: '4K',
                        }
                        col_keys   = sorted(avg_accum.keys())
                        col_labels = {b: _TICK_LABELS.get(b, str(b)) for b in col_keys}

                    # Determine column width for alignment
                    max_lbl = max(len(col_labels[k]) for k in col_keys)
                    cw = max(6, max_lbl + 1)

                    hdr = f'{"Benchmark":<25}'
                    for k in col_keys:
                        hdr += f'  {col_labels[k]:>{cw}}'
                    lines = [f'{display_label} — {bp_snap}', '', hdr,
                             '-' * len(hdr)]

                    for test in bp_tests:
                        bp_data = snap_bundles.get(test, {}).get('branch_prediction', {})
                        sweep = bp_data.get('size_sweep', pd.DataFrame())
                        if sweep.empty:
                            continue
                        if is_multi:
                            vals = {}
                            # BTFN anchor value
                            btfn_r = sweep[(sweep['scheme'] == variants[0]) & (sweep['table_bits'] == 0)]
                            if not btfn_r.empty:
                                vals['BTFN'] = float(btfn_r['mispredict_pct'].iloc[0])
                            for v in variants:
                                r = sweep[(sweep['scheme'] == v) & (sweep['table_bits'] != 0)]
                                if not r.empty:
                                    vals[var_labels[v]] = float(r['mispredict_pct'].iloc[0])
                        else:
                            rs = sweep[sweep['scheme'] == bp_scheme]
                            if rs.empty:
                                continue
                            vals = {int(r['table_bits']): r['mispredict_pct']
                                    for _, r in rs.iterrows()}
                        if not vals:
                            continue
                        row_str = f'{test:<25}'
                        for k in col_keys:
                            v = vals.get(k)
                            row_str += f'  {v:{cw}.1f}' if v is not None else ' ' * (cw + 2)
                        lines.append(row_str)

                    avg_line = f'{"— Average —":<25}'
                    for k in col_keys:
                        vs = avg_accum[k]
                        avg_line += f'  {sum(vs)/len(vs):{cw}.1f}'
                    lines.append('-' * len(hdr))
                    lines.append(avg_line)

                    with st.expander('Text summary (copy-paste friendly)'):
                        st.code('\n'.join(lines), language=None)

            _bp_fragment()

    # ── Snapshot metadata ──────────────────────────────────────────────────────
    shown = [s for s in snap_names if s != _LATEST]
    if shown:
        with st.expander('Snapshot details'):
            for sn in shown:
                mf  = manifests.get(sn, {})
                git = mf.get('git', {})
                rtl = mf.get('rtl', {})
                if mf.get('_virtual'):
                    st.markdown(f'**{sn}** — embench reference platform baseline')
                    continue
                c1, c2, c3, c4 = st.columns(4)
                c1.markdown(f'**{sn}**')
                c2.caption(f"Date: {mf.get('timestamp', '—')}")
                c3.caption(
                    f"Git: {git.get('branch', '—')}@{git.get('commit', '—')} "
                    f"— {git.get('message', '—')}"
                )
                c4.caption(f"Desc: {mf.get('description', '—') or '—'}")
                if rtl:
                    st.caption('  '.join(f'{k}: {v}' for k, v in rtl.items()))
