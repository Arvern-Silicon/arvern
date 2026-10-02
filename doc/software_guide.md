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
3. [Memory Map (testbench SoC)](#3-memory-map-testbench-soc)
4. [Linker Script](#4-linker-script)
5. [Minimal Startup](#5-minimal-startup)
6. [CSR Access — Idioms and Caveats](#6-csr-access--idioms-and-caveats)
7. [Build Discovery and aRVern CSRs](#7-build-discovery-and-arvern-csrs)
8. [Trap Handler Skeleton](#8-trap-handler-skeleton)
9. [Data-Bus Errors (RNMI)](#9-data-bus-errors-rnmi)
10. [WFI Usage](#10-wfi-usage)
11. [Counters (Zicntr / Zihpm)](#11-counters-zicntr--zihpm)
12. [Physical Memory Protection (PMP / Smepmp)](#12-physical-memory-protection-pmp--smepmp)
13. [RV32E Programming Notes](#13-rv32e-programming-notes)

---

## 1. Toolchain and ABI

### Default toolchain

| Item | Value |
|---|---|
| Triple | `riscv-none-elf` (xPack) |
| Default optimisation | `-O2` (`toolchain.build_config.OPTIMIZATION` in `run_config.json`; per-test `"optimization"` overrides) |
| `MARCH_STD` (std mode, full B, default RTL config) | `rv32im_zbb_zba_zbs_zbc_zicsr_zifencei` |
| `MARCH_COMP` (compressed mode, `INST_MODE=COMP_MODE`) | `rv32imc_zbb_zba_zbs_zbc_zcb_zcmp_zcmt_zicsr_zifencei` |
| `MABI` | `ilp32` (or `ilp32e` when `RV32E_EN == 1`) |

The `-march` and `-mabi` strings are generated from `run_config.json` into
`sim/rtl_sim/run/march_config.sh` on every test build. `source` it from your
own Makefile to inherit the same flags (see `src-c/hello_world/Makefile` for
the `INST_MODE` selection):

```bash
source sim/rtl_sim/run/march_config.sh
echo $MARCH_STD $MABI    # rv32im_zbb_zba_zbs_zbc_zicsr_zifencei ilp32
```

### Alternative toolchains

| Profile | Prefix | Notes |
|---|---|---|
| `xpacks` (default) | `riscv-none-elf-` | — |
| `gcc` | `riscv64-unknown-elf-` | `riscv-gnu-toolchain` build; `zcmt` is stripped from both `-march` strings, so `cm.jt`/`cm.jalt` are never emitted |
| `clang` | `riscv32-unknown-elf-` (LLVM with GCC newlib sysroot) | — |

Switch by editing the `"toolchain.active"` key in `run_config.json`. See
[`simulation_guide.md` §1.5](simulation_guide.md#15-alternative-toolchains).

### ABI

aRVern uses the **standard RISC-V ELF psABI** (RV32 ilp32 / ilp32e). No
aRVern-specific calling-convention deviations.

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
> and the `rv32e[m][c]…` `-march` string (§13).

---

## 2. Boot Flow

On reset:

1. `hresetn_i` asserts → all flops reset.
2. On the first clock edge after `hresetn_i` deasserts the PC takes
   `reset_vector_i[31:2]`; bits `[1:0]` are ignored, so the reset PC is
   word-aligned. A synchronous-reset build needs a running clock for this
   sample.
3. The fetch unit issues the first instruction fetch on the instruction AHB
   bus at that address. Privilege is M-mode (`2'b11`).
4. The decode pipeline starts dispatching once `inst_hready_i` returns valid
   data.

**There is no internal boot ROM** — aRVern only provides the program counter.
The boot ROM (if any) is part of the SoC and must respond on the instruction
AHB bus at `reset_vector_i`. Firmware can read its own reset vector back from
the `reset_vector` CSR (0xFFE, §7).

### Test-SoC reset vector

The bundled testbench (`bench/verilog/tb_arvern.v`) ties `reset_vector_i =
32'h2000_0000`, the start of the test boot ROM (§3).

---

## 3. Memory Map (testbench SoC)

The testbench SoC (used by `./run`, `./run_all`, `./run_benchmark`) has this map
(`bench/verilog/ahb_decoder.v`, `tb_arvern.v`):

| Region | Range | Size | Notes |
|---|---|---|---|
| ROM (`.text`, `.rodata`, `.data` load image) | `0x2000_0000`–`0x2000_FFFF` | 64 KiB | The only preloaded memory: `$readmemh("pmem.mem")`, produced by `ihex2mem.py` from `pmem.ihex` |
| SRAM_X (executable) | `0x8000_0000`–`0x8000_FFFF` | 64 KiB | `.data` / `.bss` / stack |
| SRAM_NX (non-executable) | `0x8100_0000`–`0x8100_FFFF` | 64 KiB | Not contiguous with SRAM_X |
| SRAM_LO_X (executable) | `0x0000_0000`–`0x0000_0FFF` | 4 KiB | Off by default; enabled for PMP TOR-from-0 tests |
| ACLINT (mtime / msip / sswi) | `0x0200_0000`–`0x0200_FFFF` | 64 KiB | |
| PLIC | `0x0C00_0000`–`0x0C3F_FFFF` | 4 MiB | |
| `ahb_periph_example` #0 / #1 / #2 | `0x1004_0000`, `0x1004_1000`, `0x1004_2000` | 128 B each | Used by some trap tests |

Only the ROM is preloaded; every SRAM is zero at time 0, which is why `.data`
must be copied from its ROM load address at startup (§4).

The testbench SoC's memory map is **not** the aRVern core's contract — aRVern is a
processor, not an SoC. An integrator can place the ROM and RAM wherever the
SoC fabric routes them, as long as `reset_vector_i` points at executable
memory and `sp` is set to a writable region before any C code runs.

---

## 4. Linker Script

The per-program scripts under `sim/rtl_sim/src-c/<test>/link.ld` are the ones
to copy for C code. `hello_world/link.ld`:

```
ENTRY(_start)

MEMORY
{
    ROM  (rx)  : ORIGIN = 0x20000000, LENGTH = 32K
    SRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 32K
}

SECTIONS
{
    .text : {
        *(.init)
        *(.text*)
        *(.rodata*)
        *(.srodata*)
    } > ROM

    .data : {
        *(.data*)
    } > SRAM AT > ROM          /* runtime in SRAM, init values in ROM */

    .bss (NOLOAD) : {
        *(.bss*)
        *(COMMON)
    } > SRAM

    __romdatastart    = LOADADDR(.data);
    __datastart       = ADDR(.data);
    __romdatacopysize = SIZEOF(.data);
}
```

For a real SoC, replace the `MEMORY` origins with whatever the fabric routes to
your boot ROM and RAM. The three trailing symbols feed the `.data` copy in the
startup code; add `__bssstart` / `__bssend` for the `.bss` clear.

`hello_world/startup.S` is a three-instruction stub (§5). The benchmark
programs use a complete crt0 (`src-c/dhrystone_v2.1/startup.S` with its
`link.ld`) that copies `.data` from ROM and clears `.bss` — copy that pair,
not the stub. The minimal `sim/rtl_sim/bin/link.ld` is used only for the
assembly tests.

---

## 5. Minimal Startup

The stub used by `sim/rtl_sim/src-c/hello_world/startup.S`:

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

> This stub is **not trap-safe**: it neither arms `mnstatus.NMIE` nor clears
> `mstatush.MDT`, so the first trap of any kind — including an `ecall` or a
> misaligned load — puts the hart into the critical-error state (`lockup_o`).
> It is adequate only for code that never traps.

The vectors reset to a jump table just after the reset entry — `marv_nmvec` at
`reset_vector + 4`, `mtvec` at `+8`, `stvec` at `+12` (`SU_MODE_EN = 1`) — so an
image that opens with one 32-bit jump per slot is trap-safe from its first
instruction without writing a vector CSR. The table must keep 4-byte slots when
the image is built with the C extension, where a bare `j` would shrink to `c.j`:

```asm
.section .init
.globl _start
    .option push
    .option norvc
    j _start              # reset_vector + 0   reset entry
    j rnmi_handler        # reset_vector + 4   RNMI / double-trap  (marv_nmvec)
    j trap_handler        # reset_vector + 8   M-mode trap          (mtvec)
    j strap_handler       # reset_vector + 12  S-mode trap          (stvec, SU_MODE_EN = 1)
    .option pop
_start:
```

A boot sequence that leaves the hart able to take traps does the following, in
this order:

| Step | Action | Why |
|---|---|---|
| 1 | `sp`, `gp` | Stack and `.sdata` relaxation |
| 2 | Clear `.bss`, copy `.data` | SRAM is uninitialised at reset |
| 3 | Write `mtvec`, `marv_nmvec` (0x7FD), `mnscratch` (0x740) | Trap vector, RNMI/double-trap vector, private RNMI stack. Optional if the image opens with the default jump table (below) |
| 4 | `csrsi 0x744, 8` — `mnstatus.NMIE = 1` | **Required on every build.** NMIE resets to 0, masks *all* interrupts, and while the hart runs in M-mode with NMIE = 0 every trap is an unexpected trap with no escape route (critical-error state). Must precede step 6 |
| 5 | `SU_MODE_EN = 1` only: decide `menvcfgh.DTE` | Resets to 1 (S-mode double-trap protection on). Clear it for spec-literal horizontal delegation, or leave it and clear `sstatus.SDT` in the S-mode handler prologue |
| 6 | `csrw mstatush, x0` — `MDT = 0` | MDT resets to 1; while set, a trap into M is an unexpected double trap and `mstatus.MIE` cannot be set. Step 4 must already be done |
| 7 | Enable interrupts (`mie`, `mstatus.MIE`) | Last — a write of `MIE = 1` is dropped while MDT = 1 |

Terminology: an **RNMI** (Smrnmi resumable NMI) is delivered through `marv_nmvec`
with its own CSR bank (0x740–0x744) and returns with `mnret`. An **unexpected
trap** is a trap into M-mode taken while `mstatush.MDT = 1`, or while the hart
runs in M-mode with `mnstatus.NMIE = 0`. It is **diverted** to the RNMI handler
if NMIE = 1, and otherwise enters the **critical-error state**: execution
ceases and `lockup_o` asserts until reset. Full rules in
[`traps_and_interrupts.md` §10](traps_and_interrupts.md#10-double-traps-and-the-critical-error-state).

```asm
.section .init
.globl _start
_start:
    # 1. Stack and global pointer
    la sp, _stack_top
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    # 2. Clear .bss (copy .data likewise, from __romdatastart to __datastart)
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:

    # 3. Trap vectors and the RNMI stack
    la   t0, _trap_handler
    csrw mtvec, t0
    la   t0, _rnmi_handler
    csrw 0x7FD, t0             # marv_nmvec -- RNMI and (Smdbltrp) double-trap handler
    la   t0, _rnmi_stack_top
    csrw 0x740, t0             # mnscratch = RNMI stack pointer (an RNMI cannot trust sp)

    # 4. REQUIRED, before step 6: arm NMIE
    csrsi 0x744, 8             # mnstatus.NMIE = 1

    # 5. SU_MODE_EN=1 only: DTE policy (bit 27 > imm5, so csrc rather than csrci)
    # li   t0, (1 << 27)
    # csrc 0x31A, t0           # menvcfgh.DTE = 0 -> spec-literal horizontal delegation
    #    An Ssdbltrp-aware OS leaves DTE=1 and clears sstatus.SDT in its S-mode
    #    trap-handler prologue, after saving sepc/scause/sstatus:
    #        li   t0, (1 << 24)
    #        csrc sstatus, t0   # SDT = 0 -> handler is re-entrant again

    # 6. Clear MDT (resets to 1 on every build)
    csrw 0x310, x0             # mstatush = 0 -> MDT = 0

    # 7. Enable interrupts (if the OS wants them on at start)
    # csrsi mstatus, 0x8       # MIE = 1
    # li    t0, (1<<11)|(1<<7) # MEIE | MTIE
    # csrw  mie, t0

    call main
    j .
```

Replace `_stack_top`, `_rnmi_stack_top`, `__bss_start`, `__bss_end`, `__global_pointer$` with
symbols your linker script defines.

`SU_MODE_EN = 0` builds (the `arvern.v` default): `mcounteren`, `menvcfg`,
`menvcfgh`, `medeleg` and `mideleg` do not exist and raise illegal-instruction —
skip every write to them. `marv_cfg[2]` (§7) says which build you are on.

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

`csrr` is `csrrs rd, csr, x0`. The write forms have `rd = x0`; the read
side-effect is suppressed for `csrrw`/`csrrwi` with `rd = x0`.

### CSR-access trap rules

| Trap | Trigger |
|---|---|
| Illegal-instruction (cause 2) | CSR address outside every implemented window; write to a read-only CSR; access from insufficient privilege; a CSR a build parameter removes (S-mode bank, `mcounteren`/`menvcfg*`/`medeleg`/`mideleg` at `SU_MODE_EN = 0`; `pmpcfg*`/`pmpaddr*`/`mseccfg` at `PMP_NR = 0`; counters at `ZICNTR_EN = 0`) |
| RAZ/WI silently | An unimplemented address *inside* an implemented window — see the [bank-level decode entry](spec_compliance_notes.md#non-existent-csrs-in-known-banks-read-as-0-razwi-do-not-trap). |

Practical impact: don't rely on illegal-instruction trapping to detect a
mistyped CSR address inside e.g. the 0x300 bank — you'll get a silent RAZ/WI
instead. The decode-bank set is documented in `arv_csr_top.v:any_bank_known`.

### FENCE and memory-mapped registers

A `FENCE` that names any I/O bit (`PI`/`PO`/`SI`/`SO` — including a bare `fence`,
which assembles to `fence iorw,iorw`) holds dispatch until every outstanding
data-bus access has completed; `fence rw,rw`, `FENCE.TSO` and `PAUSE` do not
drain. The drain makes a store to a memory-mapped register visible to a
subsequent read of a CSR that aliases it — `sw` to ACLINT MTIME followed by
`csrr time`, for instance. RVWMO does not require that (a CSR read is not a
memory operation, and no fence encoding orders one on any implementation), so
portable firmware reads the location back through MMIO instead; the idiom is
supported here because it is natural, and it is opt-in: a fence that does not
name I/O does not pay for it. Encodings: [`arvern_instructions.md`](arvern_instructions.md).

---

## 7. Build Discovery and aRVern CSRs

### Identifying the core

Read `marchid` first: aRVern reports `0x36` (54); `mvendorid` is `0x08FB`.
On another core, 0xFFF is a custom read-only CSR that will normally raise
illegal-instruction, so `marv_cfg` is meaningful only after `marchid` has
identified aRVern. `mimpid` (0xF13) answers the other question — **which RTL
revision** — as `{major, minor, patch}`, one byte each (`[7:0]` reserved 0).

### `marv_cfg` (0xFFF)

`marv_cfg` reports what was synthesized, at finer granularity than `misa` can
express — extension *levels* rather than presence bits, counter and trigger
counts, and the multiplier/divider choice. Reading it once at boot avoids
probing CSRs and catching traps. Field layout: `C_EXTENSION` level `[26:24]`,
`B_EXTENSION` level `[22:20]`, `mul_type` `[19:18]`, `div_type` `[17:16]`,
`ZIHPM_NR` `[15:12]`, `DM_TRIGGER_NR` `[11:8]`, `PMP_NR` `[7:6]`
(0 = none, 1 = 4, 2 = 8, 3 = 16), `SINGLE_CYCLE_BRANCH` `[5]`, `ASYNC_RST_EN`
`[4]`, `ZICNTR_EN` `[3]`, `SU_MODE_EN` `[2]`, `DEBUG_EN` `[1]`, `CCSR_EN`
`[0]`. The full table is in
[`arvern_instructions.md`](arvern_instructions.md#machine-information-registers).

```asm
    csrr t0, 0xFFF             # marv_cfg
    srli t1, t0, 20            # B_EXTENSION level in t1[2:0]
    andi t1, t1, 0x7           #   4 => Zbc present (clmul/clmulh/clmulr will execute)
    srli t2, t0, 12            # ZIHPM_NR in t2[3:0]
    andi t2, t2, 0xF
```

Reserved bits read zero but may become fields, so mask the field you want
rather than comparing whole words.

`misa` follows the spec's all-or-nothing definitions: `misa.B` means the
ratified B extension (Zba + Zbb + Zbs, Unpriv ch. 29) and `misa.M` the full M
extension (Zmmul is its subset, §12.3), so a Zbb-only or Zmmul build reads
B = 0 / M = 0. Firmware discovers the exact level from `marv_cfg`
(`B_EXT_LEVEL` `[22:20]`, `mul_type` `[19:18]`, `div_type` `[17:16]`).

### aRVern custom CSRs

All are present regardless of `CCSR_EN`; the rest of 0x7C0–0x7FF is RAZ/WI.

| CSR | Addr | Access | Reset | Notes |
|---|---|---|---|---|
| `marv_nmvec` | 0x7FD | MRW | `reset_vector + 4` | RNMI and Smdbltrp-divert vector, `[1:0]` read-only 0 |
| `marv_estat` | 0x7FE | MRW / W1C | 0 | `{uop_sourced[4], restartable[3], overrun[2], store[1], valid[0]}`; write `0x5` clears (§9) |
| `marv_ctl` | 0x7FF | MRW | `0x7` | `[0]` IRQ kills in-flight MUL/DIV, `[1]` IRQ kills an in-flight Zcmp push/pop, `[2]` post-xRET IRQ/NMI re-entry guard, `[3]` `wfi_clkgate_dis`. Semantics in [`traps_and_interrupts.md` §9](traps_and_interrupts.md#9-core-feature-control-marv_ctl) |
| `marv_epc` | 0xFFC | MRO | 0 | PC of the access that took the data-bus error |
| `marv_eaddr` | 0xFFD | MRO | 0 | Its address |
| `reset_vector` | 0xFFE | MRO | — | `{reset_vector_i[31:2], 2'b00}` — the base of the `+4 / +8 / +12` default vectors |
| `marv_cfg` | 0xFFF | MRO | — | Build configuration (above) |

---

## 8. Trap Handler Skeleton

Vectored mode (`mtvec[0] = 1`) puts **interrupts** at `mtvec_base + 4 × cause`;
exceptions and double traps always take the direct entry. Direct mode
(`mtvec[0] = 0`) sends everything to a single entry. A direct-mode handler:

```asm
.balign 4
.globl _trap_handler
_trap_handler:
    # Save caller-saved + arg registers (RV32E: omit a6-a7 and t3-t6)
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

    # Snapshot the trap state BEFORE becoming re-entrant
    csrr a0, mcause            # a0 = mcause
    csrr a1, mepc              # a1 = faulting / next PC
    csrr a2, mtval             # a2 = faulting address (0 for illegal-instr/ECALL/EBREAK/IRQ)

    # Smdbltrp: hardware set mstatush.MDT on entry. Until it is cleared, ANY
    # further trap here is an unexpected double trap. Clear it once mepc/mcause
    # /mtval are safely in registers or on the stack -- not before.
    csrw 0x310, x0             # mstatush = 0 -> MDT = 0, handler is re-entrant

    call c_trap_handler        # C dispatch

    # Restore
    lw   ra,  60(sp)
    lw   t0,  56(sp)
    # ... (rest)
    addi sp, sp, 64

    mret
```

A practical handler splits on `mcause[31]` (interrupt), then fans out by
`mcause[4:0]`:

| `mcause` | Event | aRVern specifics |
|---:|---|---|
| 0 | Instruction address misaligned | Reachable only with `C_EXTENSION = 0` |
| 1 | Instruction access fault | PMP execute denial, or an instruction-bus error response |
| 2 | Illegal instruction | Includes absent-CSR access, `sfence.vma` (every build), U-mode `wfi` |
| 3 | Breakpoint | `ebreak`; with `DEBUG_EN = 1` and `dcsr.ebreakm/s/u` set, `ebreak` enters Debug Mode instead and no trap is taken ([`debug_interface.md` §7](debug_interface.md#7-hart-side-debug-csrs)) |
| 4 / 6 | Load / store address misaligned | |
| 5 / 7 | Load / store access fault | **PMP denial only** (`PMP_NR > 0`); a data-bus error is never reported here (§9) |
| 8 / 9 / 11 | `ecall` from U / S / M | |
| 16 | Double trap (Ssdbltrp) | `mtval2` holds the original cause code; `SU_MODE_EN = 1` |
| 12–15 | Page faults | Never raised — no MMU |
| Interrupts 1 / 3 / 5 / 7 / 9 / 11 | SSI / MSI / STI / MTI / SEI / MEI | |
| Interrupts 16–31 | Platform IRQs (`irq_platform_i`) | |

`mtval` and priority details: [`traps_and_interrupts.md` §2](traps_and_interrupts.md#2-synchronous-exceptions).

### Interrupt-source semantics

- `MEIP` / `MTIP` / `MSIP` are level bits driven by the pins.
- `mip.SSIP` is set by a one-cycle pulse on `irq_s_software_i` (ACLINT SSWI)
  and stays set until software clears it through `mip` or (when delegated)
  `sip` — an IPI handler must clear it; there is no hardware de-assert.
- `mip[31:16]` platform IRQs are sticky: set by `irq_platform_i`, cleared only
  by a write to `mip` (or `sip` when delegated).
- `STIP` and the `SEIP` software bit are writable through `mip` only;
  `sip` reads them but ignores writes.

Details: [`traps_and_interrupts.md` §3](traps_and_interrupts.md#3-standard-interrupts-mip--mie)
and [§4](traps_and_interrupts.md#4-platform-interrupts-mip3116).

### RNMI handler

Its address lives in `marv_nmvec` (0x7FD, reset `reset_vector + 4`, §7). Two
things make this more than "the same structure, ending in `MNRET`".

**The vector is shared.** Both a real RNMI *and* an Smdbltrp double-trap divert
land here. `mncause[31]` is the only discriminator:

| `mncause` | Meaning |
|---|---|
| `0x8000_0002` | external RNMI pin |
| `0x8000_0003` | data-bus error — `marv_epc`/`marv_eaddr`/`marv_estat` describe it |
| `0x0000_00xx` | **double trap**; low bits are the cause that precipitated it |

**Nothing may trap inside the handler.** RNMI entry clears `mnstatus.NMIE`,
and while the hart runs in M-mode with NMIE = 0 any trap is an unexpected trap
with no RNMI to divert to: the critical-error state. Until `mnret`, the C code
must not `ecall`/`ebreak`, touch unmapped or PMP-denied memory, or execute
anything that can fault. `mstatus.MPRV` is also ignored while NMIE = 0.

**`MNRET` does not always clear MDT.** It clears it only when returning *below*
M. A divert sets `MNPP = M`, so returning from one leaves MDT set and the next
trap doubles straight back here. Clear it explicitly.

```asm
.balign 4
.globl _rnmi_handler
_rnmi_handler:
    # An RNMI can land anywhere, so do not trust sp. mnscratch (0x740) holds a
    # private save area pointer that boot code installed.
    csrrw sp, 0x740, sp        # swap in the RNMI stack, stash the interrupted sp

    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)

    csrr t0, 0x742             # mncause
    bgez t0, rnmi_double_trap  # bit 31 clear -> Smdbltrp divert, not an RNMI

    # --- real RNMI: 2 = pin, 3 = data-bus error
    andi t1, t0, 0xFF
    li   t0, 3
    bne  t1, t0, rnmi_pin
    #     bus error: marv_epc (0xFFC) / marv_eaddr (0xFFD) / marv_estat (0x7FE)
    #     name the faulting access. See section 9.
rnmi_pin:
    call c_rnmi_handler
    j    rnmi_exit

rnmi_double_trap:
    # mtval and mtval2 are NOT provided on a divert -- the precipitating cause
    # is in mncause[7:0] and mnepc holds the faulting PC. Recovery is
    # policy: panic, or repair and resume.
    call c_double_trap_handler

rnmi_exit:
    # REQUIRED before returning into M-mode, or the next trap re-enters here.
    csrw 0x310, x0             # mstatush = 0 -> MDT = 0

    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    csrrw sp, 0x740, sp        # restore the interrupted sp
    mnret                      # .word 0x70200073 if the assembler lacks Smrnmi
```

> `mnret` needs a toolchain that knows Smrnmi; otherwise emit
> `.word 0x70200073`.

See [`integration_guide.md` §6](integration_guide.md#6-nmi-interface-smrnmi)
for the pin contract.

---

## 9. Data-Bus Errors (RNMI)

A **data**-bus error (an AHB error response on a load or store) is delivered as a
resumable NMI with `mncause = 0x8000_0003` — **not** as `mcause = 5/7`. Causes 5
and 7 are raised only by the PMP checkers (`PMP_NR > 0`, §12): a cause-5/7 trap
always means a PMP denial, never a bus error. Instruction-bus errors are
unaffected and remain a synchronous `mcause = 1`.

Three CSRs carry the evidence, all latched on the faulting access's own
address phase so they cannot disagree with each other:

| CSR | Address | Meaning |
|---|---|---|
| `marv_epc`   | 0xFFC | PC of the access that faulted — **what** faulted |
| `marv_eaddr` | 0xFFD | the address that faulted |
| `marv_estat` | 0x7FE | `{uop_sourced[4], restartable[3], overrun[2], store[1], valid[0]}` |

`marv_estat.valid` and `.overrun` are **W1C** — write `0x5` to clear before the next
access. Capture is **first-fault-wins**: a second error while `valid` is set sets
`overrun` and leaves the first fault's evidence intact.

### `mnepc` is a resume point; replay is opt-in

`mnepc` points **past** the faulting access, so a plain `MNRET` always makes forward
progress. That is deliberate: retrying by default would loop, because a hard bus
error faults again. A handler that wants to retry must ask for it:

```asm
    csrr  t0, 0x7FE            # marv_estat
    andi  t1, t0, 0x8          # restartable?
    beqz  t1, no_replay
    csrr  t1, 0xFFC            # marv_epc = the faulting macro-op
    csrw  0x741, t1            # mnepc <- replay it
no_replay:
    li    t0, 0x5
    csrw  0x7FE, t0            # W1C valid|overrun
    mnret
```

**When the NMI interrupted a trap handler, resume it — do not replay.** An interrupt
that was about to kill a `cm.push`/`cm.pop` when the sequence's own access took the
bus error is still taken as a kill: its `mepc` names the `cm.*` instruction, and the
resumable NMI then arrives inside that interrupt handler with `restartable = 1`.
Resuming (`MNRET` to `mnepc`) is the correct action there — the macro-op replays when
the interrupt handler returns. Replaying from `marv_epc` would re-execute it inside
the interrupt handler's context. So only replay when `mnepc` is in the interrupted
program, not in a trap handler.

### `restartable` is exact — and one case is never restartable

`marv_estat.restartable` reports whether the sequence that **issued** the faulting
access still owns the pipeline. A `cm.push` whose last posted store faults *after*
the macro-op retired reads `0`: replaying it would decrement `sp` a second time.

**Zcmt table reads always read `restartable = 0`.** Re-executing a `cm.jt` re-reads
the same table entry and takes the same hard error. For this one class `mnepc` names
the `cm.jt` **itself** rather than a resume point — the jump target was never read, so
there is no correct place to continue, and falling through would silently execute past
a jump. **A plain `MNRET` therefore loops, by design.** On a JT-sourced bus error the
handler must not simply return: panic, or redirect `mnepc` explicitly.

---

## 10. WFI Usage

```asm
# Park CPU until any enabled IRQ or NMI fires
wfi
```

WFI behaves as a clean pipeline drain + stall — it is **not** a trap (`mcause`
is not updated). On wake:

- `mepc` (if an IRQ takes the trap) is set to `WFI_PC + 4`, so `MRET` resumes
  past the WFI.
- `hclk_en_o` is deasserted while sleeping. If the SoC gates the core clock
  from it, every core flop freezes, `mcycle` included. Set `marv_ctl[3]`
  (`wfi_clkgate_dis`, §7) to keep `hclk_en_o` asserted during WFI — for debug,
  or when the SoC has no clock gate; `mcycle` then keeps counting.

**Wake set**: any *individually* enabled source — `(mip & mie) != 0` — or a
pending NMI (pin or data-bus error, with `mnstatus.NMIE = 1`) wakes the core,
even with `mstatus.MIE = 0`; a debug halt request wakes it too. If no enabled
source can ever fire, WFI stalls forever, so configure `mie` and the external
sources before entering it.

**Privilege**: U-mode WFI raises illegal-instruction regardless of `mstatus.TW`
(the bounded time limit is 0); S-mode WFI sleeps unless `TW = 1`. An RTOS idle
task must run in M or S mode, or request idle through an `ecall`. Table in
[`traps_and_interrupts.md` §8](traps_and_interrupts.md#8-wfi-sleep-and-wake).

---

## 11. Counters (Zicntr / Zihpm)

Available when `ZICNTR_EN == 1` (cycle / time / instret) and `ZIHPM_NR > 0`
(HPM counters 3–10). With `ZICNTR_EN = 0` and `ZIHPM_NR = 0` the counter CSRs
are absent and `rdcycle` traps.

### M-mode access (`mcycle` / `mhpmcounter*`)

```asm
csrr   t0, mcycle
csrr   t1, mcycleh        # for 64-bit value, take care of carry
csrr   t2, minstret
```

`time` / `timeh` are served by the SoC timer over the `time_req/gnt`
interface and are the only CSR reads that can stall.

### U-mode access (read-only shadows)

U-mode access to `cycle` / `time` / `instret` (and the HPM shadows) requires
the corresponding bit set in **both `mcounteren` and `scounteren`** — M-mode
and S-mode each independently gate U-mode visibility, and a U-mode read traps
illegal-instruction unless both allow it. S-mode's own counter access is gated
by `mcounteren` alone.

```asm
# M-mode: enable user-mode cycle + instret reads
li    t0, 0x5                  # bit 0 = cycle, bit 2 = instret
csrw  mcounteren, t0
```

`SU_MODE_EN = 0` builds: `mcounteren` does not exist (illegal-instruction);
there is no lower privilege to gate.

### `mcountinhibit`

```asm
# Freeze mcycle without disabling Zicntr entirely (debugging)
csrsi  mcountinhibit, 0x1      # bit 0 stops mcycle
csrci  mcountinhibit, 0x1      # restart it
```

Bit 1 (`time`) is hardwired 0.

### Programming an HPM counter (`ZIHPM_NR > 0`)

```asm
li    t0, 0x5
csrw  mhpmevent3, t0           # event 5 = branch taken
csrw  mhpmcounter3, x0         # clear
csrci mcountinhibit, 0x8       # bit 3 = counter 3 runs
# ... region under test ...
csrr  t1, mhpmcounter3
```

Event codes (`0x01`–`0x12`: pipeline stalls, branches, loads/stores,
exceptions, interrupts, platform events) are tabulated in
[`arvern_instructions.md`](arvern_instructions.md#hardware-performance-counters-zihpm).
Counters above `ZIHPM_NR` read 0 and ignore writes, without trapping.

### 64-bit read pattern

For a glitch-free 64-bit value despite the 32-bit high/low split:

```asm
1:  csrr  t0, cycleh
    csrr  t1, cycle
    csrr  t2, cycleh
    bne   t0, t2, 1b           # high half rolled over during read → retry
```

### Accepted deviations

- `mcycle` **freezes during WFI sleep** when the SoC gates the clock (single
  clock domain).
- `minstret` does not count an instruction that takes a synchronous exception
  (Unpriv Zicntr). The one deviation is asynchronous: an instruction whose
  data access later returns a bus error (RNMI, §9) remains counted — it did
  retire.

Both documented in `spec_compliance_notes.md`.

---

## 12. Physical Memory Protection (PMP / Smepmp)

Present when `PMP_NR != 0`. With `PMP_NR = 0` the CSRs are **absent**, not RAZ/WI: an access
raises illegal-instruction, so probe with a trap handler installed or read `marv_cfg[7:6]`
first (`0`=none, `1`=4, `2`=8, `3`=16).

### Discovering the usable entry count

Sixteen entries always exist architecturally; entries at or above `PMP_NR` are read-only
zero. Priv 2.3.3 says to discover the count by WARL probing — write a non-zero `A` and read
back:

```asm
    li   t0, 0x18              # A = NAPOT
    csrw pmpcfg0, t0
    csrr t1, pmpcfg0
    beqz t1, no_pmp            # read back zero => entry 0 is not writable
```

### Writing a rule

`pmpaddr` holds `address[33:2]`, so shift the byte address right by 2. NAPOT encodes the
size in the trailing ones:

```asm
    # 16-byte NAPOT region at 0x80000400, read-only, locked
    li   t0, 0x80000400
    srli t0, t0, 2
    ori  t0, t0, 1             # one trailing 1 => 16 bytes
    csrw pmpaddr0, t0
    li   t0, 0x99              # L | A=NAPOT | R
    csrw pmpcfg0, t0
```

With `A = NAPOT`: no trailing ones = 8 bytes, one = 16, two = 32, and so on.
For a 4-byte region use `A = NA4` (selectable because `G = 0`).

For **TOR**, entry `g` spans `[pmpaddr[g-1], pmpaddr[g])` — the lower bound comes from the
*neighbouring* register, regardless of that neighbour's own `A` field, so an `A=OFF` entry
is a perfectly good way to supply a bound.

A write to any `pmpcfg*` / `pmpaddr*` / `mseccfg` is self-synchronising: it
triggers a FENCE.I-style refetch, so the next instruction is already checked
against the new rules. No `fence.i` is needed, and `sfence.vma` raises
illegal-instruction on every build.

### Rules that matter in practice

- **Lowest-numbered match wins**, and it wins outright — a later entry cannot widen what an
  earlier one denied. Put specific rules first and catch-alls last.
- **An unlocked rule does not bind M-mode.** `pmpcfg.L` is what makes a rule apply to
  machine mode as well; without it, M-mode ignores the entry entirely.
- **Locking is one-way.** Once `L` is set, that entry's `pmpcfg` *and* `pmpaddr` are
  read-only until reset, unless `mseccfg.RLB` is set. A locked TOR entry also freezes the
  `pmpaddr` below it, since that register is its lower bound.
- **No match is not the same as no rules.** If any entry is implemented, an S/U access that
  matches nothing is **denied**. Machine mode is allowed unless `mseccfg.MMWP`. Firmware
  that installs PMP and then drops to U-mode without a covering rule will fault on its very
  first instruction.

### Smepmp (`mseccfg`, 0x747)

Three one-way bits: `MML` (bit 0) and `MMWP` (bit 1) are sticky-set, and `RLB` (bit 2)
becomes stuck-clear once any rule is locked. Only a reset clears them.

- **`MMWP`** makes machine mode an allowlist: an M-mode access matching no rule faults.
- **`MML`** replaces the permission meaning of `L`/`R`/`W`/`X` with the truth table of Priv
  6.2.1 — `R=0,W=1` becomes the Shared-Region marker rather than a reserved encoding, and
  M-mode execute is withdrawn on a no-match. With `MML` set, a `pmpcfg` write that would
  create a locked rule granting M-mode execute is **ignored** unless `RLB` is set, which is
  why boot code sets `RLB` while installing such rules and clears it afterwards. The
  restriction is applied per entry: the other bytes of the same `pmpcfg` word are
  written, so read the register back.

### Handling the faults

A denial raises cause **5** (load), **7** (store) or **1** (instruction fetch), with `mtval`
holding the faulting address. All three are delegatable via `medeleg`, so an S-mode kernel
can program PMP for its U-mode tasks and handle the faults itself.

Cause 1 has one wrinkle worth knowing: for a 32-bit instruction whose two halves fall in
different regions, `mepc` holds the instruction's address while `mtval` holds the half that
could not be fetched — they deliberately differ.

Note that a load or store denied by PMP produces **no bus transfer at all**, so a denied
store cannot partially land. A denied *fetch* is issued on the bus but never executed; see
[`integration_guide.md` §4.6](integration_guide.md#46-platform-contract-pmp-and-the-instruction-bus-pmp_nr--0)
for what that requires of the platform.

---

## 13. RV32E Programming Notes

When `RV32E_EN == 1`:

- Only registers x0–x15 exist physically.
- Use the `ilp32e` ABI: `-march=rv32e* -mabi=ilp32e`.
- a6–a7, s2–s11, t3–t6 are absent; the calling convention is restricted to
  x0–x15.
- **Do not** write to x16–x31 — they read 0 / writes are dropped (no trap).
  Conforming RV32E programs never name these registers.
- The decoder is RV32I/RV32E **bit-identical** — the narrowing lives in the
  register file. See
  [`spec_compliance_notes.md`](spec_compliance_notes.md#rv32e-reserved-registers-x16x31-read-0--writes-dropped-no-trap-rv32e_en1).

**Building an RV32E test in the regression:**

```bash
./run inst_rv32e_basic -e_mode
```

`-e_mode` pins `RV32E_EN = 1` for that invocation (`run_config.json` on disk is
untouched); the generated `arv_parameterization.v` / `march_config.sh` then
carry `rv32e…` / `ilp32e`. See `simulation_guide.md` for the full flow.

---

## See Also

- [`integration_guide.md`](integration_guide.md) — pinout, reset / boot, AHB contract
- [`traps_and_interrupts.md`](traps_and_interrupts.md) — full trap + IRQ details
- [`arvern_instructions.md`](arvern_instructions.md) — ISA + CSR reference
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — every firmware-visible deviation
