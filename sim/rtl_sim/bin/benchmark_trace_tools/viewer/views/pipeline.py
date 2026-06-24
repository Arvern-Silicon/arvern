#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    pipeline.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: pipeline-stage analysis.
#----------------------------------------------------------------------------

"""Pipeline view — CPI, IPC, stall analysis."""

import streamlit as st
import pandas as pd
import plotly.express as px

from ._utils import kpi, section, bar, show_table


def render(stats: dict):
    st.title('Pipeline Analysis')

    pipe      = stats.get('pipeline', {})
    stall_pct = round(pipe.get('stall_rate', 0) * 100, 1)

    c1, c2, c3, c4, c5 = st.columns(5)
    kpi(c1, 'Total Instructions', f'{pipe.get("total_instructions", 0):,}',
        help='Total instructions retired during the simulation.')
    kpi(c2, 'Total Cycles', f'{pipe.get("total_cycles", 0):,}',
        help='Clock cycles from first to last instruction.')
    kpi(c3, 'IPC', f'{pipe.get("ipc", 0):.3f}',
        help='Instructions Per Cycle. Theoretical maximum is 1.0 '
             'for a single-issue in-order pipeline. Higher is better.')
    kpi(c4, 'CPI', f'{pipe.get("cpi", 0):.3f}',
        help='Cycles Per Instruction — inverse of IPC. '
             'Ideal is 1.0. Every stall cycle adds to this value.')
    kpi(c5, 'Stall %', f'{stall_pct:.1f}%',
        help='Fraction of cycles wasted in stalls. '
             'Breakdown by cause shown below.')

    st.markdown('---')

    # ── Stall breakdown ────────────────────────────────────────────────────────
    section('Stall Breakdown')
    st.caption(
        '**Load-use hazard**: the instruction after a LOAD reads the loaded register — '
        'pipeline waits 1 cycle for data. '
        '**MUL/DIV multi-cycle**: multiply and divide units take multiple cycles. '
        '**Memory wait state**: AHB bus inserted wait states (slow memory). '
        '**Branch taken/not-taken**: pipeline bubble from branch resolution. '
        '**Jump**: redirect penalty for JAL/JALR. '
        '**Zcmp/Zcmt multi-cycle**: compressed stack (PUSH/POP) and table jump instructions. '
        '**CSR/System**: CSR access or system instruction overhead. '
        '**Fetch wait state**: instruction AHB bus wait states (slow ROM/flash).'
    )
    stalls_df = pipe.get('stalls_by_cause', pd.DataFrame())
    if not stalls_df.empty:
        active = stalls_df[stalls_df['cycles'] > 0]
        if not active.empty:
            col_c, col_t = st.columns([1, 1])
            with col_c:
                fig = px.bar(active, x='cause', y='cycles',
                             title='Stall cycles by cause',
                             labels={'cause': 'Cause', 'cycles': 'Cycles'},
                             color='cause',
                             color_discrete_sequence=px.colors.qualitative.Set2)
                fig.update_layout(showlegend=False)
                st.plotly_chart(fig)
            with col_t:
                show_table(active)
        else:
            st.info('No stalls detected in this trace.')

    st.markdown('---')

    # ── CPI per instruction category ──────────────────────────────────────────
    section('CPI per Instruction Category')
    st.caption(
        'CPI broken down by instruction type. Categories with CPI > 1 are '
        'contributing most to pipeline inefficiency. The red dashed line '
        'shows the overall CPI.'
    )
    cpi_cat = pipe.get('cpi_by_category', pd.DataFrame())
    if not cpi_cat.empty:
        fig2 = bar(cpi_cat, x='category', y='cpi', title='CPI per Category',
                   xlabel='Category', ylabel='CPI')
        cpi_val = pipe.get('cpi', 1.0)
        fig2.add_hline(y=cpi_val, line_dash='dash', line_color='red',
                       annotation_text=f'Overall CPI={cpi_val:.3f}')
        st.plotly_chart(fig2)
        show_table(cpi_cat)
