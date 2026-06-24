#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    bench_utils.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Shared utility helpers (Embench baselines, snapshot I/O) for benchmark_trace_tools.
#----------------------------------------------------------------------------

"""Shared utilities for bench_snapshot and bench_compare."""

import json
import math
import pickle
import re
from pathlib import Path


# ── Embench baseline data ──────────────────────────────────────────────────────

_EMBENCH_BASELINE_DIR = (
    Path(__file__).resolve().parent.parent.parent / 'src-c' / 'embench-iot' / 'baseline-data'
)

# Label used as the virtual snapshot name throughout the tooling
EMBENCH_BASELINE_LABEL = 'embench_baseline'


def _load_embench_baseline():
    speed, size_bl = {}, {}
    sp = _EMBENCH_BASELINE_DIR / 'speed.json'
    sz = _EMBENCH_BASELINE_DIR / 'size.json'
    if sp.exists():
        with open(sp) as f:
            speed = json.load(f)
    if sz.exists():
        with open(sz) as f:
            size_bl = json.load(f)
    return speed, size_bl


_EMBENCH_SPEED_BL, _EMBENCH_SIZE_BL = _load_embench_baseline()


def embench_baseline_available() -> bool:
    """True if embench baseline JSON files are present."""
    return bool(_EMBENCH_SPEED_BL)


def gsd_interpretation(gsd) -> str:
    """Short, plain-language label characterising the spread for a GSD value.

    Calibrated against Embench's own convention (per `pylib/embench_core.py`)
    that GSD > ~1.30 means the geometric mean alone is misleading and the
    per-benchmark detail matters more than the headline number.

    Bands:
        ≤ 1.20  -- tight; geomean reliable, no caveat printed
        ≤ 1.50  -- moderate spread
        ≤ 2.00  -- wide; geomean usable but the per-bench rows tell the real story
        >  2.00 -- very wide; the geomean is dominated by a few outliers and
                   on its own is a coin-flip description of performance
    """
    if gsd is None:
        return ""
    if gsd <= 1.20:
        return ""
    if gsd <= 1.50:
        return "moderate spread"
    if gsd <= 2.00:
        return "wide — use with care"
    return "very wide — caution"


def geomean_ratio(target_bundles: dict, ref_bundles: dict):
    """Geomean / GSD of per-bench reference-to-target ms ratios.

    Generalized "Speed Score" against any chosen reference (not just M4). For
    each embench bench present in BOTH dicts with positive Time(ms) scores,
    compute R_b = ref_ms / target_ms (so >1 means target is faster than ref),
    then aggregate via geometric mean + GSD using Embench's own formulas
    (`pylib/embench_core.py:compute_geomean` + `compute_geosd`).

    Both inputs use the standard bundle format (the synthetic M4 baseline
    bundles from `load_embench_baseline_bundles()` are interchangeable with
    any real snapshot bundle dict), so feeding the same bundles in as both
    target and reference yields (1.0, 1.0, n) by construction.

    Skips non-embench tests, missing benches, non-positive times, and any
    bench whose score unit isn't Time(ms) -- CoreMark/MHz and DMIPS/MHz
    are rate units that would invert the ratio direction.

    Returns:
        (geomean, gsd, n)
          geomean : float  -- geomean of R_b   (None if n == 0)
          gsd     : float  -- exp(sqrt(sum(ln(R_b/GM)^2)/n))  (1.0 if n == 1)
          n       : int    -- number of contributing benchmarks
    """
    ratios = []
    for test, tgt_bundle in target_bundles.items():
        if not test.startswith('embench_'):
            continue
        ref_bundle = ref_bundles.get(test)
        if ref_bundle is None:
            continue
        ref_ms,    ref_unit = extract_metric(ref_bundle, 'score')
        target_ms, tgt_unit = extract_metric(tgt_bundle, 'score')
        if ref_ms is None or ref_ms <= 0:
            continue
        if target_ms is None or target_ms <= 0:
            continue
        # Only ratio-able when both sides are time-in-ms.
        if (ref_unit and ref_unit != 'Time(ms)') or (tgt_unit and tgt_unit != 'Time(ms)'):
            continue
        ratios.append(ref_ms / target_ms)
    n = len(ratios)
    if n == 0:
        return (None, None, 0)
    gm = math.exp(sum(math.log(r) for r in ratios) / n)
    if n == 1:
        return (gm, 1.0, n)
    lnsize = sum(math.log(r / gm) ** 2 for r in ratios)
    gsd = math.exp(math.sqrt(lnsize / n))
    return (gm, gsd, n)


def embench_speed_score(bundles: dict):
    """Canonical Embench-IoT Speed Score for a set of target bundles.

    Per-bench ratio R_b = M4_baseline_ms / target_ms (higher = faster than M4),
    aggregated via geometric mean + GSD. Wraps `geomean_ratio()` with the M4
    baseline (speed.json) as the reference.

    This is the *fixed* M4-anchored Speed Score that Embench publishes for
    cross-platform comparison. For ratios against a user-chosen reference
    (e.g. in the snapshot-compare viewer), call `geomean_ratio()` directly.

    Returns:
        (speed_score, gsd, n) -- same shape as `geomean_ratio()`. By
        construction, feeding `load_embench_baseline_bundles()` back through
        this helper yields (1.0, 1.0, 22) -- M4 vs itself.
    """
    if not _EMBENCH_SPEED_BL:
        return (None, None, 0)
    return geomean_ratio(bundles, load_embench_baseline_bundles())


def load_embench_baseline_bundles() -> dict:
    """Synthesize minimal bundles from embench speed.json / size.json.

    Returns {test_name: bundle} where each bundle carries only the metadata
    fields used by extract_metric (score and size).  Other attributes (ipc,
    branch_miss, …) will return None for these bundles.
    """
    bundles = {}
    for bench_name in sorted(_EMBENCH_SPEED_BL):
        test     = f'embench_{bench_name}'
        time_ms  = float(_EMBENCH_SPEED_BL[bench_name])
        size_sec = _EMBENCH_SIZE_BL.get(bench_name, {})
        size_str = '  '.join(f'{k}={v}' for k, v in size_sec.items())
        bundles[test] = {
            'metadata': {
                'Test': test,
                'benchmark': {
                    'Score':        f'{time_ms:.1f}  (Time(ms))',
                    'Size (bytes)': size_str,
                },
            },
        }
    return bundles


# ── Attribute catalogue ────────────────────────────────────────────────────────

ATTR_LABELS = {
    'score':       'Score (raw)',
    'text_size':   'Text size (bytes)',
    'total_size':  'Total size (bytes)',
    'ipc':         'IPC',
    'branch_miss': 'Branch miss %',
}

# True = higher is better, False = lower is better, None = depends on benchmark
ATTR_HIGHER_IS_BETTER = {
    'score':       None,
    'text_size':   False,
    'total_size':  False,
    'ipc':         True,
    'branch_miss': False,
}

_SCORE_UNIT_HIB = {
    'CoreMark/MHz': True,
    'DMIPS/MHz':    True,
    'Time(ms)':     False,
}


# ── Parsing helpers ────────────────────────────────────────────────────────────

def parse_score(raw: str):
    """Return (float_value, unit_str) from e.g. '3.38  (CoreMark/MHz)'."""
    m  = re.match(r'^\s*([\d.]+)', raw)
    um = re.search(r'\((.+)\)', raw)
    return (float(m.group(1)) if m else None,
            um.group(1).strip() if um else '')


def parse_size(raw: str) -> dict:
    """Return {section: bytes} from 'text=N rodata=N data=N bss=N'."""
    sizes = {}
    for tok in raw.split():
        kv = tok.split('=')
        if len(kv) == 2:
            try:
                sizes[kv[0]] = int(kv[1])
            except ValueError:
                pass
    return sizes


def score_higher_is_better(bundle: dict):
    """Return True / False / None depending on this bundle's score unit."""
    raw = bundle.get('metadata', {}).get('benchmark', {}).get('Score', '')
    _, unit = parse_score(raw)
    return _SCORE_UNIT_HIB.get(unit)


def detect_suite(test: str) -> str:
    """Return the suite prefix (e.g. 'embench', 'coremark', 'dhrystone')."""
    return test.split('_', 1)[0]


# ── Metric extraction ──────────────────────────────────────────────────────────

def precompute_metrics(bundle: dict) -> dict:
    """Extract all scalar metrics from a bundle into a flat dict.

    Called once at preprocessing time so that extract_metric() can avoid
    re-parsing strings and filtering DataFrames on every render.
    """
    meta = bundle.get('metadata', {})
    bm   = meta.get('benchmark', {})

    score_val, score_unit = parse_score(bm.get('Score', ''))
    sizes = parse_size(bm.get('Size (bytes)', ''))

    branch_miss = None
    bp = bundle.get('branch_prediction', {})
    if isinstance(bp, dict):
        summary = bp.get('summary')
        if summary is not None and hasattr(summary, 'empty') and not summary.empty:
            row = summary[summary.scheme == 'bimodal_2bit']
            if not row.empty:
                branch_miss = float(row.iloc[0]['mispredict_pct'])

    return {
        'score_value':  score_val,
        'score_unit':   score_unit,
        'text_size':    sizes.get('text'),
        'total_size':   sum(sizes.values()) if sizes else None,
        'ipc':          bundle.get('pipeline', {}).get('ipc'),
        'branch_miss':  branch_miss,
    }


def extract_metric(bundle, attr: str):
    """Return (numeric_value, unit_str) for the requested attribute.

    Returns (None, '') when data is unavailable or bundle is None.
    Uses pre-computed metrics when available (from precompute_metrics()),
    falls back to on-the-fly parsing for older pkl files.
    """
    if bundle is None:
        return None, ''

    # Fast path: use pre-computed metrics if present
    pm = bundle.get('_metrics')
    if pm is not None:
        if attr == 'score':
            return pm.get('score_value'), pm.get('score_unit', '')
        if attr == 'text_size':
            return pm.get('text_size'), 'bytes'
        if attr == 'total_size':
            return pm.get('total_size'), 'bytes'
        if attr == 'ipc':
            return pm.get('ipc'), ''
        if attr == 'branch_miss':
            return pm.get('branch_miss'), '%'
        return None, ''

    # Slow path: parse on the fly (old pkl without _metrics)
    meta = bundle.get('metadata', {})
    bm   = meta.get('benchmark', {})

    if attr == 'score':
        raw = bm.get('Score', '')
        v, unit = parse_score(raw)
        return v, unit

    if attr == 'text_size':
        sizes = parse_size(bm.get('Size (bytes)', ''))
        return sizes.get('text'), 'bytes'

    if attr == 'total_size':
        sizes = parse_size(bm.get('Size (bytes)', ''))
        return (sum(sizes.values()) if sizes else None), 'bytes'

    if attr == 'ipc':
        return bundle.get('pipeline', {}).get('ipc'), ''

    if attr == 'branch_miss':
        bp = bundle.get('branch_prediction', {})
        if isinstance(bp, dict):
            summary = bp.get('summary')
            if summary is not None and not summary.empty:
                row = summary[summary.scheme == 'bimodal_2bit']
                if not row.empty:
                    return float(row.iloc[0]['mispredict_pct']), '%'
        return None, ''

    return None, ''


# ── Snapshot I/O ───────────────────────────────────────────────────────────────

def load_snapshot_bundles(snap_name: str, snap_dir: Path) -> dict:
    """Load bundles for a snapshot name.

    Handles the special EMBENCH_BASELINE_LABEL without touching the filesystem
    snapshot directory.
    """
    if snap_name == EMBENCH_BASELINE_LABEL:
        return load_embench_baseline_bundles()
    bundles = {}
    for pkl in sorted(snap_dir.glob('*.stats.pkl')):
        try:
            with open(pkl, 'rb') as f:
                b = pickle.load(f)
            test = b.get('metadata', {}).get('Test', '')
            if test:
                bundles[test] = b
        except Exception:
            pass
    return bundles


def load_latest_bundles(traces_dir: Path) -> dict:
    """Return {test_name: bundle} for the most recent pkl per benchmark
    in traces_dir/latest/."""
    latest = {}   # test -> (mtime, bundle)
    for p in sorted((traces_dir / 'latest').glob('*.stats.pkl')):
        try:
            with open(p, 'rb') as f:
                b = pickle.load(f)
            test  = b.get('metadata', {}).get('Test', '')
            mtime = b.get('mtime', 0)
            if test and (test not in latest or mtime > latest[test][0]):
                latest[test] = (mtime, b)
        except Exception:
            pass
    return {t: b for t, (_, b) in latest.items()}


def list_snapshots(traces_dir: Path) -> list:
    """Return [(name, manifest_dict), ...] sorted by name.

    Prepends a virtual entry for the embench baseline if baseline data is
    available, so callers get it automatically in the list.
    """
    result = []

    # Virtual entry for embench baseline
    if embench_baseline_available():
        n_benchmarks = len(_EMBENCH_SPEED_BL)
        result.append((EMBENCH_BASELINE_LABEL, {
            'description': 'Embench reference platform baseline',
            'benchmarks':  [f'embench_{b}' for b in sorted(_EMBENCH_SPEED_BL)],
            '_virtual':    True,
            '_n':          n_benchmarks,
        }))

    # Real on-disk snapshots
    snap_root = traces_dir / 'snapshots'
    if snap_root.is_dir():
        for d in sorted(snap_root.iterdir()):
            if d.is_dir():
                manifest = {}
                mp = d / 'manifest.json'
                if mp.exists():
                    try:
                        with open(mp) as f:
                            manifest = json.load(f)
                    except Exception:
                        pass
                result.append((d.name, manifest))

    return result
