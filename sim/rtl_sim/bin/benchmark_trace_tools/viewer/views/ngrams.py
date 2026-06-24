#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    ngrams.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: instruction n-gram analysis.
#----------------------------------------------------------------------------

"""N-grams & Immediates view — instruction sequences + immediate distributions."""

import streamlit as st
import pandas as pd
import plotly.express as px

from ._utils import kpi, section, show_table


def render(stats: dict):
    st.title('N-grams & Immediates')

    # ── N-grams ────────────────────────────────────────────────────────────────
    st.markdown('## Instruction N-grams')
    st.caption(
        'An **N-gram** is a sequence of N consecutive instructions. '
        'Frequent N-grams reveal recurring code idioms that could be targeted '
        'for macro-fusion, new compressed encodings, or custom instructions.\n\n'
        '**Bigram (N=2)**: pairs of consecutive instructions. '
        '**Trigram (N=3)**: triples — reveals 3-instruction idioms like '
        'LUI+ADDI+LD (PC-relative load of a global).'
    )

    n      = st.radio('N-gram size', [2, 3], horizontal=True, key='ngram_n')
    top_k  = st.slider('Top K', 5, 50, 20, key='ngram_k')
    df_raw = stats.get('ngrams2' if n == 2 else 'ngrams3', pd.DataFrame())

    if df_raw is None or df_raw.empty:
        st.warning(f'No {n}-gram data available.')
    else:
        df = df_raw.head(top_k)

        c1, c2 = st.columns(2)
        kpi(c1, f'Unique {n}-grams', f'{len(df_raw):,}',
            help=f'Total number of distinct {n}-instruction sequences observed.')
        kpi(c2, 'Most common', str(df.iloc[0]['ngram']) if not df.empty else '—',
            help='The most frequently occurring instruction sequence.')

        st.markdown('---')

        fig = px.bar(df.sort_values('count', ascending=True),
                     x='count', y='ngram', orientation='h',
                     title=f'Top {top_k} {"bi" if n==2 else "tri"}grams',
                     labels={'ngram': 'Sequence', 'count': 'Count'},
                     color='count', color_continuous_scale='Blues')
        fig.update_layout(height=max(400, top_k * 22))
        st.plotly_chart(fig)

        if n == 2:
            section('Macro-Fusion Candidates')
            st.caption(
                '**Macro-fusion** combines two consecutive instructions into a single '
                'micro-operation, executing them in one cycle. Common candidates:\n\n'
                '- **LUI+ADDI**: load 32-bit constant (the `li` pseudo-instruction)\n'
                '- **AUIPC+JALR**: long-range indirect call\n'
                '- **AUIPC+LW**: PC-relative load of a global variable\n\n'
                'High counts here indicate good candidates for hardware or compiler optimization.'
            )
            fusion_df = stats.get('fusion_candidates', pd.DataFrame())
            if fusion_df is not None and not fusion_df.empty:
                show_table(fusion_df)
            else:
                st.info('No known macro-fusion candidates found in top bigrams.')

        st.markdown('---')
        section('Full Table')
        show_table(df_raw)

    # ── Immediates ─────────────────────────────────────────────────────────────
    st.markdown('---')
    st.markdown('## Immediate Value Analysis')
    st.caption(
        'Analysis of compile-time constant values embedded in instructions. '
        'Helps identify opportunities for the **C (compressed) extension** '
        'which encodes small immediates in fewer bits.'
    )

    imm = stats.get('immediates', {})
    if not imm:
        st.info('No immediate data available.')
        return

    c1, c2, c3 = st.columns(3)
    kpi(c1, 'ADDI C.ADDI-eligible count', f'{imm.get("addi_comp_eligible", 0):,}',
        help='Number of ADDI instructions whose immediate fits in [-32, 31] '
             'AND rd==rs1. These can be encoded as C.ADDI (16-bit) saving 2 bytes each.')
    kpi(c2, 'ADDI C.ADDI-eligible %', f'{imm.get("addi_comp_pct", 0):.1f}%',
        help='Fraction of ADDI instructions eligible for C.ADDI compression. '
             'High values suggest the C extension would significantly reduce code size.')
    kpi(c3, 'LUI+ADDI consecutive pairs', f'{imm.get("lui_addi_pairs", 0):,}',
        help='Number of LUI immediately followed by ADDI — the standard way to '
             'load a 32-bit constant. Each pair could be a macro-fusion candidate '
             'or replaced by a single C.LI if the value fits in 6 bits.')

    st.markdown('---')

    col1, col2 = st.columns(2)
    with col1:
        section('ADDI Immediate Distribution')
        st.caption(
            'Distribution of immediate values used with ADDI. '
            'Immediates in **[-32, 31]** are eligible for C.ADDI (16-bit encoding). '
            'Small positive values (0..31) dominate in most workloads.'
        )
        addi_hist = imm.get('addi_imm_hist', pd.DataFrame())
        if not addi_hist.empty:
            fig2 = px.bar(addi_hist, x='imm_bin', y='count',
                          title='ADDI immediate value distribution',
                          labels={'imm_bin': 'Range', 'count': 'Count'})
            st.plotly_chart(fig2)
    with col2:
        section('Load Offset Distribution')
        st.caption(
            'Distribution of offsets used in load instructions (LW, LH, LB, etc.). '
            'Offsets in **[0, 31]** (word-aligned) or **[-32, 31]** are eligible for '
            'the compressed CL-type encoding (C.LW, C.LD). '
            'Small positive offsets dominate for struct field access.'
        )
        off_hist = imm.get('load_offset_hist', pd.DataFrame())
        if not off_hist.empty:
            fig3 = px.bar(off_hist, x='offset_bin', y='count',
                          title='Load instruction offset distribution',
                          labels={'offset_bin': 'Offset range', 'count': 'Count'})
            st.plotly_chart(fig3)
