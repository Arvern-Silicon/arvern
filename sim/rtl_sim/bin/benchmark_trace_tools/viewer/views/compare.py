#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    compare.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: side-by-side trace comparison.
#----------------------------------------------------------------------------

"""Compare view — side-by-side comparison of two pre-computed stats bundles."""

import streamlit as st
import pandas as pd
import plotly.graph_objects as go

from ._utils import kpi, section, show_table


def _copyable_table(df: pd.DataFrame, label: str = 'Copy as text'):
    """Show a dataframe as tab-separated text inside an expander for easy copy-paste."""
    with st.expander(label):
        st.code(df.to_string(index=False), language=None)


def _bundle_label(bundle: dict) -> str:
    meta  = bundle.get('metadata', {})
    parts = [meta.get('Test', ''), meta.get('Mode', ''),
             meta.get('toolchain', {}).get('Optimization', '')]
    parts = [p for p in parts if p]
    return '  |  '.join(parts) if parts else bundle.get('filename', '?')


def _pct_delta(a, b):
    try:
        d = (float(b) - float(a)) / abs(float(a)) * 100
        return f'{d:+.1f}%'
    except (TypeError, ValueError, ZeroDivisionError):
        return None


def render(bundle_a: dict, bundle_b: dict):
    st.title('Trace Comparison')
    st.caption(
        'Side-by-side comparison of two execution traces. '
        'Use this view to compare different **test programs**, **compiler options** '
        '(e.g. -O0 vs -O2), **ISA extensions** (with/without C or M), or '
        '**hardware configurations**. '
        'Green deltas (B vs A) are improvements; red are regressions — '
        'except for CPI and stall rate where lower is better.'
    )

    default_la = _bundle_label(bundle_a)
    default_lb = _bundle_label(bundle_b)
    if default_la == default_lb:
        default_la += ' (A)'
        default_lb += ' (B)'

    # Reset labels when the selected traces change
    path_a = bundle_a.get('path', '')
    path_b = bundle_b.get('path', '')
    if st.session_state.get('_cmp_path_a') != path_a:
        st.session_state['_cmp_path_a'] = path_a
        st.session_state['cmp_la'] = default_la
    if st.session_state.get('_cmp_path_b') != path_b:
        st.session_state['_cmp_path_b'] = path_b
        st.session_state['cmp_lb'] = default_lb

    la = st.text_input('Label A', key='cmp_la')
    lb = st.text_input('Label B', key='cmp_lb')
    if la == lb:
        la += ' (A)'
        lb += ' (B)'

    pa = bundle_a.get('pipeline', {})
    pb = bundle_b.get('pipeline', {})
    ma = bundle_a.get('_metrics', {}) or {}
    mb = bundle_b.get('_metrics', {}) or {}

    # ── Benchmark Score & Size ────────────────────────────────────────────────
    score_a = ma.get('score_value')
    score_b = mb.get('score_value')
    size_a = ma.get('total_size')
    size_b = mb.get('total_size')

    if score_a is not None or score_b is not None or size_a is not None or size_b is not None:
        section('Benchmark Score & Binary Size')
        cols = st.columns(4)
        if score_a is not None:
            kpi(cols[0], f'Score  {la}', f'{score_a:,.2f}',
                help='Benchmark score for trace A. Higher is better.')
        if score_b is not None:
            kpi(cols[1], f'Score  {lb}', f'{score_b:,.2f}',
                delta=_pct_delta(score_a, score_b) if score_a else None,
                help='Benchmark score for trace B. Positive delta means B is faster.')
        if size_a is not None:
            kpi(cols[2], f'Binary  {la}', f'{size_a:,} B',
                help='Total binary size for trace A (text + data + bss).')
        if size_b is not None:
            kpi(cols[3], f'Binary  {lb}', f'{size_b:,} B',
                delta=_pct_delta(size_a, size_b) if size_a else None,
                help='Total binary size for trace B. Negative delta means smaller code.')
        st.markdown('---')

    # ── Pipeline KPIs ──────────────────────────────────────────────────────────
    section('Pipeline KPIs')
    st.caption(
        '**IPC** (Instructions Per Cycle): higher is better — measures how many instructions '
        'the processor completes each clock cycle. Maximum is 1 for a scalar in-order pipeline. '
        '**CPI** (Cycles Per Instruction): reciprocal of IPC — lower is better. '
        '**Stall %**: fraction of cycles where the pipeline is stalled (load-use hazards, '
        'multiply/divide latency, memory wait states). Lower is better.'
    )

    c1, c2, c3, c4 = st.columns(4)
    kpi(c1, f'IPC  {la}',  f'{pa.get("ipc", 0):.3f}',
        help='Instructions Per Cycle for trace A. Higher = better pipeline utilization.')
    kpi(c2, f'IPC  {lb}',  f'{pb.get("ipc", 0):.3f}',
        delta=_pct_delta(pa.get('ipc'), pb.get('ipc')),
        help='Instructions Per Cycle for trace B. Positive delta means B is faster.')
    kpi(c3, f'CPI  {la}',  f'{pa.get("cpi", 0):.3f}',
        help='Cycles Per Instruction for trace A. Lower = fewer stalls.')
    kpi(c4, f'CPI  {lb}',  f'{pb.get("cpi", 0):.3f}',
        delta=_pct_delta(pa.get('cpi'), pb.get('cpi')),
        help='Cycles Per Instruction for trace B. Negative delta means B is more efficient.')

    c5, c6, c7, c8 = st.columns(4)
    kpi(c5, f'Instrs  {la}', f'{pa.get("total_instructions", 0):,}',
        help='Total dynamic instruction count for trace A. '
             'Fewer instructions = compiler did more work (strength reduction, inlining, etc.).')
    kpi(c6, f'Instrs  {lb}', f'{pb.get("total_instructions", 0):,}',
        delta=_pct_delta(pa.get('total_instructions'), pb.get('total_instructions')),
        help='Total dynamic instruction count for trace B. '
             'Negative delta means B executed fewer instructions.')
    kpi(c7, f'Stall %  {la}', f'{pa.get("stall_rate", 0)*100:.1f}%',
        help='Pipeline stall rate for trace A: fraction of cycles where no instruction retired. '
             'Caused by load-use hazards, mul/div latency, or memory wait states.')
    kpi(c8, f'Stall %  {lb}', f'{pb.get("stall_rate", 0)*100:.1f}%',
        delta=_pct_delta(pa.get('stall_rate'), pb.get('stall_rate')),
        help='Pipeline stall rate for trace B. Negative delta means fewer stalls.')

    # Pipeline table
    pipe_rows = [
        {'metric': 'Instructions', la: pa.get('total_instructions'), lb: pb.get('total_instructions')},
        {'metric': 'Cycles',       la: pa.get('total_cycles'),       lb: pb.get('total_cycles')},
        {'metric': 'IPC',          la: pa.get('ipc'),                lb: pb.get('ipc')},
        {'metric': 'CPI',          la: pa.get('cpi'),                lb: pb.get('cpi')},
        {'metric': 'Stall cycles', la: pa.get('stall_cycles'),       lb: pb.get('stall_cycles')},
        {'metric': 'Stall rate',   la: pa.get('stall_rate'),         lb: pb.get('stall_rate')},
    ]
    if score_a is not None or score_b is not None:
        pipe_rows.insert(0, {'metric': 'Score', la: score_a, lb: score_b})
    if size_a is not None or size_b is not None:
        pipe_rows.append({'metric': 'Binary size (B)', la: size_a, lb: size_b})
    pipe_df = pd.DataFrame(pipe_rows)
    show_table(pipe_df)
    _copyable_table(pipe_df, 'Copy pipeline comparison as text')

    st.markdown('---')

    # ── Category distribution ──────────────────────────────────────────────────
    section('Category Distribution Comparison')
    st.caption(
        'Proportion of each **instruction category** (ALU, LOAD, STORE, BRANCH, JUMP, CSR, etc.) '
        'in each trace. A shift from ALU toward LOAD/STORE in trace B may indicate '
        'more memory traffic (pointer chasing, spills). '
        'A higher BRANCH % with unchanged taken rate suggests more conditional code.'
    )
    cat_a = bundle_a.get('instmix', {}).get('by_category', pd.DataFrame())
    cat_b = bundle_b.get('instmix', {}).get('by_category', pd.DataFrame())

    if not cat_a.empty and not cat_b.empty:
        merged = cat_a.merge(cat_b, on='category', how='outer',
                             suffixes=(f'_{la}', f'_{lb}')).fillna(0)
        fig = go.Figure()
        fig.add_trace(go.Bar(name=la, x=merged['category'],
                             y=merged[f'pct_{la}'], marker_color='steelblue'))
        fig.add_trace(go.Bar(name=lb, x=merged['category'],
                             y=merged[f'pct_{lb}'], marker_color='coral'))
        fig.update_layout(barmode='group', title='Category %  —  A vs B',
                          yaxis_title='%', xaxis_title='Category',
                          legend=dict(orientation='h', y=1.02, yanchor='bottom'))
        st.plotly_chart(fig)
        show_table(merged)
        _copyable_table(merged, 'Copy category comparison as text')

    st.markdown('---')

    # ── Mnemonic comparison ────────────────────────────────────────────────────
    section('Mnemonic Frequency Comparison (top 40)')
    st.caption(
        'Per-instruction frequency comparison. '
        '**delta_pct** = B% − A%: positive means trace B uses that instruction more. '
        'Large deltas on ADDI/LW/SW indicate changed data access patterns. '
        'A new MUL column in B suggests the M extension was enabled. '
        'C.* mnemonics (e.g. C.ADDI, C.LW) appear when the **C (compressed) extension** is active.'
    )
    mn_a = bundle_a.get('instmix', {}).get('by_mnem', pd.DataFrame())
    mn_b = bundle_b.get('instmix', {}).get('by_mnem', pd.DataFrame())

    if not mn_a.empty and not mn_b.empty:
        merged_mn = mn_a.merge(mn_b, on='mnem_base', how='outer',
                               suffixes=(f'_{la}', f'_{lb}')).fillna(0)
        merged_mn['delta_pct'] = (merged_mn[f'pct_{lb}']
                                  - merged_mn[f'pct_{la}']).round(3)
        merged_mn = merged_mn.sort_values(f'count_{la}', ascending=False)

        fig2 = go.Figure()
        top = merged_mn.head(30)
        fig2.add_trace(go.Bar(name=la, x=top['mnem_base'],
                              y=top[f'count_{la}'], marker_color='steelblue'))
        fig2.add_trace(go.Bar(name=lb, x=top['mnem_base'],
                              y=top[f'count_{lb}'], marker_color='coral'))
        fig2.update_layout(barmode='group', title='Mnemonic counts — A vs B',
                           yaxis_title='Count',
                           legend=dict(orientation='h', y=1.02, yanchor='bottom'))
        st.plotly_chart(fig2)

        show_table(merged_mn)
        _copyable_table(merged_mn, 'Copy mnemonic comparison as text')
