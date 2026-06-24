#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    stats.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Compute aggregate statistics from a benchmark trace.
#----------------------------------------------------------------------------

"""
trace_stats.py — arvern trace statistics engine.

All functions accept a TraceData (from trace_parser.load()) and return
plain dicts or DataFrames.  No GUI dependency — usable from notebooks,
scripts, or the Streamlit viewer.

Modules
-------
pipeline          CPI/IPC, stall detection and breakdown
instmix           Instruction frequency, category distribution, extension usage
branches          Conditional branch analysis, register pairs, transition matrices
jumps             JALR patterns, call/return, RAS depth
memory            Load/store patterns, strides, SP-relative, load-use distance
registers         Register pressure, reuse distance, live register count
dependencies      RAW hazard chains, producer-consumer distance
ngrams            Bigram/trigram instruction sequences
immediates        Immediate value distributions, compression eligibility
loops             Back-edge detection, trip counts, loop body size
hotcode           PC execution frequency, top hotspots
branch_prediction Branch predictor simulation (static, bimodal, GShare)
"""

from collections import Counter, defaultdict
from typing import Optional

import numpy as np
import pandas as pd

try:
    from numba import njit
except ImportError:
    def njit(*args, **kwargs):
        def decorator(func): return func
        return decorator

from .parser import (
    TraceData,
    CAT_BRANCH, CAT_JUMP, CAT_LOAD, CAT_STORE,
    CAT_MUL, CAT_DIV, CAT_ALU_R, CAT_ALU_I, CAT_UPPER, CAT_CSR, CAT_SYSTEM,
    CAT_COMP_BR, CAT_COMP_JMP, CAT_COMP_LD, CAT_COMP_ST, CAT_COMP_ALU, CAT_COMP_STK,
)

# SP register number
_SP = 2


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _mask(df, **kwargs):
    """Return boolean mask for rows matching all keyword conditions."""
    m = pd.Series(True, index=df.index)
    for col, val in kwargs.items():
        if isinstance(val, (list, tuple, set, frozenset)):
            m &= df[col].isin(val)
        else:
            m &= df[col] == val
    return m


def _reg_name(n: int) -> str:
    """RISC-V ABI register name."""
    _NAMES = [
        'zero','ra','sp','gp','tp',
        't0','t1','t2',
        's0','s1',
        'a0','a1','a2','a3','a4','a5','a6','a7',
        's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
        't3','t4','t5','t6',
    ]
    return f'x{n}({_NAMES[n]})' if n < len(_NAMES) else f'x{n}'


# ─── pipeline ─────────────────────────────────────────────────────────────────

def pipeline(td: TraceData) -> dict:
    """CPI/IPC and stall analysis.

    Returns
    -------
    dict with keys:
      total_instructions  int
      total_cycles        int
      ipc                 float
      cpi                 float
      stall_cycles        int          total stall cycles detected
      stall_rate          float        stall_cycles / total_cycles
      stalls_by_cause     DataFrame    columns: cause, cycles, pct
      cpi_by_category     DataFrame    columns: category, count, cycles, cpi
    """
    df = td.df
    if df.empty:
        return {}

    n_instr = len(df)
    cyc_min = int(df.cycle.min())
    cyc_max = int(df.cycle.max())
    total_cycles = cyc_max - cyc_min + 1
    ipc = n_instr / total_cycles
    cpi = total_cycles / n_instr

    # Stall detection: gap between consecutive instruction cycles minus 1
    gaps = df.cycle.diff().fillna(1).astype(int) - 1   # stall cycles per instruction
    gaps = gaps.clip(lower=0)
    stall_cycles = int(gaps.sum())

    # Classify stalls by cause using the *preceding* instruction
    load_mask    = df.category.isin([CAT_LOAD, CAT_COMP_LD])
    mul_mask     = df.category == CAT_MUL
    div_mask     = df.category == CAT_DIV
    mem_mask     = df.category.isin([CAT_LOAD, CAT_STORE, CAT_COMP_LD, CAT_COMP_ST])
    br_mask      = df.category.isin([CAT_BRANCH, CAT_COMP_BR])
    jump_mask    = df.category.isin([CAT_JUMP, CAT_COMP_JMP])
    stack_mask   = df.category == CAT_COMP_STK
    csr_sys_mask = df.category.isin([CAT_CSR, CAT_SYSTEM])

    # Branch taken/not-taken split
    br_taken_mask  = br_mask & (df.br_taken == True)
    br_ntaken_mask = br_mask & (df.br_taken == False)

    load_stalls     = int(gaps[load_mask.shift(1, fill_value=False)].sum())
    mul_stalls      = int(gaps[mul_mask.shift(1, fill_value=False)].sum())
    div_stalls      = int(gaps[div_mask.shift(1, fill_value=False)].sum())
    mem_stalls      = int(gaps[mem_mask.shift(1, fill_value=False)].sum())
    br_taken_stalls = int(gaps[br_taken_mask.shift(1, fill_value=False)].sum())
    br_ntaken_stalls= int(gaps[br_ntaken_mask.shift(1, fill_value=False)].sum())
    jump_stalls     = int(gaps[jump_mask.shift(1, fill_value=False)].sum())
    stack_stalls    = int(gaps[stack_mask.shift(1, fill_value=False)].sum())
    csr_sys_stalls  = int(gaps[csr_sys_mask.shift(1, fill_value=False)].sum())

    # mem_stalls already includes load_stalls; split out pure memory-wait stalls
    mem_wait_stalls = max(0, mem_stalls - load_stalls)

    classified = (load_stalls + mul_stalls + div_stalls + mem_wait_stalls +
                  br_taken_stalls + br_ntaken_stalls + jump_stalls +
                  stack_stalls + csr_sys_stalls)
    fetch_stalls = max(0, stall_cycles - classified)

    stalls_by_cause = pd.DataFrame([
        {'cause': 'Load-use hazard',       'cycles': load_stalls},
        {'cause': 'MUL multi-cycle',       'cycles': mul_stalls},
        {'cause': 'DIV multi-cycle',       'cycles': div_stalls},
        {'cause': 'Memory wait state',     'cycles': mem_wait_stalls},
        {'cause': 'Branch taken',          'cycles': br_taken_stalls},
        {'cause': 'Branch not-taken',      'cycles': br_ntaken_stalls},
        {'cause': 'Jump (JAL/JALR)',       'cycles': jump_stalls},
        {'cause': 'Zcmp/Zcmt multi-cycle', 'cycles': stack_stalls},
        {'cause': 'CSR/System',            'cycles': csr_sys_stalls},
        {'cause': 'Fetch wait state',      'cycles': fetch_stalls},
    ])
    stalls_by_cause['pct'] = (stalls_by_cause.cycles / stall_cycles * 100).round(1) if stall_cycles else 0

    # CPI per instruction category
    df2 = df.copy()
    df2['_gap'] = gaps
    cpi_cat = (df2.groupby('category')
                  .agg(count=('cycle', 'count'), cycles=('_gap', 'sum'))
                  .reset_index())
    cpi_cat['cycles'] += cpi_cat['count']   # add 1 execute cycle per instruction
    cpi_cat['cpi']     = (cpi_cat.cycles / cpi_cat['count']).round(3)
    cpi_cat = cpi_cat.sort_values('count', ascending=False).reset_index(drop=True)

    return {
        'total_instructions': n_instr,
        'total_cycles':       total_cycles,
        'ipc':                round(ipc, 3),
        'cpi':                round(cpi, 3),
        'stall_cycles':       stall_cycles,
        'stall_rate':         round(stall_cycles / total_cycles, 3) if total_cycles else 0,
        'stalls_by_cause':    stalls_by_cause,
        'cpi_by_category':    cpi_cat,
    }


# ─── instmix ──────────────────────────────────────────────────────────────────

def instmix(td: TraceData) -> dict:
    """Instruction mix and extension utilization.

    Returns
    -------
    dict with keys:
      by_category    DataFrame  columns: category, count, pct
      by_mnem        DataFrame  columns: mnem_base, count, pct  (top 40)
      compressed_pct float      % of compressed instructions
      ext_summary    DataFrame  columns: extension, count, pct  (STD/C/M/B totals)
      ext_detail     DataFrame  columns: extension, count, pct  (sub-extensions)
    """
    df = td.df
    if df.empty:
        return {}

    n = len(df)

    by_cat = (df.groupby('category').size()
                .reset_index(name='count')
                .sort_values('count', ascending=False)
                .reset_index(drop=True))
    by_cat['pct'] = (by_cat['count'] / n * 100).round(2)

    by_mnem = (df.groupby('mnem_base').size()
                 .reset_index(name='count')
                 .sort_values('count', ascending=False)
                 .head(40)
                 .reset_index(drop=True))
    by_mnem['pct'] = (by_mnem['count'] / n * 100).round(2)

    comp_pct = round(df.is_comp.sum() / n * 100, 2)

    # Extension mnemonic sets
    _ZBB_MNEMS = {
        'ANDN','ORN','XNOR','CLZ','CTZ','CPOP','SEXT.B','SEXT.H','ZEXT.H',
        'MIN','MINU','MAX','MAXU','ROL','ROR','ORC.B','REV8','RORI',
    }
    _ZBA_MNEMS  = {'SH1ADD','SH2ADD','SH3ADD'}
    _ZBS_MNEMS  = {'BCLR','BEXT','BINV','BSET','BCLRI','BEXTI','BINVI','BSETI'}
    _ZBC_MNEMS  = {'CLMUL','CLMULR','CLMULH'}

    _ZCA_MNEMS = {
        'C.LW','C.SW','C.LWSP','C.SWSP','C.JAL','C.J','C.JR','C.JALR',
        'C.BEQZ','C.BNEZ','C.ADDI','C.LI','C.LUI','C.SLLI','C.SRLI',
        'C.SRAI','C.ANDI','C.ADD','C.SUB','C.AND','C.OR','C.XOR','C.MV',
        'C.ADDI4SPN','C.ADDI16SP','C.NOP','C.EBREAK',
    }
    _ZCB_MNEMS = {
        'C.LBU','C.LHU','C.LH','C.SB','C.SH',
        'C.ZEXT.B','C.SEXT.B','C.ZEXT.H','C.SEXT.H','C.NOT','C.MUL',
    }
    _ZCMP_MNEMS = {'CM.PUSH','CM.POP','CM.POPRET','CM.POPRETZ','CM.MVA01S','CM.MVSA01'}
    _ZCMT_MNEMS = {'CM.JT','CM.JALT'}

    _C_CATS = [CAT_COMP_ALU, CAT_COMP_BR, CAT_COMP_JMP,
               CAT_COMP_LD,  CAT_COMP_ST, CAT_COMP_STK]
    _ALL_B_MNEMS = _ZBB_MNEMS | _ZBA_MNEMS | _ZBS_MNEMS | _ZBC_MNEMS

    # Summary: high-level extension totals
    c_cnt = int(df.category.isin(_C_CATS).sum())
    m_cnt = int(df.category.isin([CAT_MUL, CAT_DIV]).sum())
    b_cnt = int(df.mnem_base.isin(_ALL_B_MNEMS).sum())
    std_cnt = n - c_cnt - m_cnt - b_cnt
    ext_summary = pd.DataFrame([
        {'extension': 'Standard (RV32I)', 'count': std_cnt},
        {'extension': 'C (Compressed)',    'count': c_cnt},
        {'extension': 'M (Mul/Div)',       'count': m_cnt},
        {'extension': 'B (Bit-manip)',     'count': b_cnt},
    ])
    ext_summary['pct'] = (ext_summary['count'] / n * 100).round(2)

    # Detail: individual sub-extensions + standard
    detail_rows = [{'extension': 'Standard (RV32I)', 'count': std_cnt}]
    for ext, cats in [('M (MUL)', [CAT_MUL]), ('M (DIV)', [CAT_DIV])]:
        cnt = int(df.category.isin(cats).sum())
        detail_rows.append({'extension': ext, 'count': cnt})
    for ext, mnems in [('Zca', _ZCA_MNEMS), ('Zcb', _ZCB_MNEMS),
                       ('Zcmp', _ZCMP_MNEMS), ('Zcmt', _ZCMT_MNEMS),
                       ('Zbb', _ZBB_MNEMS), ('Zba', _ZBA_MNEMS),
                       ('Zbs', _ZBS_MNEMS), ('Zbc', _ZBC_MNEMS)]:
        cnt = int(df.mnem_base.isin(mnems).sum())
        detail_rows.append({'extension': ext, 'count': cnt})
    ext_detail = pd.DataFrame(detail_rows)
    ext_detail['pct'] = (ext_detail['count'] / n * 100).round(2)

    return {
        'by_category':    by_cat,
        'by_mnem':        by_mnem,
        'compressed_pct': comp_pct,
        'ext_summary':    ext_summary,
        'ext_detail':     ext_detail,
    }


# ─── branches ─────────────────────────────────────────────────────────────────

def branches(td: TraceData) -> dict:
    """Conditional branch analysis.

    Returns
    -------
    dict with keys:
      total            int
      taken_pct        float
      forward_pct      float
      backward_pct     float
      by_mnem          DataFrame  columns: mnem_base, count, taken, taken_pct
      distance_hist    DataFrame  columns: distance_bin, count
      rs1_freq         DataFrame  columns: reg, name, count, pct
      rs2_freq         DataFrame  columns: reg, name, count, pct
      pair_freq        DataFrame  columns: rs1, rs2, count, pct   (top 20)
      zero_compare_pct float      % of branches comparing against x0
      self_compare_cnt int        branches where rs1==rs2 (always taken/never)
      pair_transition  DataFrame  columns: from_pair, to_pair, count  (top 20)
      taken_rate_by_pair DataFrame columns: rs1, rs2, total, taken, taken_pct
    """
    df  = td.df
    brm = df[df.category.isin([CAT_BRANCH, CAT_COMP_BR])].copy()
    if brm.empty:
        return {'total': 0}

    n = len(brm)

    # Determine taken: next executed PC != fall-through PC (PC + instr_size).
    # Use the full trace to get the PC of the instruction immediately after
    # each branch — shift(-1) on df gives the correct next-instruction PC
    # regardless of how many non-branch instructions lie in between.
    instr_size = brm.instr.apply(lambda x: 2 if (x & 0x3) != 0x3 else 4)
    next_pc    = df['pc'].shift(-1).reindex(brm.index)
    taken_mask = (next_pc != (brm.pc + instr_size)).fillna(False)
    brm['taken'] = taken_mask

    # Forward/backward
    # For compressed branches the offset is encoded differently,
    # but we can infer direction from whether next_pc < current pc
    brm['backward'] = next_pc < brm.pc

    taken_pct    = round(brm.taken.mean() * 100, 1)
    forward_pct  = round((~brm.backward).mean() * 100, 1)
    backward_pct = round(brm.backward.mean() * 100, 1)

    by_mnem = (brm.groupby('mnem_base')
                  .agg(count=('taken','count'), taken=('taken','sum'))
                  .reset_index())
    by_mnem['taken_pct'] = (by_mnem.taken / by_mnem['count'] * 100).round(1)
    by_mnem = by_mnem.sort_values('count', ascending=False).reset_index(drop=True)

    # Branch distance (jump offset in instructions, approx from PC delta)
    pc_delta = (next_pc - brm.pc).dropna().astype(int)
    bins     = [-10000,-100,-20,-8,-4,0,4,8,20,100,10000]
    labels   = ['<-100','-100..-21','-20..-9','-8..-5','-4..-1','0..3','4..7','8..19','20..99','>100']
    dist_cut = pd.cut(pc_delta, bins=bins, labels=labels)
    dist_hist = dist_cut.value_counts().reset_index()
    dist_hist.columns = ['distance_bin', 'count']
    dist_hist = dist_hist.sort_index()

    # Register usage (only for standard branches that have rs1/rs2)
    std_br = brm[brm.rs1.notna()]

    def _reg_freq(col):
        freq = (std_br[col].dropna().astype(int)
                           .value_counts()
                           .reset_index())
        freq.columns = ['reg', 'count']
        freq['name'] = freq.reg.apply(_reg_name)
        freq['pct']  = (freq['count'] / len(std_br) * 100).round(1)
        return freq.sort_values('count', ascending=False).reset_index(drop=True)

    rs1_freq = _reg_freq('rs1')
    rs2_freq = _reg_freq('rs2') if std_br.rs2.notna().any() else pd.DataFrame()

    # Pair frequency
    pair_df = std_br[std_br.rs1.notna() & std_br.rs2.notna()].copy()
    pair_df['rs1'] = pair_df.rs1.astype(int)
    pair_df['rs2'] = pair_df.rs2.astype(int)
    pair_freq = (pair_df.groupby(['rs1','rs2']).agg(
                    count=('taken','count'),
                    taken=('taken','sum'))
                 .reset_index()
                 .sort_values('count', ascending=False)
                 .head(20)
                 .reset_index(drop=True))
    pair_freq['pct']       = (pair_freq['count'] / n * 100).round(1)
    pair_freq['taken_pct'] = (pair_freq.taken / pair_freq['count'] * 100).round(1)
    pair_freq['rs1_name']  = pair_freq.rs1.apply(_reg_name)
    pair_freq['rs2_name']  = pair_freq.rs2.apply(_reg_name)

    # Zero-compare: either rs1 or rs2 is x0
    zero_cmp = int(((pair_df.rs1 == 0) | (pair_df.rs2 == 0)).sum())
    zero_pct  = round(zero_cmp / len(pair_df) * 100, 1) if len(pair_df) else 0

    # Self-compare (rs1 == rs2)
    self_cmp  = int((pair_df.rs1 == pair_df.rs2).sum())

    # Pair transition matrix: what pair follows each pair?
    if len(pair_df) > 1:
        pair_key      = pair_df.rs1.astype(str) + ',' + pair_df.rs2.astype(str)
        from_pair     = pair_key.iloc[:-1].values
        to_pair       = pair_key.iloc[1:].values
        trans_counts  = Counter(zip(from_pair, to_pair))
        trans_df      = pd.DataFrame(
            [{'from_pair': k[0], 'to_pair': k[1], 'count': v}
             for k, v in trans_counts.most_common(20)]
        )
    else:
        trans_df = pd.DataFrame(columns=['from_pair','to_pair','count'])

    return {
        'total':             n,
        'taken_pct':         taken_pct,
        'forward_pct':       forward_pct,
        'backward_pct':      backward_pct,
        'by_mnem':           by_mnem,
        'distance_hist':     dist_hist,
        'rs1_freq':          rs1_freq,
        'rs2_freq':          rs2_freq,
        'pair_freq':         pair_freq,
        'zero_compare_pct':  zero_pct,
        'self_compare_cnt':  self_cmp,
        'pair_transition':   trans_df,
    }


# ─── jumps ────────────────────────────────────────────────────────────────────

def jumps(td: TraceData) -> dict:
    """JALR and JAL analysis — call/return patterns, RAS depth, autocorrelation.

    Returns
    -------
    dict with keys:
      jalr_total          int
      jalr_rs1_freq       DataFrame  columns: reg, name, count, pct
      jalr_offset_hist    DataFrame  columns: offset, count
      jalr_rs1_transition DataFrame  columns: from_reg, to_reg, count  (top 20)
      call_return_ratio   dict       {call, return, other, total}
      ras_depth_hist      DataFrame  columns: depth, count
      jal_total           int
      indirect_call_pct   float      JALR calls / total calls
      hot_targets         DataFrame  columns: pc, count  (top 20)
    """
    df = td.df

    # JALR
    jalr = df[df.mnem_base == 'JALR'].copy()
    jalr_total = len(jalr)

    if jalr_total == 0:
        jalr_result = {
            'jalr_total': 0, 'jalr_rs1_freq': pd.DataFrame(),
            'jalr_offset_hist': pd.DataFrame(), 'jalr_rs1_transition': pd.DataFrame(),
        }
    else:
        # rs1 frequency
        rs1_freq = (jalr.rs1.dropna().astype(int)
                        .value_counts()
                        .reset_index())
        rs1_freq.columns = ['reg', 'count']
        rs1_freq['name'] = rs1_freq.reg.apply(_reg_name)
        rs1_freq['pct']  = (rs1_freq['count'] / jalr_total * 100).round(1)
        rs1_freq = rs1_freq.sort_values('count', ascending=False).reset_index(drop=True)

        # Offset distribution (decoded from instruction bits [31:20])
        def _jalr_offset(instr):
            raw = (instr >> 20) & 0xFFF
            return raw if raw < 2048 else raw - 4096  # sign extend 12-bit

        jalr['offset'] = jalr.instr.apply(_jalr_offset)
        off_hist = jalr.offset.value_counts().head(20).reset_index()
        off_hist.columns = ['offset', 'count']
        off_hist = off_hist.sort_values('count', ascending=False).reset_index(drop=True)

        # rs1 autocorrelation / transition matrix
        rs1_seq   = jalr.rs1.dropna().astype(int)
        if len(rs1_seq) > 1:
            from_r = rs1_seq.iloc[:-1].values
            to_r   = rs1_seq.iloc[1:].values
            trans  = Counter(zip(from_r.tolist(), to_r.tolist()))

            # Late-source per transition: for the "to" JALR, did the preceding
            # instruction in the full trace write to its rs1?
            to_indices = rs1_seq.iloc[1:].index
            prev_rd    = df['rd'].shift(1).reindex(to_indices)
            to_rs1     = rs1_seq.iloc[1:]
            is_late    = (prev_rd.notna() & (prev_rd == to_rs1)).values
            trans_late = Counter()
            for (f, t), late in zip(zip(from_r.tolist(), to_r.tolist()), is_late):
                if late:
                    trans_late[(f, t)] += 1

            trans_df = pd.DataFrame(
                [{'from_reg': _reg_name(k[0]), 'to_reg': _reg_name(k[1]),
                  'count': v, 'late_count': trans_late.get(k, 0)}
                 for k, v in trans.most_common(20)]
            )
            trans_df['late_pct'] = (trans_df['late_count'] / trans_df['count'] * 100).round(1)
        else:
            trans_df = pd.DataFrame(columns=['from_reg','to_reg','count','late_count','late_pct'])

        jalr_result = {
            'jalr_total':          jalr_total,
            'jalr_rs1_freq':       rs1_freq,
            'jalr_offset_hist':    off_hist,
            'jalr_rs1_transition': trans_df,
        }

    # JAL
    jal = df[df.mnem_base == 'JAL']
    jal_total = len(jal)

    # Call / return / other classification
    # call   : JALR with rd=x1  OR  JAL with rd=x1
    # return : JALR with rd=x0 and rs1=x1
    # other  : everything else
    def _classify_jalr(row):
        rd  = int(row.rd)  if pd.notna(row.rd)  else -1
        rs1 = int(row.rs1) if pd.notna(row.rs1) else -1
        if rd == 1:
            return 'call'
        if rd == 0 and rs1 == 1:
            return 'return'
        return 'other'

    if not jalr.empty:
        jalr['cr_class'] = jalr.apply(_classify_jalr, axis=1)
        cr_counts = jalr.cr_class.value_counts().to_dict()
    else:
        cr_counts = {}

    jal_calls = int((jal.rd == 1).sum()) if not jal.empty else 0
    cr_counts['call'] = cr_counts.get('call', 0) + jal_calls

    call_return = {
        'call':   cr_counts.get('call',   0),
        'return': cr_counts.get('return', 0),
        'other':  cr_counts.get('other',  0),
        'total':  jalr_total + jal_total,
    }

    # RAS depth simulation
    depth   = 0
    depths  = []
    for row in df[df.mnem_base.isin(['JAL','JALR','C.JAL','C.JALR','C.JR'])].itertuples():
        mnem = row.mnem_base
        rd   = int(row.rd)  if pd.notna(row.rd)  else -1
        rs1  = int(row.rs1) if pd.notna(row.rs1) else -1
        if mnem in ('JAL','C.JAL') and rd == 1:
            depth += 1
        elif mnem in ('JALR','C.JALR') and rd == 1:
            depth += 1
        elif mnem in ('JALR','C.JR') and rd == 0 and rs1 == 1:
            depth = max(0, depth - 1)
        depths.append(depth)

    ras_hist = pd.Series(depths).value_counts().reset_index()
    ras_hist.columns = ['depth', 'count']
    ras_hist = ras_hist.sort_values('depth').reset_index(drop=True)

    # Hot jump targets (next pc after JAL/JALR)
    jumps_df = df[df.category.isin([CAT_JUMP, CAT_COMP_JMP])].copy()
    if not jumps_df.empty:
        target_pcs = df['pc'].shift(-1).reindex(jumps_df.index).dropna().astype(int)
        hot_tgt = (target_pcs.value_counts()
                              .head(20)
                              .reset_index())
        hot_tgt.columns = ['pc', 'count']
        hot_tgt['pc'] = hot_tgt.pc.apply(lambda x: f'0x{x:08x}')
    else:
        hot_tgt = pd.DataFrame(columns=['pc','count'])

    total_calls = call_return['call']
    indirect_call_pct = (
        round(cr_counts.get('call', 0) / total_calls * 100, 1)
        if total_calls else 0
    )

    # ── Late-source statistic for JALR ──────────────────────────────────────
    # How often does the instruction immediately before a JALR/C.JALR/C.JR
    # write to the JALR's rs1 (the jump target register)?
    jalr_all = df[df.mnem_base.isin(['JALR', 'C.JALR', 'C.JR'])].copy()
    n_jalr = len(jalr_all)
    if n_jalr > 0:
        prev_rd   = df['rd'].shift(1).reindex(jalr_all.index)
        jalr_rs1  = jalr_all['rs1']
        late_jalr = (prev_rd.notna()) & (prev_rd == jalr_rs1)
        jalr_late_src_pct = round(late_jalr.sum() / n_jalr * 100, 1)
    else:
        jalr_late_src_pct = 0.0

    # ── Shadow register analysis for JALR rs1 ────────────────────────────
    # Simulates LRU shadow register files of various sizes to determine
    # how many shadow registers are needed to cache JALR target registers.
    _SHADOW_SIZES = [1, 2, 4, 8]

    rs1_stream = (jalr.rs1.dropna().astype(int).tolist()
                  if not jalr.empty else [])

    # Build parallel late-source stream: True if the instruction before this
    # JALR writes to rs1 (i.e. RAW hazard — already stalling 1 cycle)
    if not jalr.empty and n_jalr > 0:
        late_stream = late_jalr.reindex(jalr.index, fill_value=False).tolist()
    else:
        late_stream = []

    if len(rs1_stream) >= 2:
        # Switch rate: % of consecutive JALRs where rs1 changes
        switches = sum(1 for i in range(1, len(rs1_stream))
                       if rs1_stream[i] != rs1_stream[i - 1])
        jalr_rs1_switch_rate = round(switches / (len(rs1_stream) - 1) * 100, 1)

        # Run length distribution: consecutive same-rs1 runs (aggregated + per-register)
        run_lengths = []          # (register, run_length) tuples
        cur_reg = rs1_stream[0]
        run_len = 1
        for i in range(1, len(rs1_stream)):
            if rs1_stream[i] == rs1_stream[i - 1]:
                run_len += 1
            else:
                run_lengths.append((cur_reg, run_len))
                cur_reg = rs1_stream[i]
                run_len = 1
        run_lengths.append((cur_reg, run_len))

        # Aggregated run length stats
        rl_vals = [rl for _, rl in run_lengths]
        rl_series = pd.Series(rl_vals)
        jalr_rs1_run_length = {
            'min':    int(rl_series.min()),
            'max':    int(rl_series.max()),
            'median': round(float(rl_series.median()), 1),
            'mean':   round(float(rl_series.mean()), 1),
            'hist':   (rl_series.value_counts()
                       .head(20)
                       .reset_index()
                       .rename(columns={'index': 'length', 0: 'count'})
                       .sort_values('length')
                       .reset_index(drop=True)),
        }

        # Per-register run length distribution
        rl_df = pd.DataFrame(run_lengths, columns=['reg', 'length'])
        rl_df['name'] = rl_df['reg'].apply(_reg_name)
        per_reg_rows = []
        for reg_name, grp in rl_df.groupby('name'):
            for length, count in grp['length'].value_counts().items():
                per_reg_rows.append({
                    'register': reg_name,
                    'length':   int(length),
                    'count':    int(count),
                })
        jalr_rs1_run_length_by_reg = (
            pd.DataFrame(per_reg_rows)
            .sort_values(['register', 'length'])
            .reset_index(drop=True)
            if per_reg_rows else pd.DataFrame()
        )

        # Shadow register hit rate sweep (LRU simulation)
        # Two metrics:
        #   hit_rate          — standard LRU hit rate (shadow has the register)
        #   effective_hit_rate — misses with late-source are "free" (already
        #                        stalling for RAW hazard), so they count as hits
        shadow_hit_rates = []
        has_late = len(late_stream) == len(rs1_stream)
        for size in _SHADOW_SIZES:
            cache = []  # LRU: index 0 = most recently used
            hits = 0
            free_misses = 0  # misses masked by late-source stall
            for i, reg in enumerate(rs1_stream):
                if reg in cache:
                    hits += 1
                    cache.remove(reg)
                    cache.insert(0, reg)  # move to front
                else:
                    if has_late and late_stream[i]:
                        free_misses += 1
                    cache.insert(0, reg)
                    if len(cache) > size:
                        cache.pop()
            hit_rate = round(hits / len(rs1_stream) * 100, 1)
            eff_rate = round((hits + free_misses) / len(rs1_stream) * 100, 1)
            shadow_hit_rates.append({
                'shadow_regs':      size,
                'hit_rate':         hit_rate,
                'effective_hit_rate': eff_rate,
                'miss_rate':        round(100 - hit_rate, 1),
                'free_miss_rate':   round(free_misses / len(rs1_stream) * 100, 1),
            })
        jalr_shadow_hit_sweep = pd.DataFrame(shadow_hit_rates)
    else:
        jalr_rs1_switch_rate  = 0.0
        jalr_rs1_run_length   = {
            'min': 0, 'max': 0, 'median': 0, 'mean': 0,
            'hist': pd.DataFrame(),
        }
        jalr_rs1_run_length_by_reg = pd.DataFrame()
        jalr_shadow_hit_sweep = pd.DataFrame()

    return {
        **jalr_result,
        'call_return_ratio':      call_return,
        'ras_depth_hist':         ras_hist,
        'jal_total':              jal_total,
        'indirect_call_pct':      indirect_call_pct,
        'hot_targets':            hot_tgt,
        'jalr_late_source_pct':   jalr_late_src_pct,
        'jalr_rs1_switch_rate':        jalr_rs1_switch_rate,
        'jalr_rs1_run_length':         jalr_rs1_run_length,
        'jalr_rs1_run_length_by_reg':  jalr_rs1_run_length_by_reg,
        'jalr_shadow_hit_sweep':       jalr_shadow_hit_sweep,
    }


# ─── memory ───────────────────────────────────────────────────────────────────

def memory(td: TraceData) -> dict:
    """Memory access pattern analysis.

    Returns
    -------
    dict with keys:
      total_loads          int
      total_stores         int
      load_store_ratio     float
      access_size          DataFrame  columns: size, count, pct
      sp_relative_pct      float
      stride_hist          DataFrame  columns: stride, count  (top 20 strides)
      load_use_dist_hist   DataFrame  columns: distance, count
      addr_range           dict       {min, max, span}
    """
    df   = td.df
    ld_m = df.category.isin([CAT_LOAD,  CAT_COMP_LD])
    st_m = df.category.isin([CAT_STORE, CAT_COMP_ST])
    mem_m = ld_m | st_m

    mem_df = df[mem_m].copy()
    n_ld   = int(ld_m.sum())
    n_st   = int(st_m.sum())

    if mem_df.empty:
        return {'total_loads': 0, 'total_stores': 0}

    ls_ratio = round(n_ld / n_st, 2) if n_st else float('inf')

    # Access size from mnemonic
    _SIZE_MAP = {
        'LB':1,'LBU':1,'SB':1,'C.LBU':1,'C.SB':1,
        'LH':2,'LHU':2,'SH':2,'C.LHU':2,'C.LH':2,'C.SH':2,
        'LW':4,'SW':4,'C.LW':4,'C.LWSP':4,'C.SW':4,'C.SWSP':4,
    }
    mem_df['size'] = mem_df.mnem_base.map(_SIZE_MAP).fillna(4).astype(int)
    size_df = mem_df.groupby('size').size().reset_index(name='count')
    size_df.columns = ['size','count']
    size_df['pct'] = (size_df['count'] / len(mem_df) * 100).round(1)

    # SP-relative
    sp_rel_pct = round(
        (mem_df.rs1.fillna(-1).astype(int) == _SP).sum() / len(mem_df) * 100, 1
    )

    # Stride = difference between consecutive memory addresses
    addrs  = mem_df.mem_addr.dropna().astype(int)
    strides = addrs.diff().dropna().astype(int)
    stride_hist = (strides.value_counts()
                           .head(20)
                           .reset_index())
    stride_hist.columns = ['stride', 'count']
    stride_hist = stride_hist.sort_values('count', ascending=False).reset_index(drop=True)

    # Load-to-use distance: cycles between a LOAD and first dependent instruction
    # Single pass over the full trace: track pending loads by destination register,
    # consume on first use as rs1/rs2, overwrite on new write to same register.
    load_use_dists = []
    ld_set = set(df.index[ld_m & df.rd.notna()])
    rd_to_load_cycle = {}
    for row in df.itertuples():
        # Check use before recording new load (handles back-to-back load→use)
        for rs_val in (row.rs1, row.rs2):
            if pd.notna(rs_val):
                rs_val = int(rs_val)
                if rs_val in rd_to_load_cycle:
                    dist = int(row.cycle) - rd_to_load_cycle[rs_val]
                    if 1 <= dist <= 16:
                        load_use_dists.append(dist)
                    del rd_to_load_cycle[rs_val]
        # Record load destination or clear on overwrite by non-load
        if row.Index in ld_set:
            rd_to_load_cycle[int(row.rd)] = int(row.cycle)
        elif pd.notna(row.rd):
            rd_to_load_cycle.pop(int(row.rd), None)

    lud_hist = (pd.Series(load_use_dists)
                  .value_counts()
                  .reset_index())
    lud_hist.columns = ['distance', 'count']
    lud_hist = lud_hist.sort_values('distance').reset_index(drop=True)

    valid_addrs = mem_df.mem_addr.dropna().astype(int)
    addr_range = {
        'min':  int(valid_addrs.min()) if len(valid_addrs) else 0,
        'max':  int(valid_addrs.max()) if len(valid_addrs) else 0,
        'span': int(valid_addrs.max() - valid_addrs.min()) if len(valid_addrs) else 0,
    }

    return {
        'total_loads':        n_ld,
        'total_stores':       n_st,
        'load_store_ratio':   ls_ratio,
        'access_size':        size_df,
        'sp_relative_pct':    sp_rel_pct,
        'stride_hist':        stride_hist,
        'load_use_dist_hist': lud_hist,
        'addr_range':         addr_range,
    }


# ─── registers ────────────────────────────────────────────────────────────────

def registers(td: TraceData) -> dict:
    """Register file pressure analysis.

    Returns
    -------
    dict with keys:
      write_freq    DataFrame  columns: reg, name, count, pct  (x0-x31)
      rs1_freq      DataFrame  columns: reg, name, count, pct
      rs2_freq      DataFrame  columns: reg, name, count, pct
      reuse_dist    DataFrame  columns: distance_bin, count
      caller_saved_pct  float   % of writes to caller-saved regs (t0-t6, a0-a7)
      callee_saved_pct  float   % of writes to callee-saved regs (s0-s11)
    """
    df = td.df

    def _reg_hist(col):
        freq = (df[col].dropna().astype(int)
                       .value_counts()
                       .reindex(range(32), fill_value=0)
                       .reset_index())
        freq.columns = ['reg', 'count']
        freq['name'] = freq.reg.apply(_reg_name)
        freq['pct']  = (freq['count'] / freq['count'].sum() * 100).round(2)
        return freq

    wr_freq  = _reg_hist('rd')
    rs1_freq = _reg_hist('rs1')
    rs2_freq = _reg_hist('rs2')

    # ABI groups
    _CALLER = set(range(5, 8)) | set(range(10, 18)) | set(range(28, 32))  # t0-t2,a0-a7,t3-t6
    _CALLEE = {8, 9} | set(range(18, 28))                                  # s0-s1, s2-s11

    total_wr = wr_freq['count'].sum()
    caller_pct = round(wr_freq[wr_freq.reg.isin(_CALLER)]['count'].sum() / total_wr * 100, 1) if total_wr else 0
    callee_pct = round(wr_freq[wr_freq.reg.isin(_CALLEE)]['count'].sum() / total_wr * 100, 1) if total_wr else 0

    # Register reuse distance: instructions between write and next read of same reg
    last_write = {}
    dists = []
    for row in df.itertuples():
        for rs_val in (row.rs1, row.rs2):
            if pd.notna(rs_val):
                rs_val = int(rs_val)
                if rs_val in last_write:
                    d = row.Index - last_write[rs_val]  # iloc distance
                    dists.append(min(d, 64))
        if pd.notna(row.rd):
            last_write[int(row.rd)] = row.Index

    bins   = [0,1,2,4,8,16,32,64,float('inf')]
    labels = ['1','2','3-4','5-8','9-16','17-32','33-64','>64']
    cut    = pd.cut(pd.Series(dists), bins=bins, labels=labels, right=True)
    reuse  = cut.value_counts().reset_index()
    reuse.columns = ['distance_bin', 'count']
    reuse = reuse.sort_index()

    return {
        'write_freq':       wr_freq,
        'rs1_freq':         rs1_freq,
        'rs2_freq':         rs2_freq,
        'reuse_dist':       reuse,
        'caller_saved_pct': caller_pct,
        'callee_saved_pct': callee_pct,
    }


# ─── dependencies ─────────────────────────────────────────────────────────────

def dependencies(td: TraceData) -> dict:
    """RAW hazard and dependency chain analysis.

    Returns
    -------
    dict with keys:
      prod_consumer_dist  DataFrame  columns: distance, count  (1-16 instr gap)
      common_chains       DataFrame  columns: chain, count     (top 20 bigrams)
      avg_chain_length    float
    """
    df = td.df

    last_write_idx = {}   # reg → instruction index of last write
    prod_dists     = []
    chains         = []   # (producer_mnem, consumer_mnem) bigrams

    for i, row in enumerate(df.itertuples()):
        for rs_attr in ('rs1', 'rs2'):
            rs = getattr(row, rs_attr)
            if pd.notna(rs):
                rs = int(rs)
                if rs in last_write_idx:
                    dist = i - last_write_idx[rs]
                    if 1 <= dist <= 32:
                        prod_dists.append(dist)
                        # Record (producer_mnem, consumer_mnem) pair
                        prod_idx = last_write_idx[rs]
                        chains.append((df.iloc[prod_idx].mnem_base, row.mnem_base))

        if pd.notna(row.rd) and int(row.rd) != 0:
            last_write_idx[int(row.rd)] = i

    dist_df = pd.Series(prod_dists).value_counts().reset_index()
    dist_df.columns = ['distance', 'count']
    dist_df = dist_df.sort_values('distance').reset_index(drop=True)

    chain_df = pd.DataFrame(Counter(chains).most_common(20),
                            columns=['chain_tuple', 'count'])
    chain_df['chain'] = chain_df.chain_tuple.apply(lambda t: f'{t[0]} → {t[1]}')
    chain_df = (chain_df[['chain','count']]
                  .sort_values('count', ascending=False)
                  .head(20)
                  .reset_index(drop=True))

    avg_len = round(np.mean(prod_dists), 2) if prod_dists else 0

    return {
        'prod_consumer_dist': dist_df,
        'common_chains':      chain_df,
        'avg_chain_length':   avg_len,
    }


# ─── ngrams ───────────────────────────────────────────────────────────────────

def ngrams(td: TraceData, n: int = 2, top_k: int = 20) -> pd.DataFrame:
    """Most common instruction n-grams (bigrams or trigrams).

    Returns DataFrame with columns: ngram, count, pct.
    """
    df    = td.df
    mnems = df.mnem_base.tolist()
    grams = Counter(zip(*[mnems[i:] for i in range(n)]))
    total = sum(grams.values())

    result = pd.DataFrame(
        [{'ngram': ' → '.join(g), 'count': c} for g, c in grams.most_common(top_k)]
    )
    if not result.empty:
        result['pct'] = (result['count'] / total * 100).round(3)
    return result


_FUSION_CANDIDATES = {
    ('LUI',   'ADDI'):   'LI pseudo (32-bit constant materialization)',
    ('AUIPC', 'ADDI'):   'PC-relative address formation',
    ('AUIPC', 'JALR'):   'Indirect long-range call',
    ('AUIPC', 'LW'):     'PC-relative load',
    ('AUIPC', 'LD'):     'PC-relative load',
    ('ADD',   'ADDI'):   'Base+offset address idiom',
}


def fusion_candidates(bigrams: pd.DataFrame) -> pd.DataFrame:
    """Filter bigrams for known macro-fusion candidate pairs.

    Parameters
    ----------
    bigrams : DataFrame with columns: ngram, count, pct  (from ngrams(n=2))

    Returns
    -------
    DataFrame with columns: sequence, count, pct, description
    """
    if bigrams is None or bigrams.empty:
        return pd.DataFrame(columns=['sequence', 'count', 'pct', 'description'])

    rows = []
    for row in bigrams.itertuples():
        parts = str(row.ngram).split(' → ')
        if len(parts) == 2:
            key = (parts[0].strip().upper(), parts[1].strip().upper())
            desc = _FUSION_CANDIDATES.get(key)
            if desc:
                rows.append({
                    'sequence':    row.ngram,
                    'count':       row.count,
                    'pct':         getattr(row, 'pct', 0),
                    'description': desc,
                })
    return pd.DataFrame(rows) if rows else pd.DataFrame(
        columns=['sequence', 'count', 'pct', 'description'])


# ─── immediates ───────────────────────────────────────────────────────────────

def immediates(td: TraceData) -> dict:
    """Immediate value distribution analysis.

    Returns
    -------
    dict with keys:
      addi_imm_hist      DataFrame  columns: imm_bin, count
      addi_comp_eligible int        ADDI with imm in [-32,31] (C.ADDI eligible)
      addi_comp_pct      float
      lui_addi_pairs     int        consecutive LUI+ADDI pairs (32-bit constants)
      load_offset_hist   DataFrame  columns: offset_bin, count
    """
    df = td.df

    # ADDI immediate: bits [31:20], sign-extended
    addi = df[df.mnem_base == 'ADDI'].copy()
    if not addi.empty:
        addi['imm'] = addi.instr.apply(
            lambda x: ((x >> 20) & 0xFFF) - (4096 if ((x >> 20) & 0x800) else 0)
        )
        bins   = [-2048,-512,-128,-32,-1,0,31,127,511,2047]
        labels = ['<-512','-512..-129','-128..-33','-32..-2','-1','0..31','32..127','128..511','512..2047']
        cut    = pd.cut(addi.imm, bins=bins, labels=labels, right=True)
        hist   = cut.value_counts().reset_index()
        hist.columns = ['imm_bin', 'count']
        hist   = hist.sort_index()
        c_elig = int(((addi.imm >= -32) & (addi.imm <= 31) & (addi.rs1 == addi.rd)).sum())
        c_pct  = round(c_elig / len(addi) * 100, 1)
    else:
        hist, c_elig, c_pct = pd.DataFrame(), 0, 0.0

    # LUI+ADDI consecutive pairs
    pairs = 0
    mnems = df.mnem_base.tolist()
    for i in range(len(mnems) - 1):
        if mnems[i] == 'LUI' and mnems[i+1] == 'ADDI':
            pairs += 1

    # Load offset distribution
    loads = df[df.category.isin([CAT_LOAD, CAT_COMP_LD])].copy()
    if not loads.empty:
        loads['offset'] = loads.instr.apply(
            lambda x: ((x >> 20) & 0xFFF) - (4096 if ((x >> 20) & 0x800) else 0)
        )
        bins2   = [-2048,-128,-32,-8,0,7,31,127,2047]
        labels2 = ['<-128','-128..-33','-32..-9','-8..-1','0..7','8..31','32..127','128..2047']
        cut2    = pd.cut(loads.offset, bins=bins2, labels=labels2, right=True)
        off_hist = cut2.value_counts().reset_index()
        off_hist.columns = ['offset_bin', 'count']
        off_hist = off_hist.sort_index()
    else:
        off_hist = pd.DataFrame()

    return {
        'addi_imm_hist':      hist,
        'addi_comp_eligible': c_elig,
        'addi_comp_pct':      c_pct,
        'lui_addi_pairs':     pairs,
        'load_offset_hist':   off_hist,
    }


# ─── loops ────────────────────────────────────────────────────────────────────

def loops(td: TraceData) -> dict:
    """Loop detection and characterization via branch back-edges.

    Returns
    -------
    dict with keys:
      total_back_branches  int
      back_branch_pct      float     % of all branches
      loop_sites           DataFrame columns: back_edge_pc, target_pc,
                                              body_size, trips, taken_pct
      trip_count_hist      DataFrame columns: trip_bin, count
    """
    df = td.df
    br = df[df.category.isin([CAT_BRANCH, CAT_COMP_BR])].copy()
    if br.empty:
        return {'total_back_branches': 0}

    next_pc = df['pc'].shift(-1).reindex(br.index).fillna(0).astype(int)
    back    = next_pc < br.pc

    n_back  = int(back.sum())
    back_pct = round(n_back / len(br) * 100, 1)

    back_br = br[back].copy()
    back_br['target_pc'] = next_pc[back].astype(int)
    back_br['body_size'] = (back_br.pc - back_br.target_pc) // 4  # approx instr count

    # Trip count: consecutive taken back-branches to the same target
    trips_lists: dict[tuple, list] = defaultdict(list)
    cur_trips:   dict[tuple, int]  = defaultdict(int)
    prev_key: Optional[tuple] = None
    for row in back_br.itertuples():
        key = (int(row.pc), int(row.target_pc))
        if key == prev_key:
            cur_trips[key] += 1
        else:
            if prev_key is not None and cur_trips[prev_key]:
                trips_lists[prev_key].append(cur_trips[prev_key])
                cur_trips[prev_key] = 0
            cur_trips[key] = 1
        prev_key = key
    if prev_key and cur_trips[prev_key]:
        trips_lists[prev_key].append(cur_trips[prev_key])

    all_trips: list[int] = []
    site_rows = []
    all_keys = set(trips_lists) | set(cur_trips)
    for key in all_keys:
        pc, tgt = key
        trips = trips_lists[key]
        all_trips.extend(trips)
        site_rows.append({
            'back_edge_pc': f'0x{pc:08x}',
            'target_pc':    f'0x{tgt:08x}',
            'body_size':    int((pc - tgt) // 4),
            'trips':        len(trips),
            'avg_trip_cnt': round(np.mean(trips), 1) if trips else 0,
        })

    sites_df = (pd.DataFrame(site_rows)
                  .sort_values('trips', ascending=False)
                  .reset_index(drop=True))

    bins   = [0,1,2,4,8,16,32,64,256,float('inf')]
    labels = ['1','2','3-4','5-8','9-16','17-32','33-64','65-256','>256']
    trip_hist = pd.cut(pd.Series(all_trips), bins=bins, labels=labels, right=True)
    trip_hist = trip_hist.value_counts().reset_index()
    trip_hist.columns = ['trip_bin', 'count']
    trip_hist = trip_hist.sort_index()

    return {
        'total_back_branches': n_back,
        'back_branch_pct':     back_pct,
        'loop_sites':          sites_df,
        'trip_count_hist':     trip_hist,
    }


# ─── hotcode ──────────────────────────────────────────────────────────────────

def hotcode(td: TraceData, top_k: int = 30) -> dict:
    """PC execution frequency and hotspot analysis.

    Returns
    -------
    dict with keys:
      top_pcs      DataFrame  columns: pc, pc_hex, count, pct, category
      pc_hist      DataFrame  columns: pc_hex, count  (all PCs, sorted by count)
    """
    df = td.df
    if df.empty:
        return {}

    n = len(df)
    freq = df.groupby('pc').agg(
        count=('pc', 'count'),
        category=('category', lambda x: x.mode().iloc[0]),
    ).reset_index()
    freq['pct']    = (freq['count'] / n * 100).round(2)
    freq['pc_hex'] = freq.pc.apply(lambda x: f'0x{x:08x}')
    freq = freq.sort_values('count', ascending=False).reset_index(drop=True)

    top = freq.head(top_k).copy()

    return {
        'top_pcs': top[['pc','pc_hex','count','pct','category']],
        'pc_hist': freq[['pc_hex','count']],
    }


# ─── Numba JIT helpers for branch predictor simulation ───────────────────────

@njit(cache=True)
def _sim_bimodal_jit(pcs, taken, n, table_size, two_bit):
    """Simulate 1-bit or 2-bit bimodal predictor. Returns miss count."""
    mask = table_size - 1
    if two_bit:
        table = np.full(table_size, 2, dtype=np.int8)
    else:
        table = np.zeros(table_size, dtype=np.uint8)
    miss = 0
    for i in range(n):
        idx = (pcs[i] >> 2) & mask
        actual = 1 if taken[i] else 0
        if two_bit:
            pred = 1 if table[idx] >= 2 else 0
            miss += 1 if pred != actual else 0
            if actual:
                table[idx] = min(3, table[idx] + 1)
            else:
                table[idx] = max(0, table[idx] - 1)
        else:
            miss += 1 if table[idx] != actual else 0
            table[idx] = actual
    return miss


@njit(cache=True)
def _sim_gshare_jit(pcs, taken, n, table_size):
    """Simulate GShare predictor. Returns miss count."""
    mask = table_size - 1
    table = np.full(table_size, 2, dtype=np.int8)
    ghr = 0
    miss = 0
    for i in range(n):
        idx = ((pcs[i] >> 2) ^ ghr) & mask
        actual = 1 if taken[i] else 0
        pred = 1 if table[idx] >= 2 else 0
        miss += 1 if pred != actual else 0
        if actual:
            table[idx] = min(3, table[idx] + 1)
        else:
            table[idx] = max(0, table[idx] - 1)
        ghr = ((ghr << 1) | actual) & mask
    return miss


@njit(cache=True)
def _sim_micro_tage_jit(pcs, taken, n, base_entries, tagged_entries, tag_width):
    """Simulate micro-TAGE predictor. Returns miss count."""
    base_mask = base_entries - 1
    tag_mask = tagged_entries - 1
    tag_w_mask = (1 << tag_width) - 1
    # history length: log2(tagged_entries) + 4
    tag_idx_bits = 0
    tmp = tagged_entries
    while tmp > 1:
        tag_idx_bits += 1
        tmp >>= 1
    hist_len = tag_idx_bits + 4
    hist_mask = (1 << hist_len) - 1

    base_table = np.full(base_entries, 2, dtype=np.int8)
    tag_counters = np.full(tagged_entries, 2, dtype=np.int8)
    tag_tags = np.full(tagged_entries, -1, dtype=np.int32)
    tag_useful = np.zeros(tagged_entries, dtype=np.uint8)
    ghr = 0
    miss = 0

    for i in range(n):
        pc_val = pcs[i]
        actual = 1 if taken[i] else 0

        base_idx = (pc_val >> 2) & base_mask
        tag_idx = ((pc_val >> 2) ^ ghr) & tag_mask
        tag_val = ((pc_val >> 2) ^ (ghr >> tag_idx_bits)) & tag_w_mask

        tag_hit = (tag_tags[tag_idx] == tag_val)
        if tag_hit:
            pred = 1 if tag_counters[tag_idx] >= 2 else 0
        else:
            pred = 1 if base_table[base_idx] >= 2 else 0

        miss += 1 if pred != actual else 0

        if tag_hit:
            if actual:
                tag_counters[tag_idx] = min(3, tag_counters[tag_idx] + 1)
            else:
                tag_counters[tag_idx] = max(0, tag_counters[tag_idx] - 1)
            base_pred = 1 if base_table[base_idx] >= 2 else 0
            if pred == actual and base_pred != actual:
                tag_useful[tag_idx] = 1
            elif pred != actual:
                tag_useful[tag_idx] = 0
        else:
            if pred != actual:
                if tag_useful[tag_idx] == 0:
                    tag_tags[tag_idx] = tag_val
                    tag_counters[tag_idx] = 2 if actual else 1
                    tag_useful[tag_idx] = 0

        if actual:
            base_table[base_idx] = min(3, base_table[base_idx] + 1)
        else:
            base_table[base_idx] = max(0, base_table[base_idx] - 1)

        ghr = ((ghr << 1) | actual) & hist_mask

    return miss


@njit(cache=True)
def _sim_tournament_jit(pcs, taken, n, entries):
    """Simulate tournament predictor. Returns miss count."""
    t_mask = entries - 1
    bimod_tbl = np.full(entries, 2, dtype=np.int8)
    gshare_tbl = np.full(entries, 2, dtype=np.int8)
    choice_tbl = np.full(entries, 2, dtype=np.int8)
    ghr = 0
    hist_mask = t_mask
    miss = 0

    for i in range(n):
        pc_val = pcs[i]
        actual = 1 if taken[i] else 0
        b_idx = (pc_val >> 2) & t_mask
        g_idx = ((pc_val >> 2) ^ ghr) & t_mask
        c_idx = ghr & t_mask

        pred_b = 1 if bimod_tbl[b_idx] >= 2 else 0
        pred_g = 1 if gshare_tbl[g_idx] >= 2 else 0
        pred_c = pred_g if choice_tbl[c_idx] >= 2 else pred_b

        if pred_c != actual:
            miss += 1

        # Update choice only when predictors disagree
        if pred_b != pred_g:
            if pred_g == actual:
                choice_tbl[c_idx] = min(3, choice_tbl[c_idx] + 1)
            else:
                choice_tbl[c_idx] = max(0, choice_tbl[c_idx] - 1)

        # Update both predictors
        if actual:
            bimod_tbl[b_idx] = min(3, bimod_tbl[b_idx] + 1)
            gshare_tbl[g_idx] = min(3, gshare_tbl[g_idx] + 1)
        else:
            bimod_tbl[b_idx] = max(0, bimod_tbl[b_idx] - 1)
            gshare_tbl[g_idx] = max(0, gshare_tbl[g_idx] - 1)

        ghr = ((ghr << 1) | actual) & hist_mask

    return miss


# ─── branch_prediction ────────────────────────────────────────────────────────

def branch_prediction(td: TraceData) -> dict:
    """Simulate branch predictor schemes on the trace.

    Returns
    -------
    dict with keys:
      total_branches        int
      oracle_mispredict_pct float    theoretical minimum misprediction %
      summary               DataFrame  scheme / label / table_bits / mispredict_pct
      size_sweep            DataFrame  scheme / table_bits / mispredict_pct
      hardest               DataFrame  pc_hex / total / mispredict_pct / taken_pct
    """
    df  = td.df
    brm = df[df.category.isin([CAT_BRANCH, CAT_COMP_BR])].copy()
    if brm.empty:
        return {'total_branches': 0}

    # ── Extract taken / not-taken ──────────────────────────────────────────────
    instr_size = brm.instr.apply(lambda x: 2 if (x & 0x3) != 0x3 else 4)
    next_pc    = df['pc'].shift(-1).reindex(brm.index)
    taken_mask = (next_pc != (brm.pc + instr_size)).fillna(False)

    pcs      = brm.pc.to_numpy(dtype=np.int64)
    taken    = taken_mask.to_numpy(dtype=bool)
    next_pcs = next_pc.to_numpy(dtype=np.float64)   # may contain NaN

    n = len(pcs)

    # ── Per-PC direction for BTFN ─────────────────────────────────────────────
    # direction[pc] = True  → backward (predict taken)
    # direction[pc] = False → forward  (predict not-taken)
    direction: dict = {}
    for i in range(n):
        if taken[i] and pcs[i] not in direction and not np.isnan(next_pcs[i]):
            direction[pcs[i]] = int(next_pcs[i]) < pcs[i]

    # ── Helper ────────────────────────────────────────────────────────────────
    def _pct(misses: int) -> float:
        return round(misses / n * 100, 2) if n else 0.0

    # ── Static predictors ─────────────────────────────────────────────────────
    always_nt_miss = int(taken.sum())
    always_t_miss  = int((~taken).sum())

    btfn_miss = 0
    for i in range(n):
        pred_taken = direction.get(pcs[i], False)   # forward → predict NT
        btfn_miss += int(pred_taken != taken[i])

    # ── Table sizes to sweep ──────────────────────────────────────────────────
    TABLE_BITS = [2, 3, 4, 5, 6, 7, 8, 10, 12]

    summary_rows:    list = []
    size_sweep_rows: list = []

    summary_rows.extend([
        {'scheme': 'always_nt', 'label': 'Always NT',  'table_bits': None, 'mispredict_pct': _pct(always_nt_miss)},
        {'scheme': 'always_t',  'label': 'Always T',   'table_bits': None, 'mispredict_pct': _pct(always_t_miss)},
        {'scheme': 'btfn',      'label': 'BTFN',       'table_bits': None, 'mispredict_pct': _pct(btfn_miss)},
    ])

    # ── 1-bit bimodal ─────────────────────────────────────────────────────────
    for bits in TABLE_BITS:
        size = 1 << bits
        miss = _sim_bimodal_jit(pcs, taken, n, size, False)
        mp = _pct(miss)
        size_sweep_rows.append({'scheme': 'bimodal_1bit', 'table_bits': bits, 'mispredict_pct': mp})
        if bits == 6:
            summary_rows.append({'scheme': 'bimodal_1bit', 'label': f'1-bit bimodal ({bits}b)', 'table_bits': bits, 'mispredict_pct': mp})

    # ── 2-bit saturating bimodal ──────────────────────────────────────────────
    for bits in TABLE_BITS:
        size = 1 << bits
        miss = _sim_bimodal_jit(pcs, taken, n, size, True)
        mp = _pct(miss)
        size_sweep_rows.append({'scheme': 'bimodal_2bit', 'table_bits': bits, 'mispredict_pct': mp})
        if bits == 6:
            summary_rows.append({'scheme': 'bimodal_2bit', 'label': f'2-bit bimodal ({bits}b)', 'table_bits': bits, 'mispredict_pct': mp})

    # ── GShare ────────────────────────────────────────────────────────────────
    for bits in TABLE_BITS:
        size = 1 << bits
        miss = _sim_gshare_jit(pcs, taken, n, size)
        mp = _pct(miss)
        size_sweep_rows.append({'scheme': 'gshare', 'table_bits': bits, 'mispredict_pct': mp})
        if bits == 8:
            summary_rows.append({'scheme': 'gshare', 'label': f'GShare ({bits}b hist)', 'table_bits': bits, 'mispredict_pct': mp})

    # ── Micro-TAGE (bimodal base + one tagged table) ───────────────────────
    # 12 flavors: base 32 or 64 × tagged 8/16/32 × tag width 6 or 8 bits
    #
    # Naming: micro_tage_B{base}T{tagged}w{tag_width}
    #   e.g.  micro_tage_B32T8w6  = base 32, tagged 8, 6-bit tag
    #
    # Each variant uses table_bits matching its base (5 for 32, 6 for 64)
    # so they appear at the correct x position in size-sweep charts.

    _UTAGE_CONFIGS = [
        # (base_entries, tagged_entries, tag_width)
        (32,  8, 6),
        (32, 16, 6),  (32, 16, 8),
        (32, 32, 6),  (32, 32, 8),
        (64,  8, 6),
        (64, 16, 6),  (64, 16, 8),
        (64, 32, 6),  (64, 32, 8),
        (64, 64, 6),  (64, 64, 8),
    ]

    for base_entries, tagged_entries, tag_width in _UTAGE_CONFIGS:
        base_bits = int(np.log2(base_entries))
        scheme_name = f'micro_tage_B{base_entries}T{tagged_entries}w{tag_width}'
        miss = _sim_micro_tage_jit(pcs, taken, n, base_entries, tagged_entries, tag_width)
        mp = _pct(miss)
        size_sweep_rows.append({
            'scheme':         scheme_name,
            'table_bits':     base_bits,
            'mispredict_pct': mp,
        })
        # Add best 64-base variant to summary bar chart
        if base_entries == 64 and tagged_entries == 32 and tag_width == 8:
            summary_rows.append({
                'scheme':         scheme_name,
                'label':          f'µTAGE B{base_entries} T{tagged_entries} w{tag_width}',
                'table_bits':     base_bits,
                'mispredict_pct': mp,
            })

    # ── Tournament predictor (bimodal vs GShare + choice) ──────────────────
    # All three tables are flat 2-bit saturating counter arrays.
    #   Predictor A: bimodal   — index = (PC >> 2) & mask
    #   Predictor B: GShare    — index = ((PC >> 2) XOR GHR) & mask
    #   Choice:      selector  — index = GHR & mask  (>=2 → use GShare)
    # Choice only updates when A and B disagree.

    _TOURNAMENT_ENTRIES = [32, 64]

    for t_entries in _TOURNAMENT_ENTRIES:
        t_bits = int(np.log2(t_entries))
        miss = _sim_tournament_jit(pcs, taken, n, t_entries)
        scheme_name = f'tournament_{t_entries}'
        mp = _pct(miss)
        size_sweep_rows.append({
            'scheme':         scheme_name,
            'table_bits':     t_bits,
            'mispredict_pct': mp,
        })
        # Add 64-entry variant to summary bar chart
        if t_entries == 64:
            summary_rows.append({
                'scheme':         scheme_name,
                'label':          f'Tournament {t_entries}',
                'table_bits':     t_bits,
                'mispredict_pct': mp,
            })

    # ── Oracle floor ─────────────────────────────────────────────────────────
    pc_taken     = defaultdict(int)
    pc_not_taken = defaultdict(int)
    for i in range(n):
        if taken[i]:
            pc_taken[pcs[i]] += 1
        else:
            pc_not_taken[pcs[i]] += 1

    oracle_miss = sum(
        min(pc_taken.get(pc, 0), pc_not_taken.get(pc, 0))
        for pc in set(pc_taken) | set(pc_not_taken)
    )
    oracle_pct = _pct(oracle_miss)

    # ── Per-PC breakdown using 2-bit bimodal 64-entry ─────────────────────────
    table64 = np.full(64, 2, dtype=np.int8)
    pc_misses: dict = defaultdict(int)
    pc_totals: dict = defaultdict(int)
    for i in range(n):
        idx    = (int(pcs[i]) >> 2) & 63
        pred   = 1 if table64[idx] >= 2 else 0
        actual = int(taken[i])
        pc_totals[pcs[i]] += 1
        if pred != actual:
            pc_misses[pcs[i]] += 1
        table64[idx] = min(3, table64[idx] + 1) if actual else max(0, table64[idx] - 1)

    hard_rows = []
    for pc, total in pc_totals.items():
        if total < 10:
            continue
        miss_cnt  = pc_misses.get(pc, 0)
        taken_cnt = pc_taken.get(pc, 0)
        hard_rows.append({
            'pc_hex':         f'0x{pc:08x}',
            'total':          total,
            'mispredict_pct': round(miss_cnt / total * 100, 1),
            'taken_pct':      round(taken_cnt / total * 100, 1),
        })

    hardest = (
        pd.DataFrame(hard_rows)
          .sort_values('mispredict_pct', ascending=False)
          .head(30)
          .reset_index(drop=True)
        if hard_rows else
        pd.DataFrame(columns=['pc_hex', 'total', 'mispredict_pct', 'taken_pct'])
    )

    # ── Inject BTFN as table_bits=0 anchor in size_sweep ───────────────────
    btfn_pct = _pct(btfn_miss)
    utage_schemes = [
        f'micro_tage_B{b}T{t}w{w}' for b, t, w in _UTAGE_CONFIGS
    ]
    tournament_schemes = [f'tournament_{e}' for e in _TOURNAMENT_ENTRIES]
    btfn_anchors = [
        {'scheme': s, 'table_bits': 0, 'mispredict_pct': btfn_pct}
        for s in ['bimodal_1bit', 'bimodal_2bit', 'gshare']
                 + utage_schemes + tournament_schemes
    ]
    size_sweep_rows = btfn_anchors + size_sweep_rows

    # ── Late-source statistic ────────────────────────────────────────────────
    # How often does the instruction immediately before a conditional branch
    # write to one of the branch's source registers (rs1 / rs2)?
    # This creates a RAW hazard on the branch inputs — the comparison operand
    # is not yet available, forcing a stall or requiring forwarding.
    prev_rd  = df['rd'].shift(1).reindex(brm.index)
    br_rs1   = brm['rs1']
    br_rs2   = brm['rs2']
    late_src = (
        (prev_rd.notna()) &
        ((prev_rd == br_rs1) | (prev_rd == br_rs2))
    )
    late_src_pct = round(late_src.sum() / n * 100, 1) if n else 0.0

    return {
        'total_branches':       n,
        'oracle_mispredict_pct': oracle_pct,
        'late_source_pct':      late_src_pct,
        'summary':              pd.DataFrame(summary_rows),
        'size_sweep':           pd.DataFrame(size_sweep_rows),
        'hardest':              hardest,
    }


# ─── compare ──────────────────────────────────────────────────────────────────

def compare(td_a: TraceData, td_b: TraceData, label_a: str = 'A', label_b: str = 'B') -> dict:
    """Side-by-side comparison of two traces.

    Returns
    -------
    dict with keys:
      pipeline   DataFrame  key pipeline metrics side by side
      instmix    DataFrame  category counts and pct for both traces
      top_mnems  DataFrame  top-20 mnemonic comparison
    """
    pa = pipeline(td_a)
    pb = pipeline(td_b)

    pipe_df = pd.DataFrame([
        {'metric': 'Instructions', label_a: pa.get('total_instructions'), label_b: pb.get('total_instructions')},
        {'metric': 'Cycles',       label_a: pa.get('total_cycles'),       label_b: pb.get('total_cycles')},
        {'metric': 'IPC',          label_a: pa.get('ipc'),                label_b: pb.get('ipc')},
        {'metric': 'CPI',          label_a: pa.get('cpi'),                label_b: pb.get('cpi')},
        {'metric': 'Stall cycles', label_a: pa.get('stall_cycles'),       label_b: pb.get('stall_cycles')},
        {'metric': 'Stall rate',   label_a: pa.get('stall_rate'),         label_b: pb.get('stall_rate')},
        {'metric': 'Compressed %', label_a: instmix(td_a).get('compressed_pct'), label_b: instmix(td_b).get('compressed_pct')},
    ])

    ma = instmix(td_a).get('by_category', pd.DataFrame())
    mb = instmix(td_b).get('by_category', pd.DataFrame())
    if not ma.empty and not mb.empty:
        mix_df = ma.merge(mb, on='category', how='outer', suffixes=(f'_{label_a}', f'_{label_b}')).fillna(0)
    else:
        mix_df = pd.DataFrame()

    mna = instmix(td_a).get('by_mnem', pd.DataFrame())
    mnb = instmix(td_b).get('by_mnem', pd.DataFrame())
    if not mna.empty and not mnb.empty:
        top_df = mna.merge(mnb, on='mnem_base', how='outer', suffixes=(f'_{label_a}', f'_{label_b}')).fillna(0)
        top_df = top_df.sort_values(f'count_{label_a}', ascending=False).head(20)
    else:
        top_df = pd.DataFrame()

    return {
        'pipeline':  pipe_df,
        'instmix':   mix_df,
        'top_mnems': top_df,
    }
