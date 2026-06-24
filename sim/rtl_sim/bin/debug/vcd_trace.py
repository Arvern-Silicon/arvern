#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    vcd_trace.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Tabulate VCD signal values over a cycle range (workhorse signal-timeline tool).
#----------------------------------------------------------------------------

"""
Extract and display signal traces from a VCD file.

The output is a table where each row corresponds to a clock edge and shows
the values of all requested signals.  Rows are printed only when at least one
signal changes value (delta-compressed output), or every cycle with --every.

Time units:
  The tool works in "ticks" (VCD timestamps).  Use --clk-period to convert
  to cycle numbers (default: auto-detect from clock transitions).

Signal matching:
  Signals are matched by their leaf name (case-insensitive substring match).
  Use exact hierarchy paths for disambiguation, e.g.:
    dut.arv_csr_top_inst.arv_csr_traps_inst.trap_taken

Usage:
  python3 vcd_trace.py <vcd_file> <signal1> [signal2 ...] [options]

Examples:
  # Show irq_software and trap_taken from cycle 550 to 700
  python3 vcd_trace.py tb_arvern.vcd irq_software trap_taken --cycles 550:700

  # Show all transitions of mstatus_mie (any range)
  python3 vcd_trace.py tb_arvern.vcd mstatus_mie --transitions

  # Show a group of trap-related signals, clock period 10000 ticks
  python3 vcd_trace.py tb_arvern.vcd irq_software_i mstatus_mie irq_detect \\
      trap_pending_o trap_taken irq_suppress_post_mret \\
      --cycles 540:640 --clk-period 10000
"""

import argparse
import re
import sys
from collections import defaultdict


# ─── VCD Parser ───────────────────────────────────────────────────────────────

class VCDParser:
    """Minimal streaming VCD parser — no external dependencies."""

    def __init__(self, path):
        self.path      = path
        self.id_to_sig = {}   # vcd_id  -> list of (full_name, width)
        self.sig_to_id = {}   # full_name -> vcd_id
        self._timescale_str = ''
        self._parse_header()

    def _parse_header(self):
        scope_stack = []
        with open(self.path) as f:
            in_var = False
            for line in f:
                line = line.strip()
                if line.startswith('$timescale'):
                    # may span lines; collect until $end
                    ts_buf = line
                    if '$end' not in ts_buf:
                        for cont in f:
                            ts_buf += ' ' + cont.strip()
                            if '$end' in ts_buf:
                                break
                    m = re.search(r'\$timescale\s+(.+?)\s*\$end', ts_buf)
                    if m:
                        self._timescale_str = m.group(1).strip()
                elif line.startswith('$scope'):
                    m = re.search(r'\$scope\s+\w+\s+(\S+)', line)
                    if m:
                        scope_stack.append(m.group(1))
                elif line.startswith('$upscope'):
                    if scope_stack:
                        scope_stack.pop()
                elif line.startswith('$var'):
                    parts = line.split()
                    # $var <type> <width> <id> <name> ...
                    if len(parts) >= 5:
                        width  = int(parts[2])
                        vid    = parts[3]
                        name   = parts[4]
                        full   = '.'.join(scope_stack + [name]) if scope_stack else name
                        entry  = (full, width)
                        self.id_to_sig.setdefault(vid, []).append(entry)
                        self.sig_to_id[full] = vid
                elif '$enddefinitions' in line:
                    break

    @property
    def timescale(self):
        return self._timescale_str

    def all_signal_names(self):
        names = []
        for entries in self.id_to_sig.values():
            for full, _ in entries:
                names.append(full)
        return sorted(names)

    def find_signals(self, patterns):
        """
        Return list of (full_name, vcd_id, width) matching the given patterns.
        Each pattern is matched as a case-insensitive substring against full names.
        If a pattern looks like a full path (contains '.'), prefer exact match.
        """
        results = []
        seen_ids = set()
        for pat in patterns:
            pat_lower = pat.lower()
            matches = []
            for full, vid in self.sig_to_id.items():
                if pat_lower in full.lower():
                    matches.append(full)
            if not matches:
                print(f'Warning: no signal matching "{pat}"', file=sys.stderr)
                continue
            # Prefer exact (case-insensitive) suffix match
            exact = [m for m in matches if m.lower().endswith(pat_lower)]
            chosen = exact if exact else matches
            for full in chosen:
                vid = self.sig_to_id[full]
                if vid not in seen_ids:
                    width = next(w for fn, w in self.id_to_sig[vid] if fn == full)
                    results.append((full, vid, width))
                    seen_ids.add(vid)
        return results

    def stream_changes(self, vids_of_interest, t_start=0, t_end=None):
        """
        Yield (timestamp, {vid: value_str}) for each timestamp in [t_start, t_end]
        where at least one signal in vids_of_interest changes.
        value_str is a binary string (e.g. '0', '1', '00110101...').
        """
        interest = set(vids_of_interest)
        current  = {}      # vid -> current value string
        pending  = {}      # vid -> new value at current timestamp
        cur_t    = None

        def emit():
            if cur_t is None or not pending:
                return None
            if t_end is not None and cur_t > t_end:
                return None
            if cur_t < t_start:
                current.update(pending)
                pending.clear()
                return None
            snapshot = dict(current)
            snapshot.update(pending)
            current.update(pending)
            pending.clear()
            return (cur_t, dict(snapshot))

        with open(self.path) as f:
            in_defs = True
            results = []
            for raw_line in f:
                line = raw_line.strip()
                if not line:
                    continue

                # Skip header until $enddefinitions
                if in_defs:
                    if '$enddefinitions' in line:
                        in_defs = False
                    continue

                if line.startswith('#'):
                    # New timestamp
                    ev = emit()
                    if ev:
                        yield ev
                    new_t = int(line[1:])
                    if t_end is not None and new_t > t_end:
                        return
                    cur_t = new_t
                elif line.startswith('b') or line.startswith('B'):
                    # Vector: b<value> <id>
                    parts = line.split()
                    if len(parts) == 2:
                        val = parts[0][1:]
                        vid = parts[1]
                        if vid in interest:
                            pending[vid] = val
                            current.setdefault(vid, 'x' * 32)
                elif len(line) >= 2 and line[0] in '01xzXZ':
                    # Scalar: <value><id>
                    val = line[0]
                    vid = line[1:]
                    if vid in interest:
                        pending[vid] = val
                        current.setdefault(vid, 'x')

            # Flush last timestamp
            ev = emit()
            if ev:
                yield ev


# ─── Formatting helpers ────────────────────────────────────────────────────────

def bin_to_hex(bstr, width):
    """Convert binary string to hex representation."""
    if any(c in bstr for c in 'xzXZ'):
        return bstr  # keep as-is if contains X/Z
    val = int(bstr, 2)
    hex_digits = (width + 3) // 4
    return f'0x{val:0{hex_digits}X}'


def format_val(bstr, width, as_hex=True):
    if width == 1:
        return bstr
    return bin_to_hex(bstr, width) if as_hex else bstr


def ticks_to_cycle(t, clk_period):
    if clk_period:
        return t // clk_period
    return t


# ─── Auto-detect clock period ─────────────────────────────────────────────────

def detect_clk_period(parser, clk_signal='free_clk'):
    """Find VCD period of the first signal whose name contains clk_signal."""
    matches = parser.find_signals([clk_signal])
    if not matches:
        return None
    _, vid, _ = matches[0]
    edges = []
    for t, snap in parser.stream_changes([vid], t_start=0, t_end=None):
        if vid in snap and snap[vid] == '1':
            edges.append(t)
            if len(edges) >= 3:
                break
    if len(edges) >= 2:
        return edges[1] - edges[0]
    return None


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser_arg = argparse.ArgumentParser(
        description='Extract signal traces from a VCD file.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser_arg.add_argument('vcd',      help='Path to VCD file')
    parser_arg.add_argument('signals',  nargs='*', help='Signal name patterns to display')
    parser_arg.add_argument('--cycles', metavar='START:END',
                            help='Cycle range to display (e.g. 540:640)')
    parser_arg.add_argument('--ticks',  metavar='START:END',
                            help='Raw tick range to display (overrides --cycles)')
    parser_arg.add_argument('--clk-period', type=int, metavar='N',
                            help='Clock period in ticks (auto-detected if omitted)')
    parser_arg.add_argument('--every',  action='store_true',
                            help='Print a row every tick that has any activity (default: only on changes to listed signals)')
    parser_arg.add_argument('--transitions', action='store_true',
                            help='Show only rows where at least one listed signal transitions')
    parser_arg.add_argument('--list',   action='store_true',
                            help='List all signals in the VCD file and exit')
    parser_arg.add_argument('--grep',   metavar='PATTERN',
                            help='List signals matching PATTERN and exit')
    parser_arg.add_argument('--hex',    action='store_true', default=True,
                            help='Display vector values as hex (default: on)')
    parser_arg.add_argument('--bin',    action='store_true',
                            help='Display vector values as binary')
    args = parser_arg.parse_args()

    vcd_parser = VCDParser(args.vcd)

    if args.list:
        for name in vcd_parser.all_signal_names():
            print(name)
        return 0

    if args.grep:
        pat = args.grep.lower()
        for name in vcd_parser.all_signal_names():
            if pat in name.lower():
                print(name)
        return 0

    if not args.signals:
        parser_arg.error('Specify signal patterns to display (or --list / --grep)')

    # Resolve signals
    sigs = vcd_parser.find_signals(args.signals)
    if not sigs:
        print('No signals found.', file=sys.stderr)
        return 1

    # Clock period
    clk_period = args.clk_period
    if clk_period is None:
        clk_period = detect_clk_period(vcd_parser)
        if clk_period:
            print(f'# Auto-detected clock period: {clk_period} ticks ({vcd_parser.timescale})',
                  file=sys.stderr)

    # Time range
    t_start, t_end = 0, None
    if args.ticks:
        parts = args.ticks.split(':')
        t_start = int(parts[0]) if parts[0] else 0
        t_end   = int(parts[1]) if len(parts) > 1 and parts[1] else None
    elif args.cycles and clk_period:
        parts = args.cycles.split(':')
        t_start = int(parts[0]) * clk_period if parts[0] else 0
        t_end   = int(parts[1]) * clk_period if len(parts) > 1 and parts[1] else None

    # Column headers
    names     = [s[0].split('.')[-1] for s in sigs]  # leaf names for display
    full_names = [s[0] for s in sigs]
    vids      = [s[1] for s in sigs]
    widths    = [s[2] for s in sigs]
    col_widths = [max(len(n), 4) for n in names]
    as_hex    = not args.bin

    # Determine display widths for hex values
    for i, w in enumerate(widths):
        if w > 1:
            hex_len = (w + 3) // 4 + 2  # 0xNN...
            col_widths[i] = max(col_widths[i], hex_len)

    # Print header
    cycle_hdr = 'Cycle' if clk_period else 'Tick'
    hdr = f'{"":>8}  ' + '  '.join(n.rjust(col_widths[i]) for i, n in enumerate(names))
    sep = '-' * len(hdr)
    print(sep)
    print(hdr)
    print(f'{"":>8}  ' + '  '.join(f[-(col_widths[i]):].rjust(col_widths[i]) for i, f in enumerate(full_names)))
    print(sep)

    prev_vals = {}
    for t, snap in vcd_parser.stream_changes(vids, t_start=t_start, t_end=t_end):
        # Check if any listed signal changed
        changed = any(vid in snap and snap.get(vid) != prev_vals.get(vid) for vid in vids)
        if args.transitions and not changed:
            continue

        cycle = ticks_to_cycle(t, clk_period)
        row_vals = []
        for i, vid in enumerate(vids):
            val = snap.get(vid, prev_vals.get(vid, 'x'))
            row_vals.append(format_val(val, widths[i], as_hex))

        print(f'{cycle:>8}  ' + '  '.join(v.rjust(col_widths[i]) for i, v in enumerate(row_vals)))
        prev_vals = {vid: snap.get(vid, prev_vals.get(vid, 'x')) for vid in vids}

    print(sep)
    return 0


if __name__ == '__main__':
    sys.exit(main())
