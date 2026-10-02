<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Supported Instructions
  <br clear="all">
</h1>

This document lists all instructions and CSRs supported by the aRVern RISC-V processor core, indexed by extension. Parameter names are those of `rtl/verilog/arvern.v`; see [`integration_guide.md`](integration_guide.md#1-configuration-parameters) for the full parameter reference.

## Table of Contents

- [Configuration](#configuration)
- [Privilege Modes](#privilege-modes)
- [RV32I Base Integer Instructions](#rv32i-base-integer-instructions)
  - [Arithmetic Instructions](#arithmetic-instructions)
  - [Logical Instructions](#logical-instructions)
  - [Shift Instructions](#shift-instructions)
  - [Compare Instructions](#compare-instructions)
  - [Branch Instructions](#branch-instructions)
  - [Jump Instructions](#jump-instructions)
  - [Load Instructions](#load-instructions)
  - [Store Instructions](#store-instructions)
  - [System Instructions](#system-instructions)
  - [Control and Status Register (CSR) Instructions](#control-and-status-register-csr-instructions)
  - [Illegal-instruction rules](#illegal-instruction-rules)
- [M Extension — Integer Multiply/Divide](#m-extension--integer-multiplydivide)
- [Zmmul Extension — Integer Multiply Only](#zmmul-extension--integer-multiply-only)
- [B Extension — Bit Manipulation](#b-extension--bit-manipulation)
  - [Zbb — Basic Bit Manipulation](#zbb--basic-bit-manipulation)
  - [Zba — Address Generation](#zba--address-generation)
  - [Zbs — Single-Bit Operations](#zbs--single-bit-operations)
  - [Zbc — Carry-less Multiply](#zbc--carry-less-multiply)
- [C Extension — Compressed Instructions](#c-extension--compressed-instructions)
  - [Zca — Base Compressed](#zca--base-compressed)
  - [Zcb — Compressed Code-Size Reduction](#zcb--compressed-code-size-reduction)
  - [Zcmp — Compressed Push/Pop/Moves](#zcmp--compressed-pushpopmoves)
  - [Zcmt — Compressed Table Jumps](#zcmt--compressed-table-jumps)
- [Smrnmi — Resumable NMI Extension](#smrnmi--resumable-nmi-extension)
- [Instruction Format Legend](#instruction-format-legend)
- [Implemented CSR Registers](#implemented-csr-registers)
  - [Machine-Level Trap Setup and Handling](#machine-level-trap-setup-and-handling)
  - [PMP / Smepmp CSRs](#pmp--smepmp-csrs)
  - [Machine Information Registers](#machine-information-registers)
  - [Counter / Timer CSRs (Zicntr)](#counter--timer-csrs-zicntr)
  - [Hardware Performance Counters (Zihpm)](#hardware-performance-counters-zihpm)
  - [Counter Setup CSRs](#counter-setup-csrs)
  - [Supervisor-Level CSRs](#supervisor-level-csrs)
  - [Resumable NMI CSRs (Smrnmi)](#resumable-nmi-csrs-smrnmi)
  - [External Debug CSRs (Sdext / Sdtrig)](#external-debug-csrs-sdext--sdtrig)
  - [aRVern-Specific Built-in CSRs](#arvern-specific-built-in-csrs)
  - [Zcmt CSR](#zcmt-csr)
- [Total Instruction Count](#total-instruction-count)
- [Reference](#reference)

## Configuration

The processor supports the instruction set extensions and privilege features listed below, each gated by a top-level RTL parameter (see [`integration_guide.md` §1](integration_guide.md#1-configuration-parameters) for the full parameter reference). For measured performance and code-size impact of each combination, see [`benchmarking_guide.md`](benchmarking_guide.md); for synthesized area, see [`synthesis_guide.md` §2](synthesis_guide.md#2-area-results).

| Extension | Configuration | Description |
|-----------|--------------|-------------|
| **RV32I** | `RV32E_EN = 0` | Base integer instruction set (32 registers) |
| **RV32E** | `RV32E_EN = 1` | Reduced register set (16 registers) |
| **Zmmul** | `M_EXTENSION = 1` | Integer multiply only |
| **M** | `M_EXTENSION = 2` | Integer multiply + divide |
| **Zbb** | `B_EXTENSION ≥ 1` | Basic bit manipulation |
| **Zba** | `B_EXTENSION ≥ 2` | Address-generation helpers |
| **Zbs** | `B_EXTENSION ≥ 3` | Single-bit operations |
| **Zbc** | `B_EXTENSION ≥ 4` | Carry-less multiply |
| **Zca** | `C_EXTENSION ≥ 1` | Base compressed instructions |
| **Zcb** | `C_EXTENSION ≥ 2` | Compressed code-size reduction |
| **Zcmp** | `C_EXTENSION ≥ 3` | Compressed push/pop/move |
| **Zcmt** | `C_EXTENSION ≥ 4` | Compressed table jumps |
| **Zicsr** | *always* | CSR instructions |
| **Zifencei** | *always* | `FENCE.I` |
| **Zicntr** | `ZICNTR_EN = 1` | Cycle / time / instret counters |
| **Zihpm** | `ZIHPM_NR > 0` (0–8 counters) | Hardware performance monitor |
| **S-mode** | `SU_MODE_EN = 1` | Supervisor mode + full trap delegation |
| **U-mode** | `SU_MODE_EN = 1` | User mode |
| **Ssdbltrp** | `SU_MODE_EN = 1` | S-mode double trap (`sstatus.SDT`, `menvcfgh.DTE`, `mtval2`) |
| **Smdbltrp** | *always* | M-mode double trap (`mstatush.MDT`, critical-error state) |
| **Smrnmi** | *always* | Resumable NMI (`MNRET`) |
| **PMP + Smepmp** | `PMP_NR ∈ {4, 8, 16}` | Physical memory protection, `mseccfg` (Smepmp included whenever `PMP_NR ≠ 0`) |
| **Sdext** | `DEBUG_EN = 1` | External debug (frozen-hart, no Program Buffer) |
| **Sdtrig** | `DM_TRIGGER_NR > 0` (0–8, needs `DEBUG_EN = 1`) | `mcontrol6` triggers |

`MUL_TYPE` (1 / 2 / 3 = single-cycle / four-cycle / sixteen-cycle multiplier) and `DIV_TYPE` (1 / 2 / 3 = radix-8 / radix-4 / radix-2 divider) select implementations, not instructions. The `arvern.v` defaults (the `classic` persona) are `RV32E_EN=0`, `C_EXTENSION=1`, `M_EXTENSION=2`, `B_EXTENSION=1`, `MUL_TYPE=1`, `DIV_TYPE=3`, `CCSR_EN=0`, `SU_MODE_EN=0`, `ZICNTR_EN=1`, `PMP_NR=0`, `ZIHPM_NR=0`, `SINGLE_CYCLE_BRANCH=1`, `ASYNC_RST_EN=1`, `DEBUG_EN=0`, `DM_TRIGGER_NR=0` — the default build has no S/U mode.

## Privilege Modes

| Mode | MPP/SPP encoding | HPROT[1]/HSMODE encoding | Always present? | Notes |
|------|------------------|--------------------------|------------------|-------|
| Machine (M) | `2'b11` | `2'b10` | Yes | Top privilege, all CSRs accessible |
| Supervisor (S) | `2'b01` | `2'b11` | `SU_MODE_EN = 1` | Physical S-mode: full trap delegation (`mideleg`/`medeleg`), `SRET`, `sstatus`/`sie`/`sip` masked by `mideleg`, `scounteren`, `satp` is a WARL stub (no paged MMU). When `SU_MODE_EN = 0`, all S-mode CSRs are absent and raise illegal-instruction, as does `SRET`. (`SFENCE.VMA` raises illegal-instruction in *all* configs regardless of `SU_MODE_EN` — aRVern implements no address translation / MMU.) |
| User (U) | `2'b00` | `2'b00` | `SU_MODE_EN = 1` | `mcounteren`-gated counter access; standard restrictions on M/S CSRs. When `SU_MODE_EN = 0`, U-mode never entered (mstatus.MPP forced to M; mret target always M). |

> The two encodings deliberately use different conventions: `MPP`/`SPP`
> follow the RISC-V Privileged spec, while `HSMODE` is an "S-mode flag"
> (asserted only in S-mode), chosen so that an SoC that only cares about
> privileged-vs-user can leave `*_hsmode_o` unconnected without silently
> downgrading M-mode accesses. See [`memory_and_ahb.md` §5](memory_and_ahb.md#5-hprot-and-hsmode--privilege-encoding) for the full rationale.

The core implements **physical S-mode** (no MMU), so S-mode code runs flat on the same address space as M-mode. The `satp` CSR is present as a WARL stub for spec conformance.

## RV32I Base Integer Instructions

### Arithmetic Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| ADD         | R-type | Add |
| SUB         | R-type | Subtract |
| ADDI        | I-type | Add immediate |
| LUI         | U-type | Load upper immediate |
| AUIPC       | U-type | Add upper immediate to PC |

### Logical Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| XOR         | R-type | Exclusive OR |
| OR          | R-type | OR |
| AND         | R-type | AND |
| XORI        | I-type | Exclusive OR immediate |
| ORI         | I-type | OR immediate |
| ANDI        | I-type | AND immediate |

### Shift Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| SLL         | R-type | Shift left logical |
| SRL         | R-type | Shift right logical |
| SRA         | R-type | Shift right arithmetic |
| SLLI        | I-type | Shift left logical immediate |
| SRLI        | I-type | Shift right logical immediate |
| SRAI        | I-type | Shift right arithmetic immediate |

### Compare Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| SLT         | R-type | Set less than (signed) |
| SLTU        | R-type | Set less than unsigned |
| SLTI        | I-type | Set less than immediate (signed) |
| SLTIU       | I-type | Set less than immediate unsigned |

### Branch Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| BEQ         | B-type | Branch if equal |
| BNE         | B-type | Branch if not equal |
| BLT         | B-type | Branch if less than (signed) |
| BGE         | B-type | Branch if greater or equal (signed) |
| BLTU        | B-type | Branch if less than unsigned |
| BGEU        | B-type | Branch if greater or equal unsigned |

### Jump Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| JAL         | J-type | Jump and link |
| JALR        | I-type | Jump and link register |

### Load Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| LB          | I-type | Load byte (sign-extended) |
| LH          | I-type | Load halfword (sign-extended) |
| LW          | I-type | Load word |
| LBU         | I-type | Load byte unsigned |
| LHU         | I-type | Load halfword unsigned |

### Store Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| SB          | S-type | Store byte |
| SH          | S-type | Store halfword |
| SW          | S-type | Store word |

### System Instructions

| Instruction | Format | Legal from | Description |
|-------------|--------|------------|-------------|
| ECALL       | I-type | M / S / U | Environment call (trap to handler) |
| EBREAK      | I-type | M / S / U | Environment break |
| FENCE       | I-type | M / S / U | Memory fence. Memory-to-memory ordering holds by construction, so a fence with no I/O bit set (`fence rw,rw`, `FENCE.TSO`, `PAUSE`) costs only its issue slot. A fence naming I/O additionally drains the data bus — see below. |
| FENCE.I     | I-type | M / S / U | Instruction-stream fence. Flushes the instruction buffer via a redirect to `PC+4`, and always drains outstanding data accesses first: instruction fetch uses a separate AHB bus, so the ordering `FENCE` gets for free does not apply here. A write to any `pmpcfg*` / `pmpaddr*` / `mseccfg*` CSR triggers the same refetch of the instruction after the CSR op. |
| MRET        | I-type | M | Machine-mode trap return (restores from `mepc`/`mstatus`). Illegal below M. |
| SRET        | I-type | M, S (unless `mstatus.TSR = 1`) | Supervisor-mode trap return (restores from `sepc`/`sstatus`). Illegal in U; raises illegal-instruction everywhere when `SU_MODE_EN == 0`. |
| WFI         | I-type | M, S (unless `mstatus.TW = 1`) | Wait for interrupt. Drops `hclk_en_o` when both AHB masters are drained, enabling SoC-level clock gating. Illegal in U (bounded time limit of 0 — see `spec_compliance_notes.md`). |
| MNRET       | I-type | M | NMI return (Smrnmi). Always present. Illegal below M. See [Smrnmi](#smrnmi--resumable-nmi-extension). |

**`FENCE` and the I/O bits.** The load/store unit issues in program order and AHB completes
a master's transfers in issue order, so every ordering `FENCE` is defined to provide already
holds without it. The argument bits therefore select cost, not correctness:

| encoding | behaviour |
|---|---|
| any of `PI`, `PO`, `SI`, `SO` set — including a bare `fence`, which assembles to `fence iorw,iorw` | holds dispatch until outstanding data accesses have completed on the AHB data bus |
| no I/O bit — `fence rw,rw`, `fence r,r`, `fence w,w`, `FENCE.TSO`, `PAUSE` | no drain |

### Control and Status Register (CSR) Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| CSRRW       | I-type | CSR read/write |
| CSRRS       | I-type | CSR read and set bits |
| CSRRC       | I-type | CSR read and clear bits |
| CSRRWI      | I-type | CSR read/write immediate |
| CSRRSI      | I-type | CSR read and set bits immediate |
| CSRRCI      | I-type | CSR read and clear bits immediate |

### Illegal-instruction rules

What raises illegal-instruction, beyond the privilege rules in the System table
(`arv_decode.v`; the spec posture for the permissive cases is in
[`spec_compliance_notes.md`](spec_compliance_notes.md)):

| Encoding | Behaviour |
|---|---|
| M encodings (`funct7 = 0000001`) with `M_EXTENSION = 0` | trap |
| `DIV` / `DIVU` / `REM` / `REMU` under Zmmul (`M_EXTENSION = 1`) | trap |
| `C.MUL` without M / Zmmul | trap |
| `C.SEXT.B` / `C.SEXT.H` / `C.ZEXT.H` without Zbb (`B_EXTENSION = 0`) | trap — these three depend on Zbb as well as Zcb; `C.ZEXT.B`, `C.NOT` and the Zcb loads/stores depend on Zcb only |
| Any 16-bit parcel (`inst[1:0] ≠ 11`) with `C_EXTENSION = 0` | trap |
| Zcmp with `rlist < 4` | trap (fails the decode match) |
| Reserved `LOAD` / `STORE` / `BRANCH` `funct3`, `SYSTEM funct3 = 100` | trap |
| Non-existent CSR (outside every implemented bank, or a gated bank whose gate is off) | trap |
| `sfence.vma` | trap in every configuration (no MMU) |
| Encodings of an absent B sub-extension (e.g. `SH1ADD` at `B_EXTENSION = 1`) | **no trap** — fall through to the base `funct3` op |
| Reserved `OP` / `OP-IMM` `funct7`, reserved `JALR funct3`, reserved `MISC-MEM funct3` | **no trap** — execute as the nearest defined op / NOP |
| RV32E: `x16`–`x31` as any operand | **no trap** — reads return 0, writes are dropped |
| Unimplemented CSR inside an implemented bank | **no trap** — RAZ/WI (see [Implemented CSR Registers](#implemented-csr-registers)) |

## M Extension — Integer Multiply/Divide

Enabled when `M_EXTENSION == 2`. The `MUL_TYPE` parameter selects the multiplier implementation (1-cycle / 4-cycle / 16-cycle); `DIV_TYPE` selects the divider radix (radix-8 / radix-4 / radix-2).

| Instruction | Format | Description |
|-------------|--------|-------------|
| MUL         | R-type | Multiply (lower 32 bits) |
| MULH        | R-type | Multiply high (signed × signed) |
| MULHSU      | R-type | Multiply high (signed × unsigned) |
| MULHU       | R-type | Multiply high (unsigned × unsigned) |
| DIV         | R-type | Divide (signed) |
| DIVU        | R-type | Divide unsigned |
| REM         | R-type | Remainder (signed) |
| REMU        | R-type | Remainder unsigned |

## Zmmul Extension — Integer Multiply Only

Enabled when `M_EXTENSION == 1`. Provides multiply without divide/remainder (useful when DIV area is unaffordable).

| Instruction | Format | Description |
|-------------|--------|-------------|
| MUL         | R-type | Multiply (lower 32 bits) |
| MULH        | R-type | Multiply high (signed × signed) |
| MULHSU      | R-type | Multiply high (signed × unsigned) |
| MULHU       | R-type | Multiply high (unsigned × unsigned) |

## B Extension — Bit Manipulation

Selected via `B_EXTENSION` (cumulative levels 0–4). Each sub-extension is additive on top of the previous one.

### Zbb — Basic Bit Manipulation

Enabled when `B_EXTENSION >= 1`.

| Instruction | Format | Description |
|-------------|--------|-------------|
| ANDN        | R-type | AND with inverted operand |
| ORN         | R-type | OR with inverted operand |
| XNOR        | R-type | Exclusive NOR |
| CLZ         | I-type | Count leading zeros |
| CTZ         | I-type | Count trailing zeros |
| CPOP        | I-type | Population count (number of set bits) |
| MAX         | R-type | Maximum (signed) |
| MAXU        | R-type | Maximum (unsigned) |
| MIN         | R-type | Minimum (signed) |
| MINU        | R-type | Minimum (unsigned) |
| SEXT.B      | I-type | Sign-extend byte |
| SEXT.H      | I-type | Sign-extend halfword |
| ZEXT.H      | R-type (rs2 field must be 0) | Zero-extend halfword |
| ROL         | R-type | Rotate left |
| ROR         | R-type | Rotate right |
| RORI        | I-type | Rotate right immediate |
| ORC.B       | I-type | Bitwise OR-combine, byte granule |
| REV8        | I-type | Byte-reverse (endian swap) |

### Zba — Address Generation

Enabled when `B_EXTENSION >= 2`.

| Instruction | Format | Description |
|-------------|--------|-------------|
| SH1ADD      | R-type | `rd = (rs1 << 1) + rs2` (shift-1 add) |
| SH2ADD      | R-type | `rd = (rs1 << 2) + rs2` (shift-2 add) |
| SH3ADD      | R-type | `rd = (rs1 << 3) + rs2` (shift-3 add) |

> The `.UW` variants (`ADD.UW`, `SH1ADD.UW`, etc., `SLLI.UW`) are RV64-only and are not included in the RV32 implementation.

### Zbs — Single-Bit Operations

Enabled when `B_EXTENSION >= 3`.

| Instruction | Format | Description |
|-------------|--------|-------------|
| BCLR        | R-type | Bit clear |
| BCLRI       | I-type | Bit clear immediate |
| BEXT        | R-type | Bit extract |
| BEXTI       | I-type | Bit extract immediate |
| BINV        | R-type | Bit invert |
| BINVI       | I-type | Bit invert immediate |
| BSET        | R-type | Bit set |
| BSETI       | I-type | Bit set immediate |

### Zbc — Carry-less Multiply

Enabled when `B_EXTENSION >= 4`.

| Instruction | Format | Description |
|-------------|--------|-------------|
| CLMUL       | R-type | Carry-less multiply (low half) |
| CLMULH      | R-type | Carry-less multiply (high half) |
| CLMULR      | R-type | Carry-less multiply (reversed) |

## C Extension — Compressed Instructions

Selected via `C_EXTENSION` (cumulative levels 0–4). All instructions are 16-bit and freely interleave with 32-bit base instructions.

### Zca — Base Compressed

Enabled when `C_EXTENSION >= 1`.

**Arithmetic and Logical:**

| Instruction | Format | Description |
|-------------|--------|-------------|
| C.ADDI4SPN  | CIW    | Add immediate scaled by 4 to SP (targets x8-x15) |
| C.ADDI      | CI     | Add immediate |
| C.ADDI16SP  | CI     | Add immediate scaled by 16 to SP |
| C.LI        | CI     | Load immediate |
| C.LUI       | CI     | Load upper immediate |
| C.SLLI      | CI     | Shift left logical immediate |
| C.SRLI      | CB     | Shift right logical immediate |
| C.SRAI      | CB     | Shift right arithmetic immediate |
| C.ANDI      | CB     | AND immediate |
| C.ADD       | CR     | Add |
| C.MV        | CR     | Move (copy register) |
| C.SUB       | CA     | Subtract |
| C.XOR       | CA     | Exclusive OR |
| C.OR        | CA     | OR |
| C.AND       | CA     | AND |
| C.NOP       | CI     | No operation |

**Load and Store:**

| Instruction | Format | Description |
|-------------|--------|-------------|
| C.LW        | CL     | Load word (base: x8-x15, dest: x8-x15) |
| C.LWSP      | CI     | Load word from stack (base: SP) |
| C.SW        | CS     | Store word (base: x8-x15, src: x8-x15) |
| C.SWSP      | CSS    | Store word to stack (base: SP) |

**Control Transfer:**

| Instruction | Format | Description |
|-------------|--------|-------------|
| C.J         | CJ     | Jump |
| C.JAL       | CJ     | Jump and link (RV32 only) |
| C.JR        | CR     | Jump register |
| C.JALR      | CR     | Jump and link register |
| C.BEQZ      | CB     | Branch if equal to zero |
| C.BNEZ      | CB     | Branch if not equal to zero |

**System:**

| Instruction | Format | Description |
|-------------|--------|-------------|
| C.EBREAK    | CR     | Environment break |

### Zcb — Compressed Code-Size Reduction

Enabled when `C_EXTENSION >= 2`.

**Load and Store (byte and halfword):**

| Instruction | Format | Description |
|-------------|--------|-------------|
| C.LBU       | CLB    | Load byte unsigned (base: x8-x15, dest: x8-x15) |
| C.LHU       | CLH    | Load halfword unsigned (base: x8-x15, dest: x8-x15) |
| C.LH        | CLH    | Load halfword (sign-extended) (base: x8-x15, dest: x8-x15) |
| C.SB        | CSB    | Store byte (base: x8-x15, src: x8-x15) |
| C.SH        | CSH    | Store halfword (base: x8-x15, src: x8-x15) |

**Sign/Zero Extension:**

| Instruction | Format | Description |
|-------------|--------|-------------|
| C.ZEXT.B    | CU     | Zero-extend byte (AND with 0xFF) |
| C.SEXT.B    | CU     | Sign-extend byte (requires Zbb — illegal-instruction at `B_EXTENSION = 0`) |
| C.ZEXT.H    | CU     | Zero-extend halfword (AND with 0xFFFF) (requires Zbb) |
| C.SEXT.H    | CU     | Sign-extend halfword (requires Zbb) |

**Arithmetic and Logical:**

| Instruction | Format | Description |
|-------------|--------|-------------|
| C.NOT       | CU     | Bitwise NOT (XOR with -1) |
| C.MUL       | CA     | Multiply low (requires M or Zmmul) |

### Zcmp — Compressed Push/Pop/Moves

Enabled when `C_EXTENSION >= 3`. These instructions execute as multi-cycle micro-op sequences (handled by the UOP sequencer in `arv_uop_sequencer.v`).

| Instruction | Format | Description |
|-------------|--------|-------------|
| CM.PUSH     | CMPP   | Push a register list to the stack |
| CM.POP      | CMPP   | Pop a register list from the stack |
| CM.POPRET   | CMPP   | Pop a register list and return (load `ra`, then JALR x0, ra) |
| CM.POPRETZ  | CMPP   | `POPRET` and additionally zero `a0` (for void returns) |
| CM.MVA01S   | CMMV   | Move two `s` registers to `a0`/`a1` (in a single micro-op pair) |
| CM.MVSA01   | CMMV   | Move `a0`/`a1` to two `s` registers (in a single micro-op pair) |

`CM.PUSH` / `CM.POP` take N memory cycles (N = `rlist` − 3, or 13 for `rlist` = 15) plus one
SP-update cycle; `CM.POPRET` / `CM.POPRETZ` one more for the return. `rlist` 0–3 is reserved
and raises illegal-instruction. `CM.MVA01S` / `CM.MVSA01` take 2 ALU cycles. An IRQ (or
NMI) that arrives while a `CM.PUSH`/`CM.POP*` still has a memory op ahead stops the sequence
issuing; once the access already on the bus completes, the sequence is killed and restarts
from scratch (`mepc` = its own PC), which is safe because `sp` is written last. Arriving
later (last memory op, SP update, return), during `CM.MVA01S`/`CM.MVSA01` or a Zcmt table
jump, or with the kill disabled (`marv_ctl[1]` = 0), the interrupt waits for the sequence
to complete.

### Zcmt — Compressed Table Jumps

Enabled when `C_EXTENSION >= 4`. Implements indirect-jump dispatch through a jump table whose base address is held in the `jvt` CSR (address 0x017, `BASE[31:6]` only — 64-byte aligned, `MODE` read-only 0).

| Instruction | Format | Description |
|-------------|--------|-------------|
| CM.JT       | CMJT   | Jump-table jump: `PC ← Mem32[jvt.BASE + index × 4]` with bit 0 cleared (`index` 0–31) |
| CM.JALT     | CMJT   | Jump-and-link via jump table (`index` 32–255; same dispatch as `CM.JT`, returns to `ra`) |

The table read is a data-bus access but is PMP-checked as an **instruction fetch**: X
permission at the current privilege, never under MPRV, and a denial reports cause 1
(instruction access fault) with the `cm.jt` PC. A data-bus error during the read is the
non-resumable `cm.jt` case of `spec_compliance_notes.md`.

## Smrnmi — Resumable NMI Extension

Smrnmi is always present. It provides resumable NMI handling with dedicated CSRs
and a return instruction (`MNRET`).

`mncause` identifies why the RNMI handler was entered:

| `mncause` | Source |
|---|---|
| `0x8000_0002` | external RNMI input pin |
| `0x8000_0003` | data-bus error (load or store). Instruction-bus errors are unaffected and remain a synchronous `mcause=1`. |
| `0x0000_00cc` | Smdbltrp double trap diverted to the RNMI handler (bit 31 clear; `cc` = cause code of the trap that was doubled, 16 for a doubled Ssdbltrp trap) |

The pin wins if both are pending; the bus error stays pending and is delivered next.

| Element | Detail |
|---------|--------|
| Trigger | Level-sensitive `nmi_i` input (no internal synchronizer — drive synchronous to `hclk_i`) |
| Vector | Loaded from `marv_nmvec` (CSR 0x7FD) at trap entry |
| Return | `MNRET` (restores from `mnepc`/`mnstatus`) |
| Preemption | NMI preempts any current privilege level and any pending standard IRQ |

See [`integration_guide.md` §6](integration_guide.md#6-nmi-interface-smrnmi) for the pin-level integration requirements.

## Instruction Format Legend

**Base (32-bit) formats:**

- **R-type**: Register-register operations (opcode, rd, funct3, rs1, rs2, funct7)
- **I-type**: Immediate operations and loads (opcode, rd, funct3, rs1, imm[11:0])
- **S-type**: Store operations (opcode, imm[4:0], funct3, rs1, rs2, imm[11:5])
- **B-type**: Branch operations (opcode, imm[11], imm[4:1], funct3, rs1, rs2, imm[12|10:5])
- **U-type**: Upper immediate operations (opcode, rd, imm[31:12])
- **J-type**: Jump operations (opcode, rd, imm[20|10:1|11|19:12])

**Compressed (16-bit) formats:**

- **CR**: Register (opcode, rs2, rd/rs1, funct4)
- **CI**: Immediate (opcode, imm, rd/rs1, funct3)
- **CSS**: Stack-relative store (opcode, rs2, imm, funct3)
- **CIW**: Wide immediate (opcode, rd', imm, funct3)
- **CL**: Load (opcode, rd', imm, rs1', funct3)
- **CS**: Store (opcode, rs2', imm, rs1', funct3)
- **CA**: Arithmetic (opcode, rs2', rd'/rs1', funct6, funct2)
- **CB**: Branch/immediate (opcode, offset, rd'/rs1', funct3)
- **CJ**: Jump (opcode, jump_target, funct3)
- **CLB** / **CLH**: Zcb byte / halfword load (opcode, rd', uimm, rs1', funct6)
- **CSB** / **CSH**: Zcb byte / halfword store (opcode, rs2', uimm, rs1', funct6)
- **CU**: Zcb unary (opcode, funct5, rd'/rs1', funct6)
- **CMPP**: Zcmp push/pop (opcode, spimm, rlist, funct6)
- **CMMV**: Zcmp register-pair move (opcode, r2s', funct2, r1s', funct6)
- **CMJT**: Zcmt table jump (opcode, index, funct6)

Compressed instructions with register primes (`rd'`, `rs1'`, `rs2'`) can only access registers x8–x15.

## Implemented CSR Registers

Access type codes: **MRW** = Machine read-write; **MRO** = Machine read-only; **SRW** = Supervisor read-write (M can also access); **URW** = User read-write; **URO** = User read-only; **DRW** = Debug-Mode read-write, reached only over the external Debug Module abstract-command port — a hart `csrrw`/`csrrs` to these addresses raises illegal-instruction. **W1C** marks a bit cleared by writing 1.

CSRs are decoded by 64-entry bank (`addr[11:6]`) in `arv_csr_top.v`, bounded at the highest implemented offset of each bank. An address outside every implemented bank, or above a bank's bound, raises illegal-instruction (`stimecmp` 0x14D traps as required); an unimplemented CSR *below* the bound of an implemented bank reads 0 and ignores writes — the posture is recorded in [`spec_compliance_notes.md`](spec_compliance_notes.md#non-existent-csrs-in-known-banks-read-as-0-razwi-do-not-trap). A bank whose gate parameter is off (`SU_MODE_EN`, `ZICNTR_EN`, `ZIHPM_NR`, `PMP_NR`, `C_EXTENSION ≥ 4`, `DM_TRIGGER_NR`) is absent, not RAZ/WI.

### Machine-Level Trap Setup and Handling

| Address | Name      | Access | Description |
|---------|-----------|--------|-------------|
| 0x300   | mstatus   | MRW    | Machine status. Live fields: SIE, MIE, SPIE, MPIE, SPP, MPP, MPRV, SUM, MXR, TVM, TW, TSR, SDT; FS/VS/XS read 0 (no F/D unit) |
| 0x301   | misa      | MRW    | ISA & extensions (WARL — writes ignored in aRVern); derivation below |
| 0x302   | medeleg   | MRW    | Machine exception delegation to S-mode (absent when `SU_MODE_EN == 0`) |
| 0x303   | mideleg   | MRW    | Machine interrupt delegation to S-mode (absent when `SU_MODE_EN == 0`) |
| 0x304   | mie       | MRW    | Machine interrupt-enable |
| 0x305   | mtvec     | MRW    | Machine trap-handler base address. `MODE` 0 (direct) and 1 (vectored) implemented; ≥ 2 WARL-rejected |
| 0x30A   | menvcfg   | MRW    | RAZ/WI; absent when `SU_MODE_EN == 0` |
| 0x310   | mstatush  | MRW    | High half of `mstatus` (RV32-only). WARL. Bit 10 is Smdbltrp's `MDT`, **resets to 1** — while set, a trap into M is a double trap and `mstatus.MIE` cannot be set. Writing `MDT=1` clears `MIE`. All other bits read 0 |
| 0x312   | medelegh  | MRW    | RAZ/WI |
| 0x31A   | menvcfgh  | MRW    | High half of `menvcfg` (RV32-only). Only `DTE` (bit 27, Ssdbltrp double-trap enable) is live and **resets to 1**; absent when `SU_MODE_EN == 0` |
| 0x340   | mscratch  | MRW    | Machine scratch register |
| 0x341   | mepc      | MRW    | Machine exception PC |
| 0x342   | mcause    | MRW    | Machine trap cause |
| 0x343   | mtval    | MRW    | Machine bad address or instruction |
| 0x344   | mip       | MRW    | Machine interrupt pending |
| 0x34A   | mtinst    | MRW    | RAZ/WI |
| 0x34B   | mtval2    | MRW    | Machine second trap value (Ssdbltrp: original cause code on a double trap). RAZ/WI when `SU_MODE_EN == 0` |

**`misa` derivation.** `misa` follows the spec's all-or-nothing extension
definitions (`arv_csr_ids.v`); partial B levels, Zmmul and the multiplier /
divider type are discovered through `marv_cfg` (0xFFF) — `B_EXTENSION` [22:20],
`mul_type` [19:18], `div_type` [17:16].

| `misa` bit | Set when | Note |
|---|---|---|
| `MXL` [31:30] | always `01` | RV32 |
| `B` (bit 1) | `B_EXTENSION ≥ 3` | the ratified B extension is exactly Zba + Zbb + Zbs (Unpriv ch. 29); Zbb alone or Zbc do not affect it |
| `C` (bit 2) | `C_EXTENSION ≥ 1` | |
| `E` / `I` (bits 4 / 8) | `RV32E_EN = 1` / `RV32E_EN = 0` | mutually exclusive |
| `M` (bit 12) | `M_EXTENSION = 2` | Zmmul is the multiplication subset of M (Unpriv §12.3) and does not set it |
| `S` / `U` (bits 18 / 20) | `SU_MODE_EN = 1` | |
| `X` (bit 23) | never | `CCSR_EN` does not set it |

### PMP / Smepmp CSRs

Present when `PMP_NR != 0` (4, 8 or 16 writable entries; other values snap down
to the next legal count). When `PMP_NR = 0` the whole set raises
illegal-instruction. Sixteen entries always exist architecturally; entries at or
above `PMP_NR` are read-only zero. Granularity `G = 0`, so NA4 is selectable;
`pmpaddr[33:32]` read as zero. State lives in `arv_csr_pmp.v`; the matchers are
in the LSU and fetch unit (`arv_pmp_check.v`). A write to any of these CSRs
triggers a `FENCE.I`-style refetch of the following instruction.

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| 0x3A0–0x3A3 | pmpcfg0–3 | MRW | Entry configuration bytes (`L`, `A`, `X`, `W`, `R`); locked entries are read-only until reset |
| 0x3B0–0x3BF | pmpaddr0–15 | MRW | Entry address (`addr[33:2]`, `[31:30]` read 0: 32-bit physical space); a locked TOR entry also locks the preceding `pmpaddr`. TOR's exclusive top cannot reach 2^32, so a region ending at the top of memory uses NAPOT |
| 0x747 | mseccfg | MRW | Smepmp: `MML` and `MMWP` are sticky-set (clear only at reset); `RLB` is stuck clear once any entry is locked. With `MML = 1` a write that would create an M-mode-executable entry is dropped per entry |
| 0x757 | mseccfgh | MRW | RAZ/WI |

### Machine Information Registers

| Address | Name       | Access | Description |
|---------|------------|--------|-------------|
| 0xF11   | mvendorid  | MRO    | Vendor ID — **`0x0000_08FB`**, Arvern Silicon's JEDEC JEP106 ID; core-owned constant in `arv_csr_ids.v` |
| 0xF12   | marchid    | MRO    | Architecture ID — **54** (`0x36`), allocated to aRVern in the RISC-V International open-source registry |
| 0xF13   | mimpid     | MRO    | Implementation version: `{major, minor, patch}`, one byte each (see below). Build configuration lives in `marv_cfg` @0xFFF |
| 0xF14   | mhartid    | MRO    | Hardware thread ID (from `hartid_i`) |
| 0xF15   | mconfigptr | MRO    | Configuration pointer — reads 0 (no configuration structure) |

**`mimpid` bit layout.** `mimpid` is architecturally an *implementation version*
register and carries nothing else. One byte per component, so the register reads
as the version directly — `0x0100_0000` is v1.0.0, `0x0102_0300` would be v1.2.3.

| Bits | Field | Meaning |
|:---:|---|---|
| `[31:24]` | `MAJOR` | 0–255 |
| `[23:16]` | `MINOR` | 0–255 |
| `[15:8]` | `PATCH` | 0–255 |
| `[7:0]` | *reserved* | read-only zero |

Set via the `RTL_VERSION` localparam in `arvern.v`.

### Counter / Timer CSRs (Zicntr)

Present when `ZICNTR_EN == 1`. The user-mode shadows are read-only views of the machine counters, gated by `mcounteren` / `scounteren`. When `ZICNTR_EN == 0` these CSRs are absent: with `ZIHPM_NR == 0` too, the whole 0xB00 / 0xB80 / 0xC00 / 0xC80 windows raise illegal-instruction; with `ZIHPM_NR > 0` the windows exist for the HPM counters and `mcycle` / `minstret` / `cycle` / `time` / `instret` read 0.

| Address | Name      | Access | Description |
|---------|-----------|--------|-------------|
| 0xB00   | mcycle    | MRW    | Cycle counter (low 32 bits) |
| 0xB02   | minstret  | MRW    | Retired instructions (low 32 bits) |
| 0xB80   | mcycleh   | MRW    | Cycle counter (high 32 bits) |
| 0xB82   | minstreth | MRW    | Retired instructions (high 32 bits) |
| 0xC00   | cycle     | URO    | Cycle counter (low 32 bits) |
| 0xC01   | time      | URO    | Wall-clock time (low 32 bits) — sourced via `time_req_o`/`time_gnt_i`/`time_val_i` |
| 0xC02   | instret   | URO    | Retired instructions (low 32 bits) |
| 0xC80   | cycleh    | URO    | Cycle counter (high 32 bits) |
| 0xC81   | timeh     | URO    | Wall-clock time (high 32 bits) |
| 0xC82   | instreth  | URO    | Retired instructions (high 32 bits) |

### Hardware Performance Counters (Zihpm)

Present when `ZIHPM_NR > 0`. `ZIHPM_NR` (0–8) selects how many of the mhpmcounter3–10 / mhpmevent3–10 banks are physically implemented. Two-case absence rule: at `ZIHPM_NR = 0` the extension is absent and every `mhpmcounter*` / `mhpmevent*` access raises illegal-instruction; at `ZIHPM_NR > 0` the whole set exists and the unprovided counters (index > `ZIHPM_NR` + 2, up to 31) are read-only zero, not absent (Priv §3.1.10).

| Address range | Name (range) | Access | Description |
|---------------|--------------|--------|-------------|
| 0xB03–0xB0A   | mhpmcounter3–10  | MRW | HPM event counters (low 32 bits) |
| 0xB83–0xB8A   | mhpmcounterh3–10 | MRW | HPM event counters (high 32 bits) |
| 0x323–0x32A   | mhpmevent3–10    | MRW | Per-counter event selector (encoding below) |
| 0xC03–0xC0A   | hpmcounter3–10   | URO | User-mode shadows (gated by `mcounteren` from S/U, and also by `scounteren` from U) |
| 0xC83–0xC8A   | hpmcounterh3–10  | URO | User-mode shadows (gated by `mcounteren` from S/U, and also by `scounteren` from U) |

#### `mhpmevent3–10` event-selector encoding

Each `mhpmeventN` register's low bits select which event drives the matching
`mhpmcounterN`. Decoded in `rtl/verilog/arv_csr_hpm.v` (`hpm_event_pulse`
mux); a pulse on the selected source increments the counter on the next
clock. Encodings outside the table are reserved (counter stays 0).

| `mhpmeventN` value | Event source | Description |
|:--:|---|---|
| `0x00` | *(none)* | Counter disabled — no event ever pulses |
| `0x01` | `fetch stall` | Cycles the instruction fetch stage was stalled (wait state / fetch buffer drained mid-stream / branch redirect) |
| `0x02` | `LSU stall` | Cycles the load/store unit was busy in EX waiting for the data AHB to accept the transfer |
| `0x03` | `ALU stall` | Cycles the ALU was busy (multi-cycle MUL or DIV in flight) |
| `0x04` | `CSR stall` | Cycles a CSR access was blocked in EX (typically WFI sleep) |
| `0x05` | `branch taken` | Conditional branch (BEQ/BNE/BLT/BGE/BLTU/BGEU, C.BEQZ/C.BNEZ) dispatched and resolved taken; unconditional jumps (JAL/JALR/C.J/C.JAL/C.JR/C.JALR) are not counted |
| `0x06` | `branch not taken` | Conditional branch resolved not-taken |
| `0x07` | `load` | Every LOAD-class dispatch (`LB`/`LH`/`LW`/`LBU`/`LHU`, `C.LW`/`C.LWSP`, Zcb `C.LBU`/`C.LHU`/`C.LH`); the memory micro-ops of `CM.POP*` and the `CM.JT` table read are not counted |
| `0x08` | `store` | Every STORE-class dispatch (`SB`/`SH`/`SW`, `C.SW`/`C.SWSP`, Zcb `C.SB`/`C.SH`); the memory micro-ops of `CM.PUSH` are not counted |
| `0x09` | `exception` | Every trap entry that is not a standard interrupt — synchronous exceptions **and RNMIs**. The Smdbltrp critical-error entry is not counted (it updates no architectural state) |
| `0x0A` | `interrupt` | Every standard (`mip`-sourced) interrupt entry; RNMIs count under `0x09` |
| `0x0B` | `platform_events_i[0]` | Integrator-defined external event #0 (`hpm_platform_events_i[0]`) |
| `0x0C` | `platform_events_i[1]` | Integrator-defined external event #1 |
| `0x0D` | `platform_events_i[2]` | Integrator-defined external event #2 |
| `0x0E` | `platform_events_i[3]` | Integrator-defined external event #3 |
| `0x0F` | `platform_events_i[4]` | Integrator-defined external event #4 |
| `0x10` | `platform_events_i[5]` | Integrator-defined external event #5 |
| `0x11` | `platform_events_i[6]` | Integrator-defined external event #6 |
| `0x12` | `platform_events_i[7]` | Integrator-defined external event #7 |

> Any write outside the table (a bit set in `[31:5]`, or `[4:0]` > `0x12`) is
> WARL-folded to 0 — the counter is then disabled and a read-back shows 0. The
> integrator wires `hpm_platform_events_i[7:0]` to SoC-level events of their
> choice (cache miss, DMA done, GPIO toggle, etc.); the bits are level-sampled
> every `hclk_i` cycle — a one-cycle pulse adds 1, a level adds 1 per cycle —
> see [`integration_guide.md` §9](integration_guide.md#9-hpm-platform-events).
> Pure firmware self-instrumentation (selectors `0x01`–`0x0A`) needs
> no SoC support — just `csrw mhpmeventN, <code>` and read the
> matching `mhpmcounterN` later.

### Counter Setup CSRs

| Address | Name          | Access | Description |
|---------|---------------|--------|-------------|
| 0x306   | mcounteren    | MRW    | Enable user-mode counter access (Zicntr + Zihpm); absent when `SU_MODE_EN == 0` |
| 0x320   | mcountinhibit | MRW    | Stop individual counter increment |

### Supervisor-Level CSRs

Present when `SU_MODE_EN == 1`. S-mode trap-handling registers and per-mode shadows of `mstatus`/`mie`/`mip`. The `satp` register is a WARL stub (aRVern is physical S-mode — no paged MMU). **When `SU_MODE_EN == 0`, every register in this section is absent** — an access raises illegal-instruction, as the whole 0x100/0x140/0x180 bank is dropped from the CSR decode.

| Address | Name       | Access | Description |
|---------|------------|--------|-------------|
| 0x100   | sstatus    | SRW    | Supervisor status (shadow of mstatus's S-visible fields, incl. `SDT`) |
| 0x104   | sie        | SRW    | Supervisor interrupt enable (mideleg-masked) |
| 0x105   | stvec      | SRW    | Supervisor trap-handler base address. `MODE` 0 (direct) and 1 (vectored) implemented; ≥ 2 WARL-rejected |
| 0x106   | scounteren | SRW    | Enable user-mode counter access from S-mode |
| 0x10A   | senvcfg    | SRW    | RAZ/WI |
| 0x140   | sscratch   | SRW    | Supervisor scratch register |
| 0x141   | sepc       | SRW    | Supervisor exception PC |
| 0x142   | scause     | SRW    | Supervisor trap cause |
| 0x143   | stval      | SRW    | Supervisor bad address or instruction |
| 0x144   | sip        | SRW    | Supervisor interrupt pending (mideleg-masked) |
| 0x180   | satp       | SRW    | Address-translation/protection — WARL stub: reads 0 (`MODE` = Bare), writes ignored; an S-mode access with `mstatus.TVM = 1` raises illegal-instruction |

### Resumable NMI CSRs (Smrnmi)

Always present — Smrnmi is unconditional.

| Address | Name      | Access | Description |
|---------|-----------|--------|-------------|
| 0x740   | mnscratch | MRW    | NMI scratch register |
| 0x741   | mnepc     | MRW    | NMI exception PC (target of `MNRET`) |
| 0x742   | mncause   | MRO    | NMI cause (written by hardware on RNMI entry only; a CSR write is ignored, no trap) |
| 0x744   | mnstatus  | MRW    | NMI status (priv level, NMIE) |

### External Debug CSRs (Sdext / Sdtrig)

Present when `DEBUG_EN == 1` (RISC-V Debug Spec 1.0, frozen-hart model). These CSRs split into two access classes with very different reachability:

**Sdtrig trigger CSRs** — additionally require `DM_TRIGGER_NR > 0` (1–8 hardware triggers). These *are* reachable from M-mode via ordinary CSR instructions (bank `0x7A0-0x7A5`, decoded in `arv_debug_trigger.v`); with `DM_TRIGGER_NR = 0` the bank is absent and raises illegal-instruction.

| Address | Name     | Access | Description |
|---------|----------|--------|-------------|
| 0x7A0   | tselect  | MRW    | Trigger select — WARL index, clamped to `DM_TRIGGER_NR − 1` |
| 0x7A1   | tdata1   | MRW    | Trigger data 1 (`mcontrol6`; WARL-canonicalised). Read-only to the hart while the selected trigger's `dmode = 1` (a debugger-owned trigger); firmware-owned triggers stay writable. `s`/`u` read 0 when `SU_MODE_EN = 0`; data-value match (`select = 1`) is WARL 0 |
| 0x7A2   | tdata2   | MRW    | Trigger data 2 (match value); same hart-write gating as `tdata1` |
| 0x7A3   | tdata3   | MRW    | Trigger data 3 — RAZ/WI (not implemented) |
| 0x7A4   | tinfo    | MRO    | Trigger info — supported-type bitmask |
| 0x7A5   | tcontrol | MRW    | Trigger control (`mte`/`mpte` in-handler re-trigger guard) |

**Debug-Mode CSRs** — `dcsr` / `dpc` / `dscratch0` / `dscratch1` are **Debug-Mode-only**: they are reached exclusively over the external Debug Module abstract-command port, *not* via `csrrw`/`csrrs` from the hart. A general (M-mode or lower) CSR access to these addresses raises illegal-instruction (their `register_select` bits are excluded from the hart's `any_bank_known` decode in `arv_csr_top.v`). Owned by `arv_csr_debug.v`.

| Address | Name      | Access | Description |
|---------|-----------|--------|-------------|
| 0x7B0   | dcsr      | DRW    | Debug control/status (`ebreakm`/`s`/`u`, `step`, `stepie`, `stopcount`, `stoptime`, `cause`, `prv`) |
| 0x7B1   | dpc       | DRW    | Debug PC — resume address |
| 0x7B2   | dscratch0 | DRW    | Debug scratch 0 — not implemented (no Program Buffer); abstract access fails with `cmderr=3` |
| 0x7B3   | dscratch1 | DRW    | Debug scratch 1 — not implemented; abstract access fails with `cmderr=3` |

### aRVern-Specific Built-in CSRs

Seven non-standard CSRs that live in the M-mode custom address ranges
(`0x7C0-0x7FF` RW, `0xFC0-0xFFF` RO) and are decoded inside the core
itself rather than going through the external `ccsr_*` port group.
Always present (the addresses are reserved by the core regardless of
`CCSR_EN`, so the custom-CSR interface cannot alias them).

| Address | Name          | Access | Gated by   | Description |
|---------|---------------|--------|------------|-------------|
| 0x7FE   | `marv_estat`  | MRW    | *always*   | Data-bus-error status: `{restartable[3], uop_sourced[4], store[1], overrun[2], valid[0]}`. `valid` and `overrun` are **W1C** (write `0x5` to clear); the rest are read-only. First-fault-wins — a second error while `valid` is set sets `overrun` and leaves the captured evidence intact. Internal CSR (independent of `CCSR_EN`). |
| 0x7FD   | `marv_nmvec`  | MRW    | *always*   | RNMI handler base address (32-bit, 4-byte aligned; `[1:0]` read-only zero). **Resets to `reset_vector_i + 4`**, the slot after the reset entry and ahead of `mtvec` (+8) and `stvec` (+12). Firmware-writable, so a hart can place its own RNMI handler — which, under Smdbltrp, is also its double-trap handler. Internal CSR (independent of `CCSR_EN`). |
| 0x7FF   | `marv_ctl`    | MRW    | *always*   | aRVern core feature-control — 4 bits at `[3:0]` (`[31:4]` WARL-zero): `[0]` IRQ-kill of an in-flight MUL/DIV, `[1]` IRQ-kill of an in-flight Zcmp push/pop, `[2]` livelock protection after `MRET`/`MNRET`, `[3]` WFI clock-gating disable. Internal CSR (independent of `CCSR_EN`). Reset = `4'b0111`. Bit table in [`traps_and_interrupts.md` §9](traps_and_interrupts.md#9-core-feature-control-marv_ctl). |
| 0xFFC   | `marv_epc`    | MRO    | *always*   | PC of the access that took a data-bus error — **what faulted**, as distinct from `mnepc` (where to resume). Latched on the faulting access's own address phase, so it cannot disagree with `marv_eaddr`. |
| 0xFFD   | `marv_eaddr`  | MRO    | *always*   | Address that took the data-bus error. Latched with `marv_epc`. |
| 0xFFE   | `reset_vector`| MRO    | *always*   | Reset PC (32-bit). Read-only mirror of the integrator-driven `reset_vector_i` input port — firmware can read it to discover its own reset vector. Internal CSR (independent of `CCSR_EN`). |
| 0xFFF   | `marv_cfg`    | MRO    | *always*   | Build-configuration discovery word: extension levels, multiplier/divider type, counter and trigger counts, and presence flags. See the field table below. Internal CSR (independent of `CCSR_EN`). |

These CSRs are decoded directly in `arv_csr_top.v` and are masked out of the
`ccsr_reg_sel_o` one-hot fan-out, so a CCSR peripheral cannot accidentally see or
capture writes to any of the seven: 0x7FD (`marv_nmvec`), 0x7FE (`marv_estat`),
0x7FF (`marv_ctl`), 0xFFC (`marv_epc`), 0xFFD (`marv_eaddr`), 0xFFE
(`reset_vector`) and 0xFFF (`marv_cfg`).

**`marv_cfg` (0xFFF) bit layout.** The synthesized build configuration, at finer
granularity than `misa` can express — software reads it once at boot to discover
which extensions, multiplier/divider, counters and debug resources are present
without probing CSRs for traps. All fields are synthesis-time constants.

| Bits | Field | Encoding |
|:---:|---|---|
| `[31:28]` | *reserved* | |
| `[27]` | *reserved* | widens `C_EXTENSION` upward |
| `[26:24]` | `C_EXTENSION` | 0=none, 1=Zca, 2=+Zcb, 3=+Zcmp, 4=+Zcmt |
| `[23]` | *reserved* | widens `B_EXTENSION` upward |
| `[22:20]` | `B_EXTENSION` | 0=none, 1=Zbb, 2=+Zba, 3=+Zbs, 4=+Zbc |
| `[19:18]` | `mul_type` | 0=none, 1=single-cycle, 2=four-cycle, 3=sixteen-cycle |
| `[17:16]` | `div_type` | 0=none, 1=radix-8 (12-cyc), 2=radix-4 (17-cyc), 3=radix-2 (33-cyc) |
| `[15:12]` | `ZIHPM_NR` | 0–8 `mhpmcounter3–10` |
| `[11:8]` | `DM_TRIGGER_NR` | 0–8 Sdtrig triggers (0 when `DEBUG_EN=0`) |
| `[7:6]` | `PMP_NR` | writable PMP entries: 0=none, 1=4, 2=8, 3=16 (Smepmp included when non-zero) |
| `[5]` | `SINGLE_CYCLE_BRANCH` | 1 = zero-bubble taken branch |
| `[4]` | `ASYNC_RST_EN` | 1 = asynchronous reset |
| `[3]` | `ZICNTR_EN` | `cycle` / `time` / `instret` present |
| `[2]` | `SU_MODE_EN` | S+U privilege modes present |
| `[1]` | `DEBUG_EN` | Sdext DM/DTM present |
| `[0]` | `CCSR_EN` | custom-CSR interface present |

One semantic owner per nibble, so a hex dump decodes by eye:

| digit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| | *reserved* | C level | B level | mul/div | HPM count | trigger count | PMP + microarch | presence flags |

`0x0447_14ff` is therefore C=4 (Zcmt), B=4 (Zbc), mul=1/div=3, one HPM counter,
four triggers, 16 PMP regions, single-cycle branch + async reset, and all four
presence flags set.

`PMP_NR` reports the number of **writable** entries. Sixteen always exist
architecturally; a smaller build hardwires the surplus to read-only zero, which
Priv §3.7.1 permits (*"All PMP CSR fields are WARL and may be read-only zero"*) and
which §3.7.1.1 makes behaviourally identical to absent. Software can also probe the
count directly by writing a non-zero `A` to each `pmpcfg` and reading it back.
Digit 7 of the word is reserved as a whole nibble and reads zero, so allocating it
later is a compatible change.

> **Reserved bits sit ABOVE the field they extend.** A value field widens upward,
> so every published encoding keeps its bit position. A reserved bit placed
> *below* would move the LSB when absorbed, silently changing the meaning of
> every value already in the field.

> `marv_cfg` is defined only for cores that `marchid` identifies as aRVern. A
> core without it reads `0x00000000` from 0xFFF — which is also a legal
> `marv_cfg` value for a minimal build, so the register cannot self-identify.

> The `mul_type` / `div_type` fields read `0` when the multiplier / divider is
> absent (`M_EXTENSION = 0`, or `M_EXTENSION = 1` Zmmul which has a multiplier
> but no divider). The encoding is defined in `arv_csr_ids.v`.

### Zcmt CSR

Present when `C_EXTENSION >= 4`; otherwise absent (illegal-instruction).

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| 0x017   | jvt  | URW    | Jump-vector-table base for `CM.JT` / `CM.JALT`: `BASE[31:6]` writable (64-byte aligned), `MODE[5:0]` read-only 0. User-level CSR, accessible from every privilege |

## Total Instruction Count

| Group | Count |
|-------|------:|
| RV32I (40) + Zicsr (6)               |  46 |
| System (MRET/SRET/MNRET/WFI/FENCE.I) |  +5 |
| M / Zmmul                            |  8 / 4 |
| Zbb                                  |  18 |
| Zba (RV32 subset)                    |  3  |
| Zbs                                  |  8  |
| Zbc                                  |  3  |
| Zca                                  |  27 |
| Zcb                                  |  11 |
| Zcmp                                 |  6  |
| Zcmt                                 |  2  |

**Maximum total** (all extensions enabled): **137 instructions** (RV32I 46 + system 5 + M 8 + full B 32 + full C 46).

## Reference

For detailed instruction encodings and behaviour:

- RISC-V Unprivileged Specification — [`specs/riscv-unprivileged.pdf`](specs/riscv-unprivileged.pdf)
- RISC-V Privileged Specification — [`specs/riscv-privileged.pdf`](specs/riscv-privileged.pdf)
- [`integration_guide.md`](integration_guide.md) — parameter reference, ports, CSR-bank semantics
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — implementation choices in UNSPECIFIED / implementation-defined cases + a few acknowledged gray-area choices
- [`simulation_guide.md`](simulation_guide.md) — how to build, run, and benchmark
