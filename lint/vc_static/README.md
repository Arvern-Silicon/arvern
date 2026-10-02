# VC Static Lint

Signoff-grade structural lint for the arvern RTL. Separate from and additional
to the Verilator lint in `sim/rtl_sim/run/run_lint`; neither replaces the other.

## Usage

Run from this directory, with `vc_static_shell` on PATH:

```bash
./run_vclint                      # default config: structural + netlist + quick-lint
./run_vclint -lang                # add the LANGUAGE_CHECK stage (slower, noisier)
./run_vclint -lang -j 1           # ...serially; -j > 1 deadlocks this checker intermittently
./run_vclint -rtl_config 11       # lint one sweep config (index or persona name)
./run_vclint -rtl_config light    # ...e.g. light / classic / performance / ultra, +-dbg
./run_vclint -rtl_sweep           # lint every sweep config; summary only
./run_vclint -top arv_decode      # lint a submodule instead of the whole core
./run_vclint -raw                 # ignore rules.tcl -- report every enabled rule
./run_vclint -no_params           # elaborate with arvern.v defaults, not run_config.json
./run_vclint -i                   # leave vc_static_shell open for interactive triage
./run_vclint -h                   # full option list
```

Reports land in `results/`; the run prints the summary and the file list when it
finishes. `-rtl_config` also snapshots to `results_sweep/<name>/`.

`-rtl_sweep` writes only `results_sweep/sweep_summary.log`, one line per config --
detailed reports are not kept. To investigate a row, re-run that config on its
own with `-rtl_config <idx>`.

Sweep config numbering matches `run_syn -rtl_config` and `run_all -rtl_sweep`:

```bash
python3 ../../synthesis/synopsys/gen_rtl_params.py --list-configs
```

Rule policy is in `rules.tcl` and waivers in `waivers.tcl`; both are commented
in place.

`CODING_PARAMETER_NOT_USED` is enabled against the tool default, but it belongs
to LANGUAGE_CHECK, so it reports only under `-lang` — a clean structural sweep
says nothing about dead parameters. Verilator's `UNUSEDPARAM` is the check that
runs on every config in seconds; this is the signoff-side backstop for a VC-only
audit.
