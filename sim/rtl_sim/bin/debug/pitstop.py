#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    pitstop.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Shared helper: locate and parse pitstop.log, the external-debug event
# companion to asphalt.log (produced by bench/verilog/probes_debug.v).
#
# pitstop.log is written to the simulation working directory next to the
# run's asphalt.log target. In sim/rtl_sim/run/ the visible asphalt.log is a
# symlink into WORK/<tmp>/; pitstop.log is its sibling there (and, when the
# run script links it, also sim/rtl_sim/run/pitstop.log). find_pitstop_log()
# resolves either layout so the asphalt_* tools interleave events automatically.
#
# Format spec: doc/asphalt_trace_format.md section 8.
#----------------------------------------------------------------------------

import os


def find_pitstop_log(asphalt_path):
    """Locate pitstop.log associated with the given asphalt.log path.

    Checks, in order: alongside the realpath of asphalt.log (follows the
    run/asphalt.log -> WORK/<tmp>/asphalt.log symlink to its directory), then
    alongside the literal path given. Returns the path or None.
    """
    candidates = []
    real = os.path.realpath(asphalt_path)
    candidates.append(os.path.join(os.path.dirname(real), 'pitstop.log'))
    candidates.append(os.path.join(os.path.dirname(os.path.abspath(asphalt_path)),
                                   'pitstop.log'))
    for cand in candidates:
        if os.path.isfile(cand):
            return cand
    return None


def parse_pitstop_log(path):
    """Parse pitstop.log into a cycle-sorted list of event dicts.

    Each event: {'cycle': int, 'src': 'DMI'|'SBA'|'DBG', 'text': str, '_raw': str}
    where 'text' is everything after the cycle column and '_raw' is the stripped
    line. Comment (#) and malformed lines are skipped. Returns [] for a missing
    path or a header-only file (e.g. a DEBUG_EN=0 run).
    """
    events = []
    if not path:
        return events
    try:
        fh = open(path, 'r')
    except OSError:
        return events
    with fh:
        for raw in fh:
            line = raw.rstrip('\n')
            s = line.strip()
            if not s or s.startswith('#'):
                continue
            parts = s.split(None, 1)
            if len(parts) < 2:
                continue
            try:
                cyc = int(parts[0])
            except ValueError:
                continue
            rest = parts[1]
            src = rest.split(None, 1)[0]
            events.append({'cycle': cyc, 'src': src, 'text': rest, '_raw': s})
    events.sort(key=lambda e: e['cycle'])
    return events


def load_pitstop_events(asphalt_path):
    """Convenience: find + parse in one call. Returns (path_or_None, events)."""
    path = find_pitstop_log(asphalt_path)
    return path, parse_pitstop_log(path)
