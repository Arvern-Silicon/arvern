# Third-Party Software

aRVern's own source in this repository — the RTL, testbenches, simulation
scripts, and tooling — is licensed under the **BSD 3-Clause** license
(see [LICENSE](LICENSE)).

This repository additionally **vendors** the third-party component listed below.
It is **not** aRVern code, retains its own upstream license, and is included only
as a benchmarking aid under `sim/rtl_sim/`. It is not part of the core, the IP, or
any synthesizable deliverable, and it does **not** affect the license of aRVern's
own code — the two are merely aggregated in one source tree, not combined into a
single work.

## Embench IoT benchmark suite

- **Location:** `sim/rtl_sim/src-c/embench-iot/`
- **Upstream:** https://github.com/embench/embench-iot
- **License:** **GPL-3.0-or-later** — full text in
  `sim/rtl_sim/src-c/embench-iot/COPYING`. One documentation file is **GFDL-1.2**.
- **Copyright:** Embecosm Limited, the University of Bristol, Clemson University,
  and other contributors (see the per-file headers).
- **Bundled sub-components:** the suite itself embeds further third-party
  benchmark sources under their own licenses — e.g. the **SLRE** regular-expression
  library (© 2004–2013 Sergey Lyubka). Refer to the individual file headers under
  `embench-iot/` for the authoritative per-file license and copyright.

### Note for license scanners

Because Embench is GPL-3.0, an automated license scan of this repository will
report **both** `BSD-3-Clause` and `GPL-3.0-or-later`. That is expected and
intentional: the GPL applies only to the vendored `embench-iot/` directory.
Removing that directory leaves the repository entirely BSD-3-Clause.

---

# Fetched Dependencies

Unlike the vendored component above, the following is **not** part of this
repository. No source is committed here; a setup script clones it at a pinned
revision into a gitignored directory. Nothing about it affects the license of
aRVern's own code, and a fresh clone of this repository contains none of it.

## RISC-V Architectural Certification Tests (ACT)

- **Fetched to:** `sim/arch_test/run/riscv-arch-test/` (gitignored)
- **Fetched by:** `sim/arch_test/bin/fetch_suite.sh` (pinned SHA)
- **Upstream:** https://github.com/riscv/riscv-arch-test (branch `act4`)
- **License:** Apache-2.0, BSD and CC texts ship in the upstream tree
  (`COPYING.APACHE`, `COPYING.BSD`, `COPYING.CC`)
- **Copyright:** RISC-V International and contributors

ELF generation additionally runs inside the upstream container image
`ghcr.io/riscv/act4-build`, which is pulled on demand and likewise not
redistributed here. See [`sim/arch_test/README.md`](sim/arch_test/README.md)
for why generation is containerised.
