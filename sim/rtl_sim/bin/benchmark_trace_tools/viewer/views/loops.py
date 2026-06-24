#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    loops.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: loop detection and counts.
#----------------------------------------------------------------------------

"""Loops view — back-edge detection, trip counts, loop body analysis."""

import streamlit as st
import pandas as pd
import plotly.express as px

from ._utils import kpi, section, show_table


def render(stats: dict):
    st.title('Loop Analysis')
    st.caption(
        'Loops are detected by **back-edges**: branches whose target address is '
        'lower than the branch itself (jumps backward). Each back-edge defines '
        'a loop site. The statistics below are inferred from the execution trace — '
        'no debug symbols or source code required.'
    )

    lp    = stats.get('loops', {})
    sites = lp.get('loop_sites', pd.DataFrame())

    if lp.get('total_back_branches', 0) == 0:
        st.warning('No back-edges (loop branches) found in this trace.')
        return

    c1, c2, c3 = st.columns(3)
    kpi(c1, 'Back-branch count', f'{lp["total_back_branches"]:,}',
        help='Total number of backward branch instructions executed. '
             'Each execution represents one loop iteration.')
    kpi(c2, 'Back-branch %', f'{lp.get("back_branch_pct", 0):.1f}%',
        help='Fraction of all branch instructions that are backward branches. '
             'High values indicate a loop-dominated workload.')
    kpi(c3, 'Distinct loop sites', str(len(sites)),
        help='Number of unique (branch PC, target PC) pairs observed. '
             'Each pair corresponds to one loop in the program.')

    st.markdown('---')

    section('Trip Count Distribution')
    st.caption(
        'A **trip count** is the number of times a loop iterates before the '
        'branch falls through (loop exits). '
        '**Trip = 1**: loop ran only once — effectively an if-statement. '
        '**High trip count**: hot inner loop — prime optimization target.'
    )
    trip_hist = lp.get('trip_count_histogram', pd.DataFrame())
    if not trip_hist.empty:
        fig = px.bar(trip_hist, x='trip_bin', y='count',
                     title='Loop trip count distribution',
                     labels={'trip_bin': 'Trip count', 'count': 'Occurrences'})
        st.plotly_chart(fig)

    st.markdown('---')

    section('Loop Sites')
    st.caption(
        '**back_edge_pc**: address of the backward branch instruction. '
        '**target_pc**: branch target (loop header address). '
        '**body_size**: approximate instruction count in the loop body '
        '(computed as (back_edge_pc − target_pc) / 4). '
        '**trips**: total number of times this loop was entered. '
        '**avg_trip_cnt**: average iterations per entry.'
    )
    if not sites.empty:
        show_table(sites)

    st.markdown('---')

    section('Loop Body Size Distribution')
    st.caption(
        'Distribution of loop body sizes (approximate instruction count). '
        '**Tight loops (< 8 instructions)** are the most impactful targets for '
        'loop unrolling, software pipelining, and SIMD vectorization. '
        '**Large loops (> 64 instructions)** may benefit from function outlining '
        'or algorithmic improvements.'
    )
    if not sites.empty:
        fig2 = px.histogram(sites, x='body_size', nbins=30,
                            title='Loop body size (approx. instruction count)',
                            labels={'body_size': 'Body size (instructions)'})
        st.plotly_chart(fig2)
