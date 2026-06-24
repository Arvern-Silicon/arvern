#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    _utils.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Shared utility helpers for the viewer views.
#----------------------------------------------------------------------------

"""Shared helpers for all view modules."""

from typing import Optional

import plotly.graph_objects as go
import plotly.express as px
import streamlit as st
import pandas as pd

# ── Colour palette ─────────────────────────────────────────────────────────────
PALETTE = px.colors.qualitative.Plotly

CAT_COLORS = {
    'ALU_R':        '#4C72B0',
    'ALU_I':        '#5BAFD6',
    'MUL':          '#DD8452',
    'DIV':          '#E06C75',
    'LOAD':         '#55A868',
    'STORE':        '#8FBC8F',
    'BRANCH':       '#C44E52',
    'JUMP':         '#9B59B6',
    'UPPER':        '#937860',
    'CSR':          '#CCB974',
    'SYSTEM':       '#64B5CD',
    'COMP_ALU':     '#3A7EBB',
    'COMP_BR':      '#A03030',
    'COMP_JMP':     '#7B3FA0',
    'COMP_LD':      '#3A8F58',
    'COMP_ST':      '#5A9F5A',
    'COMP_STK':     '#8B7355',
    'OTHER':        '#AAAAAA',
}


def bar(df: pd.DataFrame, x: str, y: str, color: Optional[str] = None,
        title: str = '', xlabel: str = '', ylabel: str = '',
        color_map: Optional[dict] = None, horizontal: bool = False) -> go.Figure:
    """Convenience bar chart using Plotly Express."""
    kwargs: dict = dict(x=x, y=y, title=title,
                        labels={x: xlabel or x, y: ylabel or y})
    if color:
        kwargs['color'] = color
    if color_map:
        kwargs['color_discrete_map'] = color_map
    if horizontal:
        kwargs['orientation'] = 'h'
        kwargs['x'], kwargs['y'] = kwargs['y'], kwargs['x']
    fig = px.bar(df, **kwargs)
    fig.update_layout(showlegend=bool(color), margin=dict(t=40, b=0))
    return fig


def pie(df: pd.DataFrame, names: str, values: str, title: str = '',
        color_map: Optional[dict] = None) -> go.Figure:
    kwargs: dict = dict(names=names, values=values, title=title, hole=0.35)
    if color_map:
        kwargs['color'] = names
        kwargs['color_discrete_map'] = color_map
    fig = px.pie(df, **kwargs)
    fig.update_traces(textposition='inside', textinfo='percent+label')
    fig.update_layout(showlegend=False, margin=dict(t=40, b=0))
    return fig


def heatmap(matrix: pd.DataFrame, title: str = '',
            colorscale: str = 'Blues') -> go.Figure:
    fig = go.Figure(go.Heatmap(
        z=matrix.values,
        x=[str(c) for c in matrix.columns],
        y=[str(i) for i in matrix.index],
        colorscale=colorscale,
        showscale=True,
    ))
    fig.update_layout(title=title, margin=dict(t=40, b=0),
                      xaxis_title='', yaxis_title='')
    return fig


def kpi(col, label: str, value: str, delta: Optional[str] = None,
        help: Optional[str] = None):
    """Render a single KPI metric card."""
    with col:
        st.metric(label=label, value=value, delta=delta, help=help)


def section(title: str):
    st.markdown(f'### {title}')


def show_table(df: pd.DataFrame, height: int = 400):
    st.dataframe(df, width='stretch', height=height)
