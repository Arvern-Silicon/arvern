<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Supported Instructions
  <br clear="all">
</h1>

This document lists all instructions and CSRs supported by the aRVern RISC-V processor core, indexed by extension. Parameter names and defaults are the canonical ones from `rtl/verilog/arvern.v`; see [`integration_guide.md`](integration_guide.md#1-configuration-parameters) for the full parameter reference.

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
  - [Machine Information Registers](#machine-information-registers)
  - [Counter / Timer CSRs (Zicntr)](#counter--timer-csrs-zicntr)
  - [Hardware Performance Counters (Zihpm)](#hardware-performance-counters-zihpm)
  - [Counter Setup CSRs](#counter-setup-csrs)
  - [Supervisor-Level CSRs](#supervisor-level-csrs)
  - [Resumable NMI CSRs (Smrnmi)](#resumable-nmi-csrs-smrnmi)
  - [aRVern-Specific Built-in CSRs](#arvern-specific-built-in-csrs)
  - [Zcmt CSR](#zcmt-csr)
- [Total Instruction Count](#total-instruction-count)
- [Reference](#reference)

## Configuration

The processor supports the instruction set extensions and privilege features listed below, each gated by a top-level RTL parameter (see [`integration_guide.md` §1](integration_guide.md#1-configuration-parameters) for the full parameter reference). For measured performance, area, and code-size impact of each combination, see [`characterization_guide.md` §2 onward](characterization_guide.md#2-area-results).

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
| **Zcmt** | `C_EXTENSION = 4` | Compressed table jumps |
| **Zicntr** | `ZICNTR_EN = 1` | Cycle / time / instret counters |
| **Zihpm** | `ZIHPM_NR > 0` (0–8 counters) | Hardware performance monitor |
| **Smrnmi** | `NMI_EN = 1` | Resumable NMI (`MNRET`) |
| **S-mode** | `SU_MODE_EN = 1` | Supervisor mode + full trap delegation |
| **U-mode** | `SU_MODE_EN = 1` | User mode |

## Privilege Modes

| Mode | MPP/SPP encoding | HPROT[1]/HSMODE encoding | Always present? | Notes |
|------|------------------|--------------------------|------------------|-------|
| Machine (M) | `2'b11` | `2'b10` | Yes | Top privilege, all CSRs accessible |
| Supervisor (S) | `2'b01` | `2'b11` | `SU_MODE_EN = 1` | Physical S-mode: full trap delegation (`mideleg`/`medeleg`), `SRET`, `sstatus`/`sie`/`sip` masked by `mideleg`, `scounteren`, `satp` is a WARL stub (no paged MMU). When `SU_MODE_EN = 0`, all S-mode CSRs RAZ/WI and `SRET`/`SFENCE.VMA` raise illegal-instruction. |
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

| Instruction | Format | Description |
|-------------|--------|-------------|
| ECALL       | I-type | Environment call (trap to handler) |
| EBREAK      | I-type | Environment break |
| FENCE       | I-type | Memory fence. In aRVern, implemented as a pipeline stall until all outstanding LOAD/STORE transactions complete. |
| FENCE.I     | I-type | Instruction-stream fence. Implemented as a pipeline drain (same effect as `FENCE` since there is no I-cache to invalidate). |
| MRET        | I-type | Machine-mode trap return (restores from `mepc`/`mstatus`) |
| SRET        | I-type | Supervisor-mode trap return (restores from `sepc`/`sstatus`). Raises illegal-instruction when `SU_MODE_EN == 0`. |
| WFI         | I-type | Wait for interrupt. Drops `hclk_en_o` when both AHB masters are drained, enabling SoC-level clock gating. |
| MNRET       | I-type | NMI return (Smrnmi). Only legal when `NMI_EN == 1`. See [Smrnmi](#smrnmi--resumable-nmi-extension). |

### Control and Status Register (CSR) Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| CSRRW       | I-type | CSR read/write |
| CSRRS       | I-type | CSR read and set bits |
| CSRRC       | I-type | CSR read and clear bits |
| CSRRWI      | I-type | CSR read/write immediate |
| CSRRSI      | I-type | CSR read and set bits immediate |
| CSRRCI      | I-type | CSR read and clear bits immediate |

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
| ZEXT.H      | I-type | Zero-extend halfword |
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

Selected via `C_EXTENSION` (cumulative levels 0–4). All instructions are 16-bit and freely interleave with 32-bit base instructions. Compressed instructions with register primes (`rd'`, `rs1'`, `rs2'`) can only access registers x8–x15.

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
| C.LBU       | CL     | Load byte unsigned (base: x8-x15, dest: x8-x15) |
| C.LHU       | CL     | Load halfword unsigned (base: x8-x15, dest: x8-x15) |
| C.LH        | CL     | Load halfword (sign-extended) (base: x8-x15, dest: x8-x15) |
| C.SB        | CS     | Store byte (base: x8-x15, src: x8-x15) |
| C.SH        | CS     | Store halfword (base: x8-x15, src: x8-x15) |

**Sign/Zero Extension:**

| Instruction | Format | Description |
|-------------|--------|-------------|
| C.ZEXT.B    | CA     | Zero-extend byte (AND with 0xFF) |
| C.SEXT.B    | CA     | Sign-extend byte |
| C.ZEXT.H    | CA     | Zero-extend halfword (AND with 0xFFFF) |
| C.SEXT.H    | CA     | Sign-extend halfword |

**Arithmetic and Logical:**

| Instruction | Format | Description |
|-------------|--------|-------------|
| C.NOT       | CA     | Bitwise NOT (XOR with -1) |
| C.MUL       | CA     | Multiply low (requires M or Zmmul) |

### Zcmp — Compressed Push/Pop/Moves

Enabled when `C_EXTENSION >= 3`. These instructions execute as multi-cycle micro-op sequences (handled by the UOP sequencer in `arv_uop_sequencer.v`).

| Instruction | Description |
|-------------|-------------|
| CM.PUSH     | Push a register list to the stack |
| CM.POP      | Pop a register list from the stack |
| CM.POPRET   | Pop a register list and return (load `ra`, then JALR x0, ra) |
| CM.POPRETZ  | `POPRET` and additionally zero `a0` (for void returns) |
| CM.MVA01S   | Move two `s` registers to `a0`/`a1` (in a single micro-op pair) |
| CM.MVSA01   | Move `a0`/`a1` to two `s` registers (in a single micro-op pair) |

### Zcmt — Compressed Table Jumps

Enabled when `C_EXTENSION == 4`. Implements indirect-jump dispatch through a jump table whose base address is held in the `jvt` CSR (address 0x017).

| Instruction | Description |
|-------------|-------------|
| CM.JT       | Jump-table jump (PC ← jvt + entry × 4, fetched as a 32-bit target) |
| CM.JALT     | Jump-and-link via jump table (same dispatch as `CM.JT`, returns to `ra`) |

## Smrnmi — Resumable NMI Extension

Enabled when `NMI_EN == 1`. Provides resumable NMI handling with dedicated CSRs and a return instruction (`MNRET`). When `NMI_EN == 0`, the entire mechanism is absent: the `nmi_i` input is ignored, the NMI CSRs (0x740–0x744) raise illegal-instruction, and `MNRET` raises illegal-instruction.

| Element | Detail |
|---------|--------|
| Trigger | Level-sensitive `nmi_i` input (no internal synchronizer — drive synchronous to `hclk_i`) |
| Vector | Loaded from `nmi_vector_i[31:0]` at trap entry |
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

Compressed instructions with register primes (`rd'`, `rs1'`, `rs2'`) can only access registers x8–x15.

## Implemented CSR Registers

Access type codes: **MRW** = Machine read-write; **MRO** = Machine read-only; **SRW** = Supervisor read-write (M can also access); **URO** = User read-only.

### Machine-Level Trap Setup and Handling

| Address | Name      | Access | Description |
|---------|-----------|--------|-------------|
| 0x300   | mstatus   | MRW    | Machine status (FS, MPP, MIE, SIE, MPIE, SPIE, etc.) |
| 0x301   | misa      | MRW    | ISA & extensions (WARL — writes ignored in aRVern) |
| 0x302   | medeleg   | MRW    | Machine exception delegation to S-mode (RAZ/WI when `SU_MODE_EN == 0`) |
| 0x303   | mideleg   | MRW    | Machine interrupt delegation to S-mode (RAZ/WI when `SU_MODE_EN == 0`) |
| 0x304   | mie       | MRW    | Machine interrupt-enable |
| 0x305   | mtvec     | MRW    | Machine trap-handler base address |
| 0x340   | mscratch  | MRW    | Machine scratch register |
| 0x341   | mepc      | MRW    | Machine exception PC |
| 0x342   | mcause    | MRW    | Machine trap cause |
| 0x343   | mtval    | MRW    | Machine bad address or instruction |
| 0x344   | mip       | MRW    | Machine interrupt pending |

### Machine Information Registers

| Address | Name       | Access | Description |
|---------|------------|--------|-------------|
| 0xF11   | mvendorid  | MRO    | Vendor ID (`MVENDORID` integration parameter) |
| 0xF12   | marchid    | MRO    | Architecture ID (reads 0 until an aRVern ID is allocated) |
| 0xF13   | mimpid     | MRO    | Implementation ID — RTL version `[31:20]` + build-config discovery word `[19:0]` (see below) |
| 0xF14   | mhartid    | MRO    | Hardware thread ID (from `hartid_i`) |
| 0xF15   | mconfigptr | MRO    | Configuration pointer |

**`mimpid` bit layout.** Beyond the RTL release version in the top 12 bits,
`mimpid[19:0]` encodes the synthesized build configuration at finer granularity
than `misa` can express — software can read it once at boot to discover which
extensions, multiplier/divider, and counters are present without probing CSRs
for traps. Values are fixed in the RTL by the instantiation parameters.

| Bits | Field | Meaning |
|:---:|---|---|
| `[31:20]` | `RTL_VERSION` | RTL release version (12-bit, core-owned; bump on each release via the `RTL_VERSION` localparam in `arvern.v`) |
| `[19:16]` | `ZIHPM_NR` | Number of `mhpmcounter3–10` implemented (0–8) |
| `[15]` | `ZICNTR_EN` | Zicntr present (`cycle` / `time` / `instret`) |
| `[14]` | `SINGLE_CYCLE_BRANCH` | 1 = zero-bubble taken branch (max IPC); 0 = one-bubble (max Fmax) |
| `[13]` | `NMI_EN` | Smrnmi resumable NMI present |
| `[12]` | `CCSR_EN` | Custom-CSR interface present |
| `[11:10]` | `div_type` | Divider: 0 = none, 1 = radix-8 (12-cyc), 2 = radix-4 (17-cyc), 3 = radix-2 (33-cyc) — matches `DIV_TYPE` |
| `[9:8]` | `mul_type` | Multiplier: 0 = none, 1 = single-cycle, 2 = four-cycle, 3 = sixteen-cycle — matches `MUL_TYPE` |
| `[7]` | `ZCMT_EN` | Zcmt (compressed table jumps) present |
| `[6]` | `ZCMP_EN` | Zcmp (compressed push/pop) present |
| `[5]` | `ZCB_EN` | Zcb (compressed code-size) present |
| `[4]` | `ZCA_EN` | Zca (base compressed) present |
| `[3]` | `ASYNC_RST_EN` | Reset architecture: 1 = asynchronous active-low reset, 0 = synchronous reset |
| `[2]` | `ZBS_EN` | Zbs (single-bit) present |
| `[1]` | `ZBA_EN` | Zba (address generation) present |
| `[0]` | `ZBB_EN` | Zbb (basic bitmanip) present |

> The `mul_type` / `div_type` fields read `0` when the multiplier / divider is
> absent (`M_EXTENSION = 0`, or `M_EXTENSION = 1` Zmmul which has a multiplier
> but no divider). The encoding is defined in `arv_csr_ids.v`.

### Counter / Timer CSRs (Zicntr)

Present when `ZICNTR_EN == 1`. The user-mode shadows are read-only views of the machine counters, gated by `mcounteren` / `scounteren`.

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

Present when `ZIHPM_NR > 0`. `ZIHPM_NR` (0–8) selects how many of the mhpmcounter3–10 / mhpmevent3–10 banks are physically implemented.

| Address range | Name (range) | Access | Description |
|---------------|--------------|--------|-------------|
| 0xB03–0xB0A   | mhpmcounter3–10  | MRW | HPM event counters (low 32 bits) |
| 0xB83–0xB8A   | mhpmcounterh3–10 | MRW | HPM event counters (high 32 bits) |
| 0x323–0x32A   | mhpmevent3–10    | MRW | Per-counter event selector (encoding below) |
| 0xC03–0xC0A   | hpmcounter3–10   | URO | User-mode shadows (gated by `mcounteren`) |
| 0xC83–0xC8A   | hpmcounterh3–10  | URO | User-mode shadows (gated by `mcounteren`) |

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
| `0x05` | `branch taken` | Every taken branch (BEQ/BNE/BLT/BGE/BLTU/BGEU resolved taken; JAL; JALR) |
| `0x06` | `branch not taken` | Conditional branch resolved not-taken |
| `0x07` | `load` | Every retired load instruction (`LB`/`LH`/`LW`/`LBU`/`LHU`/Zcb compressed loads) |
| `0x08` | `store` | Every retired store instruction (`SB`/`SH`/`SW`/Zcb compressed stores) |
| `0x09` | `exception` | Every synchronous exception entry |
| `0x0A` | `interrupt` | Every asynchronous interrupt entry (IRQ or NMI) |
| `0x0B` | `platform_events_i[0]` | Integrator-defined external event #0 (`hpm_platform_events_i[0]`) |
| `0x0C` | `platform_events_i[1]` | Integrator-defined external event #1 |
| `0x0D` | `platform_events_i[2]` | Integrator-defined external event #2 |
| `0x0E` | `platform_events_i[3]` | Integrator-defined external event #3 |
| `0x0F` | `platform_events_i[4]` | Integrator-defined external event #4 |
| `0x10` | `platform_events_i[5]` | Integrator-defined external event #5 |
| `0x11` | `platform_events_i[6]` | Integrator-defined external event #6 |
| `0x12` | `platform_events_i[7]` | Integrator-defined external event #7 |

> `mhpmeventN[31:5]` are WARL-zero. The integrator wires
> `hpm_platform_events_i[7:0]` to SoC-level events of their choice
> (cache miss, DMA done, GPIO toggle, etc. — synchronous to `hclk_i`,
> count-on-rising-edge); see [`integration_guide.md` §9](../doc/integration_guide.md#9-hpm-platform-events).
> Pure firmware self-instrumentation (selectors `0x01`–`0x0A`) needs
> no SoC support — just `csrw mhpmeventN, <code>` and read the
> matching `mhpmcounterN` later.

### Counter Setup CSRs

| Address | Name          | Access | Description |
|---------|---------------|--------|-------------|
| 0x306   | mcounteren    | MRW    | Enable user-mode counter access (Zicntr + Zihpm) |
| 0x320   | mcountinhibit | MRW    | Stop individual counter increment |

### Supervisor-Level CSRs

Present when `SU_MODE_EN == 1`. S-mode trap-handling registers and per-mode shadows of `mstatus`/`mie`/`mip`. The `satp` register is a WARL stub (aRVern is physical S-mode — no paged MMU). **When `SU_MODE_EN == 0`, every register in this section is RAZ/WI** (reads return 0; writes silently dropped) — consistent with the "non-existent CSRs in known banks" deviation in `spec_compliance_notes.md`.

| Address | Name       | Access | Description |
|---------|------------|--------|-------------|
| 0x100   | sstatus    | SRW    | Supervisor status (shadow of mstatus's S-visible fields) |
| 0x104   | sie        | SRW    | Supervisor interrupt enable (mideleg-masked) |
| 0x105   | stvec      | SRW    | Supervisor trap-handler base address |
| 0x106   | scounteren | SRW    | Enable user-mode counter access from S-mode |
| 0x140   | sscratch   | SRW    | Supervisor scratch register |
| 0x141   | sepc       | SRW    | Supervisor exception PC |
| 0x142   | scause     | SRW    | Supervisor trap cause |
| 0x143   | stval      | SRW    | Supervisor bad address or instruction |
| 0x144   | sip        | SRW    | Supervisor interrupt pending (mideleg-masked) |
| 0x180   | satp       | SRW    | Address-translation/protection (WARL stub) |

### Resumable NMI CSRs (Smrnmi)

Present when `NMI_EN == 1`. When `NMI_EN == 0`, accesses to this bank raise illegal-instruction.

| Address | Name      | Access | Description |
|---------|-----------|--------|-------------|
| 0x740   | mnscratch | MRW    | NMI scratch register |
| 0x741   | mnepc     | MRW    | NMI exception PC (target of `MNRET`) |
| 0x742   | mncause   | MRW    | NMI cause |
| 0x744   | mnstatus  | MRW    | NMI status (priv level, NMIE) |

### aRVern-Specific Built-in CSRs

Two non-standard CSRs that live in the M-mode custom address ranges
(`0x7C0-0x7FF` RW, `0xFC0-0xFFF` RO) and are decoded inside the core
itself rather than going through the external `ccsr_*` port group.
Always present (the addresses are reserved by the core regardless of
`CCSR_EN`, so the custom-CSR interface cannot alias them).

| Address | Name          | Access | Gated by   | Description |
|---------|---------------|--------|------------|-------------|
| 0x7FF   | `marv_ctl`    | MRW    | *always*   | aRVern core feature-control — 5 bits at `[4:0]`: IRQ-kill of in-flight multi-cycle ops, handler re-entry protection, NMI lockup escape, and WFI clock-gating policy. Internal CSR (independent of `CCSR_EN`). Reset = `5'b00111`. See below + [`traps_and_interrupts.md` §9](traps_and_interrupts.md#9-core-feature-control-marv_ctl) for full detail. |
| 0xFFE   | `reset_vector`| MRO    | *always*   | Reset PC (32-bit). Read-only mirror of the integrator-driven `reset_vector_i` input port — firmware can read it to discover its own reset vector. Internal CSR (independent of `CCSR_EN`). |
| 0xFFF   | `nmi_vector`  | MRO    | `NMI_EN==1`| NMI handler base address (32-bit, 4-byte aligned). Read-only mirror of the integrator-driven `nmi_vector_i` input port — firmware can read it to discover where the NMI handler lives. Returns illegal-instruction when `NMI_EN == 0`. |

**`marv_ctl` bit layout** (low 5 bits; `[31:5]` are WARL-zero):

| Bit | Default | Effect when set |
|:---:|:---:|---|
| `[0]` | `1` | On IRQ entry, kill any in-flight MUL/DIV operation (`trap_kill_muldiv_o → 1`) so the handler enters in the next cycle instead of waiting for the multi-cycle op to retire. NMI entry kills unconditionally regardless of this bit. |
| `[1]` | `1` | On IRQ entry, kill any in-flight UOP-sequencer (Zcmp / Zcmt) sequence (`trap_kill_uop_o → 1`). Same NMI-unconditional caveat as `[0]`. |
| `[2]` | `1` | Livelock protection: suppress one cycle of IRQ delivery immediately after `MRET` / `MNRET` so a permanent-asserted IRQ source can't re-enter the handler without making forward progress. |
| `[3]` | `0` | Allow an NMI to deassert `lockup_o` and divert to `nmi_vector` from the lockup state. Only takes effect when `NMI_EN == 1`; written-as-zero when `NMI_EN == 0` (WARL). The default `0` keeps the spec-conformant "lockup is sticky" behavior; set to `1` for safety-critical SoCs that want NMI-as-escape-route. |
| `[4]` | `0` | `wfi_clkgate_dis`: disable WFI clock-gating. When set, `hclk_en_o` stays asserted during WFI sleep — the core still stalls in WFI and wakes normally on an enabled interrupt, only the clock gating (and its power saving) is suppressed. Use as a debug aid (keep the core clocked under WFI), an SoC power policy, or belt-and-suspenders safety. The default `0` keeps clock-gating enabled. |

Both CSRs are decoded directly in `arv_csr_top.v` and are masked out
of the `ccsr_reg_sel_o` one-hot fan-out, so a CCSR peripheral cannot
accidentally see or capture writes to 0x7C0 or 0xFFF.

### Zcmt CSR

Present when `C_EXTENSION == 4`.

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| 0x017   | jvt  | MRW    | Jump-vector-table base address for `CM.JT` / `CM.JALT` |

## Total Instruction Count

| Group | Count |
|-------|------:|
| RV32I base                           |  47 |
| System (MRET/SRET/MNRET/WFI/FENCE.I) |  +5 |
| M / Zmmul                            |  8 / 4 |
| Zbb                                  |  18 |
| Zba (RV32 subset)                    |  3  |
| Zbs                                  |  8  |
| Zbc                                  |  3  |
| Zca                                  |  26 |
| Zcb                                  |  11 |
| Zcmp                                 |  6  |
| Zcmt                                 |  2  |

**Maximum total** (all extensions enabled): **~140 instructions** (RV32I + system + M + full B + full C).

## Reference

For detailed instruction encodings and behaviour:

- RISC-V Unprivileged Specification — [`specs/riscv-unprivileged.pdf`](specs/riscv-unprivileged.pdf)
- RISC-V Privileged Specification — [`specs/riscv-privileged.pdf`](specs/riscv-privileged.pdf)
- [`integration_guide.md`](integration_guide.md) — parameter reference, ports, CSR-bank semantics
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — implementation choices in UNSPECIFIED / implementation-defined cases + a few acknowledged gray-area choices
- [`simulation_guide.md`](simulation_guide.md) — how to build, run, and benchmark
