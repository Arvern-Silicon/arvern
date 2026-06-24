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

**aRVern** is a classic single-issue, in-order, 4-stage (IF / ID / EX / WB) 32-bit RISC-V processor core written in plain **Verilog-2001**, designed to be embeddable in small-to-mid SoCs without vendor IP lock-in.

It implements RV32I or RV32E, optional M/B/C extensions (all sub-extensions including Zcmp, Zcmt, Zbc), Smrnmi resumable NMI, full S-mode (physical) with trap delegation, U-mode, Zicntr / Zihpm counters, and a SoC-side clock-gating hook via WFI.

Both buses (instruction + data) are AHB-Lite, so **aRVern** drops into any AHB-Lite fabric without extra bridges.

## Key features

- **ISA**: RV32I (or RV32E) base, **Zicsr** + **Zifencei** always present, optional **M** or **Zmmul**, optional **B** (Zbb / Zba / Zbs / Zbc), optional **C** (Zca / Zcb / Zcmp / Zcmt).
- **Privilege**: M-mode always present; **S + U modes optional** via `SU_MODE_EN` (1=M+S+U, 0=M-only with S-CSRs RAZ/WI and `sret`/`sfence.vma` illegal). When enabled, S-mode is physical (full trap delegation, no MMU — `satp` is a WARL stub).
- **Trap / IRQ**: synchronous exceptions, machine + supervisor IRQs (delegable via `mideleg`), platform IRQs (`MIP[31:16]`), **Smrnmi** resumable NMI (gated by `NMI_EN`). Multi-cycle MUL/DIV/UOP ops are **killable mid-flight** on IRQ entry (`irqkill_cfg` CSR) for bounded interrupt latency. `lockup_o` exits on unrecoverable trap loops for watchdog hookup.
- **Counters**: **Zicntr** (cycle / time / instret) and **Zihpm** (0–8 `mhpmcounter3–10` + event selectors) — both optional.
- **Buses**: two independent **AHB-Lite masters** (separate instruction + data), HSMODE/HPROT privilege encoding for fabric-level routing. Pair with [`arvern-ips/ahb_interconnect`](https://github.com/Arvern-Silicon/arvern-ips/tree/main/ahb_interconnect/doc/ahb_interconnect.md) — **fused** (recommended) / hiperf / generic fabric variants.
- **Vendor extensibility**: optional **Custom CSR interface** (`CCSR_EN`) — drop-in SoC-side CSR space with single-cycle combinational reads, no core modification needed. Reference IP at [`arvern-ips/arv_custom_csr`](https://github.com/Arvern-Silicon/arvern-ips/tree/main/arv_custom_csr/doc/arv_custom_csr.md).
- **Power**: SoC-level clock gating via `hclk_en_o` — drops during `WFI` sleep when both AHB masters are drained.
- **Configurable PPA**: 1- / 4- / 16-cycle multiplier, radix-2 / 4 / 8 divider, zero- / one-bubble branch (Fmax vs IPC).
- **Coding style**: pure **Verilog-2001** — works with Icarus Verilog, Verilator (lint), Modelsim/Questa, NC-Verilog, VCS — no SystemVerilog constructs in the RTL.

See [`doc/arvern_instructions.md`](doc/arvern_instructions.md) for the full ISA / CSR inventory and [`doc/integration_guide.md`](doc/integration_guide.md) for the parameter reference.

## Where aRVern fits

Open-source RV32 cores tend to cluster at the M-mode-only end (PicoRV32, Ibex, CV32E40P) or the integrated-SoC end (NEORV32). aRVern targets the middle: **Cortex-M4-class performance** (see below) with the **full M+S+U privilege stack** (physical S-mode, full trap delegation), full **C** including Zcmp/Zcmt, and **Smrnmi** resumable NMI — but **without a paged MMU** (`satp` is a WARL stub) so area stays at MCU scale. **Pure Verilog-2001 under BSD-3-Clause**: no SystemVerilog simulator dependency, no license friction in commercial SoCs.

## Performance and area at a glance

Four reference **personas** spanning the parameter range — each persona is an archetypal integrator configuration representing a typical aRVern customer with characteristic priorities. Common to all: single-cycle taken branch (`SINGLE_CYCLE_BRANCH=1`), xPack `riscv-none-elf-gcc` 14.2 (with newlib), zero-wait-state ROM and SRAM, generic standard-cell library.

Headline speed numbers below at **`-O2`** (canonical Embench / CoreMark / Dhrystone reporting level). For `-Os / -O2 / -O3` sensitivity across all personas, see [`doc/characterization_guide.md` §3.2](doc/characterization_guide.md#32-optimization-sensitivity-4-personas--3--o-levels). Full parameter vectors in [`doc/characterization_guide.md` §1.2](doc/characterization_guide.md#12-arvern-personas).

| Persona | **Light** | **Classic** | **Performance** | **Ultra** |
|---|---:|---:|---:|---:|
| **Configuration** | <i>RV32E<br/>Zmmul(16c)<br/>M-only<br/>Zca<br/><br/><br/><br/></i> | <i>RV32I<br/>Zmmul(1c)<br/>M+S+U<br/>Zca<br/>Zbb<br/>Zicntr<br/><br/></i> | <i>RV32IM<br/>1c MUL + 12c DIV<br/>M+S+U<br/>Zca + Zcb<br/>full B<br/>Zicntr<br/><br/></i> | <i>RV32IMC<br/>1c MUL + 12c DIV<br/>M+S+U<br/>full C<br/>full B<br/>Zicntr + Zihpm×4<br/>Smrnmi NMI</i> |
| CoreMark<br/> CoreMark / MHz ↑ (`-O2`) | 2.10 | 3.14 | 3.57 | 3.54 |
| Dhrystone<br/>DMIPS / MHz ↑ (`-O2`) | 1.63 | 1.75 | 1.95 | 1.95 |
| Embench-IoT<br/>Geomean speed ↑ (`-O2`) | 0.72 | 0.97 | 1.32 | 1.32 |
| Area<br/>NAND2-equiv. kgates ↓ | _30_ | _49_ | _59_ | _67_ |

Full PPA detail (per-benchmark scores, optimization-level sensitivity, single-cycle branch knob sensitivity on the Performance persona, per-module area breakdown, Embench methodology) lives in [`doc/characterization_guide.md` §2 onward](doc/characterization_guide.md#2-area-results).

## Quick start

```bash
# 1. Install prerequisites (iverilog + xPack RISC-V GCC + Python 3.10+).
#    See doc/simulation_guide.md §1.

# 2. Run a single test (defaults to Icarus Verilog)
cd sim/rtl_sim/run
./run inst_std_add

# 3. Run a benchmark (mode auto-picked from the active RTL config)
./run_benchmark dhrystone_4mcu

# 4. Lint
./run_lint
```

If `./run inst_std_add` ends in `SIMULATION PASSED`, your install is good.

## Documentation

### For SoC integrators

| Document | Covers |
|---|---|
| [`doc/integration_guide.md`](doc/integration_guide.md) | All parameters, ports, AHB / IRQ / NMI / CCSR / Zicntr interfaces, reset architecture |
| [`doc/spec_compliance_notes.md`](doc/spec_compliance_notes.md) | How aRVern handles unspecified / implementation-defined cases, plus a few conscious gray-area choices — read before shipping |
| [`doc/memory_and_ahb.md`](doc/memory_and_ahb.md) | AHB-Lite contract: transfer types used, byte lanes, error responses, HSMODE/HPROT encoding, wait-state behaviour, the `SINGLE_CYCLE_BRANCH` address-phase implications |

### For firmware / software authors

| Document | Covers |
|---|---|
| [`doc/software_guide.md`](doc/software_guide.md) | ABI, boot flow, linker layout, startup code, CSR access idioms, trap-handler skeleton, WFI usage, counter access, RV32E notes |
| [`doc/traps_and_interrupts.md`](doc/traps_and_interrupts.md) | Synchronous-exception causes, MIP/MIE layout, IRQ priority, `mideleg`/`medeleg` delegation, Smrnmi flow, WFI sleep/wake, the `irqkill_cfg` mechanism, lockup escape |
| [`doc/arvern_instructions.md`](doc/arvern_instructions.md) | Supported instructions per extension, full CSR map (~55 CSRs), privilege modes, instruction-format legend |

### For RTL / verification contributors

| Document | Covers |
|---|---|
| [`doc/microarchitecture.md`](doc/microarchitecture.md) | Top-level block diagram, pipeline stages, unified compressed decoder, register file + JALR shadow latch, CSR subsystem topology, UOP sequencer, critical paths, parameter effects |
| [`doc/verification_guide.md`](doc/verification_guide.md) | Test taxonomy, the `.s` + `.v` pair convention, x31 sync mechanism, `run_config.json` test registry, regression policy, worked example of adding a new test |
| [`doc/simulation_guide.md`](doc/simulation_guide.md) | Install prerequisites (incl. Python tier breakdown), the `./run` / `./run_all` / `./run_lint` / `./run_benchmark` scripts, waveforms, debug tooling |
| [`doc/synthesis_guide.md`](doc/synthesis_guide.md) | The bundled Design Compiler flow, `LIB_FLAVOR` mechanism, constraints, DFT insertion, RTL-config sweep, closing timing on the two Fmax-binding parameters |

### For performance analysts / tool authors

| Document | Covers |
|---|---|
| [`doc/characterization_guide.md`](doc/characterization_guide.md) | Synthesized area per persona and per module, plus what CoreMark / Dhrystone / Embench-IoT measure on aRVern, score sensitivity to RTL config and compiler `-O`, snapshot comparison, fair-comparison practices |
| [`doc/asphalt_trace_format.md`](doc/asphalt_trace_format.md) | Canonical column-by-column spec for `asphalt.log` (per-instruction dispatched-instruction trace), trailing-annotation catalogue, compressed-snapshot file layout |

### Spec PDFs

Under [`doc/specs/`](doc/specs/): `riscv-unprivileged.pdf`, `riscv-privileged.pdf`, `riscv-asm.pdf`, `riscv-plic.pdf`, `riscv_aclic.pdf`.

## Repository layout

```
arvern/
├── rtl/verilog/                RTL sources (single source of truth)
│   ├── arvern.v                Top-level integration
│   ├── arv_fetch.v             Instruction fetch
│   ├── arv_decode.v            Decoder (unified RV32I + compressed)
│   ├── arv_int_registers.v     Integer register file (RV32I/RV32E)
│   ├── arv_alu.v               ALU (+ B-extension ops)
│   ├── arv_alu_muldiv.v        Multiplier / divider
│   ├── arv_load_store.v        LSU + data-bus interface
│   ├── arv_csr_top.v           CSR address decode + read mux
│   ├── arv_csr_traps.v         Trap FSM + mstatus/mie/mip + S-mode shadows
│   ├── arv_csr_cntr.v          Zicntr counters
│   ├── arv_csr_hpm.v           Zihpm counters (0–8)
│   ├── arv_csr_ids.v           mvendorid / marchid / mimpid / mhartid / misa
│   └── arv_uop_sequencer.v     Zcmp / Zcmt micro-op sequencer
├── bench/verilog/              Testbench infrastructure (tb_arvern.v, probes,
│                                AHB-bus model, ROM/SRAM, protocol checker)
├── sim/rtl_sim/                Simulation flow (see doc/simulation_guide.md)
├── synthesis/synopsys/         Design Compiler flow (technology-flavored)
└── doc/                        Documentation + spec PDFs
```

## Related repositories

`arvern` is the CPU core of the **aRVern** open-source RISC-V ecosystem.

Companion repositories:

- **[arvern-ips](https://github.com/arvern-dev/arvern-ips)** — AHB-Lite
  IP library: interconnect (3 variants), ROM / SRAM controllers, custom-CSR peripheral, peripheral template.

- **[arvern-soc](https://github.com/arvern-dev/arvern-soc)** — Reference
  SoC integration assembling `arvern` + `arvern-ips`.



## License

BSD 3-Clause — see [`LICENSE`](LICENSE).

---

<p align="center">
  <a href="https://github.com/arvern-dev">github.com/arvern-dev</a>
  &nbsp;·&nbsp;
  <a href="mailto:arvernsilicon@gmail.com">arvernsilicon@gmail.com</a>
</p>
