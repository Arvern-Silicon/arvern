#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    instmix.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: instruction-mix breakdown.
#----------------------------------------------------------------------------

"""Instruction Mix view — frequency distribution, extension utilization."""

import streamlit as st
import pandas as pd

from ._utils import kpi, section, bar, pie, show_table, CAT_COLORS
_MNEM_TO_SUBEXT = {}
for _ext, _mnems in [
    ('Zca', {'C.LW','C.SW','C.LWSP','C.SWSP','C.JAL','C.J','C.JR','C.JALR',
             'C.BEQZ','C.BNEZ','C.ADDI','C.LI','C.LUI','C.SLLI','C.SRLI',
             'C.SRAI','C.ANDI','C.ADD','C.SUB','C.AND','C.OR','C.XOR','C.MV',
             'C.ADDI4SPN','C.ADDI16SP','C.NOP','C.EBREAK'}),
    ('Zcb', {'C.LBU','C.LHU','C.LH','C.SB','C.SH',
             'C.ZEXT.B','C.SEXT.B','C.ZEXT.H','C.SEXT.H','C.NOT','C.MUL'}),
    ('Zcmp', {'CM.PUSH','CM.POP','CM.POPRET','CM.POPRETZ','CM.MVA01S','CM.MVSA01'}),
    ('Zcmt', {'CM.JT','CM.JALT'}),
    ('Zbb', {'ANDN','ORN','XNOR','CLZ','CTZ','CPOP','SEXT.B','SEXT.H','ZEXT.H',
             'MIN','MINU','MAX','MAXU','ROL','ROR','ORC.B','REV8','RORI'}),
    ('Zba', {'SH1ADD','SH2ADD','SH3ADD'}),
    ('Zbs', {'BCLR','BEXT','BINV','BSET','BCLRI','BEXTI','BINVI','BSETI'}),
    ('Zbc', {'CLMUL','CLMULR','CLMULH'}),
    ('M (MUL)', {'MUL','MULH','MULHSU','MULHU'}),
    ('M (DIV)', {'DIV','DIVU','REM','REMU'}),
]:
    for _m in _mnems:
        _MNEM_TO_SUBEXT[_m] = _ext


def render(stats: dict):
    st.title('Instruction Mix')

    mix     = stats.get('instmix', {})
    by_mnem = mix.get('by_mnem', pd.DataFrame())

    c1, c2, c3, c4 = st.columns(4)
    kpi(c1, 'Compressed %', f'{mix.get("compressed_pct", 0):.1f}%',
        help='Percentage of instructions using the 16-bit RVC encoding. '
             'Each compressed instruction saves 2 bytes of code size vs the '
             'standard 32-bit encoding.')
    kpi(c2, 'Unique mnemonics', str(stats.get('mnem_nunique', len(by_mnem))),
        help='Number of distinct instruction types seen in this trace.')
    if not by_mnem.empty:
        top1 = by_mnem.iloc[0]
        kpi(c3, 'Most common instr', str(top1['mnem_base']),
            help='The single most frequently executed instruction mnemonic.')
        kpi(c4, 'Its frequency', f'{top1["count"]:,}  ({top1["pct"]:.1f}%)',
            help='Execution count and percentage of total instructions.')

    st.markdown('---')

    section('Distribution by Category')
    cat_df = mix.get('by_category', pd.DataFrame())
    if not cat_df.empty:
        col1, col2 = st.columns([1, 1])
        with col1:
            fig = pie(cat_df, names='category', values='count',
                      title='Instruction categories', color_map=CAT_COLORS)
            st.plotly_chart(fig)
        with col2:
            fig2 = bar(cat_df.sort_values('count', ascending=True),
                       x='count', y='category', horizontal=True,
                       title='Count by category', xlabel='Count', ylabel='Category')
            st.plotly_chart(fig2)

    st.markdown('---')

    section('Extension Utilization')
    st.caption(
        '**Standard**: base RV32I instructions. '
        '**C**: 16-bit compressed instructions (Zca + Zcb + Zcmp + Zcmt). '
        '**M**: integer multiply and divide. '
        '**B**: bit-manipulation (Zbb + Zba + Zbs + Zbc).'
    )
    ext_sum = mix.get('ext_summary', pd.DataFrame())
    if not ext_sum.empty:
        active_sum = ext_sum[ext_sum['count'] > 0]
        if not active_sum.empty:
            col_a, col_b = st.columns([1, 1])
            with col_a:
                fig4 = bar(active_sum,
                           x='extension', y='count',
                           title='Instructions per extension',
                           xlabel='Extension', ylabel='Count')
                st.plotly_chart(fig4)
            with col_b:
                show_table(active_sum)
        else:
            st.info('No extension instructions found in this trace.')

    ext_det = mix.get('ext_detail', pd.DataFrame())
    if not ext_det.empty:
        active_det = ext_det[ext_det['count'] > 0]
        if not active_det.empty:
            st.markdown('---')
            section('Sub-Extension Breakdown')
            st.caption(
                '**M**: MUL (multiply) and DIV (divide). '
                '**Zca/Zcb/Zcmp/Zcmt**: compressed sub-extensions. '
                '**Zbb/Zba/Zbs/Zbc**: bit-manipulation sub-extensions.'
            )
            col_c, col_d = st.columns([1, 1])
            with col_c:
                fig5 = bar(active_det.sort_values('count', ascending=False),
                           x='extension', y='count',
                           title='Instructions per sub-extension',
                           xlabel='Sub-Extension', ylabel='Count')
                st.plotly_chart(fig5)
            with col_d:
                show_table(active_det)

    st.markdown('---')

    section('Top Mnemonics')
    if not by_mnem.empty:
        top_n = st.slider('Show top N', 5, min(50, len(by_mnem)), 20,
                          key='instmix_topn')
        top_df = by_mnem.head(top_n).copy()
        top_df['sub-ext'] = top_df['mnem_base'].map(_MNEM_TO_SUBEXT).fillna('Standard')
        col_m1, col_m2 = st.columns([1, 1])
        with col_m1:
            fig_m = bar(top_df.sort_values('count', ascending=True),
                        x='count', y='mnem_base', horizontal=True,
                        title=f'Top {top_n} instructions',
                        xlabel='Count', ylabel='Instruction')
            st.plotly_chart(fig_m)
        with col_m2:
            show_table(top_df)
