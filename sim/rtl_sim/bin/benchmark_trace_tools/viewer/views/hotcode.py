#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    hotcode.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: hot-code (frequency) analysis.
#----------------------------------------------------------------------------

"""Hot Code view — most executed PC addresses."""

import streamlit as st
import plotly.express as px

from ._utils import kpi, section, show_table


def render(stats: dict):
    st.title('Hot Code — PC Execution Frequency')
    st.caption(
        'Identifies the **hottest instruction addresses** — the program counter (PC) values '
        'that were executed most often. Hot PCs are prime candidates for optimization: '
        'inlining, loop unrolling, or custom hardware acceleration. '
        '**PC** = Program Counter (address of the instruction in memory).'
    )

    hot      = stats.get('hotcode', {})
    top_pcs  = hot.get('top_pcs',  None)
    all_pcs  = hot.get('pc_hist',  None)

    if top_pcs is None or top_pcs.empty:
        st.warning('No PC execution data available.')
        return

    unique_pcs = len(all_pcs) if all_pcs is not None else len(top_pcs)

    c1, c2, c3 = st.columns(3)
    kpi(c1, 'Unique PCs executed', f'{unique_pcs:,}',
        help='Number of distinct instruction addresses executed at least once. '
             'A small value relative to total instructions indicates a tight, '
             'loop-dominated workload with high temporal locality.')
    kpi(c2, 'Hottest PC', str(top_pcs.iloc[0]['pc_hex']),
        help='Address of the single most-executed instruction. '
             'This is usually the back-edge branch of the innermost hot loop.')
    kpi(c3, 'Hottest PC count', f'{top_pcs.iloc[0]["count"]:,}',
        help='Number of times the hottest instruction was executed. '
             'Divide by total instructions to get the fraction of runtime spent there.')

    st.markdown('---')

    top_k = st.slider('Top N', 10, min(200, len(top_pcs)), 50, key='hc_topn')
    display = top_pcs.head(top_k)

    section(f'Top {top_k} Hottest PC Addresses')
    st.caption(
        'Each bar represents one instruction address. '
        'The **category** column (hover) shows the instruction type at that address. '
        'Tightly clustered hot PCs indicate a small hot loop; '
        'spread-out hot PCs suggest a more diverse workload.'
    )
    fig = px.bar(display, x='pc_hex', y='count',
                 title=f'Top {top_k} most executed PCs',
                 labels={'pc_hex': 'PC address', 'count': 'Execution count'},
                 color='count', color_continuous_scale='Reds',
                 hover_data=['category', 'pct'])
    fig.update_xaxes(tickangle=45, type='category')
    st.plotly_chart(fig)

    st.markdown('---')
    section('Table')
    st.caption('**pct**: percentage of all executed instructions at this address. '
               '**category**: instruction class (ALU, LOAD, BRANCH, etc.).')
    show_table(display)
