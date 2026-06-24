#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    dependencies.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: instruction-dependency analysis.
#----------------------------------------------------------------------------

"""Dependencies view — RAW hazards, producer-consumer distances."""

import streamlit as st
import pandas as pd
import plotly.express as px

from ._utils import kpi, section, show_table


def render(stats: dict):
    st.title('Data Dependencies (RAW Hazards)')
    st.caption(
        'A **RAW (Read After Write) hazard** occurs when an instruction reads a '
        'register that was written by a recent preceding instruction. '
        'In the arvern pipeline, ALU→ALU dependencies are resolved by forwarding '
        '(no stall). Load→use dependencies at distance 1 require a 1-cycle stall.'
    )

    dep = stats.get('dependencies', {})
    if not dep:
        st.warning('No dependency data available.')
        return

    c1, c2 = st.columns(2)
    chains_df = dep.get('common_chains', pd.DataFrame())
    kpi(c1, 'Avg dependency chain length', f'{dep.get("avg_chain_length", 0):.2f} instr',
        help='Average number of instructions in a producer→consumer dependency chain. '
             'Longer chains indicate deeply pipelined computation sequences.')
    kpi(c2, 'Unique chain patterns', str(len(chains_df)),
        help='Number of distinct (producer mnemonic → consumer mnemonic) pairs observed.')

    st.markdown('---')

    section('Producer → Consumer Distance')
    st.caption(
        'Number of instructions between a **write** (producer) and the **read** that '
        'depends on it (consumer). '
        '**Distance 1**: back-to-back — forwarding handles ALU ops but LOAD causes a stall. '
        '**Distance ≥ 2**: the pipeline can hide the latency without stalling.'
    )
    pc_hist = dep.get('prod_consumer_dist', pd.DataFrame())
    if not pc_hist.empty:
        fig = px.bar(pc_hist, x='distance', y='count',
                     title='Instructions between producer write and consumer read',
                     labels={'distance': 'Distance (instructions)', 'count': 'Count'})
        fig.add_vline(x=1, line_dash='dash', line_color='orange',
                      annotation_text='Load-use zone')
        fig.add_vline(x=0, line_dash='dot', line_color='red',
                      annotation_text='Back-to-back')
        st.plotly_chart(fig)

    st.markdown('---')

    section('Most Common Dependency Chains')
    st.caption(
        'Most frequent (producer → consumer) instruction pairs. '
        'A high count of LOAD→ALU indicates the compiler is scheduling loads '
        'poorly (should insert independent instructions between load and use). '
        'MUL→ADD is a common multiply-accumulate pattern.'
    )
    if not chains_df.empty:
        show_table(chains_df)
    else:
        st.info('No chain data available.')
