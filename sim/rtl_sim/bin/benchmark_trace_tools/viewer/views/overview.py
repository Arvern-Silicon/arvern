#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    overview.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: overall benchmark overview.
#----------------------------------------------------------------------------

"""Overview view — trace metadata + high-level KPIs."""

import streamlit as st
from ._utils import kpi, section, CAT_COLORS, pie, show_table


def render(stats: dict):
    meta = stats.get('metadata', {})
    test_name = meta.get('Test', 'Unknown')
    st.title(f'Overview — {test_name}')

    # ── Pipeline KPIs ──────────────────────────────────────────────────────────
    section('Performance Summary')
    pipe = stats.get('pipeline', {})
    metrics = stats.get('_metrics', {})

    score_val = metrics.get('score_value') if metrics else None
    score_unit = metrics.get('score_unit', '') if metrics else ''

    if score_val is not None:
        c1, c2, c3, c4, c5, c6 = st.columns(6)
        kpi(c1, 'Benchmark Score', f'{score_val:,.2f}',
            help='Benchmark score reported by the test program.')
    else:
        c2, c3, c4, c5, c6 = st.columns(5)
    kpi(c2, 'Total Instructions', f'{pipe.get("total_instructions", 0):,}',
        help='Total number of instructions retired during the simulation.')
    kpi(c3, 'Total Cycles', f'{pipe.get("total_cycles", 0):,}',
        help='Total clock cycles from first to last instruction.')
    kpi(c4, 'IPC', f'{pipe.get("ipc", 0):.3f}',
        help='Instructions Per Cycle. Higher is better. '
             'Theoretical maximum is 1.0 for a single-issue in-order pipeline.')
    kpi(c5, 'CPI', f'{pipe.get("cpi", 0):.3f}',
        help='Cycles Per Instruction. Lower is better. '
             'Inverse of IPC. Ideal value is 1.0. '
             'Values above 1.0 indicate stall cycles.')
    kpi(c6, 'Stall %', f'{pipe.get("stall_rate", 0)*100:.1f}%',
        help='Percentage of cycles lost to pipeline stalls. '
             'Caused by load-use hazards, multi-cycle MUL/DIV, '
             'or memory wait states.')

    st.markdown('---')

    # ── Instruction mix ────────────────────────────────────────────────────────
    section('Instruction Mix')
    mix    = stats.get('instmix', {})
    cat_df = mix.get('by_category', None)

    if cat_df is not None and not cat_df.empty:
        col_c, col_t = st.columns([1, 1])
        with col_c:
            fig = pie(cat_df, names='category', values='count',
                      title='Instructions by Category', color_map=CAT_COLORS)
            st.plotly_chart(fig)
        with col_t:
            show_table(cat_df, height=350)

    ext_sum = mix.get('ext_summary', None)
    ext_pcts = {}
    if ext_sum is not None and not ext_sum.empty:
        ext_pcts = dict(zip(ext_sum['extension'], ext_sum['pct']))

    c1, c2, c3, c4, c5, c6 = st.columns(6)
    kpi(c1, 'Standard %', f'{ext_pcts.get("Standard (RV32I)", 0):.1f}%',
        help='Percentage of base RV32I instructions.')
    kpi(c2, 'C (Compressed) %', f'{ext_pcts.get("C (Compressed)", 0):.1f}%',
        help='Percentage of 16-bit compressed extension instructions.')
    kpi(c3, 'M (Mul/Div) %', f'{ext_pcts.get("M (Mul/Div)", 0):.1f}%',
        help='Percentage of multiply/divide extension instructions.')
    kpi(c4, 'B (Bit-manip) %', f'{ext_pcts.get("B (Bit-manip)", 0):.1f}%',
        help='Percentage of bit-manipulation extension instructions.')
    kpi(c5, 'Unique PCs', f'{stats.get("pc_nunique", 0):,}',
        help='Number of distinct program counter values executed. '
             'Approximates the number of unique instructions in the hot path.')
    kpi(c6, 'Instr types', str(stats.get('mnem_nunique', 0)),
        help='Number of distinct instruction mnemonics seen in this trace.')

    st.markdown('---')

    # ── Metadata ───────────────────────────────────────────────────────────────
    section('Trace Metadata')
    col1, col2, col3 = st.columns(3)
    with col1:
        st.markdown('**Run info**')
        for k in ('Test', 'Mode', 'Variant', 'Simulator', 'Date'):
            v = meta.get(k, '')
            if v:
                st.markdown(f'- **{k}**: `{v}`')
    with col2:
        st.markdown('**RTL configuration**')
        for k, v in meta.get('rtl', {}).items():
            st.markdown(f'- **{k}**: `{v}`')
    with col3:
        st.markdown('**Toolchain**')
        for k, v in meta.get('toolchain', {}).items():
            st.markdown(f'- **{k}**: `{v}`')
        bm = meta.get('benchmark', {})
        if bm:
            st.markdown('**Benchmark**')
            for k, v in bm.items():
                st.markdown(f'- **{k.capitalize()}**: `{v}`')
