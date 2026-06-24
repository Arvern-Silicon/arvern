#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    registers.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: register usage statistics.
#----------------------------------------------------------------------------

"""Registers view — write/read heatmaps, reuse distance, pressure."""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

from ._utils import kpi, section, show_table


_ABI = ['zero','ra','sp','gp','tp','t0','t1','t2',
        's0','s1','a0','a1','a2','a3','a4','a5',
        'a6','a7','s2','s3','s4','s5','s6','s7',
        's8','s9','s10','s11','t3','t4','t5','t6']


def _freq_series(df):
    if df is None or df.empty:
        return pd.Series(dtype=int)
    return df.set_index('reg')['count']


def _heatmap(ser, title):
    nregs = 32
    data  = [int(ser.get(i, 0)) for i in range(nregs)]
    rows, cols = 4, 8
    z, text = [], []
    for r in range(rows):
        zr, tr = [], []
        for c in range(cols):
            i = r * cols + c
            zr.append(data[i])
            tr.append(f'x{i}/{_ABI[i]}<br>{data[i]:,}')
        z.append(zr)
        text.append(tr)
    fig = go.Figure(go.Heatmap(
        z=z, text=text, texttemplate='%{text}',
        colorscale='Blues', showscale=True,
        hovertemplate='%{text}<extra></extra>',
    ))
    fig.update_layout(
        title=title,
        xaxis=dict(showticklabels=False, showgrid=False),
        yaxis=dict(showticklabels=False, showgrid=False, autorange='reversed'),
        margin=dict(t=50, b=0), height=280,
    )
    return fig


def render(stats: dict):
    st.title('Register Pressure')
    st.caption(
        'Register pressure measures how intensively the 32 integer registers are used. '
        'High pressure on a small set of registers can indicate spilling opportunities '
        'or guide the compiler/programmer to restructure code.'
    )

    reg    = stats.get('registers', {})
    wr_ser = _freq_series(reg.get('write_freq'))
    r1_ser = _freq_series(reg.get('rs1_freq'))
    r2_ser = _freq_series(reg.get('rs2_freq'))

    c1, c2 = st.columns(2)
    kpi(c1, 'Caller-saved usage %', f'{reg.get("caller_saved_pct", 0):.1f}%',
        help='Fraction of register reads/writes on caller-saved registers '
             '(t0-t6, a0-a7). These must be saved by the caller before a call.')
    kpi(c2, 'Callee-saved usage %', f'{reg.get("callee_saved_pct", 0):.1f}%',
        help='Fraction of register reads/writes on callee-saved registers '
             '(s0-s11). These must be preserved across function calls by the callee.')

    st.markdown('---')

    section('Write Frequency (rd)')
    st.caption('How often each register is written. Darker = written more frequently. Hover for exact count.')
    if not wr_ser.empty:
        st.plotly_chart(_heatmap(wr_ser, 'Register write frequency'))

    col1, col2 = st.columns(2)
    with col1:
        section('Read Frequency — rs1')
        st.caption('rs1: first source operand (left-hand side of ALU ops, branch LHS, load/store base).')
        if not r1_ser.empty:
            st.plotly_chart(_heatmap(r1_ser, 'rs1 read frequency'))
    with col2:
        section('Read Frequency — rs2')
        st.caption('rs2: second source operand (right-hand side of ALU ops, branch RHS, store data).')
        if not r2_ser.empty:
            st.plotly_chart(_heatmap(r2_ser, 'rs2 read frequency'))

    st.markdown('---')

    section('Register Reuse Distance')
    st.caption(
        'Number of instructions between a register **write** and its next **read**. '
        '**Distance 1**: the very next instruction reads the result — forwarding path is used. '
        '**Distance 2-3**: short live range, register is used quickly. '
        '**Long distance**: register holds a value for many instructions (long live range) — '
        'may be a candidate for rematerialization or spilling.'
    )
    reuse = reg.get('reuse_dist', pd.DataFrame())
    if not reuse.empty:
        fig = px.bar(reuse, x='distance_bin', y='count',
                     title='Instructions between write and next read',
                     labels={'distance_bin': 'Distance', 'count': 'Count'})
        st.plotly_chart(fig)

    st.markdown('---')

    section('Top Registers by Activity')
    rows = [{'reg': f'x{i}/{_ABI[i]}',
             'writes':    int(wr_ser.get(i, 0)),
             'rs1_reads': int(r1_ser.get(i, 0)),
             'rs2_reads': int(r2_ser.get(i, 0))}
            for i in range(32)]
    act_df = pd.DataFrame(rows)
    act_df['total'] = act_df['writes'] + act_df['rs1_reads'] + act_df['rs2_reads']
    show_table(act_df.sort_values('total', ascending=False))
