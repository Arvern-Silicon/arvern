#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    save_trace.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Serialise a benchmark trace into a compact pickle.
#----------------------------------------------------------------------------

"""
Save arvern asphalt.log with embedded metadata and optional zstd compression.

Reads the current run context (RTL configuration, toolchain, simulator) from
the files present in the run directory, prepends a self-describing metadata
header to the trace, and writes the result to a uniquely-named file.

Filename format:
  trace_<test>_<mode>_<rtl>_<toolchain>_<variant>_<YYYYMMDD_HHMMSS>.log[.zst]

Example:
  trace_inst_add_std_m2_c3_b4_mul1_div3_gcc_O3_nominal_20250222_143022.log.zst

Usage (from sim/rtl_sim/run/):
  python3 ../bin/save_trace.py --test inst_add [options]
  python3 ../bin/save_trace.py --test instc_cm_push --mode comp --compress
  python3 ../bin/save_trace.py --test inst_add --variant rwsrom rsalu --compress
"""

import argparse
import os
import re
import subprocess
import sys
import zstandard as zstd
from datetime import datetime
from pathlib import Path


# ─── RTL parameter value descriptions ────────────────────────────────────────

_RTL_DESC = {
    'RV32E_EN':            {0: 'RV32I',          1: 'RV32E'},
    'C_EXTENSION':         {0: 'none',           1: 'Zca',            2: 'Zca+Zcb',          3: 'Zca+Zcb+Zcmp',  4: 'Zca+Zcb+Zcmp+Zcmt'},
    'M_EXTENSION':         {0: 'none',           1: 'Zmmul',          2: 'M'},
    'B_EXTENSION':         {0: 'none',           1: 'Zbb',            2: 'Zbb+Zba',          3: 'Zbb+Zba+Zbs',   4: 'Zbb+Zba+Zbs+Zbc'},
    'MUL_TYPE':            {1: '1-cycle',        2: '4-cycle',        3: '16-cycle'},
    'DIV_TYPE':            {1: '12-cycle',       2: '17-cycle',       3: '33-cycle'},
    'CCSR_EN':             {0: 'absent',         1: 'present'},
    'NMI_EN':              {0: 'absent',         1: 'Smrnmi present'},
    'SU_MODE_EN':          {0: 'M-only',         1: 'M+S+U'},
    'ZICNTR_EN':           {0: 'absent',         1: 'present'},
    'SINGLE_CYCLE_BRANCH': {0: 'one-bubble',     1: 'zero-bubble'},
    # ZIHPM_NR and MVENDORID are free-valued (use raw integer / hex string)
}

# Display order for RTL parameters in the metadata header
_RTL_ORDER = ('RV32E_EN', 'C_EXTENSION', 'M_EXTENSION', 'B_EXTENSION',
              'MUL_TYPE', 'DIV_TYPE', 'CCSR_EN', 'NMI_EN', 'SU_MODE_EN',
              'ZICNTR_EN', 'ZIHPM_NR', 'SINGLE_CYCLE_BRANCH', 'MVENDORID')


# ─── Metadata readers ─────────────────────────────────────────────────────────

def read_rtl_params(param_file='./arv_parameterization.v'):
    """Parse parameter values from auto-generated arv_parameterization.v."""
    params = {}
    if os.path.exists(param_file):
        with open(param_file) as f:
            for line in f:
                m = re.match(r'\s*parameter\s+(\w+)\s*=\s*(\d+)', line)
                if m:
                    params[m.group(1)] = int(m.group(2))
    return params


def read_march_info(config_file='./march_config.sh'):
    """Extract variable assignments from the generated march_config.sh."""
    info = {}
    if not os.path.exists(config_file):
        return info
    with open(config_file) as f:
        for line in f:
            # Match both  export VAR="value"  and  VAR="value"
            m = re.match(r'(?:export\s+)?(\w+)="([^"]*)"', line.strip())
            if m:
                info[m.group(1)] = m.group(2)
    return info


def read_toolchain_version(march_info):
    """Return the first line of TC_CC --version, or empty string on failure."""
    tc_cc = march_info.get('TC_CC', '')
    if not tc_cc:
        return ''
    # TC_CC may contain flags (e.g. "clang --target=riscv32-unknown-elf")
    cmd = tc_cc.split() + ['--version']
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        first_line = (r.stdout or r.stderr).splitlines()[0].strip()
        return first_line
    except Exception:
        return ''


# ─── Filename component builders ──────────────────────────────────────────────

def rtl_abbrev(params):
    """
    Build a compact RTL config string for the filename.

    Uses lowercase abbreviations: m<M_EXT>_c<C_EXT>_b<B_EXT>[_mul<N>][_div<N>]
    MUL/DIV types are appended only when the relevant extension is active.
    """
    parts = []
    for key, prefix in (('M_EXTENSION', 'm'), ('C_EXTENSION', 'c'), ('B_EXTENSION', 'b')):
        if key in params:
            parts.append(f'{prefix}{params[key]}')
    m_ext = params.get('M_EXTENSION', 0)
    if m_ext >= 1 and 'MUL_TYPE' in params:
        parts.append(f'mul{params["MUL_TYPE"]}')
    if m_ext >= 2 and 'DIV_TYPE' in params:
        parts.append(f'div{params["DIV_TYPE"]}')
    return '_'.join(parts) if parts else 'default'


def tc_abbrev(march_info):
    """
    Build a compact toolchain string for the filename.

    Detects profile from CROSS prefix and derives a short label.
    Appends the optimization level with the leading '-' stripped.
    """
    cross  = march_info.get('CROSS', '')
    tc_cc  = march_info.get('TC_CC', '')
    opt    = march_info.get('TC_OPT', '')

    if 'riscv-none-elf' in cross:
        tc = 'xpacks'
    elif 'clang' in tc_cc:
        tc = 'llvm'
    else:
        tc = 'gcc'

    opt_str = opt.lstrip('-').replace(' ', '') if opt else ''
    return f'{tc}_{opt_str}' if opt_str else tc


def variant_abbrev(variant_args):
    """
    Build a compact variant string for the filename.

    Strips leading dashes and joins flags with '-'.  Returns 'nominal' when
    no variant flags are specified.
    """
    if not variant_args:
        return 'nominal'
    parts = [v.lstrip('-') for v in variant_args]
    return '-'.join(parts)


# ─── Metadata header builder ──────────────────────────────────────────────────

def build_header(test, mode, variant_args, rtl_params, march_info, simulator, timestamp,
                 score=None, score_metric=None, size_info=None, tc_version=''):
    """Return a self-describing comment block to prepend to the saved trace."""
    SEP  = '# ' + '=' * 66
    lines = [
        SEP,
        '# arvern Trace Archive',
        SEP,
        f'# Date          : {timestamp.strftime("%Y-%m-%d %H:%M:%S")}',
        f'# Test          : {test}',
        f'# Mode          : {mode.upper()}',
        f'# Variant       : {", ".join(v.lstrip("-") for v in variant_args) if variant_args else "nominal"}',
        f'# Simulator     : {simulator}',
        '#',
        '# RTL Configuration:',
    ]

    for key in _RTL_ORDER:
        if key in rtl_params:
            val  = rtl_params[key]
            desc = _RTL_DESC.get(key, {}).get(val, str(val))
            lines.append(f'#   {key:<14} = {val}  ({desc})')

    lines += [
        '#',
        '# Toolchain:',
    ]
    march_key = 'MARCH_COMP' if mode.upper() == 'COMP' else 'MARCH_STD'
    for var, label in (('CROSS',    'Prefix       '),
                       ('TC_CC',    'CC           '),
                       ('TC_OPT',   'Optimization '),
                       (march_key,  'MARCH        ')):
        if var in march_info and march_info[var]:
            lines.append(f'#   {label} : {march_info[var]}')
    if tc_version:
        lines.append(f'#   Version      : {tc_version}')

    if score is not None or size_info:
        lines += ['#', '# Benchmark Results:']
        if score is not None:
            metric_str = f'  ({score_metric})' if score_metric else ''
            score_str  = f'{int(score)}' if isinstance(score, float) and score == int(score) else f'{score}'
            lines.append(f'#   Score          : {score_str}{metric_str}')
        if size_info:
            lines.append(f'#   Size (bytes)   : text={size_info.get("text", 0)}'
                         f'  rodata={size_info.get("rodata", 0)}'
                         f'  data={size_info.get("data", 0)}'
                         f'  bss={size_info.get("bss", 0)}')

    lines += [SEP, '']
    return '\n'.join(lines)


# ─── Main logic ───────────────────────────────────────────────────────────────

def save_trace(test, mode, variant_args, compress, outdir, source,
               score=None, score_metric=None, size_info=None, quiet=False):
    """Read trace, prepend metadata header, write to named output file."""

    if not os.path.exists(source):
        print(f'Error: source trace file not found: {source}', file=sys.stderr)
        return 1

    # Gather metadata
    rtl_params = read_rtl_params('./arv_parameterization.v')
    march_info = read_march_info('./march_config.sh')
    tc_version = read_toolchain_version(march_info)
    simulator  = os.environ.get('VERILOG_SIMULATOR', 'iverilog')
    timestamp  = datetime.now()

    # Build output filename
    rtl_str  = rtl_abbrev(rtl_params)
    tc_str   = tc_abbrev(march_info)
    var_str  = variant_abbrev(variant_args)
    ts_str   = timestamp.strftime('%Y%m%d_%H%M%S')
    ext      = '.log.zst' if compress else '.log'
    filename = f'trace_{test}_{mode}_{rtl_str}_{tc_str}_{var_str}_{ts_str}{ext}'

    Path(outdir).mkdir(parents=True, exist_ok=True)
    dest = os.path.join(outdir, filename)

    # Build content: metadata header + original trace
    header  = build_header(test, mode, variant_args, rtl_params, march_info,
                           simulator, timestamp,
                           score=score, score_metric=score_metric, size_info=size_info,
                           tc_version=tc_version)
    with open(source, 'r', errors='replace') as f:
        content = f.read()

    combined = header + content

    if compress:
        with zstd.open(dest, 'wt', encoding='utf-8') as f:
            f.write(combined)
    else:
        with open(dest, 'w', encoding='utf-8') as f:
            f.write(combined)

    size = os.path.getsize(dest)
    if size < 1024 * 1024:
        size_str = f'{size / 1024:.1f} KB'
    else:
        size_str = f'{size / 1024 / 1024:.1f} MB'

    if not quiet:
        print(f'Saved: {dest}  ({size_str})')
    return 0


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description='Save arvern asphalt.log with metadata and optional compression.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples (run from sim/rtl_sim/run/):
  python3 ../bin/save_trace.py --test inst_add
  python3 ../bin/save_trace.py --test inst_add --variant rwsrom rsalu
  python3 ../bin/save_trace.py --test instc_cm_push --mode comp --compress
  python3 ../bin/save_trace.py --test coremark --mode std --compress --outdir ~/arv_traces
        """
    )
    parser.add_argument('--test',     required=True,
                        help='Test name (e.g. inst_add, instc_cm_push)')
    parser.add_argument('--mode',     default='std', choices=['std', 'comp'],
                        help='Instruction mode (default: std)')
    parser.add_argument('--variant',  nargs='*', default=[], metavar='FLAG',
                        help='Variant flags, e.g. --variant rwsrom rsalu')
    parser.add_argument('--compress', action='store_true',
                        help='zstd-compress the output file (.log.zst)')
    parser.add_argument('--outdir',   default='./benchmark_traces/latest', metavar='DIR',
                        help='Output directory (default: ./benchmark_traces/latest)')
    parser.add_argument('--source',   default='./asphalt.log', metavar='FILE',
                        help='Source trace file (default: ./asphalt.log)')

    args = parser.parse_args()
    return save_trace(args.test, args.mode, args.variant or [],
                      args.compress, args.outdir, args.source)


if __name__ == '__main__':
    sys.exit(main())
