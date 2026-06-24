#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    branches.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: branch statistics.
#----------------------------------------------------------------------------

"""Branches & Jumps view — conditional branch analysis + JALR patterns."""

import streamlit as st
import pandas as pd
import plotly.express as px

from ._utils import kpi, section, bar, show_table


def render(stats: dict):
    st.title('Branches & Jumps')

    br  = stats.get('branches', {})
    jmp = stats.get('jumps', {})

    # ──────────────────────────────────────────────────────────────────────────
    st.markdown('## Conditional Branches')

    if br.get('total', 0) == 0:
        st.warning('No conditional branches found in this trace.')
    else:
        c1, c2, c3, c4, c5 = st.columns(5)
        kpi(c1, 'Total branches', f'{br["total"]:,}',
            help='Total BEQ / BNE / BLT / BGE / BLTU / BGEU instructions '
                 '(including compressed C.BEQZ / C.BNEZ).')
        kpi(c2, 'Taken %', f'{br.get("taken_pct", 0):.1f}%',
            help='Percentage of branches where the branch was actually taken '
                 '(PC jumps to target). Not-taken means execution falls through.')
        kpi(c3, 'Forward %', f'{br.get("forward_pct", 0):.1f}%',
            help='Branches whose target is at a higher address than the branch '
                 'itself (if-then, skip-over). Typically not taken.')
        kpi(c4, 'Backward %', f'{br.get("backward_pct", 0):.1f}%',
            help='Branches whose target is at a lower address (loop back-edges). '
                 'Typically taken. High backward % = loop-heavy workload.')
        kpi(c5, 'Zero-compare %', f'{br.get("zero_compare_pct", 0):.1f}%',
            help='Branches that compare a register against x0 (zero). '
                 'Common idiom: BEQZ / BNEZ. May be compressible to C.BEQZ / C.BNEZ.')

        st.markdown('---')

        section('By Mnemonic')
        by_mnem = br.get('by_mnem', pd.DataFrame())
        if not by_mnem.empty:
            col1, col2 = st.columns([1, 1])
            with col1:
                fig = px.bar(by_mnem, x='mnem_base', y='count',
                             color='taken_pct', color_continuous_scale='RdYlGn',
                             title='Branch count by mnemonic (color = taken %)',
                             labels={'mnem_base': 'Mnemonic', 'count': 'Count',
                                     'taken_pct': 'Taken %'})
                st.plotly_chart(fig)
            with col2:
                show_table(by_mnem)

        st.markdown('---')

        section('Branch Distance Histogram')
        st.caption(
            'Distribution of branch offsets (how far the branch jumps). '
            'Short-range branches (±32B) are eligible for 16-bit C.BEQZ / C.BNEZ encoding.'
        )
        dist_hist = br.get('distance_hist', pd.DataFrame())
        if not dist_hist.empty:
            fig2 = px.bar(dist_hist, x='distance_bin', y='count',
                          title='Branch offset distribution',
                          labels={'distance_bin': 'Offset range (bytes)', 'count': 'Count'})
            fig2.update_xaxes(tickangle=30)
            st.plotly_chart(fig2)

        st.markdown('---')

        section('Source Register Usage')
        st.caption(
            'Most frequently used source registers in branch conditions. '
            'rs1 is the left-hand side operand, rs2 is the right-hand side '
            '(or x0 for BEQZ/BNEZ).'
        )
        rs1_freq = br.get('rs1_freq', pd.DataFrame())
        rs2_freq = br.get('rs2_freq', pd.DataFrame())
        col1, col2 = st.columns(2)
        with col1:
            if not rs1_freq.empty:
                fig3 = bar(rs1_freq.head(16), x='name', y='count',
                           title='Most used rs1 (LHS)', xlabel='Register', ylabel='Count')
                st.plotly_chart(fig3)
        with col2:
            if not rs2_freq.empty:
                fig4 = bar(rs2_freq.head(16), x='name', y='count',
                           title='Most used rs2 (RHS)', xlabel='Register', ylabel='Count')
                st.plotly_chart(fig4)

        # ── Late-source hazard KPIs ──────────────────────────────────────────
        bp          = stats.get('branch_prediction', {})
        br_late     = bp.get('late_source_pct')
        jalr_late_s = jmp.get('jalr_late_source_pct')

        section('Late-Source Hazard')
        st.caption(
            'How often the instruction immediately before a branch or JALR writes '
            'to one of its source registers. This creates a RAW data hazard — the '
            'operand is not yet available when the branch/jump is decoded, requiring '
            'forwarding or a pipeline stall.'
        )
        lc1, lc2 = st.columns(2)
        kpi(lc1, 'Branch late src %',
            f'{br_late:.1f}%' if br_late is not None else 'N/A',
            help='Percentage of conditional branches where the preceding instruction '
                 'writes to rs1 or rs2 (the comparison operands).')
        kpi(lc2, 'JALR late src %',
            f'{jalr_late_s:.1f}%' if jalr_late_s is not None else 'N/A',
            help='Percentage of JALR/C.JALR/C.JR where the preceding instruction '
                 'writes to rs1 (the jump target address register).')

        st.markdown('---')

        section('Most Used (rs1, rs2) Pairs')
        st.caption(
            'Most common register pairs used together in branch conditions. '
            'Recurring pairs (e.g. a0/a1) reveal common comparison idioms '
            'and may guide register allocation or fusion opportunities.'
        )
        pair_freq = br.get('pair_freq', pd.DataFrame())
        if not pair_freq.empty:
            top_n = st.slider('Show top N pairs', 5, min(30, len(pair_freq)), 15,
                              key='br_topn')
            df_p = pair_freq.head(top_n).copy()
            df_p['pair'] = ('x' + df_p['rs1'].astype(str)
                            + ' / x' + df_p['rs2'].astype(str))
            fig5 = bar(df_p.sort_values('count', ascending=True),
                       x='count', y='pair', horizontal=True,
                       title=f'Top {top_n} (rs1,rs2) pairs',
                       xlabel='Count', ylabel='Pair')
            st.plotly_chart(fig5)
            show_table(pair_freq.head(top_n))

        st.markdown('---')

        section('Consecutive Branch Pair Transitions')
        st.caption(
            'Shows how often one (rs1,rs2) register pair is immediately followed '
            'by another in consecutive branches. High counts on a specific transition '
            'indicate a recurring branch idiom or loop pattern that could benefit '
            'from branch prediction specialization.'
        )
        pair_trans = br.get('pair_transition', pd.DataFrame())
        if not pair_trans.empty:
            show_table(pair_trans)

        st.markdown('---')

        section('Miscellaneous')
        c1, c2 = st.columns(2)
        kpi(c1, 'Self-compare branches (rs1==rs2)', str(br.get('self_compare_cnt', 0)),
            help='Branches where rs1 and rs2 are the same register. '
                 'BEQ rs1,rs1 is always taken; BNE rs1,rs1 is never taken. '
                 'These are compile-time-predictable branches.')
        taken_by_pair = br.get('taken_rate_by_pair', pd.DataFrame())
        kpi(c2, 'Unique (rs1,rs2) pairs tracked',
            str(len(taken_by_pair)) if not taken_by_pair.empty else '0',
            help='Number of distinct register pairs seen in branch instructions.')
        if not taken_by_pair.empty:
            show_table(taken_by_pair.head(20))

    # ──────────────────────────────────────────────────────────────────────────
    st.markdown('---')
    st.markdown('## JALR / Jump Register Analysis')
    st.caption(
        '**JAL** (Jump And Link): direct jump with PC-relative offset, stores return '
        'address in rd. Used for direct function calls and unconditional branches.\n\n'
        '**JALR** (Jump And Link Register): indirect jump to rs1+offset, stores return '
        'address in rd. Used for indirect calls, virtual dispatch, and function returns.'
    )

    jalr_total = jmp.get('jalr_total', 0)
    jal_total  = jmp.get('jal_total',  0)

    c1, c2, c3 = st.columns(3)
    kpi(c1, 'JALR count', f'{jalr_total:,}',
        help='Total indirect jumps/calls/returns via JALR instruction.')
    kpi(c2, 'JAL count', f'{jal_total:,}',
        help='Total direct jumps/calls via JAL instruction.')
    kpi(c3, 'Indirect call %', f'{jmp.get("indirect_call_pct", 0):.1f}%',
        help='Fraction of all calls (JAL+JALR with rd=ra) that use JALR. '
             'High values indicate heavy use of function pointers or virtual calls.')

    call_ret = jmp.get('call_return_ratio', {})
    if call_ret:
        c1, c2, c3 = st.columns(3)
        kpi(c1, 'Calls', str(call_ret.get('call', 0)),
            help='JAL/JALR instructions with rd=x1 (ra). Saves return address.')
        kpi(c2, 'Returns', str(call_ret.get('return', 0)),
            help='JALR instructions with rd=x0 and rs1=x1 (ra). '
                 'Classic return-from-function pattern.')
        kpi(c3, 'Other', str(call_ret.get('other', 0)),
            help='JALR instructions that are neither calls nor returns '
                 '(e.g. tail calls, computed gotos, switch tables).')

    if jalr_total > 0:
        jalr_rs1   = jmp.get('jalr_rs1_freq',      pd.DataFrame())
        jalr_trans = jmp.get('jalr_rs1_transition', pd.DataFrame())
        col1, col2 = st.columns(2)
        with col1:
            if not jalr_rs1.empty:
                fig_j = bar(jalr_rs1.head(16), x='name', y='count',
                            title='JALR — most used rs1',
                            xlabel='Register', ylabel='Count')
                st.plotly_chart(fig_j)
                st.caption(
                    'The base register used for indirect jumps. ra (x1) dominates '
                    'for returns; other registers indicate indirect calls or '
                    'computed gotos.'
                )
        with col2:
            if not jalr_trans.empty:
                st.markdown('**JALR rs1 register transitions** (consecutive JALRs)')
                st.caption(
                    'How often one JALR base register is followed by another. '
                    'Strong diagonal = same register repeated (e.g. always returning '
                    'via ra). Off-diagonal entries reveal indirect call patterns.'
                )
                show_table(jalr_trans)

        ras = jmp.get('ras_depth_hist', pd.DataFrame())
        if not ras.empty:
            section('Return Address Stack (RAS) Depth')
            st.caption(
                'The RAS is a small hardware stack that predicts function return '
                'addresses. Each CALL pushes the return address; each RETURN pops it. '
                'Deep call stacks (depth > 8) can overflow a typical 8-entry RAS, '
                'causing mispredictions.'
            )
            fig_ras = px.bar(ras, x='depth', y='count',
                             title='RAS depth distribution',
                             labels={'depth': 'RAS depth', 'count': 'Occurrences'})
            st.plotly_chart(fig_ras)
