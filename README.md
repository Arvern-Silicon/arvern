<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)"
            srcset="doc/img/aRVern_dark_title.png">
    <img src="doc/img/aRVern_light_title.png" alt="aRVern" width="500">
  </picture>
</p>


<p align="center">
  Open-source, configurable <strong>RV32I[E]MBC</strong> RISC-V processor core
  for the <strong>aRVern</strong> ecosystem.
</p>

---

## What is aRVern?

**aRVern** is a single-issue, in-order, 4-stage (IF / ID / EX / WB) 32-bit RISC-V core in plain **Verilog-2001**, licensed **BSD-3-Clause**. It targets small-to-mid SoCs that want Cortex-M4-class throughput in a smaller footprint, and it connects to any AHB-Lite fabric directly: both its instruction and data ports are AHB-Lite masters.

Everything beyond the base pipeline is a parameter. Out of the box `arvern.v` is the **Classic** persona (RV32I, M, Zbb, Zca, Zicntr, M-mode only); every other configuration is a parameter override. Companion repositories: [`arvern-ips`](https://github.com/Arvern-Silicon/arvern-ips) (AHB-Lite IP: interconnect, ROM / SRAM controllers, ACLINT, PLIC, custom-CSR peripheral, debug transport modules) and [`arvern-soc`](https://github.com/Arvern-Silicon/arvern-soc) (reference SoC assembling the two).

## What it supports

- **ISA**: RV32I or RV32E base; Zicsr and Zifencei always; **M** or **Zmmul**; **B** as Zbb / +Zba / +Zbs / +Zbc; **C** as Zca / +Zcb / +Zcmp / +Zcmt.
- **Arithmetic options**: 1-, 4- or 16-cycle multiplier; 12-, 17- or 33-cycle divider; zero- or one-bubble taken branch (clock speed vs IPC).
- **Privilege**: M-mode always; optional **M + S + U** (S-mode is physical: trap delegation, no MMU).
- **Memory protection**: optional **PMP + Smepmp**, 0 / 4 / 8 / 16 entries, checked on instruction fetch and on load/store.
- **Traps and interrupts**: machine and supervisor interrupts with delegation, 16 platform interrupt lines, **Smrnmi** resumable NMI, **Smdbltrp** and **Ssdbltrp** double-trap handling with a critical-error output for a watchdog. Multi-cycle operations are aborted on interrupt entry, so interrupt latency is bounded. Timer and interrupt controllers (ACLINT, PLIC) are SoC IPs from `arvern-ips`, not part of the core.
- **Counters**: **Zicntr** (cycle / time / instret) and **Zihpm** (0–8 event counters), both optional.
- **External debug**: optional **RISC-V Debug 1.0** Debug Module (frozen hart, no program buffer): halt / resume / single-step, abstract register access, system bus access, **Sdtrig** with 0–8 triggers. JTAG, UART, I2C and cJTAG transport modules live in `arvern-ips`. JTAG: OpenOCD with any adapter it supports, a J-Link, or [`arvern-tools`](https://github.com/Arvern-Silicon/arvern-tools) (FT232H). cJTAG: a J-Link in its cJTAG mode — SEGGER Ozone (select cJTAG as the target interface when connecting) or the J-Link GDB Server. OpenOCD over cJTAG is not validated; `arvern-tools` cJTAG support is planned. UART and I2C: `arvern-tools`.
- **Buses**: two independent AHB-Lite masters; the access privilege is exported on the bus so a fabric can enforce protection without PMP.
- **Vendor extensibility**: optional custom-CSR interface for SoC-side CSRs, no core modification needed.
- **Power**: clock-enable output for SoC-level clock gating during `WFI` sleep.
- **Identity**: registered `mvendorid` / `marchid` / `mimpid`, plus a `marv_cfg` CSR that reports the build configuration to firmware.
- **Reset**: asynchronous or synchronous reset selected by one parameter.
- **Portability**: no SystemVerilog in the RTL; regressed on Icarus Verilog and Verilator, and the run scripts also support Questa, NC-Verilog and VCS; FuseSoC core file (`arvern.core`) at the repository root.

## Maturity

- **Directed regression**: about 425 directed assembly tests plus 29 C programs (hello_world, CoreMark, Dhrystone, Embench-IoT), each run across up to 36 timing variants (random wait states on ROM / SRAM / peripherals, random ALU stalls, three interconnect variants, random interrupt injection); the whole suite also runs on 58 RTL configurations.
- **Conformance**: passes the official [RISC-V Architectural Certification Tests](https://github.com/riscv/riscv-arch-test) (ACT4) on all four personas — 620 tests, no waivers (light 69, classic 109, performance 220, ultra 222). Result and what the suite does not reach: [`doc/spec_compliance_notes.md`](doc/spec_compliance_notes.md#architectural-certification-result-riscv-arch-test).
- **Code coverage**: 100 % line, branch and toggle coverage (Verilator) over three coverage configurations; every exclusion is argued in [`sim/rtl_sim/run/waivers_cov.md`](sim/rtl_sim/run/waivers_cov.md).
- **Lint**: Verilator lint and VC Static signoff lint (`lint/vc_static/`), clean on all 58 configurations.
- **Synthesis**: clean on all four personas through the bundled Design Compiler flow.

## Release notes

Latest release: **1.0.0**. 

What changed in each release, and how to upgrade: [`CHANGELOG.md`](CHANGELOG.md).

## Cost by persona

Four reference **personas** span the parameter range. Common to all: single-cycle taken branch (`SINGLE_CYCLE_BRANCH=1`), xPack `riscv-none-elf-gcc` with newlib, zero-wait-state ROM and SRAM, `-O2` (the canonical Embench / CoreMark / Dhrystone reporting level). Area: same library and constraints for every persona, scan inserted. Full parameter vectors in [`doc/benchmarking_guide.md` §1.2](doc/benchmarking_guide.md#12-arvern-personas); `-Os / -O2 / -O3` sensitivity in [§2.2](doc/benchmarking_guide.md#22-optimization-sensitivity-4-personas--3--o-levels).

| Persona | **Light** | **Classic** | **Performance** | **Ultra** |
|---|---:|---:|---:|---:|
| **Configuration** | <i>RV32E<br/>no debug<br/>Zmmul(16c)<br/>M-only<br/>no PMP<br/>Zca<br/><br/><br/></i> | <i>RV32I<br/>no debug<br/>1c MUL + 33c DIV<br/>M-only<br/>no PMP<br/>Zca<br/>Zbb<br/>Zicntr<br/></i> | <i>RV32I<br/>no debug<br/>1c MUL + 12c DIV<br/>M+S+U<br/>PMP ×4<br/>Zca + Zcb<br/>full B<br/>Zicntr<br/></i> | <i>RV32I<br/>no debug<br/>1c MUL + 12c DIV<br/>M+S+U<br/>PMP ×8<br/>full C<br/>full B<br/>Zicntr + Zihpm×4</i> |
| CoreMark<br/> CoreMark / MHz ↑ (`-O2`) | 2.10 | 3.08 | 3.57 | 3.54 |
| Dhrystone<br/>DMIPS / MHz ↑ (`-O2`) | 1.63 | 1.81 | 1.95 | 1.95 |
| Embench-IoT<br/>Geomean speed ↑ (`-O2`) | 0.72 | 1.25 | 1.32 | 1.32 |
| Area<br/>NAND2-equiv. kgates ↓ | _32_ | _52_ | _69_ | _82_ |

> **Any other configuration** is equally supported; what each option costs, measured one
> feature at a time on the smallest and on the fullest build, is in
> [`doc/synthesis_guide.md` §2.4](doc/synthesis_guide.md#24-feature-cost). External debug
> (`DEBUG_EN=1`, off in every persona above) is **~4.3 kGates** plus **~1.0 kGates** per
> Sdtrig trigger ([§2.3](doc/synthesis_guide.md#23-debug-subsystem-area-cost)).

Per-benchmark scores and methodology: [`doc/benchmarking_guide.md`](doc/benchmarking_guide.md). Per-module area: [`doc/synthesis_guide.md` §2](doc/synthesis_guide.md#2-area-results).

## Try it in ten minutes

The testbench uses ROM, SRAM, interconnect and peripheral IP from `arvern-ips`, checked out **next to** this repository (`../arvern-ips`). Prerequisites are Icarus Verilog, the xPack RISC-V GCC and Python 3 ([`doc/simulation_guide.md` §1](doc/simulation_guide.md#1-prerequisites)).

```bash
git clone https://github.com/Arvern-Silicon/arvern.git
git clone https://github.com/Arvern-Silicon/arvern-ips.git
cd arvern/sim/rtl_sim/run
./run hello_world
```

The run takes seconds and ends in `SIMULATION PASSED` when the install is good. Set `VERILOG_SIMULATOR=verilator|vsim|ncverilog|vcs` to use another simulator; `./run_all -fast` runs the whole directed suite, `./run_benchmark dhrystone_4mcu` a benchmark, `./run_lint` the lint.

## Where to go next

The RISC-V specification PDFs the documents cite are under [`doc/specs/`](doc/specs/).

| Reader | Documents |
|---|---|
| **SoC integrator** — wiring the core into a chip or FPGA | [`doc/integration_guide.md`](doc/integration_guide.md) — parameters, ports, reset architecture, IRQ / NMI / CCSR / debug wiring · [`doc/memory_and_ahb.md`](doc/memory_and_ahb.md) — the AHB-Lite contract: transfer types, byte lanes, error responses, privilege encoding · [`doc/synthesis_guide.md`](doc/synthesis_guide.md) — the Design Compiler flow, constraints, DFT, per-persona and per-module area |
| **Firmware developer** — bare-metal or RTOS code on the core | [`doc/software_guide.md`](doc/software_guide.md) — ABI, boot flow, linker layout, CSR idioms, trap-handler skeleton · [`doc/traps_and_interrupts.md`](doc/traps_and_interrupts.md) — exception causes, interrupt priority, delegation, NMI, double traps, WFI · [`doc/spec_compliance_notes.md`](doc/spec_compliance_notes.md) — the conformance result and every implementation-defined choice; read before shipping · [`doc/debug_interface.md`](doc/debug_interface.md) — hart-side debug CSRs and `ebreak` behaviour |
| **Debug-tool / DTM author** — OpenOCD, probe or transport bring-up | [`doc/debug_interface.md`](doc/debug_interface.md) — DMI protocol, Debug Module register map, abstract commands, system bus access, Sdtrig |
| **Verification contributor** — writing or running tests | [`doc/simulation_guide.md`](doc/simulation_guide.md) — prerequisites, the `run` scripts, waveforms, debug tooling · [`doc/verification_guide.md`](doc/verification_guide.md) — test conventions, the x31 sync mechanism, the test registry, regression policy · [`doc/asphalt_trace_format.md`](doc/asphalt_trace_format.md) — the per-instruction trace format · [`doc/benchmarking_guide.md`](doc/benchmarking_guide.md) — what the benchmarks measure and how to compare fairly · [`sim/arch_test/README.md`](sim/arch_test/README.md) — the riscv-arch-test flow |
| **Core designer / reviewer** — modifying or auditing the RTL | [`doc/microarchitecture.md`](doc/microarchitecture.md) — block diagram, pipeline, decoder, CSR topology, critical paths · [`doc/arvern_instructions.md`](doc/arvern_instructions.md) — instruction inventory and full CSR map · [`doc/spec_compliance_notes.md`](doc/spec_compliance_notes.md) — why each deviation is legal and the audit hook that guards it |

## License

BSD 3-Clause — see [`LICENSE`](LICENSE).

---

<p align="center">
  <a href="https://github.com/Arvern-Silicon">github.com/Arvern-Silicon</a>
  &nbsp;·&nbsp;
  <a href="mailto:arvernsilicon@gmail.com">arvernsilicon@gmail.com</a>
</p>
