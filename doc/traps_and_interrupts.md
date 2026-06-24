<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Traps, Exceptions, and Interrupts
  <br clear="all">
</h1>

This document is the reference for everything trap-related in
aRVern: synchronous exception causes, IRQ delivery, NMI handling (Smrnmi),
WFI sleep, the IRQ-kill mechanism for multi-cycle ops, and the lockup escape
path. It targets **firmware authors** writing trap handlers and **SoC
integrators** wiring up CLINT/PLIC/NMI sources.

For ports and pin-level integration, see
[`integration_guide.md`](integration_guide.md). For accepted spec deviations,
see [`spec_compliance_notes.md`](spec_compliance_notes.md).

---

## Table of Contents

1. [Trap Taxonomy](#1-trap-taxonomy)
2. [Synchronous Exceptions](#2-synchronous-exceptions)
3. [Standard Interrupts (MIP / MIE)](#3-standard-interrupts-mip--mie)
4. [Platform Interrupts (MIP[31:16])](#4-platform-interrupts-mip3116)
5. [IRQ Priority and Delivery](#5-irq-priority-and-delivery)
6. [Delegation to S-mode (mideleg / medeleg)](#6-delegation-to-s-mode-mideleg--medeleg)
7. [Smrnmi — Resumable NMI](#7-smrnmi--resumable-nmi)
8. [WFI Sleep and Wake](#8-wfi-sleep-and-wake)
9. [Core Feature Control (marv_ctl)](#9-core-feature-control-marv_ctl)
10. [Lockup Detection and Escape](#10-lockup-detection-and-escape)
11. [Trap Entry and Return Summary](#11-trap-entry-and-return-summary)

---

## 1. Trap Taxonomy

Three classes of trap can redirect the pipeline:

| Class | Source | Vector | Return | CSR bank |
|---|---|---|---|---|
| Synchronous exception | The faulting instruction itself | `mtvec` (or `stvec` if delegated) | `MRET` (or `SRET`) | `mcause` (M-mode) / `scause` (S-mode) |
| Standard / platform IRQ | `irq_*_i` external inputs latched into `MIP` | `mtvec` (or `stvec` if delegated) | `MRET` (or `SRET`) | `mcause` / `scause` |
| Resumable NMI (Smrnmi) | `nmi_i` external input | `nmi_vector_i` | `MNRET` | `mncause` / `mnstatus` |

NMI is **separate** from the standard IRQ delivery path. It uses dedicated CSRs
(0x740–0x744), preempts everything (including M-mode IRQ handlers), and is
gated by the `NMI_EN` parameter. Sync exceptions can be delegated to S-mode
via `medeleg`; standard IRQs can be delegated via `mideleg`.

---

## 2. Synchronous Exceptions

Implemented causes — these populate `mcause[4:0]` (or `scause[4:0]`) on entry.
The high bit of `mcause` indicates IRQ vs exception (0 = exception).

| Cause | Name | Trigger |
|------:|---|---|
| 0 | Instruction address misaligned | Taken branch / JAL / JALR to a non-2-byte-aligned target (only reachable with C-extension disabled or for misaligned 32-bit target) |
| 1 | Instruction access fault | `inst_hresp_i = 1` on the fetch of the trapping PC |
| 2 | Illegal instruction | Decoder couldn't classify the encoding; or a privileged instruction (`MRET`/`SRET`/`MNRET`/`WFI`) executed at insufficient privilege; or CSR access denied; or M/B/C-extension feature absent |
| 3 | Breakpoint | `EBREAK` / `C.EBREAK` |
| 4 | Load address misaligned | LH/LW with low bit(s) set |
| 5 | Load access fault | `data_hresp_i = 1` on a load data phase |
| 6 | Store address misaligned | SH/SW with low bit(s) set |
| 7 | Store access fault | `data_hresp_i = 1` on a store data phase |
| 8 | Environment call from U-mode | `ECALL` at privilege `2'b00` |
| 9 | Environment call from S-mode | `ECALL` at privilege `2'b01` |
| 11 | Environment call from M-mode | `ECALL` at privilege `2'b11` |

**`mtval` is sampled at trap entry:**

| Cause | `mtval` content |
|---|---|
| 0, 4, 6 | The faulting (mis-aligned) address |
| 1, 5, 7 | The faulting (access-faulting) address |
| 2 | The faulting instruction encoding (16- or 32-bit) |
| 3 | Implementation-defined (aRVern writes 0) |
| 8, 9, 11 | 0 |

**Accepted deviation:** `minstret` counts trapping instructions (dispatch-stage
count). See `spec_compliance_notes.md`.

---

## 3. Standard Interrupts (MIP / MIE)

The standard RISC-V interrupt-pending / interrupt-enable bits implemented by
arvern. All are levels (not edges) — they remain pending as long as the
external signal is asserted.

| MIP bit | Cause | Name | Source |
|--------:|------:|---|---|
| 1 | 1 | SSI — Supervisor Software Interrupt | `irq_s_software_i` (typically ACLINT SSWI register) *OR* software-writable bit in `sip` (when delegated) or `mip` |
| 3 | 3 | MSI — Machine Software Interrupt | `irq_m_software_i` (typically ACLINT MSWI register) |
| 5 | 5 | STI — Supervisor Timer Interrupt | Software-writable bit in `sip` (when delegated). No HW input — set by M-mode firmware via SBI `set_timer`; future Sstc would handle this internally via `stimecmp` CSR. |
| 7 | 7 | MTI — Machine Timer Interrupt | `irq_m_timer_i` (typically ACLINT MTIMER `mtime >= mtimecmp`) |
| 9 | 9 | SEI — Supervisor External Interrupt | `irq_s_external_i` (typically PLIC S-mode context) *OR* software-writable shadow in `sip` |
| 11 | 11 | MEI — Machine External Interrupt | `irq_m_external_i` (typically PLIC M-mode context) |

The corresponding `mie` bits (MSIE / MTIE / MEIE / SSIE / STIE / SEIE) are the
M-mode enables. `sie` is a `mideleg`-masked view of `mie`. Global enable is
`mstatus.MIE` (M-mode) or `sstatus.SIE` (S-mode).

> **MIP[1] / SSIP — hardware edge-set.** Per ACLINT 1.0-rc4, the SSWI device emits a
> one-cycle EDGE on `irq_s_software_i` when an M-mode SETSSIP write fires. The core's
> `mip.SSIP` flop latches the edge: HW-edge sets the flop, SW (M-mode `csrw mip` or
> delegated S-mode `csrw sip`) can set or clear it. Same-cycle HW-edge + SW-clear
> resolves to SET (HW wins) — matching the RISC-V convention for SIP bits and the
> typical "ACLINT SETSSIP fires while S-mode is mid-clear" race. The HW path is gated
> by `SU_MODE_EN` (tied 0 in M-only builds). SSI delivery to M-mode (when
> `mideleg.SSI=0`) and to S-mode (when `mideleg.SSI=1`) both observe the latched value.

---

## 4. Platform Interrupts (MIP[31:16])

Platform-designated interrupts use the upper 16 bits of MIP:

| Port | Width | Pending bits | Cause |
|---|---|---|---|
| `irq_platform_i[15:0]` | 16 | `MIP[31:16]` | 16…31 |

Each platform IRQ has its own enable bit in `mie[31:16]` and can be delegated
to S-mode via `mideleg[31:16]` (the `mideleg_dpu` field). Trap cause is
`mcause = 16 + bit_index`.

**CDC requirement:** `irq_platform_i` is fed directly into pipeline control
without an internal synchronizer. If it crosses from another clock domain,
add a 2-FF synchronizer in the SoC wrapper (see `integration_guide.md` §5.2).

---

## 5. IRQ Priority and Delivery

When multiple IRQs are pending and enabled, aRVern resolves priority **per
RISC-V Privileged Spec §3.1.9 ordering**:

1. **MEI** (cause 11) — highest standard priority
2. MSI (cause 3)
3. MTI (cause 7)
4. SEI (cause 9)
5. SSI (cause 1)
6. **STI** (cause 5) — lowest standard priority
7. Platform IRQs (causes 16–31) — lowest of all; within the group, lower bit number wins

Per RISC-V Priv. spec, M-mode IRQs (3 / 7 / 11) are always delivered to M-mode
regardless of `mideleg` (those bits in `mideleg` are hardwired 0). Supervisor
and platform IRQs are routed to S-mode when delegated and `sstatus.SIE = 1`,
or to M-mode otherwise.

**Global enables:** an M-mode IRQ fires only if `mstatus.MIE = 1`. An S-mode
IRQ (delegated) fires only if the core is currently in U-mode, **or** in
S-mode with `sstatus.SIE = 1`. M-mode never takes a delegated IRQ from S-mode
unless `mideleg` undelegates it.

The resolved IRQ-pending vector is computed in `arv_csr_traps.v` around line
1510 (`irq_vector_prio`) — useful for tracing in a waveform.

---

## 6. Delegation to S-mode (mideleg / medeleg)

`medeleg` and `mideleg` route specific traps to S-mode instead of M-mode.

**`medeleg[31:0]` — synchronous exception delegation**

Each bit corresponds to a sync-exception cause (bit N ↔ cause N). Bits with
no implemented exception (10, 14, …) are hardwired 0. Common delegated
causes:

| Bit | Cause | Use |
|---:|------:|---|
| 0 | 0 | Instruction address misaligned |
| 1 | 1 | Instruction access fault |
| 2 | 2 | Illegal instruction |
| 3 | 3 | Breakpoint |
| 4 | 4 | Load misaligned |
| 5 | 5 | Load access fault |
| 6 | 6 | Store misaligned |
| 7 | 7 | Store access fault |
| 8 | 8 | Environment call from U-mode (typically delegated for syscalls) |

> Bit 11 (`Ecall from M-mode`) is hardwired 0 per spec — M-mode `ECALL` always
> traps to M-mode.

**`mideleg[31:0]` — IRQ delegation**

Per RISC-V Priv. spec §3.1.9, only S-mode IRQs (causes 1, 5, 9) and platform
IRQs (causes ≥ 16) are delegatable. M-mode IRQ bits (3, 7, 11) in `mideleg`
are hardwired 0.

| `mideleg` bit | Delegates |
|---:|---|
| 1 (`mideleg_ssi`) | SSI (cause 1) |
| 5 (`mideleg_sti`) | STI (cause 5) |
| 9 (`mideleg_sei`) | SEI (cause 9) |
| 16+N (`mideleg_dpu[N]`) | Platform IRQ N |

When delegated **and** the IRQ would be taken in S-mode, the trap goes through
the S-mode CSR bank (`sepc`/`scause`/`stval`/`sstatus`), `SRET` returns.

---

## 7. Smrnmi — Resumable NMI

Enabled when `NMI_EN == 1`. Provides a fully-resumable non-maskable interrupt
with its own CSR bank and return instruction.

### Pin-level

| Signal | Dir | Description |
|---|---|---|
| `nmi_i` | in | Level-sensitive NMI (no internal sync — drive synchronous to `hclk_i`) |
| `nmi_vector_i[31:0]` | in | NMI handler PC (loaded at trap entry; must be 4-byte aligned) |

### CSR bank (0x740–0x744)

| Address | Name | Description |
|---|---|---|
| 0x740 | mnscratch | NMI scratch |
| 0x741 | mnepc | PC to resume on `MNRET` |
| 0x742 | mncause | Encoded as `{1'b1, …, 5'd?}` — bit 31 set for "NMI source" |
| 0x744 | mnstatus | Holds `NMIE` (NMI enable, cleared on entry) + `MNPP` (previous priv level) + `MNPV` |

When `NMI_EN == 0`: the entire bank raises illegal-instruction on access, `nmi_i`
is ignored, and `MNRET` raises illegal-instruction.

### Entry flow

1. NMI asserts (`nmi_i = 1`).
2. Pipeline drains current instruction (sync excp / IRQ in flight is dropped — see
   `trap_smrnmi_excp_preempt` deviation if a posted store error races NMI).
3. `mnepc` ← faulting / next-to-execute PC; `mncause` ← `{1, …}`; `mnstatus.MNPP` ←
   current privilege; `mnstatus.NMIE` ← 0 (mask further NMIs).
4. `priv` ← `2'b11` (M-mode); PC ← `nmi_vector_i`.

### Return (`MNRET`)

`MNRET` is privileged (M-mode only). It restores `pc ← mnepc`,
`priv ← mnstatus.MNPP`, and sets `mnstatus.NMIE = 1` (re-enables NMI).
Behaviour with `NMI_EN == 0`: illegal-instruction trap.

### Special cases

- **NMI during WFI sleep:** wakes the core and saves `mnepc = WFI_PC + 4` (so
  `MNRET` resumes past WFI).
- **NMI escape from lockup:** controlled by the custom `marv_ctl[3]` bit
  (see §9 + §10).

---

## 8. WFI Sleep and Wake

`WFI` (cause-22 in spec terms; aRVern implements as a clean drain + stall, not
a trap) puts the core into the deepest power state available:

1. Pipeline drains to commit.
2. `id_wfi_active` asserts.
3. Once both AHB masters are idle (`*_htrans = 00`) and the data-bus dphase is
   clear, `hclk_en_o` deasserts.
4. The SoC-level ICG (driven by `hclk_en_o`) gates `hclk_i` — *all* internal
   flops freeze, including counters.

### Wake conditions

`wfi_wakeup_o` re-asserts when any enabled IRQ or NMI becomes pending:

| Source | Condition |
|---|---|
| Any M-mode IRQ | `(mip & mie)` becomes non-zero |
| Any delegated S-mode IRQ | Likewise (the mask depends on global enables) |
| NMI | `nmi_i = 1` (when `NMI_EN == 1`) |

A separate **live wake-up** path (`wfi_wakeup_live_o` — line 1979) bypasses the
registered `mip` so the SoC can ungate `hclk_en_o` combinationally on the very
first cycle the IRQ asserts.

### Saved PC

| Wake by | `mepc` / `mnepc` saved as |
|---|---|
| Standard IRQ | `WFI_PC + 4` (resume after WFI) |
| NMI | `WFI_PC + 4` (same) |

> **Accepted deviation:** `mcycle` freezes during WFI sleep — see
> [`spec_compliance_notes.md`](spec_compliance_notes.md#mcycle-freezes-during-wfi-sleep-zicntr).

---

## 9. Core Feature Control (marv_ctl)

aRVern provides an **aRVern-specific custom CSR** (`marv_ctl`, address 0x7FF)
that gathers core feature/policy controls — IRQ-kill of in-flight long ops,
handler-re-entry protection, NMI lockup escape, and WFI clock-gating policy.
`marv_ctl` is an **internal** CSR: it exists and works regardless of the
`CCSR_EN` parameter (which gates only the *external* custom-CSR interface).
This is a 5-bit configuration:

| Bit | Name | Effect |
|---:|---|---|
| 0 | `irqkill_muldiv_en` | If 1: a pending IRQ kills an in-flight MUL/DIV (the op aborts; PC is replayed on `MRET`) |
| 1 | `irqkill_uop_en` | If 1: a pending IRQ kills an in-flight Zcmp/Zcmt UOP sequence |
| 2 | IRQ-suppress post-MRET / MNRET | If 1: a single instruction must dispatch after `MRET`/`MNRET` before the next IRQ can be taken (prevents handler re-entry livelock if the handler doesn't clear the source) |
| 3 | NMI-escape from lockup (requires `NMI_EN == 1`) | If 1: a pending NMI can deassert sticky `lockup_o` and dispatch the NMI handler. WARL-forced to 0 when `NMI_EN == 0`. |
| 4 | `wfi_clkgate_dis` | If 1: disable WFI clock-gating — the core keeps `hclk_en_o` asserted during WFI (it still stalls and wakes normally, only the clock gating is suppressed). Safety/debug/power-policy knob. |

This CSR is at address **0x7FF** (custom M-mode RW). Reset value is `5'b00111`:
bits [2:0] = 1 (IRQ-kill of MUL/DIV + UOP and post-(M)RET re-entry protection
**enabled** by default), bit [3] = 0 (NMI lockup-escape off), bit [4] = 0 (WFI
clock-gating **enabled**, i.e. the core may gate its clock during WFI). SoC
firmware adjusts the bits during boot; the CSR is wired into the trap FSM and
the WFI clock-gating path so changes take effect immediately.

### Practical guidance

- **Real-time SoCs:** set bits 0 + 1 to keep worst-case IRQ latency to a small
  bounded value (~10 cycles instead of div-radix-2's 33+ cycles).
- **Handlers that themselves may not clear the IRQ source:** set bit 2 to
  prevent immediate re-entry.
- **Safety-critical SoCs with an external watchdog NMI:** set bit 3 so a
  watchdog NMI can escape a lockup.

The kill mechanism saves `mepc` to the killed instruction's PC, so `MRET`
re-executes it (the op restarts from scratch). For Zcmp/Zcmt this is
architecturally correct because the op's effects are committed atomically at
WB (no partial state).

---

## 10. Lockup Detection and Escape

aRVern detects an **unrecoverable trap re-entry** condition and asserts the
sticky `lockup_o` output. A lockup typically means the handler itself faulted
before the original cause was cleared — usually a runaway `mtvec` pointing
into invalid memory.

### Detection

The pipeline enters lockup when a trap is taken while already in the trap
sequence (`trap_stage[N]` re-asserts before completing). The exact ladder is
in `arv_csr_traps.v` — search for `in_lockup`.

### Recovery

| Method | Conditions |
|---|---|
| `hresetn_i` assertion | Always works — clean reset |
| NMI delivery | Requires `NMI_EN == 1` *and* `marv_ctl[3] == 1`. The NMI deasserts `lockup_o` and jumps to `nmi_vector_i`. The handler can then attempt a graceful shutdown / re-init. |

When the NMI-escape path is disabled (default), `hresetn_i` is the only
recovery — the SoC should treat `lockup_o` as a fatal condition (route to a
watchdog reset controller).

---

## 11. Trap Entry and Return Summary

### Entry side-effects (M-mode)

| Item | Update |
|---|---|
| `mepc` | The faulting PC (sync) or next-to-execute PC (IRQ) — IRQ-killed op replays from its start |
| `mcause` | `{is_irq, …, cause[4:0]}` |
| `mtval` | Per cause (see §2) |
| `mstatus.MPP` | Previous privilege level |
| `mstatus.MPIE` | Previous `mstatus.MIE` |
| `mstatus.MIE` | Cleared (mask further M-mode IRQs) |
| `pc` | `mtvec` (DIRECT mode) — vectored mode is implemented (`mtvec[0]=1`): `pc = mtvec_base + 4 × cause` |
| `priv` | `2'b11` (M-mode) |

### Entry side-effects (S-mode — delegated)

Mirror of M-mode but through `sepc`/`scause`/`stval`/`sstatus.SPP`/`sstatus.SPIE`/`sstatus.SIE`. PC goes to `stvec`.

### Entry side-effects (NMI)

| Item | Update |
|---|---|
| `mnepc` | Saved PC |
| `mncause` | `{is_nmi=1, …}` |
| `mnstatus.MNPP` | Previous privilege level |
| `mnstatus.NMIE` | Cleared (mask further NMIs) |
| `pc` | `nmi_vector_i` |
| `priv` | `2'b11` |

### Return

| Instruction | Restores |
|---|---|
| `MRET` | `pc ← mepc`; `priv ← mstatus.MPP`; `mstatus.MIE ← MPIE`; `MPP ← U` (if priv was M) |
| `SRET` | `pc ← sepc`; `priv ← sstatus.SPP`; `sstatus.SIE ← SPIE`; `SPP ← U` |
| `MNRET` | `pc ← mnepc`; `priv ← mnstatus.MNPP`; `mnstatus.NMIE ← 1` |

---

## See Also

- [`integration_guide.md`](integration_guide.md#5-interrupt-interface) — pin-level IRQ / NMI wiring
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — posted-store fault drop, NMI+WFI race
- [`arvern_instructions.md`](arvern_instructions.md#smrnmi--resumable-nmi-extension) — Smrnmi summary in the ISA reference
- `rtl/verilog/arv_csr_traps.v` — implementation
