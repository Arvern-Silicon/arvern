#!/usr/bin/env python3
"""Render the doc/synthesis_guide.md §2 area tables (and the README / benchmarking
guide area rows) from results_sweep/persona_*/report.area_analysis.txt.

    ./run_syn_d -rtl_config light,classic,performance,ultra,light-dbg,classic-dbg,performance-dbg,ultra-dbg
    python3 doc_area_tables.py
"""
import re,os,sys
FEATURES = '--features' in sys.argv
R=os.path.join(os.path.dirname(os.path.abspath(__file__)),'results_sweep')
P=['light','classic','performance','ultra']
TRIG={'light':0,'classic':2,'performance':4,'ultra':8}
def load(name):
    t=open(f'{R}/persona_{name}/report.area_analysis.txt').read()
    mods={m.group(1).strip():int(m.group(2)) for m in re.finditer(r'^([A-Za-z][^|\n]*?)\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*[\d.]+%',t,re.M)}
    tot=int(re.search(r'Total NAND2 equivalent:\s*(\d+)',t).group(1))
    flops=int(re.search(r'flops\):\s*(\d+)',t).group(1))
    return mods,tot,flops
def _personas():
    D={p:load(p) for p in P}; DB={p:load(p+'-dbg') for p in P}
    k=lambda g: g/1000.0
    rows=[("Integer Register File","Integer Register File"),
          ("ALU<br/>*(incl. enabled B-ext sub-extensions)*","ALU"),
          ("MUL / DIV<br/>*(M-extension, when present)*","MUL / DIV"),
          ("Instruction Decode<br/>*(unified RV32I/E + C)*","Instruction Decode"),
          ("Instruction Fetch<br/>*(including prefetch buffer)*","Instruction Fetch"),
          ("Load/Store Unit","Load-Store Unit"),
          ("CSR core<br/>*(mtraps + ids + decode + read-mux, incl. Smrnmi)*","CSR core"),
          ("CSR Zicntr<br/>*(cycle / instret + U-mode shadows)*","CSR Zicntr"),
          ("CSR Zihpm<br/>*(mhpmcounter3–N + event selectors)*","CSR Zihpm"),
          ("UOP Sequencer<br/>*(Zcmp / Zcmt, when present)*","UOP Sequencer")]
    print("## §2.1")
    print("| Persona | Total area | Flop count |\n|---|---:|---:|")
    for p in P: print(f"| **{p.capitalize()}** | {k(D[p][1]):.1f} kGates | ~{round(D[p][2],-1):,} |")
    print("\n## §2.2 rows")
    for label,key in rows:
        print(f"| {label} | "+" | ".join(f"{k(D[p][0].get(key,0)):.1f}" for p in P)+" |")
    print("| **Total (aRVern)** | "+" | ".join(f"**{k(D[p][1]):.1f}**" for p in P)+" |")
    print("| Sequential cells (flop count) | "+" | ".join(f"~{round(D[p][2],-1):,}" for p in P)+" |")
    print("\n## §2.3 per persona")
    print("| Persona | Triggers (`DM_TRIGGER_NR`) | Base | `-dbg` total | Δ debug |\n|---|---:|---:|---:|---:|")
    for p in P: print(f"| {p.capitalize()} | {TRIG[p]} | {k(D[p][1]):.1f} | {k(DB[p][1]):.1f} | {k(DB[p][1]-D[p][1]):.1f} |")
    ld=DB['light'][0]; base=D['light'][1]; dbg=DB['light'][1]
    sub=ld.get('Debug Module core',0)+ld.get('Debug SBA',0)+ld.get('Debug CSRs (hart)',0)
    print("\n## §2.3 composition (light-dbg, 0 triggers)")
    print(f"| Debug Module core | {k(ld.get('Debug Module core',0)):.1f} |\n| Debug SBA (System Bus Access master) | {k(ld.get('Debug SBA',0)):.1f} |\n| Debug CSRs (hart-side `dcsr` / `dpc`) | {k(ld.get('Debug CSRs (hart)',0)):.1f} |")
    print(f"| **Debug modules subtotal** | **{k(sub):.1f}** |\n| Core-side debug logic (regfile abstract-access port + decode / CSR gating) | ~{k(dbg-base-sub):.1f} |\n| **Total (`DEBUG_EN=1` = Δ Light)** | **~{k(dbg-base):.1f}** |")
    # per-trigger cost: (ultra-dbg delta - light-dbg delta) / 8 is confounded by persona; use the three non-zero-trigger deltas minus the light delta
    deltas=[(TRIG[p], k(DB[p][1]-D[p][1])) for p in P]
    d0=deltas[0][1]; per=[(d-d0)/n for n,d in deltas if n]
    print(f"\nper-trigger estimate: {sum(per)/len(per):.2f} kGates (from {[f'{x:.2f}' for x in per]})")
    print("\n## README / benchmarking rows")
    print("| Area<br/>NAND2-equiv. kgates ↓ | "+" | ".join(f"_{round(k(D[p][1]))}_" for p in P)+" |")
    print("| **Area — NAND2-equivalent kgates** | "+" | ".join(f"{round(k(D[p][1]))}" for p in P)+" |")


if __name__ == '__main__' and not FEATURES:
    _personas()

# ---------------------------------------------------------------------------
# §2.4 feature-cost table: `python3 doc_area_tables.py --features`
#
# Results are looked up by PARAMETER VECTOR (the rtl_params.tcl snapshot in each
# results_sweep/ directory), never by directory name, so index renumbering of
# the sweep set cannot mis-attribute a run. Newest directory wins on duplicates.
# Each row is (label, lands-in, light-step, full-step); a step is
# (overrides-with, overrides-without) applied to the light persona / the
# run_config default; cost = area(with) - area(without) in kGates, "—" when a
# vector has no synthesis result.
# ---------------------------------------------------------------------------
def _features():
    import sys, json, glob
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'sim', 'rtl_sim', 'bin'))
    from rtl_sweep_configs import sweepable_params, PERSONAS
    cfg = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'sim', 'rtl_sim', 'run', 'run_config.json')))
    params = sweepable_params(cfg['rtl_config'])
    keys = sorted(params)
    F = {k: params[k]['default'] for k in keys}
    L = dict(F); L.update(dict(PERSONAS)['light'])
    by_vec = {}
    for d in glob.glob(f'{R}/*'):
        tcl = os.path.join(d, 'rtl_params.tcl'); rep = os.path.join(d, 'report.area_analysis.txt')
        if not (os.path.exists(tcl) and os.path.exists(rep)):
            continue
        v = {}
        for m in re.finditer(r'^set RTL_PARAM_(\w+) (\d+)', open(tcl).read(), re.M):
            if m.group(1) in params: v[m.group(1)] = int(m.group(2))
        if set(v) != set(keys):
            continue
        vec = tuple(v[k] for k in keys)
        tot = int(re.search(r'Total NAND2 equivalent:\s*(\d+)', open(rep).read()).group(1))
        mt = os.path.getmtime(rep)
        if vec not in by_vec or mt > by_vec[vec][1]:
            by_vec[vec] = (tot, mt, os.path.basename(d))
    def area(base, ov):
        v = dict(base); v.update(ov)
        e = by_vec.get(tuple(v[k] for k in keys))
        return e[0] if e else None
    def cost(base, with_, without):
        a, b = area(base, with_), area(base, without)
        return None if a is None or b is None else (a - b) / 1000.0
    fmt = lambda c: '—' if c is None else f'{c:+.1f}'
    NA = None  # step does not exist from this end
    rows = [
        ("RV32I register file (`RV32E_EN` 0, vs RV32E)", "Integer Register File", (dict(RV32E_EN=0), {}), ({}, dict(RV32E_EN=1))),
        ("Zmmul multiplier (`M_EXTENSION` 1, vs none)", "MUL / DIV", ({}, dict(M_EXTENSION=0)), (dict(M_EXTENSION=1), dict(M_EXTENSION=0))),
        ("Divider, radix-2 / 33 cycles (`M_EXTENSION` 2, `DIV_TYPE` 3, vs Zmmul)", "MUL / DIV", (dict(M_EXTENSION=2), {}), ({}, dict(M_EXTENSION=1))),
        ("Divider radix-4 / 17 cycles (`DIV_TYPE` 2, vs radix-2)", "MUL / DIV", (dict(M_EXTENSION=2, DIV_TYPE=2), dict(M_EXTENSION=2)), (dict(DIV_TYPE=2), {})),
        ("Divider radix-8 / 12 cycles (`DIV_TYPE` 1, vs radix-2)", "MUL / DIV", (dict(M_EXTENSION=2, DIV_TYPE=1), dict(M_EXTENSION=2)), (dict(DIV_TYPE=1), {})),
        ("Multiplier 4-cycle (`MUL_TYPE` 2, vs 16-cycle)", "MUL / DIV", (dict(MUL_TYPE=2), {}), (dict(MUL_TYPE=2), dict(MUL_TYPE=3))),
        ("Multiplier single-cycle (`MUL_TYPE` 1, vs 16-cycle)", "MUL / DIV", (dict(MUL_TYPE=1), {}), ({}, dict(MUL_TYPE=3))),
        ("Zbb (`B_EXTENSION` 1)", "ALU", (dict(B_EXTENSION=1), {}), (dict(B_EXTENSION=1), dict(B_EXTENSION=0))),
        ("+ Zba (`B_EXTENSION` 2)", "ALU", (dict(B_EXTENSION=2), dict(B_EXTENSION=1)), (dict(B_EXTENSION=2), dict(B_EXTENSION=1))),
        ("+ Zbs (`B_EXTENSION` 3)", "ALU", (dict(B_EXTENSION=3), dict(B_EXTENSION=2)), (dict(B_EXTENSION=3), dict(B_EXTENSION=2))),
        ("+ Zbc (`B_EXTENSION` 4)", "ALU", (dict(B_EXTENSION=4), dict(B_EXTENSION=3)), ({}, dict(B_EXTENSION=3))),
        ("Zca (`C_EXTENSION` 1, vs no compressed)", "Instruction Decode, Instruction Fetch", ({}, dict(C_EXTENSION=0)), (dict(C_EXTENSION=1), dict(C_EXTENSION=0))),
        ("+ Zcb (`C_EXTENSION` 2)", "Instruction Decode", (dict(C_EXTENSION=2), {}), (dict(C_EXTENSION=2), dict(C_EXTENSION=1))),
        ("+ Zcmp (`C_EXTENSION` 3)", "UOP Sequencer, Instruction Decode", (dict(C_EXTENSION=3), dict(C_EXTENSION=2)), (dict(C_EXTENSION=3), dict(C_EXTENSION=2))),
        ("+ Zcmt (`C_EXTENSION` 4)", "UOP Sequencer", (dict(C_EXTENSION=4), dict(C_EXTENSION=3)), ({}, dict(C_EXTENSION=3))),
        ("S + U modes (`SU_MODE_EN` 1)", "CSR core", (dict(SU_MODE_EN=1), {}), ({}, dict(SU_MODE_EN=0))),
        ("PMP 4 entries, M-only core (`PMP_NR` 4)", "Instruction Fetch, Load/Store Unit, CSR core", (dict(PMP_NR=4), {}), NA),
        ("PMP 8 entries, M-only core", "same", (dict(PMP_NR=8), {}), NA),
        ("PMP 16 entries, M-only core", "same", (dict(PMP_NR=16), {}), NA),
        ("PMP 4 entries with S + U", "same", (dict(SU_MODE_EN=1, PMP_NR=4), dict(SU_MODE_EN=1)), (dict(PMP_NR=4), dict(PMP_NR=0))),
        ("PMP 8 entries with S + U", "same", (dict(SU_MODE_EN=1, PMP_NR=8), dict(SU_MODE_EN=1)), (dict(PMP_NR=8), dict(PMP_NR=0))),
        ("PMP 16 entries with S + U", "same", (dict(SU_MODE_EN=1, PMP_NR=16), dict(SU_MODE_EN=1)), (dict(PMP_NR=16), dict(PMP_NR=0))),
        ("Zicntr (`ZICNTR_EN` 1)", "CSR Zicntr", (dict(ZICNTR_EN=1), {}), ({}, dict(ZICNTR_EN=0))),
        ("Zihpm, 1 counter (`ZIHPM_NR` 1)", "CSR Zihpm", (dict(ZIHPM_NR=1), {}), (dict(ZIHPM_NR=1), dict(ZIHPM_NR=0))),
        ("Zihpm, 4 counters", "CSR Zihpm", (dict(ZIHPM_NR=4), {}), (dict(ZIHPM_NR=4), dict(ZIHPM_NR=0))),
        ("Zihpm, 8 counters", "CSR Zihpm", (dict(ZIHPM_NR=8), {}), (dict(ZIHPM_NR=8), dict(ZIHPM_NR=0))),
        ("External debug, no triggers (`DEBUG_EN` 1)", "Debug Module core, Debug SBA, Debug CSRs", (dict(DEBUG_EN=1), {}), (dict(DEBUG_EN=1, DM_TRIGGER_NR=0), dict(DEBUG_EN=0, DM_TRIGGER_NR=0))),
        ("+ 1 Sdtrig trigger (`DM_TRIGGER_NR` 1)", "Debug Triggers", (dict(DEBUG_EN=1, DM_TRIGGER_NR=1), dict(DEBUG_EN=1)), (dict(DM_TRIGGER_NR=1), dict(DM_TRIGGER_NR=0))),
        ("+ 2 Sdtrig triggers", "Debug Triggers", (dict(DEBUG_EN=1, DM_TRIGGER_NR=2), dict(DEBUG_EN=1)), (dict(DM_TRIGGER_NR=2), dict(DM_TRIGGER_NR=0))),
        ("+ 4 Sdtrig triggers", "Debug Triggers", (dict(DEBUG_EN=1, DM_TRIGGER_NR=4), dict(DEBUG_EN=1)), (dict(DM_TRIGGER_NR=4), dict(DM_TRIGGER_NR=0))),
        ("+ 8 Sdtrig triggers", "Debug Triggers", (dict(DEBUG_EN=1, DM_TRIGGER_NR=8), dict(DEBUG_EN=1)), (dict(DM_TRIGGER_NR=8), dict(DM_TRIGGER_NR=0))),
        ("Custom CSR interface (`CCSR_EN` 1)", "CSR core", (dict(CCSR_EN=1), {}), ({}, dict(CCSR_EN=0))),
        ("One-bubble branch (`SINGLE_CYCLE_BRANCH` 0)", "Instruction Fetch, Instruction Decode", (dict(SINGLE_CYCLE_BRANCH=0), {}), (dict(SINGLE_CYCLE_BRANCH=0), {})),
        ("Synchronous reset (`ASYNC_RST_EN` 0)", "every module (smaller flops)", (dict(ASYNC_RST_EN=0), {}), (dict(ASYNC_RST_EN=0), {})),
    ]
    print(f"Light base: {area(L,{})} gates   Full base: {area(F,{})} gates   ({len(by_vec)} result vectors)")
    print("| Feature step | + on Light | − from Full | Lands in |\n|---|---:|---:|---|")
    for label, lands, ls, fs in rows:
        lc = cost(L, *ls) if ls else None
        fc = cost(F, *fs) if fs else None
        print(f"| {label} | {fmt(lc)} | {fmt(fc)} | {lands} |")

if __name__ == '__main__' and '--features' in sys.argv:
    _features()
