<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Microarchitecture
  <br clear="all">
</h1>

This document is the microarchitectural deep-dive: pipeline structure, the
unified compressed decoder, register file with the JALR shadow latch, CSR
subsystem topology, the UOP sequencer, critical paths, and how configuration
parameters move the design points.

It targets **RTL contributors** and anyone trying to understand *why* the
RTL looks the way it does. For port-level integration, see
[`integration_guide.md`](integration_guide.md); for the ISA reference, see
[`arvern_instructions.md`](arvern_instructions.md).

---

## Table of Contents

1. [Top-Level Block Diagram](#1-top-level-block-diagram)
2. [Pipeline](#2-pipeline)
3. [Fetch (`arv_fetch.v`)](#3-fetch-arv_fetchv)
4. [Decode (`arv_decode.v`)](#4-decode-arv_decodev)
5. [Register File (`arv_int_registers.v`)](#5-register-file-arv_int_registersv)
6. [ALU and MUL/DIV (`arv_alu.v`, `arv_alu_muldiv.v`)](#6-alu-and-muldiv-arv_aluv-arv_alu_muldivv)
7. [Load/Store Unit (`arv_load_store.v`)](#7-loadstore-unit-arv_load_storev)
8. [CSR Subsystem (`arv_csr_*.v`)](#8-csr-subsystem-arv_csr_v)
9. [UOP Sequencer (`arv_uop_sequencer.v`)](#9-uop-sequencer-arv_uop_sequencerv)
10. [Critical Paths](#10-critical-paths)
11. [Configuration Parameter Effects](#11-configuration-parameter-effects)
12. [Reset, Clocking, and WFI Power-Down](#12-reset-clocking-and-wfi-power-down)

---

## 1. Top-Level Block Diagram

![aRVern top-level block diagram](img/microarchitecture.svg)

The blocks, in pipeline order, with the detail the diagram collapses:

- **Fetch** (`arv_fetch`) — drives the instruction AHB master, holds the
  speculative `if_pc`, buffers parcels for compressed-instruction alignment, and
  applies the branch / trap / return redirect. The *Instruction AHB* port and the
  *branch / trap redirect* arrow attach here. See §3.
- **Decode** (`arv_decode`) — the unified RV32I + compressed decoder, the
  branch-target adder, and the central stall arbiter; it issues the regfile
  source selectors and the redirect target. See §4.
- **Integer regfile** (`arv_int_registers`) — flop-array register file plus the
  JALR shadow latch. Drawn as one bidirectional arrow: Decode issues source
  selectors and receives forwarded read data (*operands + forward*), while ALU,
  LSU, and CSR each drive a writeback port. See §5.
- **ALU** (`arv_alu`) — combinational base + B-extension ALU; it absorbs
  `arv_alu_muldiv` (M / Zmmul) when `M_EXTENSION ≥ 1`. See §6.
- **LSU** (`arv_load_store`) — the load/store unit and data AHB master: address /
  size / write-data generation, load extract-and-extend, and misalignment /
  access-fault detection. The *Data AHB* port attaches here. See §7.
- **CSR subsystem** (`arv_csr_top`) — the four-block fan-in / read-mux
  composition over `arv_csr_traps`, `arv_csr_cntr` (Zicntr), `arv_csr_hpm`
  (Zihpm), and `arv_csr_ids`, plus the optional `ccsr_*` *Custom CSR* port. The
  *IRQs + NMI* inputs and the *Zicntr time* port land here; the trap controller
  drives the branch redirect, the WFI gate (`hclk_en_o`), and `lockup_o`. See §8.
- **uOP sequencer** (`arv_uop_sequencer`) — when active it drives the ALU / LSU /
  regfile control buses directly while Decode is held stalled, expanding Zcmp /
  Zcmt instructions into micro-op (UOP) sequences. See §9.

Fourteen RTL files under `rtl/verilog/`:

| File | Role |
|---|---|
| `arvern.v` | Top — wires all submodules + parameter sanitisation (`*_USE` / `*_PROC` localparams + `$fatal` range checks) |
| `arv_fetch.v` | Instruction fetch + speculative prefetch + AHB master |
| `arv_decode.v` | Unified RV32I + compressed decoder, branch-target ALU, pipeline stall control |
| `arv_int_registers.v` | Integer register file (32 or 16 regs) + JALR shadow latch |
| `arv_alu.v` | ALU (base + B-extension) |
| `arv_alu_muldiv.v` | M / Zmmul (multiplier + optional divider) |
| `arv_load_store.v` | LSU + data-bus AHB master |
| `arv_csr_top.v` | CSR address bank decode + read mux + write-data composition |
| `arv_csr_traps.v` | mstatus/mie/mip/mtvec/mepc/mcause/mtval + S-mode shadows + mideleg/medeleg + trap FSM + IRQ/NMI prioritisation + WFI sleep + lockup detection + IRQ kill |
| `arv_csr_cntr.v` | Zicntr (mcycle / minstret + U-mode shadows) |
| `arv_csr_hpm.v` | Zihpm (mhpmcounter3–10 + mhpmevent3–10) |
| `arv_csr_ids.v` | mvendorid / marchid / mimpid / mhartid / misa |
| `arv_uop_sequencer.v` | Zcmp / Zcmt micro-op sequencing |
| `arv_dff.v` | Shared D-flop primitive — build-time async/sync reset select (`ASYNC_RST_EN`); used by the core's sequential logic |

---

## 2. Pipeline

Classic single-issue, in-order 4-stage RISC pipeline:

| Stage | Prefix | Function |
|---|---|---|
| **IF** — Instruction Fetch | `if_` | Inst AHB read address-phase, prefetch buffer, branch-target redirect |
| **ID** — Instruction Decode | `id_` | Decode (Inst AHB data-phase) + register-file read, branch-target computation, stall determination |
| **EX** — Execute | `ex_` | ALU / MUL / DIV / CSR access / LSU data AHB address-phase |
| **WB** — Write-Back | `wb_` | LSU data AHB data-phase (loads *and* stores); regfile write commit for loads |

**Per-instruction effective depth.** The pipeline depth advertised as
"4-stage" is the maximum stage count on the LOAD path. ALU and CSR results
commit directly from EX (the regfile has two write ports: one driven by
`ex_reg_dest_wdata`, one by `wb_reg_dest_wdata` — see
`arv_int_registers.v`), so back-to-back ALU/CSR ops effectively
move through 3 stages. The WB stage exists for everything the AHB data
phase needs: load result sampling (`data_hrdata_i`), store data driving
(`data_hwdata_o`), and the access-fault sample point for both directions
(`dph_error → wb_excp_*_access_fault_o`). Stores therefore go through all
four stages too — they just don't commit anything to the regfile in WB.

**Hazards** are handled by stall-and-bypass: ID stalls when a producer in EX
hasn't committed yet, and a small bypass network forwards EX/WB results to
ID-stage operand reads so back-to-back dependencies don't always stall.
Load-use hazards cost one bubble (the dependent op must wait until the WB
stage commits the load result to the regfile, one cycle after the EX-stage
address phase).

Load-use hazard (the dependent op waits for the WB-committed load, then takes
the WB→ID bypass):

```
cyc:      0    1    2    3    4
lw  x5    IF   ID   EX   WB              ; load result committed at WB (cyc 3)
add x5..       IF   ID   ID   EX   WB    ; ID held 1 cycle, then bypasses WB→ID
```

**Branch resolution** can be either single-cycle (combinational from EX) or
one-bubble (registered), per the `SINGLE_CYCLE_BRANCH` parameter — see §10.
The one-bubble case (`SINGLE_CYCLE_BRANCH = 0`):

```
cyc:      0    1    2    3
br        IF   ID   EX                   ; target registered at end of EX
(spec)         IF   --                   ; speculative sequential fetch squashed
target              IF   ID   EX         ; 1-cycle bubble
```

The whole core is a **single clock domain** (`hclk_i`) with no internal
clock-domain crossing — see §12.

---

## 3. Fetch (`arv_fetch.v`)

### Responsibilities

- Drive the instruction AHB master (`inst_h*`).
- Maintain the speculative `if_pc` register.
- Buffer pre-fetched parcels (for C-extension half-word alignment) in
  `inst_buf[]` / `inst_buf_valid[]`.
- Redirect `if_pc` on branches, traps, returns, and Zcmt table jumps.
- Deliver assembled 16- or 32-bit instructions to ID with `id_instruction_o`
  / `id_instruction_valid_o` / `id_pc_o`.
- Sample sticky `dph_error` from `inst_hresp_i` and deliver
  `id_excp_inst_access_fault_o` + `id_inst_fault_addr_o` precisely.

### Speculative prefetch

The fetch unit issues sequential PCs ahead of branch resolution. When the
decoder reports a branch (`id_branch_detect_i`), `if_pc` is overwritten with
the target and the in-flight speculative result is discarded at the decoder.

### Instruction buffer

`inst_buf` is a 3-word (6-parcel) buffer that absorbs:

- C-extension parcel alignment (a 32-bit instruction can straddle a 4-byte
  boundary).
- Single-cycle wait-state hiding (one extra fetch latency tolerated).

### Precise-exception deferral

When an upper-parcel fetch errors mid-stream of a straddling 32-bit instruction,
the fault is **deferred** until the buffer drains. `id_excp_inst_access_fault_o`
asserts only when:

```
fault_pending & (fetch_buf_drained | buffered_inst_incomplete) & ~ex_uop_has_branch_i
```

This logic is in `arv_fetch.v`. The `~ex_uop_has_branch_i` term holds the
release while a Zcmp/Zcmt **UOP-final branch** (`CM.POPRET`/`POPRETZ`/`JT`/`JALT`)
is in flight: such a branch resolves only after its multi-cycle micro-op sequence,
so the speculative sequential fetch past it must not deliver an IAF for an address
the branch is about to redirect away from — the branch's `id_branch_detect` then
clears the freeze and the abandoned-path fault is discarded. See the comment block
above the assignment for the full rationale.

---

## 4. Decode (`arv_decode.v`)

### The unified decoder

The single most important architectural choice in arvern: **compressed and
32-bit instructions are decoded in one pass**, not via a translate stage. The
opcode/funct fields, register selectors, and immediates are extracted **in
parallel** from both formats; a small final mux (`id_use_std_path` /
`id_use_c_path`) picks the right one.

This avoids the latency of (translate ⇒ standard decode) but exposes the
decode logic to more inputs, so the decode path gets longer relative to a
pure RV32I core. The path is kept shallow by construction:

- **Early path prediction.** `id_use_c_path` / `id_use_std_path` come straight
  from `id_instruction_i[1:0]` (compressed ⇔ bits ≠ `2'b11`), gating the
  standard and compressed cones apart at the very front so the synthesiser
  optimises them independently (`arv_decode.v`).
- **Parallel pre-decode.** The compressed funct3 (`id_c_funct3 =
  id_c_instruction[15:13]`) and every compressed opcode/operand decode
  (`id_c_*`) are computed in parallel; a single std-vs-C mux picks the result.
- **One-hot register-selection classes.** Compressed instructions are grouped
  by register-selection pattern into one-hot classes (`id_c_class_rs1_prime`,
  `id_c_class_rs1_sp`, `id_c_class_rs2_prime`, `id_c_class_rs2_rs2`, …) so
  source selection and the EX/WB hazard comparators collapse to a
  sum-of-products — all per-class ANDs in one level, then a shallow OR tree —
  instead of a deep priority chain (the hazard comparators in `arv_decode.v`,
  with the rationale in an in-RTL comment there).
- **Parallel immediate generation.** Every compressed immediate format
  (`id_c_imm_addi4spn`, `id_c_imm_lwsw`, `id_c_imm_lui`, …) is extracted in
  parallel and selected by the decoded instruction (`arv_decode.v`).

The net depth lands close to a pure RV32I decoder's, which matters because this
cone feeds the branch-target path below — the Fmax binder under
`SINGLE_CYCLE_BRANCH = 1` (§10).

### Pipeline-stall control

Decode is also the central stall arbiter. `id_instruction_request_o` (the
"go" signal to fetch and to itself) is the AND of every "no stall" condition:

```
id_instruction_request = ~(fetch_stall_from_fence     |
                           fetch_stall_from_xret      |
                           fetch_stall_from_trap      |
                           fetch_stall_from_jt_branch |
                           fetch_stall_from_wfi       |
                           fetch_stall_from_ex        |
                           ...)
```

`id_inst_retired_o` (the +1 to `minstret`) fires exactly when an instruction
dispatches and isn't a UOP-shadow cycle:

```verilog
assign id_inst_retired_o = id_instruction_request_o
                         & id_instruction_valid_i
                         & (id_use_std_path | id_use_c_path);   // arv_decode.v
```

### Branch-target computation

The decoder computes `id_branch_target_o` for every taken branch:

```verilog
id_branch_base_addr = (id_pc                    & {32{op_branch | op_jal       }}) |
                      (id_jalr_shadow_rdata     & {32{op_jalr   | ex_uop_ret   }}) |
                      (ex_uop_jt_branch_target  & {32{ex_uop_jt_active & ZCMT_EN}});

id_branch_target    = trap_branch_detect ? trap_branch_target
                                         : (id_branch_base_addr + id_operand_immediate_br);
```

This is the **critical timing path of the design** when
`SINGLE_CYCLE_BRANCH = 1` — see §10.

---

## 5. Register File (`arv_int_registers.v`)

### Two configurations

| `RV32E_EN` | Registers | Generate-block |
|---:|:---:|---|
| 0 | x0–x31 (RV32I, 32 regs) | `RV32I_MODE` |
| 1 | x0–x15 (RV32E, 16 regs) | `RV32E_MODE` — x16–x31 flops not instantiated, reads tied to 0, writes dropped |

The decoder is **bit-identical** between RV32I and RV32E modes — the narrowing
lives entirely in this module. This preserves verification locality: the full
RV32I regression covers RV32E decode for free.

### Flop-array register file, multiple read ports

The register file is a **flop array** — an `arv_dff` bank per architectural
register with a per-register next-state mux — not an SRAM macro. That makes
extra read ports cheap (each is a one-hot mux over the register flops), and the
design exposes several:

| Read-port pair | Output | Forwarded? | Consumer |
|---|---|:---:|---|
| ID operands | `id_reg_src1/2_rdata_w_fwd_o` | yes | ALU / CSR / LSU operands |
| Branch operands | `id_branch_rs1/2_rdata_w_fwd_o` | yes | branch condition + branch-target path (§10) |
| EX operands | `ex_reg_src1/2_rdata_wo_fwd_o` | no | execute-stage committed-state reads |
| JALR shadow | `id_jalr_shadow_rdata_o` | special | JALR target (below) |

The **separate branch read port** is what lets the branch-target adder run off
the register file in parallel with the ALU operand path — central to the
single-cycle-branch critical path (§10).

**Two write data sources, muxed per register.** Each register's next-state mux
selects an EX-stage commit (`ex_reg_dest_wdata` — ALU/CSR results) or a WB-stage
commit (`wb_reg_dest_wdata` — load results), per `arv_int_registers.v`.
So ALU/CSR ops retire from EX (3 effective stages) and loads retire from WB (§2).

**Forwarding network.** The `*_w_fwd` ports apply EX→ID and WB→ID bypass: when a
source matches an in-flight EX or WB destination (`*_eq_dest` comparators), the
producer's write data is substituted for the stale register read
(the `*_w_fwd` read assigns in `arv_int_registers.v`). The `ex_*_wo_fwd` ports deliberately
skip this and read committed state directly. This is why a load-use hazard still
costs one bubble — the dependent op can only bypass once the load result lands
at WB.

### JALR shadow latch

The JALR critical path normally goes:

```
ID-read rs1 → register-file read → JALR address compute → inst_haddr
```

To break this, aRVern maintains a **shadow latch** of the most-recently-
updated register, indexed by `shadow_sel`. When the decoder issues a JALR
whose `rs1 == shadow_sel`, the *shadow's contents* drive the JALR target
*combinationally*, bypassing the regfile read. This shaves a full register-
file-read worth of delay off the JALR path.

The shadow updates on every EX or WB write whose destination equals
`shadow_sel`, with one extra gate to honour the RV32E narrowing contract
(x16–x31 don't exist, so the shadow must not capture writes to them via
the `==` comparator when their flops aren't there):

```verilog
rv32e_shadow_sel_upper = ~RV32I_EN & shadow_sel[4];      // shadow points at x16..x31 under RV32E
shadow_wr_from_ex      = ex_reg_dest_wr & (ex_reg_dest_sel_mux == shadow_sel) & (shadow_sel != 0) & ~rv32e_shadow_sel_upper;
shadow_wr_from_wb      = wb_reg_dest_wr & (wb_reg_dest_sel_i   == shadow_sel) & (shadow_sel != 0) & ~rv32e_shadow_sel_upper;
```

A matching `rv32e_load_zero` gate on the JALR-miss data-load path forces
`id_jalr_shadow_rdata_o <= 0` when rs1 is in x16–x31 under RV32E, closing
the forwarding-mux leak the load would otherwise import from
`id_reg_src1_rdata_w_fwd_o`. `shadow_sel` itself is *not* gated — it's
still allowed to load the upper selector on a miss so the pipeline doesn't
deadlock waiting for `id_jalr_shadow_valid` (the data path forces 0,
which is the architecturally correct value).

---

## 6. ALU and MUL/DIV (`arv_alu.v`, `arv_alu_muldiv.v`)

### `arv_alu.v`

A combinational ALU implementing:

- Base RV32I (ADD/SUB, AND/OR/XOR, SLT/SLTU, SLL/SRL/SRA, immediate variants).
- Zbb (ANDN/ORN/XNOR, CLZ/CTZ/CPOP, MAX/MAXU/MIN/MINU, SEXT.B/SEXT.H/ZEXT.H,
  ROL/ROR/RORI, ORC.B, REV8).
- Zba (SH1ADD/SH2ADD/SH3ADD).
- Zbs (BCLR/BEXT/BINV/BSET + immediate forms).
- Zbc (CLMUL/CLMULH/CLMULR — combinational tree in `arv_alu.v`).

Output is `ex_alu_result`; the LSU and CSR units use independent address-
phase paths.

### `arv_alu_muldiv.v`

The multiplier and divider, gated by `M_EXTENSION`. Implementation latency
is controlled by `MUL_TYPE` and `DIV_TYPE`:

| `MUL_TYPE` | Implementation | Cycles |
|---:|---|---:|
| 1 | Combinational 32×32 → 64 | 1 |
| 2 | Iterative — 16×16 partial-product, 4-cycle accumulate | 4 |
| 3 | Iterative — lowest-area | 16 |

| `DIV_TYPE` | Implementation | Cycles |
|---:|---|---:|
| 1 | Radix-8 | 12 |
| 2 | Radix-4 | 17 |
| 3 | Radix-2 | 33 |

The multi-cycle implementations stall ID until done. An IRQ kill (see §9)
can abort a multi-cycle op mid-flight — the instruction is replayed via
`MRET` (the LSU/regfile state is unchanged because the op never committed).

---

## 7. Load/Store Unit (`arv_load_store.v`)

The LSU sits between ID and the data AHB master. It:

- Generates `data_haddr_o` / `data_hwrite_o` / `data_hsize_o` from the load/store
  instruction (`LB/LH/LW/SB/SH/SW`).
- Drives `data_hwdata_o` with the store data on its natural byte lane.
- Receives `data_hrdata_i` and extracts/extends (zero/sign) the loaded
  byte/halfword/word.
- Detects address misalignment combinationally and produces
  `excp_load_address_misaligned` / `excp_store_address_misaligned`.
- Tracks the in-flight posted store's data phase and reports
  `excp_load_access_fault` / `excp_store_access_fault` from `data_hresp_i`.
- Carries the MPRV-aware effective privilege through to `data_hprot_o` /
  `data_hsmode_o`.

No load-store queue, no MMU, no caches — purely a single-transaction LSU.

---

## 8. CSR Subsystem (`arv_csr_*.v`)

CSR access is decoded centrally in `arv_csr_top.v`, which fans out to four
specialised modules:

```
arv_csr_top.v
├── bank decode (any_bank_known, register_select)
├── read mux (combines per-module read data)
├── write data composition (CSRRW / CSRRS / CSRRC unification)
│
├──▶ arv_csr_traps.v   ← trap FSM, mstatus/mip/mie/mtvec/mepc/mcause/mtval
│                         + S-mode shadows, mideleg/medeleg, NMI, IRQ
│                         priority, WFI, lockup, IRQ-kill
├──▶ arv_csr_cntr.v    ← Zicntr: mcycle/minstret + U-mode shadows
├──▶ arv_csr_hpm.v     ← Zihpm: mhpmcounter3–10 + mhpmevent3–10
└──▶ arv_csr_ids.v     ← mvendorid / marchid / mimpid / mhartid / misa
```

### Bank-level decode

CSR addresses are decoded by **bank** (`addr[11:6]`), not per address. A
read of an unknown bank traps; a read of an unimplemented CSR within a
*known* bank is silently RAZ/WI. This is an accepted deviation — see
[`spec_compliance_notes.md`](spec_compliance_notes.md#non-existent-csrs-in-known-banks-read-as-0-razwi-do-not-trap).

### Write semantics

`register_value_nxt` is computed once per access in `arv_csr_top.v`:

```verilog
register_value_nxt = is_csrrw ?                     rs1  :    // CSRRW
                     is_csrrs ? (read_dest_wdata |  rs1) :    // CSRRS
                                (read_dest_wdata & ~rs1) ;    // CSRRC
```

Each per-CSR module then samples `register_value_nxt_i` when its `*_wr` strobe
fires.

### MIP[9] (SEIP) write-back asymmetry

The unified CSRRS/CSRRC formula above feeds the OR'd read value back into
the next-CSR-value, which would latch the external SEIP signal into the
SW-writable bit. RISC-V Priv §3.1.9 (Passages 207-208) mandates that
*"only the software-writable SEIP bit participates in the read-modify-write
sequence"* — so `mip[9]` has a dedicated write-back path in `arv_csr_top.v`
(see `mip_seip_sw_rmw_nxt` near the `register_value_nxt` block) that uses
the SW-writable bit fed back from `arv_csr_traps.v`, not the OR'd read
value. This is the only bit-level asymmetry in the CSR write path; the
architectural read returned in `rd` still includes the external signal.

### Custom CSR interface

When `CCSR_EN == 1`, an external module (in `arvern-ips: arv_custom_csr`)
can present additional CSRs through the `ccsr_*` port group. The interface
is in CSR bank 0x7C0–0x7FF (also shared with the `marv_ctl` register at
0x7FF — which is wired internally even when `CCSR_EN == 0`).

---

## 9. UOP Sequencer (`arv_uop_sequencer.v`)

Active when `C_EXTENSION >= 3` (Zcmp) or `C_EXTENSION == 4` (Zcmt). Breaks
complex compressed instructions into a sequence of micro-ops (UOPs) that look
like simple loads/stores/moves to the rest of the pipeline.

### Sequenced operations

| Instruction | Micro-op sequence |
|---|---|
| CM.PUSH ra, ... | Series of `sw` to the stack |
| CM.POP / CM.POPRET / CM.POPRETZ | Series of `lw` from stack + final `jalr` (POPRET[Z]) |
| CM.MVA01S / CM.MVSA01 | Pair of register moves |
| CM.JT / CM.JALT | Fetch jvt-relative target word + jump there |

While a UOP sequence is in flight, the sequencer drives `ex_uop_has_branch_o`,
`ex_uop_ret_branch_o`, etc., and the decoder mutes the standard / compressed
path enables so spurious `minstret` increments don't happen
(`id_inst_retired_o` gate in `arv_decode.v`).

### IRQ kill

When `marv_ctl[1]` is set (see [§9 of traps doc](traps_and_interrupts.md#9-core-feature-control-marv_ctl)), a pending IRQ aborts an
in-flight UOP sequence. The first UOP's PC is saved to `mepc`; on `MRET`
the entire sequence restarts. This is correct because UOP sequences commit
their effects atomically at the final UOP — partial state never escapes.

---

## 10. Critical Paths

The bind on Fmax depends on which features are enabled and on the
`SINGLE_CYCLE_BRANCH` setting.

### `SINGLE_CYCLE_BRANCH = 1` (high-IPC mode)

```
inst_hrdata_i
    └─▶ branch decode (in arv_decode.v)
         └─▶ id_branch_target_o
              └─▶ inst_haddr_o
```

A purely combinational loop from data-in to address-out, single cycle. This
is **the critical path of the design** when enabled. The unified decoder's
shallow-by-construction structure (§4, *The unified decoder*) keeps this cone
close to a pure RV32I decoder's depth, but it remains the tallest combinational
cone in the design in this mode. For measured Fmax / PPA across configurations
and nodes, see [`characterization_guide.md`](characterization_guide.md).

### `SINGLE_CYCLE_BRANCH = 0` (high-Fmax mode)

The decoder reads the registered instruction buffer (`inst_buf`) instead of
bypassing live `inst_hrdata_i`, so the loop is broken at the buffer flop:

```
inst_hrdata_i ─▶ FF (inst_buf) ─▶ branch decode ─▶ inst_haddr_o
```

`inst_haddr_o` is still combinational from the decoded branch target; the only
register added versus `=1` is the buffer the decoder now reads. That costs one
extra bubble per taken branch (the redirect lands a cycle later), but Fmax is no
longer limited by the `inst_hrdata → inst_haddr` loop — the critical path shifts
to wherever the next-tallest cone sits, typically the multiplier (if
`MUL_TYPE = 1`) or the LSU address generation.

### Other potential binders

| Parameter | Path it adds |
|---|---|
| `MUL_TYPE = 1` | 32×32 → 64 partial-product tree + add tree. Drops to 1 cycle. |
| `B_EXTENSION = 4` | Carry-less multiply tree in `arv_alu.v`. Combinational. |
| `C_EXTENSION = 4` | The Zcmt jump-table fetch in `arv_csr_top.v:bank_jvt`. Small. |
| Many concurrent CSR banks | CSR read mux in `arv_csr_top.v` |

---

## 11. Configuration Parameter Effects

How each parameter ripples through the microarchitecture:

| Parameter | Microarchitectural effect |
|---|---|
| `RV32E_EN = 1` | Removes 16 upper register flops + their write/decode in `arv_int_registers.v`. **No effect on decode logic.** |
| `SU_MODE_EN = 0` | M-mode only — drops S-mode + U-mode: the S-mode CSRs and `mideleg`/`medeleg` become RAZ/WI, `sret`/`sfence.vma` trap as illegal-instruction, `mstatus.MPP` is forced to M, and the `misa` S/U bits read 0. Removes the trap-delegation and S-mode shadow logic in `arv_csr_traps.v`. |
| `M_EXTENSION = 0` | Removes the entire `arv_alu_muldiv.v` module. Saves significant area. |
| `M_EXTENSION = 1` (Zmmul) | Multiplier only — omits the divider state machine. |
| `M_EXTENSION = 2` (M) | Adds the divider on top of the multiplier (latency per `DIV_TYPE`). |
| `MUL_TYPE` 1→2→3 | Reduces 1-cycle multiplier area / improves Fmax at the cost of latency. |
| `DIV_TYPE` 1→2→3 | Smaller divider, more cycles. |
| `B_EXTENSION` 0→4 | Adds ALU extension logic; CLMUL tree is the largest add. |
| `C_EXTENSION` 0→4 | Adds compressed decode (unified into the standard decoder — minimal extra width) + UOP sequencer (for ≥ 3) + jvt CSR (for == 4). |
| `NMI_EN = 1` | Adds the Smrnmi CSR bank, the trap FSM's NMI preempt path, and the `lockup_o` escape path. |
| `ZICNTR_EN = 1` | Adds the Zicntr CSRs (`mcycle`/`minstret` flops + U-mode shadows). |
| `ZIHPM_NR` 0→8 | Each implemented HPM counter adds a 64-bit counter + its event mux (see [`characterization_guide.md`](characterization_guide.md) for measured area). |
| `CCSR_EN = 1` | Exposes the `ccsr_*` external interface; minor extra logic in `arv_csr_top.v` to route reads/writes. |
| `SINGLE_CYCLE_BRANCH` 0/1 | See §10. |
| `ASYNC_RST_EN` 1/0 | Selects asynchronous vs synchronous reset uniformly across every `arv_dff` in the core. See §12. |
| `MVENDORID` | 32-bit constant returned by the `mvendorid` CSR (`arv_csr_ids.v`) — an identification value set by the integrator, not a feature knob; no logic effect. |

### Parameter sanitisation paradigm

`arvern.v` defines two layers:

1. **User-facing parameters** (`RV32E_EN`, `M_EXTENSION`, `MUL_TYPE`, ...) —
   what the integrator sets.
2. **Internal `*_USE` / `*_PROC` localparams** — silently clamp out-of-range
   inputs so the RTL never sees an undefined value.

Range checks (`generate` blocks with `$fatal` inside `pragma translate_off`)
issue an elaboration-time error if a user-facing parameter is out of range —
the simulator catches it cleanly. Synthesis sees the localparam clamping
instead. This pattern is documented in the `// PARAMETER-SANITIZATION
PARADIGM` block in `arvern.v`.

---

## 12. Reset, Clocking, and WFI Power-Down

### Single clock domain

The core has exactly one clock input, `hclk_i`; all pipeline, CSR, and bus
logic is synchronous to it. Every interrupt input, the NMI, and the Zicntr time
interface are specified as `hclk_i`-synchronous (or to be synchronised
externally), so **there is no clock-domain crossing inside the core** — a
deliberate simplification. CDC, where a system needs it, lives in the
surrounding SoC IPs, not here.

### Reset architecture (`ASYNC_RST_EN`)

All sequential state is built from one primitive, `arv_dff` (`WIDTH` /
`RST_VAL` / `en_i`), whose reset style is selected at build time by a generate
so each branch is a statically clean always block:

- `ASYNC_RST_EN = 1` (default) → `always @(posedge clk_i or negedge rst_n_i)`:
  asynchronous active-low reset.
- `ASYNC_RST_EN = 0` → `always @(posedge clk_i)` with `rst_n_i` sampled on the
  edge: synchronous reset (needs a running clock during reset assertion).

The top-level `ASYNC_RST_EN` is range-checked, mapped to `ASYNC_RST_EN_PROC`,
and threaded as `.ARST_EN(...)` into every submodule in `arvern.v`, so the whole
core is uniformly async- or sync-reset from a single switch. `reset_vector_i`
supplies the post-reset PC.

### WFI clock gating (`hclk_en_o`)

`WFI` lets the SoC stop the core clock while it sleeps. On `WFI` the core parks
and drops `hclk_en_o`:

```verilog
assign hclk_en_o = wfi_wakeup_live | ~wfi_sleep_safe_r;   // arvern.v
```

`wfi_sleep_safe_r` records that the core is safely parked (AHB masters drained);
`wfi_wakeup_live` is a *combinational* wake, so the enable can re-assert even
while the clock is gated. The wake condition is any enabled interrupt or an NMI,
independent of the global `mstatus.MIE`:

```verilog
assign wfi_wakeup_o = |(mip & mie) | nmi_detect;          // arv_csr_traps.v
```

A system that doesn't gate the clock can leave `hclk_en_o` unconnected — the
core still runs; the output merely advertises when the clock could be stopped.
See [`traps_and_interrupts.md`](traps_and_interrupts.md) for the full WFI / wake
semantics.

---

## See Also

- [`integration_guide.md`](integration_guide.md) — port-level interface
- [`memory_and_ahb.md`](memory_and_ahb.md) — AHB-Lite contract
- [`traps_and_interrupts.md`](traps_and_interrupts.md) — trap FSM details
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — every accepted divergence, with audit hooks
- [`synthesis_guide.md`](synthesis_guide.md) — how the parameters land in netlist PPA
- [`characterization_guide.md`](characterization_guide.md) — measured Fmax / area / power across configurations
