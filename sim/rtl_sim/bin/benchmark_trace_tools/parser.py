#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    parser.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Parse asphalt.log / .log.zst into structured benchmark trace records (TraceData / pandas DataFrame).
#----------------------------------------------------------------------------

"""
trace_parser.py — arvern trace file parser.

Reads .log or .log.zst trace files produced by the simulation testbench,
parses the embedded metadata header, and returns a TraceData object with:
  - metadata : dict  (RTL config, toolchain, benchmark info from header)
  - df       : pandas DataFrame, one row per executed instruction

DataFrame columns:
  cycle      int64   clock cycle counter
  time_ns    Int64   simulation timestamp in nanoseconds (nullable — absent in old traces)
  pc         int64   program counter (stored as int)
  instr      int64   raw 32-bit instruction word
  mnemonic   str     full mnemonic string  (e.g. "ADDI x1,x2,-4")
  mnem_base  str     instruction name only (e.g. "ADDI")
  mem_op     str     'R', 'W', or ''
  mem_addr   Int64   memory address  (nullable)
  mem_data   Int64   memory data     (nullable)
  rd         Int64   destination register number (nullable)
  rd_val     Int64   value written to rd         (nullable)
  rs1        Int64   source register 1           (nullable)
  rs2        Int64   source register 2           (nullable)
  category   str     instruction category
  is_comp    bool    True for compressed (C./CM.) instructions
  instr_size int     instruction size in bytes (2=compressed, 4=standard)
  br_taken   object  branch outcome: True=taken, False=not-taken, None=non-branch
"""

import re
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

try:
    import zstandard as zstd
    _HAVE_ZST = True
except ImportError:
    _HAVE_ZST = False


# ─── Instruction categories ───────────────────────────────────────────────────

CAT_ALU_R    = 'ALU_R'
CAT_ALU_I    = 'ALU_I'
CAT_MUL      = 'MUL'
CAT_DIV      = 'DIV'
CAT_LOAD     = 'LOAD'
CAT_STORE    = 'STORE'
CAT_BRANCH   = 'BRANCH'
CAT_JUMP     = 'JUMP'
CAT_UPPER    = 'UPPER'
CAT_CSR      = 'CSR'
CAT_SYSTEM   = 'SYSTEM'
CAT_COMP_BR  = 'COMP_BRANCH'
CAT_COMP_JMP = 'COMP_JUMP'
CAT_COMP_LD  = 'COMP_LOAD'
CAT_COMP_ST  = 'COMP_STORE'
CAT_COMP_ALU = 'COMP_ALU'
CAT_COMP_STK = 'COMP_STACK'
CAT_UNKNOWN  = 'UNKNOWN'

_MNEM_TO_CAT = {
    # ALU R-type
    'ADD': CAT_ALU_R, 'SUB': CAT_ALU_R, 'AND': CAT_ALU_R, 'OR': CAT_ALU_R,
    'XOR': CAT_ALU_R, 'SLL': CAT_ALU_R, 'SRL': CAT_ALU_R, 'SRA': CAT_ALU_R,
    'SLT': CAT_ALU_R, 'SLTU': CAT_ALU_R,
    'ANDN': CAT_ALU_R, 'ORN': CAT_ALU_R, 'XNOR': CAT_ALU_R,
    'SH1ADD': CAT_ALU_R, 'SH2ADD': CAT_ALU_R, 'SH3ADD': CAT_ALU_R,
    'MIN': CAT_ALU_R, 'MINU': CAT_ALU_R, 'MAX': CAT_ALU_R, 'MAXU': CAT_ALU_R,
    'ROL': CAT_ALU_R, 'ROR': CAT_ALU_R,
    'CLMUL': CAT_ALU_R, 'CLMULR': CAT_ALU_R, 'CLMULH': CAT_ALU_R,
    'BCLR': CAT_ALU_R, 'BEXT': CAT_ALU_R, 'BINV': CAT_ALU_R, 'BSET': CAT_ALU_R,
    'ZEXT.H': CAT_ALU_R,
    # ALU I-type
    'ADDI': CAT_ALU_I, 'SLTI': CAT_ALU_I, 'SLTIU': CAT_ALU_I,
    'XORI': CAT_ALU_I, 'ORI': CAT_ALU_I, 'ANDI': CAT_ALU_I,
    'SLLI': CAT_ALU_I, 'SRLI': CAT_ALU_I, 'SRAI': CAT_ALU_I,
    'CLZ': CAT_ALU_I, 'CTZ': CAT_ALU_I, 'CPOP': CAT_ALU_I,
    'SEXT.B': CAT_ALU_I, 'SEXT.H': CAT_ALU_I,
    'REV8': CAT_ALU_I, 'ORC.B': CAT_ALU_I, 'RORI': CAT_ALU_I,
    'BCLRI': CAT_ALU_I, 'BINVI': CAT_ALU_I, 'BSETI': CAT_ALU_I, 'BEXTI': CAT_ALU_I,
    'NOP': CAT_ALU_I,
    # Multiply / Divide
    'MUL': CAT_MUL, 'MULH': CAT_MUL, 'MULHSU': CAT_MUL, 'MULHU': CAT_MUL,
    'C.MUL': CAT_MUL,
    'DIV': CAT_DIV, 'DIVU': CAT_DIV, 'REM': CAT_DIV, 'REMU': CAT_DIV,
    # Load / Store
    'LB': CAT_LOAD, 'LH': CAT_LOAD, 'LW': CAT_LOAD, 'LBU': CAT_LOAD, 'LHU': CAT_LOAD,
    'SB': CAT_STORE, 'SH': CAT_STORE, 'SW': CAT_STORE,
    # Branch
    'BEQ': CAT_BRANCH, 'BNE': CAT_BRANCH, 'BLT': CAT_BRANCH,
    'BGE': CAT_BRANCH, 'BLTU': CAT_BRANCH, 'BGEU': CAT_BRANCH,
    # Jump
    'JAL': CAT_JUMP, 'JALR': CAT_JUMP,
    # Upper immediate
    'LUI': CAT_UPPER, 'AUIPC': CAT_UPPER,
    # CSR
    'CSRRW': CAT_CSR, 'CSRRS': CAT_CSR, 'CSRRC': CAT_CSR,
    'CSRRWI': CAT_CSR, 'CSRRSI': CAT_CSR, 'CSRRCI': CAT_CSR,
    # System
    'ECALL': CAT_SYSTEM, 'EBREAK': CAT_SYSTEM, 'MRET': CAT_SYSTEM,
    'SRET': CAT_SYSTEM, 'WFI': CAT_SYSTEM,
    'FENCE': CAT_SYSTEM, 'FENCE.I': CAT_SYSTEM, 'FENCE.TSO': CAT_SYSTEM, 'PAUSE': CAT_SYSTEM,
    'C.NOP': CAT_SYSTEM, 'C.EBREAK': CAT_SYSTEM,
    # Compressed branch / jump
    'C.BEQZ': CAT_COMP_BR, 'C.BNEZ': CAT_COMP_BR,
    'C.JAL': CAT_COMP_JMP, 'C.J': CAT_COMP_JMP,
    'C.JR': CAT_COMP_JMP, 'C.JALR': CAT_COMP_JMP,
    'CM.JT': CAT_COMP_JMP, 'CM.JALT': CAT_COMP_JMP,
    # Compressed load / store
    'C.LW': CAT_COMP_LD, 'C.LWSP': CAT_COMP_LD,
    'C.LBU': CAT_COMP_LD, 'C.LHU': CAT_COMP_LD, 'C.LH': CAT_COMP_LD,
    'C.SW': CAT_COMP_ST, 'C.SWSP': CAT_COMP_ST, 'C.SB': CAT_COMP_ST, 'C.SH': CAT_COMP_ST,
    # Compressed stack
    'CM.PUSH': CAT_COMP_STK, 'CM.POP': CAT_COMP_STK,
    'CM.POPRET': CAT_COMP_STK, 'CM.POPRETZ': CAT_COMP_STK,
    'CM.MVA01S': CAT_COMP_STK, 'CM.MVSA01': CAT_COMP_STK,
    # Compressed ALU
    'C.ADDI': CAT_COMP_ALU, 'C.ADDI4SPN': CAT_COMP_ALU, 'C.ADDI16SP': CAT_COMP_ALU,
    'C.LI': CAT_COMP_ALU, 'C.LUI': CAT_COMP_ALU,
    'C.SLLI': CAT_COMP_ALU, 'C.SRLI': CAT_COMP_ALU, 'C.SRAI': CAT_COMP_ALU,
    'C.ANDI': CAT_COMP_ALU,
    'C.ADD': CAT_COMP_ALU, 'C.SUB': CAT_COMP_ALU,
    'C.AND': CAT_COMP_ALU, 'C.OR': CAT_COMP_ALU, 'C.XOR': CAT_COMP_ALU,
    'C.MV': CAT_COMP_ALU,
    'C.ZEXT.B': CAT_COMP_ALU, 'C.SEXT.B': CAT_COMP_ALU,
    'C.ZEXT.H': CAT_COMP_ALU, 'C.SEXT.H': CAT_COMP_ALU,
    'C.NOT': CAT_COMP_ALU,
}


# ─── Line regex ───────────────────────────────────────────────────────────────
# The trace line format (from probes_instructions.v):
#   cycle  [time_ns]  pc  instr  mnemonic  mem  mem_addr  mem_data  tgt_reg  [sz]  [br]  [trap]  [priv]  [# note]
#
# time_ns (column 2) was added in a later revision; the group is optional so
# that older trace files without it still parse correctly.  pc always starts
# with "0x", which distinguishes it from the plain-decimal time_ns field.
#
# Strategy: cycle/pc/instr have no internal spaces; mnemonic ends before 2+
# consecutive spaces (the %-32s padding); mem is a single char; the rest have
# no internal spaces.  Non-greedy (.+?) + \s{2,} reliably splits mnemonic from
# the mem field even for instructions with spaces in operands (CM.PUSH etc.).
#
# tgt_reg can be:  x<n>=0x<val>  (load/ALU dest)
#                  [x<n>]        (store source register)
#                  -             (none)
# sz: instruction size in bytes (2 or 4).  Optional for backward compat.
# br: branch outcome T/N/-.  Optional for backward compat.
# trap: trap cause string.  Optional for backward compat.
# priv: privilege mode M/S/U.  Optional for backward compat.
# Trailing # comment (e.g. "# 5 mem ops") is ignored.

_RE_LINE = re.compile(
    r'^\s*(\d+)\s+'                              # 1: cycle
    r'(?:(\d+)\s+)?'                             # 2: time_ns  (optional — new format)
    r'(0x[0-9a-fA-F]+)\s+'                      # 3: pc
    r'(0x[0-9a-fA-F]+)\s+'                      # 4: instr
    r'(.+?)\s{2,}'                                # 5: mnemonic  (ends at 2+ spaces)
    r'([RW\-])\s+'                                # 6: mem
    r'(0x[0-9a-fA-F]+|\-)\s+'                   # 7: mem_addr
    r'(0x[0-9a-fA-F]+|\-)\s+'                   # 8: mem_data
    r'(x\d+=0x[0-9a-fA-F]+|\[x\d+\]|\S+)'      # 9: tgt_reg
    r'(?:\s+([24]))?'                              # 10: sz   (optional)
    r'(?:\s+([TN\-]))?'                            # 11: br  (optional)
    r'(?:\s+((?:IRQ|EXC):\S+|[MS]RET|\-))?'        # 12: trap (optional)
    r'(?:\s+([MSU?]))?'                            # 13: priv (optional)
    r'\s*(?:#.*)?$',                               # optional trailing comment
    re.IGNORECASE,
)

_RE_TGT = re.compile(r'^x(\d+)=0x([0-9a-fA-F]+)$', re.IGNORECASE)
_RE_STORE_SRC = re.compile(r'^\[x(\d+)\]$')


# ─── Register extraction ──────────────────────────────────────────────────────
# Instruction sets grouped by operand format (determines rs1/rs2 positions).

_FMT_RD_RS1_RS2  = frozenset({  # "xRD,xRS1,xRS2"
    'ADD','SUB','AND','OR','XOR','SLL','SRL','SRA','SLT','SLTU',
    'ANDN','ORN','XNOR','SH1ADD','SH2ADD','SH3ADD',
    'MIN','MINU','MAX','MAXU','ROL','ROR',
    'CLMUL','CLMULR','CLMULH','BCLR','BEXT','BINV','BSET',
    'MUL','MULH','MULHSU','MULHU','DIV','DIVU','REM','REMU',
})
_FMT_RD_RS1_IMM  = frozenset({  # "xRD,xRS1,imm"
    'ADDI','SLTI','SLTIU','XORI','ORI','ANDI',
    'SLLI','SRLI','SRAI','RORI','BCLRI','BINVI','BSETI','BEXTI',
    'CSRRW','CSRRS','CSRRC','CSRRWI','CSRRSI','CSRRCI',
})
_FMT_RD_RS1_ONLY = frozenset({  # "xRD,xRS1"
    'CLZ','CTZ','CPOP','SEXT.B','SEXT.H','ZEXT.H','REV8','ORC.B',
})
_FMT_LOAD        = frozenset({'LB','LH','LW','LBU','LHU'})      # "xRD,imm(xRS1)"
_FMT_STORE       = frozenset({'SB','SH','SW'})                    # "xRS2,imm(xRS1)"
_FMT_BRANCH      = frozenset({'BEQ','BNE','BLT','BGE','BLTU','BGEU'})  # "xRS1,xRS2,imm"

# Regex atoms reused for register parsing
_R  = r'x(\d+)'           # register token
_IM = r'[^,()]+'           # immediate token (anything without comma/paren)

_RE_RD_RS1_RS2  = re.compile(rf'^{_R},{_R},{_R}')
_RE_RD_RS1_IMM  = re.compile(rf'^{_R},{_R},')
_RE_RD_RS1      = re.compile(rf'^{_R},{_R}$')
_RE_RD_IMM_RS1  = re.compile(rf'^{_R},{_IM}\({_R}\)')   # load / JALR
_RE_RS2_IMM_RS1 = re.compile(rf'^{_R},{_IM}\({_R}\)')   # store (same pattern, different semantics)
_RE_RS1_RS2_IMM = re.compile(rf'^{_R},{_R},')            # branch
_RE_ONE_REG     = re.compile(rf'^{_R}')                  # single register
_RE_TWO_REG     = re.compile(rf'^{_R}[, ]+{_R}')        # two registers (compressed)


def _extract_regs(mnem_base: str, operands: str):
    """Return (rs1, rs2) as ints-or-None from the operand string.

    rd is intentionally excluded here; it is taken directly from the tgt_reg
    field in _parse_line() which is more reliable (handles compressed rd too).
    """
    rs1 = rs2 = None

    if mnem_base in _FMT_BRANCH:
        # "xRS1,xRS2,imm"
        m = _RE_RS1_RS2_IMM.match(operands)
        if m:
            rs1, rs2 = int(m.group(1)), int(m.group(2))

    elif mnem_base == 'JALR':
        # "xRD,imm(xRS1)"  — rd handled via tgt_reg; we only want rs1
        m = _RE_RD_IMM_RS1.match(operands)
        if m:
            rs1 = int(m.group(2))

    elif mnem_base in ('C.JR', 'C.JALR'):
        # "xRS1"
        m = _RE_ONE_REG.match(operands)
        if m:
            rs1 = int(m.group(1))

    elif mnem_base in _FMT_STORE or mnem_base in ('C.SW', 'C.SB', 'C.SH'):
        # "xRS2,imm(xRS1)"
        m = _RE_RS2_IMM_RS1.match(operands)
        if m:
            rs2, rs1 = int(m.group(1)), int(m.group(2))

    elif mnem_base == 'C.SWSP':
        # "xRS2,0xIMM(sp)" — rs1 is implicitly sp=x2
        m = _RE_ONE_REG.match(operands)
        if m:
            rs2, rs1 = int(m.group(1)), 2

    elif mnem_base in _FMT_LOAD:
        # "xRD,imm(xRS1)"
        m = _RE_RD_IMM_RS1.match(operands)
        if m:
            rs1 = int(m.group(2))

    elif mnem_base in ('C.LW', 'C.LBU', 'C.LHU', 'C.LH'):
        # "xRD,0xIMM(xRS1)"
        m = _RE_RD_IMM_RS1.match(operands)
        if m:
            rs1 = int(m.group(2))

    elif mnem_base == 'C.LWSP':
        # "xRD,0xIMM(sp)" — rs1 implicitly sp=x2
        rs1 = 2

    elif mnem_base in _FMT_RD_RS1_ONLY:
        # "xRD,xRS1"
        m = _RE_RD_RS1.match(operands)
        if m:
            rs1 = int(m.group(2))

    elif mnem_base in _FMT_RD_RS1_RS2:
        # "xRD,xRS1,xRS2"
        m = _RE_RD_RS1_RS2.match(operands)
        if m:
            rs1, rs2 = int(m.group(2)), int(m.group(3))

    elif mnem_base in _FMT_RD_RS1_IMM:
        # "xRD,xRS1,imm"
        m = _RE_RD_RS1_IMM.match(operands)
        if m:
            rs1 = int(m.group(2))

    elif mnem_base in ('C.ADDI', 'C.SLLI', 'C.SRLI', 'C.SRAI', 'C.ANDI',
                       'C.ZEXT.B', 'C.SEXT.B', 'C.ZEXT.H', 'C.SEXT.H', 'C.NOT'):
        # "xRD,imm" or "xRD" — rs1 is implicitly the same as rd
        m = _RE_ONE_REG.match(operands)
        if m:
            rs1 = int(m.group(1))   # rs1 == rd

    elif mnem_base in ('C.ADD', 'C.SUB', 'C.AND', 'C.OR', 'C.XOR', 'C.MUL'):
        # "xRD,xRS2" — rs1 is implicitly rd
        m = _RE_TWO_REG.match(operands)
        if m:
            rs1, rs2 = int(m.group(1)), int(m.group(2))  # rs1 == rd

    elif mnem_base == 'C.MV':
        # "xRD,xRS2"
        m = _RE_TWO_REG.match(operands)
        if m:
            rs2 = int(m.group(2))

    elif mnem_base in ('C.BEQZ', 'C.BNEZ'):
        # "xRS1,offset"
        m = _RE_ONE_REG.match(operands)
        if m:
            rs1 = int(m.group(1))

    elif mnem_base == 'C.ADDI4SPN':
        # "xRD,sp,0xIMM" — rs1 = sp
        rs1 = 2

    elif mnem_base == 'C.ADDI16SP':
        # "sp,imm" — rs1 = rs2 = sp
        rs1 = 2

    elif mnem_base in ('CM.MVA01S', 'CM.MVSA01'):
        # "xRD1,xRS"  (two register operands visible)
        m = _RE_TWO_REG.match(operands)
        if m:
            rs1 = int(m.group(2))

    return rs1, rs2


# ─── Metadata header parsing ──────────────────────────────────────────────────

def _parse_header(lines):
    """Parse the leading # comment block into a metadata dict."""
    meta   = {}
    rtl    = {}
    tc     = {}
    bench  = {}
    section = None

    for line in lines:
        content = line.lstrip('#').strip()
        if not content:
            continue
        low = content.lower()

        # Section-header detection: compare the part before any colon
        head = low.split(':')[0].strip()
        if head == 'rtl configuration':
            section = 'rtl'
            continue
        if head == 'toolchain':
            section = 'tc'
            continue
        if head == 'benchmark results':
            section = 'bench'
            continue

        # RTL lines use  KEY = VALUE  (no colon) — handle before the colon check
        if section == 'rtl':
            # e.g. "RV32E_EN    = 0  (RV32I)"
            m = re.match(r'(\w+)\s*=\s*(\d+)\s*(?:\(([^)]*)\))?', content)
            if m:
                label = m.group(3).strip() if m.group(3) else m.group(2)
                rtl[m.group(1)] = label
            continue

        if ':' not in content:
            continue
        key, _, val = content.partition(':')
        key = key.strip()
        val = val.strip()

        if section == 'tc':
            tc[key] = val
        elif section == 'bench':
            bench[key] = val
        else:
            meta[key] = val

    meta['rtl']       = rtl
    meta['toolchain'] = tc
    meta['benchmark'] = bench
    return meta


# ─── Single-line parser ───────────────────────────────────────────────────────

def _parse_line(line: str):
    """Parse one trace line; return a dict or None for header/blank lines."""
    line = line.rstrip('\n')
    if not line or line.lstrip().startswith('#'):
        return None

    m = _RE_LINE.match(line)
    if not m:
        return None

    cycle     = int(m.group(1))
    time_ns   = int(m.group(2)) if m.group(2) else None
    pc        = int(m.group(3), 16)
    instr     = int(m.group(4), 16)
    mnemonic  = m.group(5).strip()
    mem_op    = m.group(6) if m.group(6) in ('R', 'W') else ''
    mem_addr  = int(m.group(7), 16) if m.group(7) != '-' else None
    mem_data  = int(m.group(8), 16) if m.group(8) != '-' else None
    tgt_raw   = m.group(9)

    rd = rd_val = None
    mt = _RE_TGT.match(tgt_raw)
    if mt:
        rd     = int(mt.group(1))
        rd_val = int(mt.group(2), 16)

    # Split mnemonic into base name + operand string
    parts     = mnemonic.split(None, 1)
    mnem_base = parts[0] if parts else ''
    operands  = parts[1] if len(parts) > 1 else ''

    rs1, rs2 = _extract_regs(mnem_base, operands)

    # Instruction size (optional column, backward-compatible)
    sz_raw = m.group(10)
    instr_size = int(sz_raw) if sz_raw else (2 if (mnem_base.startswith('C.') or mnem_base.startswith('CM.')) else 4)

    # Branch outcome (optional column, backward-compatible)
    br_raw = m.group(11)
    br_taken = True if br_raw == 'T' else (False if br_raw == 'N' else None)

    # Trap cause (optional column, backward-compatible)
    trap_raw = m.group(12)
    trap_cause = trap_raw if (trap_raw and trap_raw != '-') else None

    # Privilege mode (optional column, backward-compatible)
    priv_raw = m.group(13)
    priv_mode = priv_raw.upper() if priv_raw else None

    return {
        'cycle':      cycle,
        'time_ns':    time_ns,
        'pc':         pc,
        'instr':      instr,
        'mnemonic':   mnemonic,
        'mnem_base':  mnem_base,
        'mem_op':     mem_op,
        'mem_addr':   mem_addr,
        'mem_data':   mem_data,
        'rd':         rd,
        'rd_val':     rd_val,
        'rs1':        rs1,
        'rs2':        rs2,
        'category':   _MNEM_TO_CAT.get(mnem_base, CAT_UNKNOWN),
        'is_comp':    mnem_base.startswith('C.') or mnem_base.startswith('CM.'),
        'instr_size': instr_size,
        'br_taken':   br_taken,
        'trap_cause': trap_cause,
        'priv_mode':  priv_mode,
    }


# ─── Public API ───────────────────────────────────────────────────────────────

@dataclass
class TraceData:
    metadata: dict
    df:       pd.DataFrame
    path:     str = ''


def _open_trace(path: str):
    """Return an open text-mode file handle for .log or .log.zst."""
    if path.endswith('.zst'):
        if not _HAVE_ZST:
            raise ImportError(
                'zstandard package required for .zst files: pip install zstandard'
            )
        return zstd.open(path, 'rt', encoding='utf-8')
    return open(path, 'r', encoding='utf-8', errors='replace')


def load(path: str) -> TraceData:
    """Load a trace file and return a TraceData object.

    Args:
        path: Path to a .log or .log.zst trace file.

    Returns:
        TraceData with .metadata dict and .df DataFrame.
    """
    header_lines = []
    rows         = []

    with _open_trace(path) as fh:
        in_header = True
        for line in fh:
            stripped = line.rstrip('\n')
            if in_header:
                if stripped.lstrip().startswith('#') or stripped == '':
                    header_lines.append(stripped)
                    continue
                in_header = False
            row = _parse_line(line)
            if row is not None:
                rows.append(row)

    metadata = _parse_header(header_lines)

    _EMPTY_COLS = [
        'cycle', 'time_ns', 'pc', 'instr', 'mnemonic', 'mnem_base',
        'mem_op', 'mem_addr', 'mem_data',
        'rd', 'rd_val', 'rs1', 'rs2',
        'category', 'is_comp', 'instr_size', 'br_taken', 'trap_cause', 'priv_mode',
    ]
    if not rows:
        return TraceData(
            metadata=metadata,
            df=pd.DataFrame(columns=_EMPTY_COLS),
            path=path,
        )

    df = pd.DataFrame(rows)

    # Use nullable integer types for optional fields
    for col in ('time_ns', 'mem_addr', 'mem_data', 'rd', 'rd_val', 'rs1', 'rs2'):
        df[col] = pd.array(df[col], dtype=pd.Int64Dtype())

    return TraceData(metadata=metadata, df=df, path=path)


# ─── CLI helper ───────────────────────────────────────────────────────────────

if __name__ == '__main__':
    import sys
    if len(sys.argv) < 2:
        print('Usage: trace_parser.py <asphalt.log[.zst]>')
        sys.exit(1)

    td = load(sys.argv[1])
    df = td.df
    print(f'File    : {td.path}')
    print(f'Test    : {td.metadata.get("Test", "?")}')
    print(f'Mode    : {td.metadata.get("Mode", "?")}')
    print(f'Rows    : {len(df):,}')
    if not df.empty:
        print(f'Cycles  : {df.cycle.min()} – {df.cycle.max()}')
        total_cycles = df.cycle.max() - df.cycle.min() + 1
        print(f'IPC     : {len(df) / total_cycles:.3f}')
        print(f'\nCategory breakdown:')
        print(df.groupby('category').size().sort_values(ascending=False).to_string())
