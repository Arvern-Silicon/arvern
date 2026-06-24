<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Software Developer Guide
  <br clear="all">
</h1>

This guide is for firmware authors, OS bring-up engineers, and anyone writing
bare-metal code targeting the aRVern core. It covers boot, ABI, the linker
layout used by the tests, CSR-access conventions, and the firmware-side
caveats called out in [`spec_compliance_notes.md`](spec_compliance_notes.md).

For the full ISA / CSR reference, see
[`arvern_instructions.md`](arvern_instructions.md).
For traps and IRQs in depth, see
[`traps_and_interrupts.md`](traps_and_interrupts.md).

---

## Table of Contents

1. [Toolchain and ABI](#1-toolchain-and-abi)
2. [Boot Flow](#2-boot-flow)
3. [Memory Map (Test SoC)](#3-memory-map-test-soc)
4. [Linker Script](#4-linker-script)
5. [Minimal Startup](#5-minimal-startup)
6. [CSR Access — Idioms and Caveats](#6-csr-access--idioms-and-caveats)
7. [Trap Handler Skeleton](#7-trap-handler-skeleton)
8. [WFI Usage](#8-wfi-usage)
9. [Counters (Zicntr / Zihpm)](#9-counters-zicntr--zihpm)
10. [RV32E Programming Notes](#10-rv32e-programming-notes)

---

## 1. Toolchain and ABI

### Default toolchain

| Item | Value |
|---|---|
| Triple | `riscv-none-elf` (xPack distribution) |
| Default optimisation | `-O3` |
| Default `-march` (std mode, full B/C, default RTL config) | `rv32imc_zbb_zba_zbs_zbc_zcb_zcmp_zcmt_zicsr_zifencei` |
| Default `-mabi` | `ilp32` (or `ilp32e` when `RV32E_EN == 1`) |

The actual `-march` and `-mabi` strings are auto-generated from
`run_config.json` into `sim/rtl_sim/run/march_config.sh` on every test build.
You can `source` it from your own Makefile to inherit the same flags:

```bash
source sim/rtl_sim/run/march_config.sh
echo $MARCH_STD $MABI    # rv32im_zbb_... ilp32
```

### Alternative toolchains

| Profile | Prefix | Status |
|---|---|---|
| `xpacks` (default) | `riscv-none-elf-` | Tested daily |
| `gcc` | `riscv64-unknown-elf-` | Supported (build-from-source / `riscv-gnu-toolchain` install) |
| `clang` | `riscv32-unknown-elf-` (LLVM with GCC newlib sysroot) | Supported |

Switch by editing the `"toolchain.active"` key in `run_config.json`. See
[`simulation_guide.md` §1.5](simulation_guide.md#15-alternative-toolchains).

### ABI

aRVern uses the **standard RISC-V ELF psABI** (RV32 ilp32 / ilp32e). No
arvern-specific calling-convention deviations.

| Register | ABI name | Role | Saved by |
|---|---|---|---|
| x0 | zero | Hardwired zero | — |
| x1 | ra | Return address | Caller |
| x2 | sp | Stack pointer | Callee |
| x3 | gp | Global pointer | — |
| x4 | tp | Thread pointer | — |
| x5–x7 | t0–t2 | Temporaries | Caller |
| x8 | s0 / fp | Saved / frame pointer | Callee |
| x9 | s1 | Saved | Callee |
| x10–x11 | a0–a1 | Arg / return value | Caller |
| x12–x15 | a2–a5 | Arguments | Caller |
| x16–x17 | a6–a7 | Arguments (RV32I only) | Caller |
| x18–x27 | s2–s11 | Saved (RV32I only) | Callee |
| x28–x31 | t3–t6 | Temporaries (RV32I only) | Caller |

> In **RV32E mode** (`RV32E_EN == 1`) x16–x31 are absent. Use the `ilp32e` ABI
> and the `rv32e[m][c]…` `-march` string. The xPack toolchain handles this
> transparently when given `-march=rv32e* -mabi=ilp32e`.

---

## 2. Boot Flow

On reset:

1. `hresetn_i` asserts → all flops reset.
2. The PC is loaded from `reset_vector_i[31:0]` (sampled at reset deassertion).
3. The fetch unit issues the first instruction fetch on the instruction AHB
   bus at `reset_vector_i`. Privilege is `M-mode` (`2'b11`).
4. The decode pipeline starts dispatching once `inst_hready_i` returns valid
   data.

**There is no internal boot ROM** — aRVern only provides the program counter.
The boot ROM (if any) is part of the SoC and must respond on the instruction
AHB bus at `reset_vector_i`.

### Test-SoC reset vector

The bundled testbench (`bench/verilog/tb_arvern.v`) ties `reset_vector_i =
32'h2000_0000`. That's the start of the test boot ROM in the test SoC's
memory map (§3).

---

## 3. Memory Map (testbench SoC)

The testbench SoC (used by `./run`, `./run_all`, `./run_benchmark`) has this map:

| Region | Range | Backed by | Notes |
|---|---|---|---|
| Boot ROM / .text | `0x2000_0000`–`0x2000_FFFF` | 64 KiB ROM | Default code-load address; mirrored from `pmem.ihex` at sim start |
| Data / .bss / stack | `0x8000_0000`–`0x8001_FFFF` | 128 KiB SRAM (X + non-X regions) | `link.ld` puts `.data`/`.bss` here |
| Peripherals (`ahb_periph_example`) | SoC-defined | AHB-Lite peripheral | Used by some traps tests |

The testbench SoC's memory map is **not** the aRVern core's contract — aRVern is a
processor, not an SoC. An integrator can place the ROM and RAM wherever the
SoC fabric routes them, as long as `reset_vector_i` points at executable
memory and `sp` is set to a writable region before any C code runs.

---

## 4. Linker Script

The simple linker script bundled at `sim/rtl_sim/bin/link.ld`:

```
SECTIONS
{
  . = 0x20000000;           /* code load address (ROM) */
  .text : { *(.text*) }
  . = 0x80000000;           /* data load address (RAM) */
  .data : { *(.data*) }
  .bss  : { *(.bss*)  }
}
```

For a real SoC, replace these addresses with whatever the fabric routes to
your boot ROM and RAM. A more complete script would also:

- Emit a `.rodata` section,
- Provide `__bss_start` / `__bss_end` symbols for crt0 to clear,
- Provide `__data_start_lma` / `__data_start_vma` for an initialised-data copy
  step (necessary if RAM is uninitialised at reset and `.data` has non-zero
  initial values).

The bundled test C programs sidestep this by either (a) clearing `.bss`
themselves in their startup, or (b) avoiding initialised globals.

---

## 5. Minimal Startup

Bare-minimum startup used by the sample C tests (`sim/rtl_sim/src-c/hello_world/startup.S`):

```asm
.section .init
.globl _start
_start:
    la sp, stack_top      # stack pointer
    call main             # call C main
    j .                   # hang on return

.section .bss
.space 4096               # 4 KiB stack
.globl stack_top
stack_top:
```

For anything more realistic, you'll want:

```asm
.section .init
.globl _start
_start:
    # 1. Stack pointer
    la sp, _stack_top

    # 2. Global pointer (so linker .sdata relaxation works)
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    # 3. Clear .bss
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:

    # 4. (Optional) copy .data from LMA to VMA
    # ...

    # 5. Install trap vector
    la   t0, _trap_handler
    csrw mtvec, t0

    # 6. Enable interrupts (if the OS wants them on at start)
    # csrsi mstatus, 0x8       # MIE = 1
    # li    t0, (1<<11)|(1<<7) # MEIE | MTIE
    # csrw  mie, t0

    call main
    j .
```

Replace `_stack_top`, `__bss_start`, `__bss_end`, `__global_pointer$` with
symbols your linker script defines.

---

## 6. CSR Access — Idioms and Caveats

### Standard idioms

```asm
csrr  rd, csr          # Read CSR
csrw  csr, rs          # Write CSR (rs1)
csrs  csr, rs          # Set bits   (read, |mask, write)
csrc  csr, rs          # Clear bits (read, &~mask, write)
csrwi csr, imm         # Write immediate (imm5)
csrsi csr, imm         # Set bits immediate
csrci csr, imm         # Clear bits immediate
```

All are pseudo-instructions for `CSRRW`/`CSRRS`/`CSRRC` with `rd = zero` (read
suppressed when allowed).

### CSR-access trap rules

| Trap | Trigger |
|---|---|
| Illegal-instruction (cause 2) | Access to an unknown CSR address bank, write to a read-only CSR, U-mode access to an M-mode CSR, etc. |
| RAZ/WI silently | Access to an *unimplemented* CSR address **within a known bank** — see the [bank-level decode deviation](spec_compliance_notes.md#non-existent-csrs-in-known-banks-read-as-0-razwi-do-not-trap). |

Practical impact: don't rely on illegal-instruction trapping to detect a
mistyped CSR address inside e.g. the 0x300 bank — you'll get a silent RAZ/WI
instead. The decode-bank set is documented in `arv_csr_top.v:any_bank_known`.

---

## 7. Trap Handler Skeleton

Vectored mode (`mtvec[0] = 1`) puts IRQs at `mtvec_base + 4 × cause`. Direct
mode (`mtvec[0] = 0`) sends all traps to a single entry. A simple direct-mode
handler:

```asm
.balign 4
.globl _trap_handler
_trap_handler:
    # Save caller-saved + arg registers
    addi sp, sp, -64
    sw   ra,  60(sp)
    sw   t0,  56(sp)
    sw   t1,  52(sp)
    sw   t2,  48(sp)
    sw   a0,  44(sp)
    sw   a1,  40(sp)
    sw   a2,  36(sp)
    sw   a3,  32(sp)
    sw   a4,  28(sp)
    sw   a5,  24(sp)
    sw   a6,  20(sp)
    sw   a7,  16(sp)
    sw   t3,  12(sp)
    sw   t4,   8(sp)
    sw   t5,   4(sp)
    sw   t6,   0(sp)

    # Dispatch by cause
    csrr a0, mcause            # a0 = mcause
    csrr a1, mepc              # a1 = faulting / next PC
    csrr a2, mtval             # a2 = bad addr / instr
    call c_trap_handler        # C dispatch

    # Restore
    lw   ra,  60(sp)
    lw   t0,  56(sp)
    # ... (rest)
    addi sp, sp, 64

    mret
```

A practical handler will pick up the IRQ/exception split (`mcause[31]`), then
fan out by `mcause[4:0]`. For the cause list, see
[`traps_and_interrupts.md`](traps_and_interrupts.md#2-synchronous-exceptions).

**Smrnmi handler:** use the same structure but end with `MNRET` instead of
`MRET`, and install it at `nmi_vector_i` (an integration constant — there's
no `nmi_vector` CSR by default; the SoC ties this signal). See
[`integration_guide.md` §6](integration_guide.md#6-nmi-interface-smrnmi).

---

## 8. WFI Usage

```asm
# Park CPU until any enabled IRQ or NMI fires
wfi
```

WFI behaves as a clean pipeline drain + stall — it is **not** a trap (`mcause`
is not updated). On wake:

- `mepc` (if an IRQ takes the trap) is set to `WFI_PC + 4`, so `MRET` resumes
  past the WFI.
- `hclk_en_o` is deasserted while sleeping → the SoC's clock gate freezes the
  core. `mcycle` does **not** advance during sleep.

**Disabled-IRQ WFI**: if no enabled IRQ source can fire, WFI hangs forever
(no spec violation — that's the documented behaviour). Make sure `mie` and
the relevant external sources are configured before entering WFI.

---

## 9. Counters (Zicntr / Zihpm)

Available when `ZICNTR_EN == 1` (cycle / time / instret) and `ZIHPM_NR > 0`
(HPM counters 3–10).

### M-mode access (`mcycle` / `mhpmcounter*`)

```asm
csrr   t0, mcycle
csrr   t1, mcycleh        # for 64-bit value, take care of carry
csrr   t2, minstret
```

### U-mode access (read-only shadows)

U-mode access to `cycle` / `time` / `instret` (and the HPM shadows) is
**enabled by `mcounteren`** (M-mode controls U-mode visibility) and
**enabled by `scounteren`** (S-mode controls U-mode visibility when the trap
is in S-mode).

```asm
# M-mode: enable user-mode cycle + instret reads
li    t0, 0x5                  # bit 0 = cycle, bit 2 = instret
csrw  mcounteren, t0
```

### `mcountinhibit`

```asm
# Freeze mcycle without disabling Zicntr entirely (debugging)
csrsi  mcountinhibit, 0x1      # bit 0 stops mcycle
csrci  mcountinhibit, 0x1      # restart it
```

### 64-bit read pattern

For a glitch-free 64-bit value despite the 32-bit high/low split:

```asm
1:  csrr  t0, cycleh
    csrr  t1, cycle
    csrr  t2, cycleh
    bne   t0, t2, 1b           # high half rolled over during read → retry
```

### Accepted deviations

- `mcycle` **freezes during WFI sleep** (single-clock-domain architecture)
- `minstret` **counts trapping instructions** (dispatch-stage count) — off-by-one
  visible only on synchronous traps

Both fully documented in `spec_compliance_notes.md`.

---

## 10. RV32E Programming Notes

When `RV32E_EN == 1`:

- Only registers x0–x15 exist physically.
- Use the `ilp32e` ABI: `-march=rv32e* -mabi=ilp32e`.
- a6–a7, s2–s11, t3–t6 are absent; the calling convention is restricted to
  x0–x15.
- **Do not** write to x16–x31 — they read 0 / writes are dropped (no trap).
  Conforming RV32E programs never name these registers.
- The decoder is RV32I/RV32E **bit-identical** — the narrowing lives in the
  register file. See
  [`spec_compliance_notes.md`](spec_compliance_notes.md#rv32e-reserved-registers-x16x31-read-0--writes-dropped-no-trap-base_isa1)
  for the rationale and the JALR-shadow caveat.

**Building an RV32E test in the regression:**

```bash
./run inst_rv32e_basic -e_mode
```

The `-e_mode` flag re-runs `gen_rtl_params` with `RV32E_EN=1` and the
`ilp32e` ABI. See `simulation_guide.md` for the full flow.

---

## See Also

- [`integration_guide.md`](integration_guide.md) — pinout, reset / boot, AHB contract
- [`traps_and_interrupts.md`](traps_and_interrupts.md) — full trap + IRQ details
- [`arvern_instructions.md`](arvern_instructions.md) — ISA + CSR reference
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — every firmware-visible deviation
