#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    branch_pred.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Viewer page: branch prediction stats.
#----------------------------------------------------------------------------

"""Branch Prediction Simulator view."""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

from ._utils import kpi, section, show_table


def render(stats: dict):
    st.title('Branch Prediction Simulator')

    bp = stats.get('branch_prediction', {})

    if not bp or bp.get('total_branches', 0) == 0:
        st.warning('No conditional branches found in this trace.')
        return

    total      = bp['total_branches']
    oracle_pct = bp['oracle_mispredict_pct']
    summary    = bp.get('summary',    pd.DataFrame())
    size_sweep = bp.get('size_sweep', pd.DataFrame())
    hardest    = bp.get('hardest',    pd.DataFrame())

    # ── KPIs ──────────────────────────────────────────────────────────────────
    best_static = best_table = None
    if not summary.empty:
        static_mask = summary.scheme.isin(['always_nt', 'always_t', 'btfn'])
        best_static = float(summary[static_mask].mispredict_pct.min())
        best_table  = float(summary[~static_mask].mispredict_pct.min())

    c1, c2, c3, c4 = st.columns(4)
    kpi(c1, 'Total branches', f'{total:,}',
        help='Total conditional branches (BEQ/BNE/BLT/etc. + compressed C.BEQZ/C.BNEZ).')
    kpi(c2, 'Oracle floor %', f'{oracle_pct:.1f}%',
        help='Minimum achievable misprediction rate: for each branch PC predict its '
             'dominant outcome (taken or not-taken). Best any per-branch predictor can do '
             'with an infinite warm-up table.')
    kpi(c3, 'Best static scheme %',
        f'{best_static:.1f}%' if best_static is not None else 'N/A',
        help='Lowest misprediction % among Always-NT, Always-T, and BTFN.')
    kpi(c4, 'Best table-based scheme %',
        f'{best_table:.1f}%' if best_table is not None else 'N/A',
        help='Lowest misprediction % among all bimodal/GShare/µTAGE variants tested.')

    st.markdown('---')

    # ── Section 1: Scheme Comparison ──────────────────────────────────────────
    section('Scheme Comparison')
    st.caption(
        'Misprediction rate for each predictor scheme. Lower is better. '
        'The dashed vertical line shows the oracle floor — the theoretical minimum '
        'achievable by any predictor with perfect per-PC history.'
    )

    with st.expander('Predictor descriptions'):
        st.markdown(
            '| Scheme | Hardware | How it works |\n'
            '|--------|----------|--------------|\n'
            '| **Always NT** | None | Always predict Not-Taken. Free — no hardware needed. Best when most branches fall through. |\n'
            '| **Always T** | None | Always predict Taken. Free — no hardware needed. Best when most branches loop back. |\n'
            '| **BTFN** | None | **B**ackward **T**aken, **F**orward **N**ot-taken. Branches to a lower address (loops) are predicted taken; branches to a higher address (if/skip) are predicted not-taken. Direction is determined statically from the sign of the offset — zero hardware cost. |\n'
            '| **1-bit bimodal** | 2^N × 1 bit | A flat SRAM table. Index = `(PC >> 2) & (size-1)` — only N bits of the PC, **not a per-PC history**. Stores the *last* outcome for that index slot. Multiple branch PCs can alias to the same entry. Mispredicts on every direction change — poor on alternating branches (e.g. loop exit). |\n'
            '| **2-bit bimodal** | 2^N × 2 bits | Same flat SRAM table and same PC hash index. Each slot is a 2-bit saturating counter (0=Strongly NT … 3=Strongly T); predict taken if ≥ 2. Requires *two* consecutive wrong outcomes to flip — tolerates single outliers and loop exits much better than 1-bit. |\n'
            '| **GShare** | 2^N × 2 bits + N-bit GHR | 2-bit saturating counters, but the table index is `(PC >> 2) XOR GHR` where GHR is a shift register of the last N branch outcomes. The XOR spreads aliasing more evenly and correlates predictions with recent global history — captures patterns like "this branch is taken only after the previous one was not." |\n'
            '| **Micro-TAGE** | Base: 2^N × 2 bits + Tagged: 2^(N-1) × (2-bit ctr + 6-bit tag + 1-bit useful) + GHR | Scaled-down TAGE with two components: a bimodal base table (indexed by PC) and one tagged table (indexed by PC XOR GHR). The tagged table stores a 6-bit partial PC tag to detect aliasing. On lookup, the tagged table has priority if the tag matches; otherwise falls back to bimodal. A 1-bit "useful" flag manages replacement — entries that prove valuable are kept, others are evicted for new allocations. Captures correlated branch patterns like GShare but with reduced destructive aliasing thanks to the tag. |\n'
            '| **Tournament** | 3 × N × 2 bits + N-bit GHR | Runs two predictors in parallel — bimodal (indexed by PC) and GShare (indexed by PC XOR GHR) — plus a 2-bit choice table (indexed by GHR) that learns which predictor to trust. The choice counter only updates when the two predictors disagree: nudged toward whichever was correct. Automatically selects bimodal for branches with stable per-PC patterns and GShare for globally correlated branches. Inspired by the Alpha 21264. |\n'
            '| **Oracle** | ∞ | For each unique branch PC, always predicts its majority outcome (taken or not-taken). Represents the theoretical minimum misprediction rate for any static per-branch predictor with a perfectly warmed-up, infinite table. |\n'
        )

    if not summary.empty:
        df_bar = summary.sort_values('mispredict_pct', ascending=True).reset_index(drop=True)

        colors = []
        for pct in df_bar.mispredict_pct:
            if pct < 5:
                colors.append('#2ecc71')
            elif pct < 15:
                colors.append('#f39c12')
            else:
                colors.append('#e74c3c')

        fig = go.Figure()
        fig.add_trace(go.Bar(
            x=df_bar.mispredict_pct,
            y=df_bar.label,
            orientation='h',
            marker_color=colors,
            text=[f'{p:.1f}%' for p in df_bar.mispredict_pct],
            textposition='outside',
        ))
        fig.add_vline(
            x=oracle_pct, line_dash='dash', line_color='#3498db',
            annotation_text=f'Oracle floor {oracle_pct:.1f}%',
            annotation_position='top right',
        )
        fig.update_layout(
            title='Misprediction rate by predictor scheme',
            xaxis_title='Misprediction %',
            yaxis_title='',
            margin=dict(t=40, b=0, r=120),
            height=max(300, len(df_bar) * 40 + 60),
        )
        st.plotly_chart(fig)

    st.markdown('---')

    # ── Section 2: Table size vs accuracy ─────────────────────────────────────
    section('Table Size vs Accuracy')
    st.caption(
        'Misprediction rate as a function of predictor table size (log₂ scale). '
        'Hardware cost: 2^N × 1 bit for 1-bit bimodal; 2^N × 2 bits for 2-bit bimodal / GShare. '
        'Diminishing returns: doubling the table typically gives <1% improvement beyond ~256 entries.'
    )

    if not size_sweep.empty:
        base_labels = {
            'bimodal_1bit': '1-bit bimodal',
            'bimodal_2bit': '2-bit bimodal',
            'gshare':       'GShare',
        }

        # ── Main size-sweep chart (bimodal / GShare) ─────────────────────────
        df_sw = size_sweep[size_sweep['scheme'].isin(base_labels)].copy()
        df_sw['Scheme'] = df_sw['scheme'].map(base_labels)

        fig2 = px.line(
            df_sw, x='table_bits', y='mispredict_pct', color='Scheme',
            markers=True,
            labels={'table_bits': 'Table index bits (N)', 'mispredict_pct': 'Misprediction %'},
            title='Misprediction % vs table size',
        )
        fig2.add_hline(
            y=oracle_pct, line_dash='dash', line_color='#3498db',
            annotation_text='Oracle floor',
            annotation_position='bottom right',
        )
        fig2.update_xaxes(
            tickvals=[0, 2, 3, 4, 5, 6, 7, 8, 10, 12],
            ticktext=['BTFN', '2b (4)', '3b (8)', '4b (16)', '5b (32)', '6b (64)',
                      '7b (128)', '8b (256)', '10b (1024)', '12b (4096)'],
        )
        st.plotly_chart(fig2)

        # ── Micro-TAGE variants chart ────────────────────────────────────────
        def _utage_label(s):
            return s.replace('micro_tage_', '').replace('B', 'B').replace('T', ' T').replace('w', ' w')

        all_schemes = list(size_sweep['scheme'].unique())
        utage_variants      = [s for s in all_schemes if s.startswith('micro_tage_')]
        tournament_variants = [s for s in all_schemes if s.startswith('tournament_')]

        if utage_variants:
            # Get BTFN value from any variant's table_bits=0 anchor
            btfn_row = size_sweep[(size_sweep['scheme'] == utage_variants[0]) & (size_sweep['table_bits'] == 0)]
            btfn_val = float(btfn_row['mispredict_pct'].iloc[0]) if not btfn_row.empty else None

            x_labels = ['BTFN'] + [_utage_label(v) for v in utage_variants]
            y_vals   = [btfn_val]
            for v in utage_variants:
                row = size_sweep[(size_sweep['scheme'] == v) & (size_sweep['table_bits'] != 0)]
                y_vals.append(float(row['mispredict_pct'].iloc[0]) if not row.empty else None)

            fig_ut = go.Figure()
            fig_ut.add_trace(go.Bar(
                x=x_labels, y=y_vals,
                text=[f'{v:.1f}%' if v is not None else '' for v in y_vals],
                textposition='outside',
            ))
            fig_ut.add_hline(
                y=oracle_pct, line_dash='dash', line_color='#3498db',
                annotation_text='Oracle floor',
                annotation_position='bottom right',
            )
            fig_ut.update_layout(
                title='Micro-TAGE variants',
                xaxis_title='Variant', yaxis_title='Misprediction %',
                xaxis=dict(type='category'),
                margin=dict(t=40, b=0),
                height=350,
            )
            st.plotly_chart(fig_ut)

        # ── Tournament variants chart ────────────────────────────────────────
        if tournament_variants:
            btfn_row_t = size_sweep[(size_sweep['scheme'] == tournament_variants[0]) & (size_sweep['table_bits'] == 0)]
            btfn_val_t = float(btfn_row_t['mispredict_pct'].iloc[0]) if not btfn_row_t.empty else None

            x_labels_t = ['BTFN'] + [s.replace('tournament_', '') + ' entries' for s in tournament_variants]
            y_vals_t   = [btfn_val_t]
            for v in tournament_variants:
                row = size_sweep[(size_sweep['scheme'] == v) & (size_sweep['table_bits'] != 0)]
                y_vals_t.append(float(row['mispredict_pct'].iloc[0]) if not row.empty else None)

            fig_tn = go.Figure()
            fig_tn.add_trace(go.Bar(
                x=x_labels_t, y=y_vals_t,
                text=[f'{v:.1f}%' if v is not None else '' for v in y_vals_t],
                textposition='outside',
            ))
            fig_tn.add_hline(
                y=oracle_pct, line_dash='dash', line_color='#3498db',
                annotation_text='Oracle floor',
                annotation_position='bottom right',
            )
            fig_tn.update_layout(
                title='Tournament variants',
                xaxis_title='Variant', yaxis_title='Misprediction %',
                xaxis=dict(type='category'),
                margin=dict(t=40, b=0),
                height=350,
            )
            st.plotly_chart(fig_tn)

    st.markdown('---')

    # ── Section 3: Hardest branches ────────────────────────────────────────────
    section('Hardest Branches to Predict')
    st.caption(
        'Branches with the highest misprediction rate under a 2-bit bimodal, 64-entry predictor '
        '(min 10 occurrences). Branches with taken_pct near 50% are fundamentally unpredictable — '
        'they flip direction too frequently for any simple predictor to track well.'
    )

    if not hardest.empty:
        show_table(hardest)
    else:
        st.info('No branches with ≥10 occurrences found.')

    st.markdown('---')

    # ── Section 4: Recommendation ─────────────────────────────────────────────
    section('Recommendation')

    if not summary.empty and best_table is not None:
        bimod64 = summary[(summary.scheme == 'bimodal_2bit') & (summary.table_bits == 6)]
        gshare8 = summary[(summary.scheme == 'gshare')       & (summary.table_bits == 8)]

        bimod64_pct = float(bimod64.mispredict_pct.iloc[0]) if not bimod64.empty else None
        gshare8_pct = float(gshare8.mispredict_pct.iloc[0]) if not gshare8.empty else None

        if bimod64_pct is not None and bimod64_pct < 5:
            st.success(
                f'**2-bit bimodal with 64 entries ({bimod64_pct:.1f}% mispredictions) is sufficient** '
                f'for this workload. Hardware cost: 128 bits (16 bytes) of SRAM. '
                f'Recommended baseline implementation.'
            )
        elif (gshare8_pct is not None and bimod64_pct is not None
              and (bimod64_pct - gshare8_pct) > 2.0):
            st.info(
                f'**GShare with 8-bit history is recommended** — reduces mispredictions from '
                f'{bimod64_pct:.1f}% (2-bit bimodal, 64 entries) to {gshare8_pct:.1f}% '
                f'(improvement: {bimod64_pct - gshare8_pct:.1f}pp). '
                f'Hardware cost: 256 entries × 2 bits + 8-bit GHR register.'
            )
        elif best_table < 10:
            st.info(
                f'**Table-based prediction is effective** (best: {best_table:.1f}%). '
                f'A 256-entry 2-bit bimodal is a good area/accuracy balance. '
                f'Oracle floor: {oracle_pct:.1f}%.'
            )
        else:
            st.warning(
                f'**High misprediction rate** (best table-based: {best_table:.1f}%). '
                f'This workload has many fundamentally unpredictable branches — '
                f'consider a ≥1024-entry predictor or a tournament/correlating predictor. '
                f'Oracle floor: {oracle_pct:.1f}%.'
            )
    else:
        st.info('Insufficient data for a recommendation.')
