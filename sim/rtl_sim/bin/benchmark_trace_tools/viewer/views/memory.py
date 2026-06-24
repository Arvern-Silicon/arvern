#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    memory.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: memory-access analysis.
#----------------------------------------------------------------------------

"""Memory view — load/store patterns, strides, SP-relative, load-use distance."""

import streamlit as st
import pandas as pd
import plotly.express as px

from ._utils import kpi, section, pie, show_table


def render(stats: dict):
    st.title('Memory Access Analysis')

    mem          = stats.get('memory', {})
    total_loads  = mem.get('total_loads',  0)
    total_stores = mem.get('total_stores', 0)
    total_acc    = total_loads + total_stores

    if total_acc == 0:
        st.warning('No memory accesses found in this trace.')
        return

    c1, c2, c3, c4 = st.columns(4)
    kpi(c1, 'Total accesses', f'{total_acc:,}',
        help='Total load + store instructions executed.')
    kpi(c2, 'Loads', f'{total_loads:,}',
        help='LB / LH / LW / LBU / LHU instructions (including compressed variants).')
    kpi(c3, 'Stores', f'{total_stores:,}',
        help='SB / SH / SW instructions (including compressed variants).')
    kpi(c4, 'Load/Store ratio', f'{mem.get("load_store_ratio", 0):.2f}',
        help='Ratio of loads to stores. Values > 1 mean more loads than stores, '
             'typical for read-heavy algorithms. Values < 1 indicate write-heavy code.')

    st.markdown('---')

    section('Access Size Distribution')
    st.caption(
        'Breakdown of memory accesses by transfer size. '
        '**Byte (8-bit)**: LB/SB — common for char arrays and packed data. '
        '**Halfword (16-bit)**: LH/SH — UTF-16, audio samples. '
        '**Word (32-bit)**: LW/SW — most common for int/pointer access on RV32.'
    )
    size_df = mem.get('access_size', pd.DataFrame())
    if not size_df.empty:
        col1, col2 = st.columns(2)
        with col1:
            fig = pie(size_df, names='size', values='count', title='Access sizes')
            st.plotly_chart(fig)
        with col2:
            show_table(size_df)

    st.markdown('---')

    section('Stack (SP-relative) Accesses')
    kpi(st.columns(1)[0], 'SP-relative %',
        f'{mem.get("sp_relative_pct", 0):.1f}%',
        help='Percentage of memory accesses that use the stack pointer (x2/sp) '
             'as the base register. High values indicate a stack-heavy workload '
             '(local variables, spills, function call frames).')

    st.markdown('---')

    section('Address Stride Pattern')
    st.caption(
        'Difference between consecutive memory access addresses. '
        '**Stride = 4**: sequential 32-bit word access (e.g. array traversal). '
        '**Stride = 0**: repeated access to the same address (e.g. polling a register). '
        'Regular strides indicate good spatial locality and are prefetch-friendly.'
    )
    stride_hist = mem.get('stride_hist', pd.DataFrame())
    if not stride_hist.empty:
        fig2 = px.bar(stride_hist, x='stride', y='count',
                      title='Address stride histogram',
                      labels={'stride': 'Stride (bytes)', 'count': 'Occurrences'})
        st.plotly_chart(fig2)

    st.markdown('---')

    section('Load-to-Use Distance')
    st.caption(
        'Number of instructions between a LOAD and the instruction that reads '
        'the loaded register. **Distance = 1** means the very next instruction '
        'uses the loaded value — this causes a **load-use hazard** and requires '
        'a 1-cycle stall in the arvern pipeline. '
        'Distance ≥ 2 allows the pipeline to hide the latency.'
    )
    ltu_hist = mem.get('load_use_dist_hist', pd.DataFrame())
    if not ltu_hist.empty:
        fig3 = px.bar(ltu_hist, x='distance', y='count',
                      title='Instructions between load and use of loaded register',
                      labels={'distance': 'Distance (instructions)', 'count': 'Count'})
        fig3.add_vline(x=1, line_dash='dash', line_color='red',
                       annotation_text='Load-use hazard (1-cycle stall)')
        st.plotly_chart(fig3)

    st.markdown('---')

    section('Address Range')
    addr = mem.get('addr_range', {})
    c1, c2, c3 = st.columns(3)
    kpi(c1, 'Min address', f'0x{addr.get("min", 0):08x}',
        help='Lowest memory address accessed during the trace.')
    kpi(c2, 'Max address', f'0x{addr.get("max", 0):08x}',
        help='Highest memory address accessed during the trace.')
    kpi(c3, 'Span', f'0x{addr.get("span", 0):08x}',
        help='Total address range covered (max - min). '
             'A large span may indicate poor spatial locality.')
