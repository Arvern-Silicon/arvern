# Changelog

All notable changes to the aRVern core are listed here. Versions follow
[Semantic Versioning](https://semver.org/); `RTL_VERSION` in `rtl/verilog/arvern.v` (read back
through `mimpid`) carries the same number.

## Versions

| Version | Date |
|---|---|
| [1.0.0](#v1.0.0) | Oct 2, 2026 |
| [0.1.0-preview](#v0.1.0-preview) | Jun 24, 2026 |

<a id="v1.0.0"></a>

## 1.0.0

First stable release. Adds external debug, memory protection and double-trap handling to the
0.1.0-preview core, and closes verification: riscv-arch-test on every reference persona, 100 %
structural code coverage, and signoff lint on 58 configurations.

### Added

- **External debug (RISC-V Debug 1.0)**, `DEBUG_EN`: frozen-hart Debug Module with halt / resume /
  single-step, abstract register access, system bus access (hart halted or running), reset-halt,
  and **Sdtrig** with 0–8 triggers (`DM_TRIGGER_NR`). New ports: an APB4 DMI slave (`dmi_*`)
  with its own reset (`dbgresetn_i`), `dbg_ndmreset_o`, `dbg_halted_o`, `dbg_debug_mode_o`,
  `dbg_stoptime_o`, and `data_hmaster_o`, which tags debugger accesses on the data bus. The
  JTAG, cJTAG, UART and I2C transports are in `arvern-ips` (`arv_dtm`). See
  [`doc/debug_interface.md`](doc/debug_interface.md).
- **Physical memory protection**, `PMP_NR` = 0 / 4 / 8 / 16 entries, with **Smepmp**. Checked on
  instruction fetch (including Zcmt table reads) and on load/store.
- **Smdbltrp** (always) and **Ssdbltrp** (with `SU_MODE_EN=1`): an unexpected trap in M-mode
  diverts to the RNMI handler or enters the critical-error state reported on `lockup_o`.
- **Data-bus errors** are reported as a resumable NMI (`mncause` = 0x80000003) with evidence
  registers `marv_epc`, `marv_eaddr` and `marv_estat`, including the restartability of an
  interrupted Zcmp sequence.
- **Configuration and control CSRs**: `marv_cfg` reports the build configuration to firmware;
  `marv_ctl` (0x7FF) holds the interrupt-kill and WFI clock-gating policy; `marv_nmvec` holds
  the NMI vector. `mimpid` reports `RTL_VERSION`.
- **Verification**:
  - riscv-arch-test (ACT4) flow under [`sim/arch_test/`](sim/arch_test/README.md);
  - Verilator line / branch / toggle coverage flow (`run_cov`), at 100 % with every exclusion
    argued in `sim/rtl_sim/run/waivers_cov.md`;
  - VC Static signoff lint (`lint/vc_static/`);
  - a 58-configuration RTL sweep for the regression and both lint flows;
  - about 425 directed tests.
- FuseSoC core file `arvern.core`.

### Changed

- **Smrnmi is always present.** The NMI vector comes from `marv_nmvec`. At reset the vectors form
  a jump table after the reset entry: `marv_nmvec` = `reset_vector + 4`, `mtvec` = `+ 8`,
  `stvec` = `+ 12`.
- **`SU_MODE_EN=0` removes S-mode completely.** The S-mode CSRs, `mideleg`, `medeleg`,
  `mcounteren` and `menvcfg[h]` are absent and raise illegal-instruction (they were RAZ/WI), and
  `sret` is illegal.
- **`lockup_o`** now reports the Smdbltrp critical-error state, which only a reset clears.
- **The default configuration** of `arvern.v` is the Classic persona: RV32I, M (1-cycle multiplier,
  33-cycle divider), Zbb, Zca, Zicntr, M-mode only. The persona definitions were revised and their
  benchmark scores and area re-measured; see the README and
  [`doc/benchmarking_guide.md`](doc/benchmarking_guide.md).
- **The run scripts' exit status** now reflects the simulation verdict (`sim_result.txt`), so
  scripts and multi-test runs see real failures.

### Removed

- The `nmi_vector_i` port (replaced by `marv_nmvec`).
- The `NMI_EN` parameter (Smrnmi is always present).
- The `MVENDORID` parameter: the core reports its own `mvendorid`.
- The `irqkill_cfg` CSR (replaced by `marv_ctl`).
- `doc/characterization_guide.md`, superseded by `doc/benchmarking_guide.md` and
  `doc/synthesis_guide.md`.

### Fixed

- Many corner cases in the interaction of traps, interrupts, debug entry, PMP and Zcmp / Zcmt
  sequences, found by design reviews and coverage-driven verification. Every fix comes with a
  directed test.

### Upgrading from 0.1.0-preview

1. Remove `nmi_vector_i`, `NMI_EN` and `MVENDORID` from the instantiation. Program the NMI
   vector through `marv_nmvec`, or rely on its reset value.
2. Tie the new debug ports inactive when `DEBUG_EN=0`, or connect an `arv_dtm`.
3. If you relied on the old defaults, set `M_EXTENSION` and `SU_MODE_EN` explicitly.
4. Firmware: run the Smdbltrp boot sequence (`csrsi 0x744, 8`, then `csrw mstatush, x0`),
   replace `irqkill_cfg` accesses with `marv_ctl`, and handle data-bus errors in the RNMI
   handler ([`doc/software_guide.md`](doc/software_guide.md)).

<a id="v0.1.0-preview"></a>

## 0.1.0-preview

Initial hardware baseline preview: the open-source repository baseline, build tooling and a
basic architectural verification setup. A pre-release for early architectural evaluation and
integration testing; features, internal interfaces and register structures were subject to
change before the first stable release.
