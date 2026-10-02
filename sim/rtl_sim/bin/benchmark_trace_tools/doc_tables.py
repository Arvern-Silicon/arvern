#!/usr/bin/env python3
"""Render the doc/benchmarking_guide.md score tables (§2.1, §2.2, §4.1) from
run_benchmark results.

    python3 -m benchmark_trace_tools.doc_tables <score_dir>

<score_dir> holds one file per sweep, <persona>_<opt>.txt (opt = Os/O2/O3), with
one "<benchmark> <score>" line per benchmark -- the `[done] ... -- <score>` lines
of `./run_benchmark -a -j 8 --rtl-config <persona>`:

    ./run_benchmark -a -j 8 --rtl-config classic 2>&1 | tee cls.log
    sed 's/\x1b\[[0-9;]*[A-Za-z]//g' cls.log | tr '\r' '\n' | grep -E '\[done' \
      | sed -E 's/.*-> ([a-z0-9_.-]+) +\([0-9:]+\) +. ([0-9.]+) .*/\1 \2/' | sort > classic_O2.txt

The M4 reference times are read from the guide's current §4.1 table. No trace
preprocessing (.stats.pkl) is needed for these tables.
"""
import math, re, sys, os
S=sys.argv[1] if len(sys.argv)>1 else '.'
DOC=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','..','..','doc','benchmarking_guide.md')
P=['light','classic','performance','ultra']
doc=open(DOC).read()
m4={}
for m in re.finditer(r'^\| ([a-z0-9_.-]+) \| (\d+) \| \d+ \| \d+ \| \d+ \| \d+ \|', doc, re.M):
    m4[m.group(1)]=int(m.group(2))
def load(p,opt):
    f=f'{S}/{p}_{opt}.txt'
    return dict((k,float(v)) for k,v in (l.split() for l in open(f))) if os.path.exists(f) else None
def geo(d):
    r=[m4[b]/d['embench_'+b] for b in m4]; return math.exp(sum(map(math.log,r))/len(r))
o2={p:load(p,'O2') for p in P}
have=[p for p in P if o2[p]]
print("## §2.1 headline (-O2)")
print("| Metric | **Light** | **Classic** | **Performance** | **Ultra** |\n|---|---:|---:|---:|---:|")
row=lambda label,f: "| "+label+" | "+" | ".join(f(o2[p]) if o2[p] else "—" for p in P)+" |"
print(row("**CoreMark / MHz** ↑ (`-O2`)", lambda d: f"{d['coremark']:.2f}"))
print(row("**Dhrystone 4mcu — DMIPS / MHz** ↑ (`-O2`)", lambda d: f"{d['dhrystone_4mcu']:.2f}"))
print(row("**Dhrystone v2.1 — DMIPS / MHz** ↑ (`-O2`)", lambda d: f"{d['dhrystone_v2.1']:.2f}"))
print(row("**Embench-IoT — Speed/MHz** ↑ (M4 = 1.0; geomean over 22, `-O2`)", lambda d: f"{geo(d):.2f}"))
print("\n## §2.2 per level")
for label,f in [("Embench Speed Score",geo),("CoreMark / MHz",lambda d:d['coremark']),("Dhrystone 4mcu",lambda d:d['dhrystone_4mcu']),("Dhrystone v2.1",lambda d:d['dhrystone_v2.1'])]:
    print(f"\n{label}\n| Persona | `-Os` | `-O2` | `-O3` |\n|---|---:|---:|---:|")
    for p in P:
        cells=[]
        for opt in ('Os','O2','O3'):
            d=load(p,opt); cells.append(f"{f(d):.2f}" if d else "—")
        print(f"| **{p.capitalize()}** | "+" | ".join(cells)+" |")
print("\n## §4.1 per-benchmark (-O2, ms)")
print("| Benchmark (run with `-O2`) | M4 reference (ms) | Light (ms) | Classic (ms) | Performance (ms) | Ultra (ms) |\n|---|---:|---:|---:|---:|---:|")
for b in m4:
    print(f"| {b} | {m4[b]} | "+" | ".join(f"{o2[p]['embench_'+b]:.0f}" if o2[p] else "—" for p in P)+" |")
print("| **Geomean Speed/MHz** ↑ (ratio) | (1.000) | "+" | ".join(f"{geo(o2[p]):.2f}" if o2[p] else "—" for p in P)+" |")
