<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Traps, Exceptions, and Interrupts
  <br clear="all">
</h1>

This document is the reference for everything trap-related in
aRVern: synchronous exception causes, IRQ delivery, resumable NMI handling
(Smrnmi), WFI sleep, the IRQ-kill mechanism for multi-cycle operations, and the
double-trap extensions. It targets **firmware authors** writing trap handlers.

For ports and pin-level integration (IRQ / NMI wiring, synchronizers), see
[`integration_guide.md`](integration_guide.md). For accepted spec deviations,
see [`spec_compliance_notes.md`](spec_compliance_notes.md).

---

## Table of Contents

- [Boot checklist](#boot-checklist)
1. [Trap Taxonomy](#1-trap-taxonomy)
2. [Synchronous Exceptions](#2-synchronous-exceptions)
3. [Standard Interrupts (MIP / MIE)](#3-standard-interrupts-mip--mie)
4. [Platform Interrupts (MIP[31:16])](#4-platform-interrupts-mip3116)
5. [IRQ Priority and Delivery](#5-irq-priority-and-delivery)
6. [Delegation to S-mode (mideleg / medeleg)](#6-delegation-to-s-mode-mideleg--medeleg)
7. [Smrnmi — Resumable NMI](#7-smrnmi--resumable-nmi)
8. [WFI Sleep and Wake](#8-wfi-sleep-and-wake)
9. [Core Feature Control (marv_ctl)](#9-core-feature-control-marv_ctl)
10. [Double Traps and the Critical-Error State](#10-double-traps-and-the-critical-error-state)
11. [Trap Entry and Return Summary](#11-trap-entry-and-return-summary)

---

## Boot checklist

Out of reset the hart cannot take a trap of any kind. Firmware must do the
following, in this order, before the first trap or interrupt:

| Step | CSR | Reset | Rule |
|---|---|---|---|
| 1 | `mnstatus.NMIE` — non-maskable-interrupt enable (0x744 bit 3) | 0 | Set to 1 (`csrsi 0x744, 8`). The reset value is mandated by Smrnmi (Priv §8: "Upon reset, NMIE contains the value 0" — RNMIs are masked so software can initialise its handler data first, and "only reset sequences will explicitly set the NMIE bit"). While 0, all interrupts are masked and every M-mode trap is an unexpected trap with no escape route — the critical-error state (§10). |
| 2 | `menvcfgh.DTE` — S-mode double-trap enable (0x31A bit 27, `SU_MODE_EN = 1`) | 1 | Leave at 1 for S-mode double-trap protection, or clear for spec-literal horizontal delegation (§10). |
| 3 | `mstatush.MDT` — M-mode-disable-trap (0x310 bit 10) | 1 | Clear (`csrw 0x310, x0`). The reset value is mandated by Smdbltrp (Priv §3.1.6.2: "Upon reset, the MDT field is set to 1"), so the boot code is protected until it is ready to take traps. While 1, a trap into M is an unexpected double trap and `mstatus.MIE` cannot be set. Step 1 must already be done. |
| 4 | `marv_ctl` (0x7FF) | `0x7` | Optional: IRQ-kill and WFI clock-gating policy (§9). |
| 5 | `marv_nmvec` (0x7FD) / `mtvec` / `stvec` | `reset_vector + 4 / + 8 / + 12` | Optional: relocate the handlers. `mnscratch` (0x740) should hold a private RNMI stack pointer. |
| 6 | `mie`, `mstatus.MIE` | 0 | Enable interrupts last. |

A worked startup listing is in [`software_guide.md` §5](software_guide.md#5-minimal-startup).

---

## 1. Trap Taxonomy

Three classes of trap can redirect the pipeline:

| Class | Source | Vector | Return | CSR bank |
|---|---|---|---|---|
| Synchronous exception | The faulting instruction itself | `mtvec` (or `stvec` if delegated) | `MRET` (or `SRET`) | `mcause` (M-mode) / `scause` (S-mode) |
| Standard / platform IRQ | `irq_*_i` external inputs latched into `MIP` | `mtvec` (or `stvec` if delegated) | `MRET` (or `SRET`) | `mcause` / `scause` |
| Resumable NMI (RNMI, Smrnmi) | `nmi_i` external input, or a data-bus error | `marv_nmvec` (0x7FD) | `MNRET` | `mncause` / `mnstatus` |

The RNMI is **separate** from the standard IRQ delivery path. It uses dedicated CSRs
(0x740–0x744), preempts everything (including M-mode IRQ handlers), and is
always present (Smrnmi is unconditional). Sync exceptions can be delegated to S-mode
via `medeleg`; standard IRQs can be delegated via `mideleg`.

---

## 2. Synchronous Exceptions

Implemented causes — these populate `mcause[4:0]` (or `scause[4:0]`) on entry.
The high bit of `mcause` indicates IRQ vs exception (0 = exception).

| Cause | Name | Trigger |
|------:|---|---|
| 0 | Instruction address misaligned | Taken branch / JAL / JALR to a target that is not 4-byte aligned. Only reachable with `C_EXTENSION = 0` (IALIGN = 32); with C present the cause is architecturally unreachable |
| 1 | Instruction access fault | A PMP rule denied execute on the fetched address (`PMP_NR > 0`), or `inst_hresp_i = 1` on the fetch of the trapping PC |
| 2 | Illegal instruction | Decoder couldn't classify the encoding; or a privileged instruction (`MRET`/`SRET`/`MNRET`/`WFI`) executed at insufficient privilege; or CSR access denied; or M/B/C-extension feature absent |
| 3 | Breakpoint | `EBREAK` / `C.EBREAK`, or a Sdtrig trigger with action 0 |
| 4 | Load address misaligned | LH/LW with low bit(s) set |
| 5 | Load access fault | A PMP rule denied read on the load address (`PMP_NR > 0`). NOT raised by `data_hresp_i`, which produces an RNMI (§7) instead |
| 6 | Store address misaligned | SH/SW with low bit(s) set |
| 7 | Store access fault | A PMP rule denied write on the store address (`PMP_NR > 0`). NOT raised by `data_hresp_i` — see cause 5 |
| 8 | Environment call from U-mode | `ECALL` at privilege `2'b00` |
| 9 | Environment call from S-mode | `ECALL` at privilege `2'b01` |
| 11 | Environment call from M-mode | `ECALL` at privilege `2'b11` |
| 16 | Double trap | Ssdbltrp (§10) |

**`mtval` is sampled at trap entry:**

| Cause | `mtval` content |
|---|---|
| 0, 4, 6 | The faulting (mis-aligned) address |
| 1, 5, 7 | The faulting (access-faulting) address. For cause 1 on a 32-bit instruction whose halves straddle two PMP regions, this is the half that could not be fetched — i.e. the instruction's address + 2, while `mepc` holds the instruction's own address |
| 2 | 0 (spec-legal — `mtval` may always be written 0 for illegal instruction) |
| 3 | 0 for `EBREAK`/`C.EBREAK` and for a Sdtrig execute breakpoint; the faulting data address for a Sdtrig load/store watchpoint (`DEBUG_EN = 1`) |
| 8, 9, 11 | 0 |
| 16 | The value the original trap would have written (see above) |

> Handlers that need the faulting instruction encoding (e.g. for emulation)
> must re-fetch it from memory at `mepc`.

**Priority.** When more than one synchronous exception is live in the same
instruction, the highest-priority one is taken:

| Priority | Cause |
|---|---|
| 1 (highest) | Instruction address breakpoint (Sdtrig, action 0 — cause 3) |
| 2 | Instruction access fault (1) |
| 3 | Illegal instruction (2) · instruction address misaligned (0) · environment call (8/9/11) · `EBREAK` (3) · load/store address breakpoint (Sdtrig — cause 3) |
| 4 | Load/store access fault (5, 7 — PMP) |
| 5 (lowest) | Load/store address misaligned (4, 6) |

A data-bus error (`data_hresp_i`) is not a synchronous exception at all: it is
delivered as an RNMI (§7) and never competes in this ordering. A
misaligned-access trap and a bus-error RNMI arising from an older access are
both reported, in that order.

**`minstret` and trapping instructions.** Unpriv §7.1 (Zicntr) and Priv §3.3.1
require that an instruction causing a synchronous exception does not increment
`minstret`. aRVern counts at dispatch and un-retires the instruction at trap
entry. Interrupts and NMIs are taken *between* instructions and un-retire
nothing — except an IRQ/NMI that kills an in-flight MUL/DIV or Zcmp
push/pop (§9), which is un-retired because it re-executes after `xRET`. An
instruction whose data access later returns a bus error stays counted: it did
retire (locked by `inst_zicntr_instret_excp`; see
[`spec_compliance_notes.md`](spec_compliance_notes.md#minstret-is-not-un-retired-by-an-asynchronous-data-bus-nmi-zicntr)).

---

## 3. Standard Interrupts (MIP / MIE)

The standard RISC-V interrupt-pending / interrupt-enable bits. The M-mode bits
(causes 3 / 7 / 11) are levels: they remain pending as long as the external
signal is asserted. See §4 for the latched platform bits.

| MIP bit | Cause | Name | Source |
|--------:|------:|---|---|
| 1 | 1 | SSI — Supervisor Software Interrupt | `irq_s_software_i` (typically ACLINT SSWI) *OR* software-writable bit in `sip` (when delegated) or `mip` |
| 3 | 3 | MSI — Machine Software Interrupt | `irq_m_software_i` (typically ACLINT MSWI register) |
| 5 | 5 | STI — Supervisor Timer Interrupt | Software-writable via `mip` only (M-mode); read-only in `sip`. No HW input — set by M-mode firmware via SBI `set_timer` |
| 7 | 7 | MTI — Machine Timer Interrupt | `irq_m_timer_i` (typically ACLINT MTIMER `mtime >= mtimecmp`) |
| 9 | 9 | SEI — Supervisor External Interrupt | `irq_s_external_i` (typically PLIC S-mode context) *OR* a software bit writable via `mip` only (read-only in `sip`) |
| 11 | 11 | MEI — Machine External Interrupt | `irq_m_external_i` (typically PLIC M-mode context) |

The corresponding `mie` bits (MSIE / MTIE / MEIE / SSIE / STIE / SEIE) are the
M-mode enables. `sie` and `sip` are `mideleg`-masked views of `mie` and `mip`:
non-delegated bits read 0 through them and writes to those bits are dropped;
`mie` / `mip` see everything. Global enable is `mstatus.MIE` (M-mode) or
`sstatus.SIE` (S-mode).

> **MIP[1] / SSIP — hardware pulse-set.** Per ACLINT 1.0-rc4, the SSWI device emits a
> one-cycle pulse on `irq_s_software_i` when an M-mode SETSSIP write fires. The core's
> `mip.SSIP` flop latches the pulse and stays set until software clears it (M-mode
> `csrw mip` or delegated S-mode `csrw sip`). Same-cycle HW-set + SW-clear
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
to S-mode via `mideleg[31:16]`. Trap cause is `mcause = 16 + bit_index`.

The pending bits are **latched, not level**: a pulse or level on
`irq_platform_i` sets the bit, and it stays set until software writes it to 0
via `mip` (or `sip` for a delegated bit). A write cannot clear a bit whose pin
is still high, and software can set a bit by writing 1. The handler must clear
the source and then the bit.

Pin timing and clock-domain crossing: [`integration_guide.md` §5.2](integration_guide.md#52-platform-interrupts).

---

## 5. IRQ Priority and Delivery

Priority is resolved in **two levels**: destined privilege mode first, then
cause order within that mode.

**Level 1 — destined privilege.** Per the RISC-V Privileged Spec, *"Interrupts
to M-mode take priority over any interrupts to lower privilege modes"* (the
rationale given is preemption: higher-privilege handlers must be able to
interrupt lower-privilege ones). So if any M-destined IRQ is pending and
enabled, no S-destined IRQ is considered at all, whatever their cause numbers.
An IRQ is M-destined when its `mideleg` bit is clear (and always, for causes
3 / 7 / 11), S-destined when it is set.

**Level 2 — cause order within one destination.** Platform IRQs above all
standard IRQs, then the **§3.1.9 ordering**:

1. **Platform IRQs** (causes 16–31) — highest; within the group, *higher*
   cause number wins (cause 31 is the highest, cause 16 the lowest)
2. **MEI** (cause 11) — highest standard priority
3. MSI (cause 3)
4. MTI (cause 7)
5. SEI (cause 9)
6. SSI (cause 1)
7. **STI** (cause 5) — lowest

Placing the platform group above the standard causes is spec-permissible:
§3.1.9 fixes the relative order of the standard interrupts but leaves the
priority of platform-use interrupts to the implementation.

Per RISC-V Priv. spec, M-mode IRQs (3 / 7 / 11) are always delivered to M-mode
regardless of `mideleg` (those bits in `mideleg` are hardwired 0). Supervisor
and platform IRQs are routed to S-mode when delegated and `sstatus.SIE = 1`,
or to M-mode otherwise.

**Global enables:** an M-mode IRQ fires whenever the core is running **below**
M-mode — then it is globally enabled regardless of `mstatus.MIE` — **or** it is
in M-mode with `mstatus.MIE = 1`. Symmetrically, a delegated S-mode IRQ fires
when the core is in U-mode, **or** in S-mode with `sstatus.SIE = 1`. M-mode
never takes a delegated IRQ from S-mode unless `mideleg` undelegates it.

IRQ delivery is deferred by one cycle after any write to `mstatus`,
`sstatus`, `mie`, `sie`, `mip`, `sip`, `mideleg`, `medeleg`, `menvcfgh` or
`mstatush`, so the instruction after `csrw mip, 0` cannot be interrupted by
the bit it just cleared.

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
| 5 | 5 | Load access fault (`PMP_NR > 0`; read-only 0 otherwise) |
| 6 | 6 | Store misaligned |
| 7 | 7 | Store access fault (`PMP_NR > 0`; read-only 0 otherwise) |
| 8 | 8 | Environment call from U-mode (typically delegated for syscalls) |

> Bit 11 (`Ecall from M-mode`) is hardwired 0 per spec — M-mode `ECALL` always
> traps to M-mode.

**`mideleg[31:0]` — IRQ delegation**

Per RISC-V Priv. spec §3.1.9, only S-mode IRQs (causes 1, 5, 9) and platform
IRQs (causes ≥ 16) are delegatable. M-mode IRQ bits (3, 7, 11) in `mideleg`
are hardwired 0.

| `mideleg` bit | Delegates |
|---:|---|
| 1 | SSI (cause 1) |
| 5 | STI (cause 5) |
| 9 | SEI (cause 9) |
| 16+N | Platform IRQ N |

When delegated **and** the IRQ would be taken in S-mode, the trap goes through
the S-mode CSR bank (`sepc`/`scause`/`stval`/`sstatus`), `SRET` returns.
A trap that is routed to S while `sstatus.SDT = 1` is escalated to M as a
double trap instead — see §10.

### PMP faults and delegation

Causes 1, 5 and 7 are produced by the PMP checkers and are ordinary delegatable
exceptions: `medeleg[1]`, `[5]` and `[7]` route them to S-mode like any other. This is
what makes PMP usable by a supervisor — an S-mode kernel that programs PMP for its
U-mode tasks handles the resulting faults itself, without a round trip through M-mode.

Delegation does not change the check. PMP is evaluated against the privilege of the
access, and a rule that denies S-mode denies it whether or not the resulting fault is
delegated; `medeleg` selects who *handles* the fault, never who *passes* the check.

A locked rule (`pmpcfg.L`) binds M-mode too, so M-mode can fault on its own rules. Such a
fault is still delegatable in principle, but delegation only applies to traps taken from a
lower privilege — a fault taken in M-mode is always handled in M-mode.

### M-only builds (`SU_MODE_EN = 0`)

`medeleg`, `mideleg`, `menvcfg` and `menvcfgh` do not exist and raise
illegal-instruction, as does the whole S-mode CSR bank; `mtval2` (0x34B) reads
0. Every trap is taken in M-mode.

---

## 7. Smrnmi — Resumable NMI

Always present. Provides a fully-resumable non-maskable interrupt (RNMI) with
its own CSR bank and return instruction. Pin contract (`nmi_i`, sampling,
synchronizers): [`integration_guide.md` §6](integration_guide.md#6-nmi-interface-smrnmi).

### CSR bank (0x740–0x744)

| Address | Name | Description |
|---|---|---|
| 0x740 | mnscratch | NMI scratch |
| 0x741 | mnepc | PC to resume on `MNRET` |
| 0x742 | mncause | Read-only, latched at entry. For an RNMI bit 31 is set and the code identifies the source: **`0x8000_0002`** = external `nmi_i` pin, **`0x8000_0003`** = data-bus error (encoding follows SiFive's U74; Smrnmi leaves the codes implementation-defined). If both are pending the **pin wins** and the bus error stays pending for the next delivery. For a Smdbltrp double-trap divert (§10) bit 31 is **0** and `[4:0]` holds the precipitating cause code. |
| 0x744 | mnstatus | Holds `NMIE` (NMI enable, bit 3 — cleared on entry, software-set-only) + `MNPP` (previous priv, bits 12:11). `MNPV` is **not** implemented (reads 0). |

The bank is always present and M-mode accessible. `marv_nmvec` (0x7FD) holds
the handler address; it resets to `reset_vector + 4`.

A data-bus error also latches `marv_epc` (0xFFC), `marv_eaddr` (0xFFD) and
`marv_estat` (0x7FE: `valid`/`overrun` W1C, `restartable`), and `mnepc`
resumes *past* the access unless the handler chooses to replay from
`marv_epc` — see [`software_guide.md` §9](software_guide.md#9-data-bus-errors-rnmi).

### Boot requirement — NMIE resets to 0 and masks ALL interrupts

Per the ratified Smrnmi spec, *"When NMIE=0, all interrupts are disabled"*, and
`mnstatus.NMIE` resets to 0 (*"normally, only reset sequences will explicitly
set the NMIE bit"*). Boot code must therefore
set `mnstatus.NMIE = 1` before any ordinary interrupt (`mie` / `mstatus.MIE`)
can be delivered:

```asm
    csrsi 0x744, 8              # mnstatus.NMIE = 1
```

Smdbltrp gives the same write a second, harder requirement: a trap taken in
M-mode while `NMIE=0` is an **unexpected trap**, so until this runs the hart
cannot take a trap at all — it goes straight to the critical-error state. Arm
`NMIE` *before* clearing `mstatus.MDT`; see §10.

### Entry flow

1. NMI asserts (`nmi_i = 1`), or a data-bus error is pending.
2. Pipeline drains the current instruction. An in-flight MUL/DIV is killed
   unconditionally, and so is a Zcmp push/pop that still has a load/store ahead
   (once its in-flight data phase completes, §9); `mnepc` names the killed
   instruction. Any other Zcmp/Zcmt sequence completes first. A
   sync exception or IRQ in flight is dropped (the posted-store case is
   described under
   [Data-bus errors are reported asynchronously, as a resumable NMI](spec_compliance_notes.md#data-bus-errors-are-reported-asynchronously-as-a-resumable-nmi)).
3. `mnepc` ← faulting / next-to-execute PC; `mncause` ← `{1, …}`; `mnstatus.MNPP` ←
   current privilege; `mnstatus.NMIE` ← 0 (mask further NMIs).
4. `priv` ← `2'b11` (M-mode); PC ← `marv_nmvec`.

### Return (`MNRET`)

`MNRET` is privileged (M-mode only). It restores `pc ← mnepc`,
`priv ← mnstatus.MNPP`, sets `mnstatus.NMIE = 1` (re-enables NMI) and rewrites
`MNPP` to M. When returning below M it also clears `mstatus.MPRV` and
`mstatus.MDT`, and clears `sstatus.SDT` when the new mode is U (§11).

### Special cases

- **NMI during WFI sleep:** wakes the core and saves `mnepc = WFI_PC + 4` (so
  `MNRET` resumes past WFI).
- **MPRV is ignored while `NMIE = 0`** (Priv §8.3): loads and stores inside an
  RNMI handler — and out of reset before NMIE is armed — use the current
  privilege regardless of `mstatus.MPRV`. A handler that borrows MPRV to touch
  U-mode memory will not get it.
- **No trap may occur inside the handler:** with `NMIE = 0` any trap taken in
  M-mode is an unexpected trap with no RNMI to divert to — the critical-error
  state (§10).

---

## 8. WFI Sleep and Wake

`WFI` (Priv §3.3.3) is implemented as a clean drain + stall, not a trap, and
puts the core into the deepest power state available:

1. Pipeline drains to commit.
2. Once both AHB masters are idle (`*_htrans = 00`) and no data-bus transfer
   is still in its data phase, `hclk_en_o` deasserts.
3. The SoC-level clock gate (driven by `hclk_en_o`) gates `hclk_i` — *all*
   internal flops freeze, including counters. `marv_ctl[3]` (§9) keeps
   `hclk_en_o` asserted instead.

### Where WFI is legal

Two **independent** rules make WFI illegal below M-mode (Priv 3.1.6.6):

| Privilege | `mstatus.TW = 0` | `mstatus.TW = 1` |
|---|---|---|
| M | sleeps | sleeps |
| S | **sleeps** (may stall indefinitely — conformant) | illegal instruction |
| U | **illegal instruction** | illegal instruction |

- **TW** is M-mode's *discretionary* hook: *"Trapping the WFI instruction can
  trigger a world switch to another guest OS, rather than wastefully idling in
  the current guest."* It bounds WFI in **any** less-privileged mode. It is
  read-only 0 when there are no modes less privileged than M (`SU_MODE_EN = 0`).
- U-mode WFI is illegal regardless of TW: the implementation-specific bounded
  time limit is 0 (see
  [`spec_compliance_notes.md`](spec_compliance_notes.md#wfi-is-not-available-to-u-mode-su_mode_en1-bounded-time-limit-of-0)).

### Wake conditions

The core wakes when any individually-enabled IRQ or NMI becomes pending
(`(mip & mie) != 0`, or an NMI with `mnstatus.NMIE = 1`):

| Source | Condition |
|---|---|
| Any M-mode IRQ | `(mip & mie)` becomes non-zero |
| Any delegated S-mode IRQ | Same `(mip & mie)` test — WFI wake is **not** gated by the global enables (`mstatus.MIE`/`sstatus.SIE`); a pending, individually-enabled interrupt wakes the core even when globally disabled (it may then remain pending rather than trap). |
| NMI | (`nmi_i` asserted **or** a data-bus error pending) **and** `mnstatus.NMIE = 1` |
| Debug halt request | Always (`DEBUG_EN = 1`) |

A separate **live wake-up** path bypasses the registered `mip` so the SoC can
ungate `hclk_en_o` combinationally on the very first cycle the IRQ asserts.

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
handler-re-entry protection, and WFI clock-gating policy.
`marv_ctl` is an **internal** CSR: it exists and works regardless of the
`CCSR_EN` parameter (which gates only the *external* custom-CSR interface).
This is a 4-bit register (bits [31:4] read 0):

| Bit | Name | Effect |
|---:|---|---|
| 0 | `irqkill_muldiv_en` | If 1: a pending IRQ kills an in-flight MUL/DIV (the op aborts; `mepc` names it and it re-executes on `MRET`) |
| 1 | `irqkill_uop_en` | If 1: a pending IRQ kills an in-flight Zcmp push/pop that still has a load/store ahead (after the access on the bus completes; the op restarts on `MRET`). If 0, or for any other Zcmp/Zcmt sequence, the IRQ waits for the sequence to complete |
| 2 | `livelock_prot_en` | If 1: a single instruction must dispatch after `MRET`/`MNRET` before the next IRQ or NMI can be taken (prevents handler re-entry livelock if the handler doesn't clear the source), and a killed op is allowed to complete once before it can be killed again |
| 3 | `wfi_clkgate_dis` | If 1: disable WFI clock-gating — the core keeps `hclk_en_o` asserted during WFI (it still stalls and wakes normally, only the clock gating is suppressed). Safety/debug/power-policy knob. |

An RNMI kills an in-flight MUL/DIV, or a push/pop that still has a load/store
ahead, **regardless of bits 0/1**; `mnepc` then names the killed instruction.

Reset value is `4'b0111`: bits [2:0] = 1 (IRQ-kill of MUL/DIV + UOP and
post-xRET re-entry protection **enabled** by default) and bit [3] = 0 (WFI
clock-gating **enabled**, i.e. the core may gate its clock during WFI).
Changes take effect immediately.

### Practical guidance

- **Real-time SoCs:** keep bits 0 + 1 set so worst-case IRQ latency is bounded
  by the pipeline drain rather than by the longest multi-cycle op (a radix-2
  divide is 33 cycles).
- **Handlers that themselves may not clear the IRQ source:** keep bit 2 set to
  prevent immediate re-entry.

The kill mechanism saves `mepc` to the killed instruction's PC, so `MRET`
re-executes it (the op restarts from scratch). For a Zcmp push/pop this is
architecturally correct because the loads/stores already performed are
idempotent and `sp` is only written after the last of them.

---

## 10. Double Traps and the Critical-Error State

A trap taken while the hart is already inside a trap handler that has not re-armed itself
is an **unexpected double trap**. aRVern implements both ratified extensions:
**Ssdbltrp** at S-level (`SU_MODE_EN = 1`) and **Smdbltrp** at M-level (every build).

> **Boot requirement — both bits, in this order.** `mnstatus.NMIE` resets to 0 and
> `mstatus.MDT` resets to 1. Firmware must **arm `NMIE` first, then clear MDT**: clearing
> MDT alone is not enough, because the `NMIE=0` arm still makes every M-mode trap
> unexpected. `mstatus.MIE` cannot be set until MDT is cleared — enable interrupts last.
> Until all of this is done the hart cannot take a trap at all. This is the extension
> working as intended — it refuses to take traps until the double-trap escape route exists.

### S-level: Ssdbltrp

Ssdbltrp protects the S-mode trap context (`sepc`/`scause`/`stval`/`sstatus.SPP/SPIE`)
from silent clobbering: if a *second* trap would be delegated into S-mode while the
S-mode handler has not yet saved (or returned from) the first, the second trap is
escalated to M-mode as a **double trap** instead of overwriting the S-mode CSR bank.

**CSR surface**

| CSR / field | Address / bit | Description |
|---|---|---|
| `sstatus.SDT` (also visible in `mstatus`) | bit 24 | S-mode Double Trap flag. HW-set on **every** trap taken into S-mode — exceptions *and* interrupts. HW-cleared by `SRET` unconditionally, and by `MRET`/`MNRET`/`dret` only when the new privilege mode is **U** (a return into S keeps the interrupted S handler protected). SW-writable (via `sstatus` or `mstatus`) only while `DTE = 1`; reads 0 and ignores writes while `DTE = 0`. A write that sets `SDT` to 1 forces `SIE` to 0 in the same access, and `SIE` can only be written to 1 while `SDT` is 0 or is being cleared by that write. |
| `menvcfgh.DTE` | 0x31A, bit 27 (menvcfg bit 59) | Double-Trap Enable. **Resets to 1** (protection by default — deliberate aRVern choice; the spec leaves the menvcfg reset value UNSPECIFIED). Writing 0 makes the extension behave as absent: spec-literal horizontal delegation, `SDT` reads 0. All other `menvcfgh` bits are RAZ. |
| `mtval2` | 0x34B | Machine second trap value (full MRW 32-bit). HW-written only on a double-trap delivery: the *original* trap's 5-bit cause code, zero-extended. |

**SDT lifecycle.** Hardware sets `SDT` on the same cycle the
`sepc`/`scause`/`sstatus` stack is written for any trap into S-mode
(interrupt entries arm it too — an S-mode *interrupt* handler that faults
before saving state is equally protected). While `SDT & DTE`, any further trap
whose delegation routing targets S-mode — delegated exception *or* delegated
interrupt — is re-routed to M-mode as a double trap. `SDT` is cleared by
hardware on `SRET` (and on `MRET`/`MNRET`/`dret` returning to U — not to S), or by
software writing `sstatus` bit 24 to 0.

**Re-entrant S-mode handlers** use the standard Ssdbltrp pattern — clear `SDT`
in the handler prologue *after* the trap context is safe:

```asm
s_trap_handler:
    # ... save sepc / scause / sstatus (incl. SDT) to the trap frame ...
    li   t0, (1 << 24)
    csrc sstatus, t0           # SDT = 0 -> nested S-mode traps allowed again
    # ... handler body may fault / take delegated IRQs safely from here on ...
```

**Double-trap delivery (to M-mode)**

| Item | Value |
|---|---|
| `mcause` | `16` with the interrupt bit **0** — even when the doubled event was an interrupt |
| `pc` | `mtvec` **direct** target (vectored mode applies to interrupts only; `mcause.interrupt = 0` here, so the direct vector is always used) |
| `mtval` | The value the original trap would have written (faulting address for causes 0/1/4–7, 0 otherwise — see §2) |
| `mtval2` | Original trap's cause **code** (5 bits, zero-extended, no interrupt bit — `mcause = 16` already identifies the double trap). aRVern's choice; see [`spec_compliance_notes.md`](spec_compliance_notes.md#ssdbltrp-warl-choices-menvcfghdte-resets-to-1-mtval2-doubled-interrupt-encoding-su_mode_en1) |
| `mepc` | Normal semantics for the original event class: faulting PC for a doubled exception, next-to-execute PC for a doubled interrupt |
| `mstatus.MPP/MPIE/MIE` | Normal M-mode trap entry side-effects (§11) |

Priv §3.1.6.2: *"the hart writes registers, except `mcause` and `mtval2`, with the same
information that the unexpected trap would have written if it was taken into M-mode.
The `mtval2` register is then set to what would be otherwise written into the `mcause`
register by the unexpected trap. The `mcause` register is set to 16."*

NMIs are never doubled — Smrnmi delivery bypasses the delegation routing
entirely (§7).

**Opt-out.** An OS that expects bit-exact spec-literal horizontal delegation
(nested delegated traps taken *in* S-mode, clobbering semantics per the base
Privileged spec) clears `menvcfgh.DTE` once at boot — see
[`software_guide.md` §5](software_guide.md#5-minimal-startup). The `SDT` flop
keeps being set by S-mode trap entries while `DTE = 0` (it is only masked),
so when re-enabling DTE later, clear `sstatus.SDT` with the same or the
following write, or the next delegated trap is doubled.

**Write timing.** A software write to `sstatus.SDT` or `menvcfgh.DTE` is
visible to the trap routing of the *very next* instruction in program order,
so e.g. `csrc sstatus, t0` immediately followed by a faulting instruction
already delegates horizontally.

### M-level: Smdbltrp

`mstatus.MDT` (`mstatush` bit 10) **resets to 1** and is set on every trap into M-mode.
It is cleared by `MRET`, by `SRET` executed in M-mode, by `MNRET`/debug-resume returning
below M, or by an explicit write of 0. There is no enable bit — `menvcfg.DTE` gates
Ssdbltrp only, so the sole way to disarm M-level detection is to clear MDT. A write that
sets MDT clears `mstatus.MIE`, and a write of `MIE = 1` is dropped while MDT = 1.

There are **two independent ways** for a non-RNMI trap delivered into M to be unexpected:

- **MDT is already set** — a second trap into M before the handler re-armed itself.
- **The hart is executing in M-mode with `mnstatus.NMIE = 0`** — *"a trap that occurs when
  executing in M-mode with `mnstatus.NMIE` set to 0 is an unexpected trap"*, regardless of
  MDT. With no RNMI deliverable there is no escape, so this arm always ends in the
  critical-error state.

Interrupts cannot precipitate one: trap entry clears `mstatus.MIE`, and MIE is settable
only while MDT is 0, so `MDT=1 ∧ MIE=1` is unreachable. An RNMI never does either — it
uses the `mnstatus` stack and does not consult MDT.

> **`NMIE` is software-set-only.** Writing 0 has no effect; only RNMI entry clears it. So
> after boot the only way to be running with `NMIE=0` is **inside an RNMI handler** — which
> means a fault in an RNMI handler is always a critical error.

> **Spec anchor** (quoted because the encoding is easy to get backwards):
> *"bit MXLEN-1 is set to 0 and the least-significant bits are set to the cause code
> corresponding to the exception that precipitated the double trap"* — Priv §8.3.

### Where a double trap goes

| `mnstatus.NMIE` | Outcome |
|---|---|
| `1` | **Diverted to the RNMI handler.** `mnepc` and `mncause` take the values `mepc`/`mcause` would have taken, `mnstatus.MNPP` reads M and `NMIE` clears. `mncause` bit 31 is **0** with the precipitating cause in the low bits (a doubled Ssdbltrp trap reports 16). The M trap stack is left untouched — the spec notes the RNMI handler is deliberately not given `mtval`/`mtval2`. |
| `0` | **Critical-error state.** No architectural state changes, not even the `pc`; execution ceases and `lockup_o` asserts for the platform. |

So the critical-error state is reachable in exactly two situations: **out of reset**
before firmware arms `NMIE` (locked by `debug_critical_error`), and **inside an RNMI
handler** (locked by `trap_m_dbltrp_cerror`).

> **Returning from the divert.** `MNRET` does not clear MDT when `MNPP` is M, so an RNMI
> handler that returns without writing MDT=0 will double straight back. The same discipline
> S-mode handlers need for `SDT`.

### The critical-error state

`lockup_o` is the architected critical-error signal. It is **sticky — only `hresetn_i`
clears it**; no `MRET`, `MNRET` or debug resume will lift it. While asserted the hart
fetches and decodes nothing.

The platform's response is platform-defined; the SoC should treat `lockup_o` as fatal and
route it to a watchdog reset controller.

A debugger can still halt the hart and read the post-mortem out — `dpc` names the
instruction it stopped on, and `mepc`/`mcause` still describe the trap that got it there.
Resuming returns it to the critical-error state. `dcsr.cetrig` is hardwired 0, so the hart
never diverts into Debug Mode on its own; see
[`spec_compliance_notes.md`](spec_compliance_notes.md) for both WARL choices.

---

## 11. Trap Entry and Return Summary

### Vectors

| CSR | Reset value | Notes |
|---|---|---|
| `marv_nmvec` (0x7FD) | `reset_vector + 4` | RNMI and double-trap divert vector, `[1:0]` read-only 0 |
| `mtvec` | `reset_vector + 8` | `MODE` is WARL: writes of 2/3 store 0/1 |
| `stvec` | `reset_vector + 12` | same WARL rule; `SU_MODE_EN = 1` |

The spec leaves these reset values unspecified; aRVern seeds them from `reset_vector_i` so
that a boot ROM opening with a jump table (`j _start`, `j _rnmi`, `j _mtrap`, `j _strap` —
one 32-bit jump per 4-byte slot, in trap-priority order, so an M-only build needs only the
first three) is trap-safe from its first instruction, without a CSR write. They are derived from the port rather than from `mtvec` so that the last-resort
RNMI/double-trap vector cannot be corrupted by the state it is meant to rescue. Firmware
that writes the vectors pays nothing; `mtvec` seeds with `MODE = 0` (direct), so vectored
mode always needs a write.

### `mstatus` / `mstatush` fields

| Field | Bit | Behaviour |
|---|---|---|
| `MIE` / `MPIE` / `MPP` | 3 / 7 / 12:11 | Standard. `MPP` is forced to M when `SU_MODE_EN = 0`. `MIE = 1` is dropped while `MDT = 1` |
| `SIE` / `SPIE` / `SPP` | 1 / 5 / 8 | Standard (`SU_MODE_EN = 1`); `SIE = 1` is dropped while `SDT = 1` |
| `MPRV` | 17 | Standard; ignored while `mnstatus.NMIE = 0`; cleared by `MRET`/`SRET`/`MNRET`/`dret` returning below M |
| `SUM` | 18 | Read-only 0 (no address translation) |
| `MXR` | 19 | Writable, no effect (no address translation) |
| `TVM` | 20 | Writable; S-mode `satp` access traps when set |
| `TW` | 21 | Timeout-wait, §8; read-only 0 when `SU_MODE_EN = 0` |
| `TSR` | 22 | `SRET` in S-mode traps when set |
| `SDT` | 24 | Ssdbltrp, §10 |
| `mstatush.MDT` | 10 | Smdbltrp, §10; resets to 1 |

### Entry side-effects (M-mode)

| Item | Update |
|---|---|
| `mepc` | The faulting PC (sync) or next-to-execute PC (IRQ) — IRQ-killed op replays from its start |
| `mcause` | `{is_irq, …, cause[4:0]}` |
| `mtval` | Per cause (see §2) |
| `mstatus.MPP` | Previous privilege level |
| `mstatus.MPIE` | Previous `mstatus.MIE` |
| `mstatus.MIE` | Cleared (mask further M-mode IRQs) |
| `mstatush.MDT` | Set |
| `pc` | `mtvec` base; in vectored mode (`mtvec[0]=1`) an **interrupt** goes to `mtvec_base + 4 × cause` — exceptions and double traps always use the base |
| `priv` | `2'b11` (M-mode) |

### Entry side-effects (S-mode — delegated)

Mirror of M-mode but through `sepc`/`scause`/`stval`/`sstatus.SPP`/`sstatus.SPIE`/`sstatus.SIE`. PC goes to `stvec`.
Additionally sets `sstatus.SDT = 1` (Ssdbltrp — arms double-trap protection; see §10).

### Entry side-effects (NMI)

| Item | Update |
|---|---|
| `mnepc` | Saved PC |
| `mncause` | `{1, …, code}` for an RNMI; `{0, …, cause}` for a double-trap divert (§10) |
| `mnstatus.MNPP` | Previous privilege level |
| `mnstatus.NMIE` | Cleared (mask further NMIs) |
| `pc` | `marv_nmvec` (CSR 0x7FD) |
| `priv` | `2'b11` |

### Return

| Instruction | Restores |
|---|---|
| `MRET` | `pc ← mepc`; `priv ← mstatus.MPP`; `mstatus.MIE ← MPIE`; `MPIE ← 1`; `MPP ← U` (when U-mode is supported); `mstatush.MDT ← 0`; `mstatus.MPRV ← 0` when the new privilege is below M; `sstatus.SDT ← 0` when the new privilege is U |
| `SRET` | `pc ← sepc`; `priv ← sstatus.SPP`; `sstatus.SIE ← SPIE`; `SPIE ← 1`; `SPP ← U`; `mstatus.MPRV ← 0`; `sstatus.SDT ← 0`; `mstatush.MDT ← 0` only when executed in M-mode |
| `MNRET` | `pc ← mnepc`; `priv ← mnstatus.MNPP`; `mnstatus.NMIE ← 1`; `MNPP ← M`; `mstatus.MPRV ← 0` and `mstatush.MDT ← 0` when returning below M; `sstatus.SDT ← 0` when the new privilege is U |
| `dret` (debug resume) | `pc ← dpc`; `priv ← dcsr.prv`; `mstatus.MPRV ← 0` and `mstatush.MDT ← 0` when `dcsr.prv ≠ M`; `sstatus.SDT ← 0` when `dcsr.prv = U` |

---

## See Also

- [`integration_guide.md`](integration_guide.md#5-interrupt-interface) — pin-level IRQ / NMI wiring
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — "Data-bus errors are reported asynchronously, as a resumable NMI", "CM.PUSH is not restartable if its last posted store faults after retirement", "Same-cycle synchronous exception wins over a simultaneously-pending enabled interrupt"
- [`arvern_instructions.md`](arvern_instructions.md#smrnmi--resumable-nmi-extension) — Smrnmi summary in the ISA reference
- [`software_guide.md`](software_guide.md#8-trap-handler-skeleton) — handler skeletons
- `rtl/verilog/arv_csr_traps.v` — implementation
