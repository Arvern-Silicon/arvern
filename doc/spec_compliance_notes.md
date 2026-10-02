<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern — Spec Compliance Notes
  <br clear="all">
</h1>

> The first section reports the **measured** conformance result: aRVern passes the official
> **RISC-V Architectural Certification Tests** (ACT4, from
> [`riscv/riscv-arch-test`](https://github.com/riscv/riscv-arch-test)) on all four published
> personas — **620 tests, no waivers**.
>
> The rest of the document records places where the RISC-V spec is UNSPECIFIED,
> implementation-defined, or permissive — aRVern's deliberate choices in those regions — and a
> small set of acknowledged gray-area decisions. **It is not a list of spec violations.** Each
> entry opens with its firmware impact, then states the behaviour, the spec basis and where to
> look — the RTL identifier that encodes the choice and the test that locks it in (an entry
> without one says so). This document is the authority on accepted deviations: no other
> document proposes "fixing" one.
>
> - **Implementation Choices** — the spec delegates the behaviour to the implementor or does not
>   address the case. Not a deviation.
> - **Deviations and Caveats** — the spec's intent is stretched or a restartability limit exists;
>   documented for transparency.

| Entry | Firmware impact | Where to look |
|---|---|---|
| [Reserved OP/OP-IMM funct7](#reserved-op--op-imm-funct7-and-reserved-shift-imm115-execute-as-the-nearest-defined-op) | none for compiled code; hand-written reserved encodings execute silently | `id_standard_ops` / `id_alu_mode`; no lock-in test |
| [Other reserved code points](#other-reserved-code-points-execute-as-the-nearest-defined-op-compressed-space-jalr-funct3-misc-mem-funct3) | none for compiled code | decode terms in `arv_decode.v`; no lock-in test |
| [minstret vs. data-bus NMI](#minstret-is-not-un-retired-by-an-asynchronous-data-bus-nmi-zicntr) | an instruction whose access later bus-errors stays counted | `inst_zicntr_instret_excp` |
| [mcycle in WFI](#mcycle-freezes-during-wfi-sleep-zicntr) | `mcycle` stops while the clock is gated | `marv_ctl[3]`; `inst_zicntr_cycle` |
| [RV32E x16–x31](#rv32e-reserved-registers-x16x31-read-0--writes-dropped-no-trap-rv32e_en1) | none for conforming code | `RV32E_MODE` generate; `inst_rv32e_xregs` |
| [dcsr.mprven](#dcsrmprven-hardwired-0-sdext-external-debug-debug_en1) | none | `dcsr` compose; no lock-in test |
| [dcsr.cetrig](#dcsrcetrig-hardwired-0--critical-errors-always-signal-the-platform-sdext-debug_en1) | a critical error asserts `lockup_o`, never halts into Debug Mode | `dcsr_cause`; `debug_critical_error` |
| [Halt in critical-error state](#halting-a-hart-already-in-the-critical-error-state-is-unspecified) | post-mortem readable; resume returns to lockup | `in_lockup`, `crit_error_pc` |
| [Ssdbltrp WARL choices](#ssdbltrp-warl-choices-menvcfghdte-resets-to-1-mtval2-doubled-interrupt-encoding-su_mode_en1) | S double-trap protection on out of reset; `mtval2` has no interrupt bit | `u_menvcfgh_dte`, `mtval2_nxt` |
| [U-mode WFI](#wfi-is-not-available-to-u-mode-su_mode_en1-bounded-time-limit-of-0) | U-mode `wfi` traps regardless of TW | `trap_wfi_umode` |
| [Misaligned + PMP-denied](#misaligned-loadstore-into-a-pmp-denied-region-reports-the-access-fault-pmp_nr0) | cause 5/7, not 4/6 | `trap_pmp_misc` |
| [Smepmp MML per entry](#smepmp-mml-write-restriction-is-applied-per-pmp-entry-not-per-pmpcfg-word-pmp_nr0) | a `pmpcfg` write can partially succeed — read it back | `mml_ignore`; `trap_pmp_mml` |
| [MNPP after MNRET](#mnstatusmnpp-is-rewritten-to-m-by-mnret-smrnmi) | `MNPP` reads M after `mnret` | `mnstatus_mnpp` next-state; `trap_smrnmi_mnpp_after_mnret` |
| [Watchpoints on the Zcmt table read](#loadstore-watchpoints-match-the-zcmt-table-read-c_extension4-dm_trigger_nr0) | a load watchpoint on a jump-table entry fires on `cm.jt`/`cm.jalt` | `ex_is_load_o` (`arv_load_store.v`); `debug_trigger_ldst_uop` |
| [Data-bus errors](#data-bus-errors-are-reported-asynchronously-as-a-resumable-nmi) | bus error = RNMI, never `mcause` 5/7; `cm.jt` case loops on plain `mnret` | `trap_nmi_bus_error`, `trap_zcmt_jt_fault` |
| [Exception vs. same-cycle IRQ](#same-cycle-synchronous-exception-wins-over-a-simultaneously-pending-enabled-interrupt) | handler may run with the IRQ still pending | `irq_detect & ~excp_detect`; `trap_excp_late_fault_irq` |
| [CM.PUSH restartability](#cmpush-is-not-restartable-if-its-last-posted-store-faults-after-retirement) | replaying a push after a late store error double-decrements `sp` | `uop_sp_upd_active` / `uop_ldst_wait` |
| [RAZ/WI in known banks](#non-existent-csrs-in-known-banks-read-as-0-razwi-do-not-trap) | a mistyped CSR inside a window reads 0 | `any_bank_known`, `hpm_csr_absent` |

---

## Architectural Certification Result (riscv-arch-test)

aRVern is run against the official **RISC-V Architectural Certification Tests** — ACT4, from
[`riscv/riscv-arch-test`](https://github.com/riscv/riscv-arch-test), pinned at
[`a5d6e02`](https://github.com/riscv/riscv-arch-test/commit/a5d6e0235d959b3165ee331d8bc3b49adb038e25).
ACT4 builds **self-checking ELFs**: expected results are produced by running the
[**sail-riscv**](https://github.com/riscv/sail-riscv) 0.13.1 reference model at generation
time and baked into each image, so a run needs no signature dump and no comparison — the test
reports its own verdict. Flow, build adjustments and per-suite counts:
[`../sim/arch_test/README.md`](../sim/arch_test/README.md).

**All four published personas pass — 620 tests, no waivers.**

| Persona | Configuration | Tests | Result |
|---|---|---|---|
| `light` | RV32E + Zmmul + Zca, M-mode only | 69 | **69/69** |
| `classic` | RV32I + M + Zbb + Zca + Zicntr, M-mode only | 109 | **109/109** |
| `performance` | + full B, Zcb, M+S+U, PMP | 220 | **220/220** |
| `ultra` | as `performance`, plus Zcmp/Zcmt and Zihpm | 222 | **222/222** |

ACT selects tests from the DUT's UDB config, so the set tracks the persona; `light` runs
instruction tests only. Two verification-only configurations are run as well: `m-pmp`
(`classic` with `PMP_NR=8` — PMP present while the S bank, `mideleg`/`medeleg`,
`mcounteren` and `menvcfg` are absent; 154 tests) and `su-nocntr` (`performance` with
`ZICNTR_EN=0` — `mcounteren` present, counters absent; 209 of 210 pass, the one gap being an
upstream `mcountinhibit` assumption).

The following points are not covered by the test suite:

- **Smepmp MML** — `mseccfg` is absent from sail-riscv 0.13.1's config schema, so Smepmp is not
  declared to the suite and the MML truth table is exercised only by the directed
  `trap_pmp_*` tests in `sim/rtl_sim/src`.
- **Smrnmi (resumable NMI)**, **Ssdbltrp** and **Smdbltrp** — the reference model implements
  none of the three. `menvcfgh.DTE` and `mstatush.MDT` are forced to 0 by the arch-test
  stimulus (each force announces itself as an `ACT-INFO:` line in the run log); the RTL keeps
  its reset values. `mnstatus.NMIE` is set to 1 by the DUT boot macro in `rvmodel_macros.h`,
  as real firmware must. All three extensions are covered instead by the directed
  `trap_smrnmi_*`, `trap_s_dbltrp_*` and `trap_m_dbltrp_*` tests in `sim/rtl_sim/src`.

Debug builds (`DEBUG_EN=1`) additionally implement Sdtrig, which the suite cannot exercise
either — the reference model has no triggers, and upstream excludes those suites by default.

---

## Implementation Choices

Entries below are spec-permissible by virtue of being UNSPECIFIED or explicitly
implementation-defined. aRVern made a deliberate choice; it is not a deviation.

### Reserved OP / OP-IMM funct7 (and reserved shift imm[11:5]) execute as the nearest defined op

**Firmware impact**: none for compiled code; a hand-written encoding with a reserved `funct7`
executes silently as the nearest defined op instead of trapping.

**Behaviour** (`arv_decode.v`): OP / OP-IMM operations are decoded by `funct3`
(`id_standard_ops`); `funct7` and shift `imm[11:5]` only select ADD/SUB, SRL/SRA and the
M / Zbb / Zba / Zbs / Zbc ops. A reserved value executes as the `funct3` op (a reserved OP
`funct7` with bit 0 set selects the MUL/DIV mode, `id_alu_mode`, when M is present). The exact
M encoding traps when M is absent, as do DIV/REM under Zmmul (`id_m_invalid`); a B encoding on
a build without that sub-extension falls through to the base op. Reserved *major opcodes* and
reserved *funct3* values (LOAD/STORE 011/110/111, BRANCH 010/011, SYSTEM 100, non-canonical
SYSTEM 000) do trap — the leniency is confined to `funct7` / `imm[11:5]` and the four code
points of the next entry.

**Spec basis**: Unpriv §2.2 *"The behavior upon decoding a reserved instruction is
UNSPECIFIED"*; §1.6 reserved encodings *"may cause a fatal trap"* — may, not must. These are
reserved encodings, not HINTs.

**Where to look**: `id_standard_ops` / `id_alu_mode` in `arv_decode.v` (timing-critical
path). No lock-in test.

### Other reserved code points execute as the nearest defined op (compressed space, JALR funct3, MISC-MEM funct3)

**Firmware impact**: none for compiled code; the four encodings below execute rather than trap.

**Behaviour** (`arv_decode.v`): **C.SH with `inst[6]=1`** executes as C.SH (`inst[6]` is not
decoded); **CM.MVSA01 with `r1s' == r2s'`** copies `a0` and `a1` into the same `sN`; **JALR
with `funct3 != 000`** executes as JALR; **MISC-MEM with a `funct3` other than FENCE `000` /
FENCE.I `001`** retires as a NOP (neither the FENCE stall nor the FENCE.I flush fires).

**Spec basis**: Unpriv §2.2 — reserved, UNSPECIFIED; none is a HINT.

**Where to look**: the C.SH, CM.MVSA01, JALR and MISC-MEM decode terms in `arv_decode.v`
(none examines the reserved field). No lock-in test.

### minstret is not un-retired by an asynchronous data-bus NMI (Zicntr)

**Firmware impact**: an instruction whose data access later returns a bus error (RNMI) stays
counted in `minstret`; a synchronously-trapping instruction, and a MUL/DIV or Zcmp/Zcmt sequence
killed by an IRQ/NMI, are un-retired.

**Behaviour**: `minstret_undo_o` (`arv_csr_traps.v`) fires for synchronous exceptions and for
`trap_kill_restart` (the killed op re-dispatches after `xRET`), not for a data-bus RNMI: the
access and any younger instructions did execute, and `mnret` resumes past them, so nothing is
double-counted.

**Spec basis**: Unpriv Zicntr and Priv §3.3.1 mandate the synchronous rule; a late
asynchronous bus response is unaddressed because reporting one is itself an implementation
choice (see [Data-bus errors](#data-bus-errors-are-reported-asynchronously-as-a-resumable-nmi)).

**Where to look**: `minstret_undo_o` in `arv_csr_traps.v`; `inst_zicntr_instret_excp`
asserts the ID/EX classes at delta==1 and the WB class NOT un-retired (delta > 1 — the exact
value is bus-timing shaped, so the property is asserted, not the number).

### mcycle freezes during WFI sleep (Zicntr)

**Firmware impact**: `mcycle` does not advance while the SoC gates the core clock during WFI;
set `marv_ctl[3]` (`wfi_clkgate_dis`) to keep it counting.

**Behaviour**: `hclk_en_o` drops when the core enters WFI with both AHB masters drained; the
SoC-level clock gate stops every core flop, `mcycle` included, until a wake event re-enables
`hclk_en_o` combinationally.

**Spec basis**: implementation-defined — `mcycle` may be real-time-anchored or a literal count
of clocked cycles; aRVern is the latter (single gated clock domain).

**Where to look**: `hclk_en_o` / `marv_ctl[3]`; `inst_zicntr_cycle` (WFI phase).

### RV32E reserved registers x16–x31 read 0 / writes dropped, no trap (RV32E_EN=1)

**Firmware impact**: none for conforming code; a reference to x16–x31 reads 0 or has its write
discarded, without a trap.

**Behaviour**: the narrowing lives only in `arv_int_registers.v` (`RV32E_MODE` generate:
x16–x31 flops absent, reads tied to 0, writes dropped), including its JALR-shadow and
decode-port forwarding paths, so the reads-0 contract holds in every window. Decode is
RV32I/RV32E bit-identical. The `light` persona passes the generated RV32E suite 69/69; no test
body names x16–x31.

**Spec basis**: Unpriv §3.2 *"All encodings specifying the other registers x16–x31 are
reserved"* — UNSPECIFIED, no illegal-instruction mandate, no source/destination distinction.

**Where to look**: the `RV32E_MODE` generate block in `arv_int_registers.v` (decode is
bit-identical between RV32I and RV32E, so RV32E verification is confined to the register file
and `misa`); `inst_rv32e_xregs`.

### dcsr.mprven hardwired 0 (Sdext external debug, DEBUG_EN=1)

**Firmware impact**: none — there is no program buffer, so the hart never executes in Debug
Mode and `MPRV` has nothing to act on there.

**Behaviour**: `dcsr.mprven` reads 0 (tied off in `arv_csr_debug.v`). `mstatus.MPRV` works
normally outside Debug Mode; debugger memory access goes through System Bus Access
(`arv_debug_sba.v`), which bypasses the hart datapath and privilege entirely.

**Spec basis**: Debug 1.0 — `dcsr.mprven` is WARL and may be hardwired.

**Where to look**: the `dcsr` compose in `arv_csr_debug.v`. No lock-in test.

### dcsr.cetrig hardwired 0 — critical errors always signal the platform (Sdext, DEBUG_EN=1)

**Firmware impact**: a double trap with no RNMI escape asserts `lockup_o` and ceases execution;
the hart never halts itself into Debug Mode.

**Behaviour**: `cetrig` reads 0 (tied off in `arv_csr_debug.v`); writes of 1 are dropped.

**Spec basis**: Debug §4.9.1 lists `cetrig` as WARL, reset 0 — `0`: *"does not enter Debug
Mode but instead asserts the critical-error signal to the platform"*. §1.3 defines WARL as
*"the implementation converts the value to one that is supported"*, and Priv §2.3.3 adds that
such writes *"will not raise an exception"*; a WARL field with one legal value is conformant.

**Where to look**: `dcsr_cause` in `arv_csr_debug.v`; `debug_critical_error` (phase A:
`lockup_o` asserted, Debug Mode not entered).

### Halting a hart already in the critical-error state is UNSPECIFIED

**Firmware impact**: a debugger can halt a locked-up hart and read the post-mortem; `dpc` names
the instruction the trap stopped on, and resuming returns the hart to the critical-error state.

**Behaviour**: debug entry requires `~trap_pending_i`, and the trap that caused the critical
error cleared it as it was taken, so `debug_req_i` is honoured. `dpc` is loaded from
`crit_error_pc`, captured sticky at critical-error entry (the value `mepc` would have taken).
On resume the sticky critical-error flop still drives `trap_stall_o` and `if_stop_cmd_o`.

**Spec basis**: neither the Priv nor the Debug spec says whether a hart in the critical-error
state with `cetrig=0` may be halted or what `dpc` reads; the adjacent `cetrig=1` rule (Debug
§4.9.1, *"Resuming from Debug Mode following an entry from the critical error state returns the
hart to the critical error state"*) is matched.

**Where to look**: `in_lockup` (cleared only by reset) and `crit_error_pc` (inside `g_debug`); `debug_critical_error`.

### Ssdbltrp WARL choices: menvcfgh.DTE resets to 1; mtval2 doubled-interrupt encoding (SU_MODE_EN=1)

**Firmware impact**: S-mode double-trap protection is on out of reset — an S handler that
traps before saving its context is delivered to M with `mcause=16`; write `menvcfgh.DTE=0`
for spec-literal horizontal delegation. For a doubled *interrupt* `mtval2` holds the cause
code only, without the interrupt bit.

**Behaviour** (`arv_csr_traps.v`, `g_ssdbltrp`): `menvcfgh.DTE` resets to 1
(`arv_dff #(.RST_VAL(1'b1)) u_menvcfgh_dte`); with DTE=0 the extension behaves as absent
(`SDT` reads 0, writes ignored, no redirect); other `menvcfgh` bits are RAZ and `menvcfg`
(0x30A) is RAZ/WI. On a double trap `mtval2 = {27'h0, cause[4:0]}` for doubled exceptions and
interrupts alike; every other register, `mtval` included, takes what the trap would have
written had it gone to M directly. `mtval2` itself is a full MRW 32-bit CSR.

**Spec basis**: Priv §3.1.6.2 mandates the redirect: *"the hart writes registers, except
`mcause` and `mtval2`, with the same information that the unexpected trap would have written if
it was taken into M-mode. The `mtval2` register is then set to what would be otherwise written
into the `mcause` register by the unexpected trap. The `mcause` register is set to 16."* The
`menvcfg` reset value is UNSPECIFIED; DTE=1 mirrors the mandated reset-to-1 of `mstatus.MDT`.
The interrupt-bit omission is aRVern's deliberate choice against that sentence: `mcause=16`
already marks the event and a handler can tell a doubled interrupt by code range.

**Where to look**: `RST_VAL` of `u_menvcfgh_dte` and the `mtval2_nxt` compose term;
`trap_s_dbltrp_*` (the ACT suite forces DTE=0, see above).

### WFI is not available to U-mode (SU_MODE_EN=1): bounded time limit of 0

**Firmware impact**: a U-mode `wfi` raises illegal-instruction regardless of `mstatus.TW`;
U-mode idle must go through a supervisor call. S-mode `wfi` with TW=0 sleeps, possibly
indefinitely.

**Behaviour**: `arv_decode.v` raises illegal-instruction for WFI in U-mode whenever
`SU_MODE_EN=1`, without stalling first; the separate TW=1 rule is implemented alongside and
covers S-mode.

**Spec basis**: Priv 3.1.6.6 — *"executing WFI in U-mode causes an illegal-instruction
exception, unless it completes within an implementation-specific, bounded time limit"*, a rule
independent of TW; 3.3.3 makes WFI *"optionally available to U-mode"*. A bound of zero is
legal, and an unbounded S-mode WFI is what TW exists to bound.

**Where to look**: `id_opcode_wfi_illegal` in `arv_decode.v`; `trap_wfi_umode` (U-mode/TW=0
traps; S-mode/TW=0 sleeps and wakes); the reference model matches via
`wfi_available_to_user_mode: false` in `sim/arch_test/src/arvern-*/sail.json`.

### Misaligned load/store into a PMP-denied region reports the access fault (PMP_NR>0)

**Firmware impact**: an access that is both misaligned and PMP-denied reports cause 5/7 with
`mtval` = effective address, not 4/6; a misaligned but permitted access reports 4/6 as usual.

**Behaviour**: the PMP checker evaluates the address whether or not the access will be issued
(a misaligned access never is), and its denial outranks the misalignment.

**Spec basis**: Priv 3.1.15 — *"Load/store/AMO address-misaligned exceptions may have either
higher or lower priority than load/store/AMO page-fault and access-fault exceptions."* The
sail-riscv reference makes the same choice (`MISALIGNED_LDST_EXCEPTION_PRIORITY: low`), so
the certification suite and aRVern agree.

**Where to look**: the exception priority in `arv_csr_traps.v`; `trap_pmp_misc` (aligned and
misaligned loads and stores into a region with no permissions: 5/7 for all four, `mtval` for
the misaligned pair).

### Smepmp MML write restriction is applied per PMP entry, not per pmpcfg word (PMP_NR>0)

**Firmware impact**: with `MML` set, a multi-byte `pmpcfg` write can partially succeed — only
the byte that would create an M-mode-executable locked rule is dropped; read the register back.

**Behaviour** (`arv_csr_pmp.v`, `mml_ignore`): the restriction is evaluated per entry and the
other three entries of the same `pmpcfgN` are written normally, as the sail-riscv reference
does.

**Spec basis**: Smepmp item 4b — *"such pmpcfg writes are ignored, leaving pmpcfg unchanged"* —
does not say whether "pmpcfg" is the entry's byte or the whole word; every other PMP rule in
the chapter is phrased per entry.

**Where to look**: `mml_ignore` in `arv_csr_pmp.v`; `trap_pmp_mml` (the full MML truth table
and the rejected locked M-execute write). Not covered by riscv-arch-test (sail 0.13.1 has no
`mseccfg`).

### mnstatus.MNPP is rewritten to M by MNRET (Smrnmi)

**Firmware impact**: `mnstatus.MNPP` reads M after `mnret`; do not use it to recover the
pre-RNMI privilege after return.

**Behaviour** (`arv_csr_traps.v`): `MNRET` sets `MNPP` back to M, mirroring the `mstatus.MPP`
rule for `MRET`; sail-riscv leaves it unchanged. The difference is observable only by reading
`mnstatus` after `MNRET` outside an RNMI handler.

**Spec basis**: Smrnmi defines `MNPP` as the privilege at RNMI entry and says nothing about its
value after `MNRET`; the field is WARL.

**Where to look**: the `mnstatus_mnpp` next-state in `arv_csr_traps.v`; `trap_smrnmi_mnpp_after_mnret` (RNMI from M and from U: the entry privilege is captured, and both MNRETs leave MNPP reading M).

### Load/store watchpoints match the Zcmt table read (C_EXTENSION>=4, DM_TRIGGER_NR>0)

**Firmware impact**: a load watchpoint (`mcontrol6.load=1`) on a jump-table entry fires when
`cm.jt`/`cm.jalt` reads that entry, as for any load of it.

**Behaviour**: the table read goes through the load/store unit and is presented to the
trigger module as a load (`ex_is_load_o`), while PMP checks it as an instruction fetch (X
permission, no MPRV). A watchpoint on the table can locate a corrupted or unexpected
dispatch; a debugger that does not want it simply does not arm one there.

**Spec basis**: Zcmt, table jump — *"It is recommended that the second fetch be ignored for
hardware triggers and breakpoints."* A recommendation, not a requirement.

**Where to look**: `ex_is_load_o` in `arv_load_store.v`; `debug_trigger_ldst_uop` (phase J arms
an action=1 watchpoint on the table entry).

## Deviations and Caveats

Entries below stretch the spec's intent in ways that match common implementations, or record a
restartability limit. Documented for transparency rather than because compliance is in question.

### Data-bus errors are reported asynchronously, as a resumable NMI

**Firmware impact**: an AHB error on a load or store arrives as an RNMI (`mncause=0x80000003`)
with `marv_epc` / `marv_eaddr` / `marv_estat` as evidence, never as `mcause` 5/7; `mnepc`
resumes past the access and replay is opt-in. One exception: a bus error on a `cm.jt`/`cm.jalt`
table read leaves `mnepc` on the `cm.jt` itself, so a plain `mnret` loops — the handler must
panic or redirect.

**Behaviour**: `mcause` 5 and 7 are raised only by the PMP checkers (`PMP_NR>0`), which decide
before the access is issued; at `PMP_NR=0` the two codes have no producer. Instruction-bus
errors stay synchronous (`mcause=1`, `medeleg[1]` a normal delegation bit). Evidence, all
latched on the faulting access's own address phase:

| CSR | holds |
|---|---|
| `mnepc` | WHERE to resume |
| `marv_epc` (0xFFC) | WHAT faulted — the faulting instruction's PC |
| `marv_eaddr` (0xFFD) | the address that faulted |
| `marv_estat` (0x7FE) | `uop_sourced[4]`, `restartable[3]`, `overrun[2]`, `store[1]`, `valid[0]` — `valid`/`overrun` W1C |

`marv_estat.restartable` is exact — keyed on whether the sequence that issued the access still
owns the pipeline (`wb_uop_seq_alive`) — and forced to 0 for Zcmt table reads
(`wb_uop_jt_sourced`). A handler that wants to retry writes `mnepc` from `marv_epc` itself.

**Spec basis**: RISC-V traps are precise, and a late data-phase response cannot be attributed
precisely without holding every access against its own response, at a real throughput cost.
aRVern therefore reports the event through a channel that is *defined* as asynchronous, and
`mcause` 5/7 keep one meaning: a PMP denial, decided before issue and recoverable. The `cm.jt`
case transposes Zcmt §28.14.2 — the table entry *"is considered an extension of the instruction
itself"* and an exception on either fetch sets `xepc` to the table-jump instruction — to the
RNMI channel: the jump target was never read, so there is no correct resume point.

**Where to look**: `nmi_bus_pending` in `arv_csr_traps.v`, `marv_estat` in `arv_csr_top.v`;
`trap_nmi_bus_error` (delivery, cause, evidence, `mtvec` never entered),
`trap_marv_ecapture_uop` / `trap_marv_ecapture_abut` (restartable classification),
`trap_zcmt_jt_fault`, `trap_excp_ldfault_vs_ecall` (a faulting load still does not write `rd`),
`trap_excp_load_rd_x0` (`lw x0` is not a side-effect-free probe).

### Same-cycle synchronous exception wins over a simultaneously-pending enabled interrupt

**Firmware impact**: an exception handler may start with an enabled interrupt still pending;
the interrupt is taken right after the handler's `xRET` (or inside it, once `mstatus.MIE`
allows). Nothing is lost; only the delivery order is inverted.

**Behaviour**: `arv_csr_traps.v` latches the trap type as `irq_detect & ~excp_detect` — a
synchronous exception co-firing with an enabled pending IRQ is taken first.

**Spec basis**: the conventional reading (and sail-riscv) takes a pending enabled interrupt
before the instruction's synchronous exception, with `mepc` at the faulting instruction so it
re-faults after `xRET`. Reversing the order here would interact with the kill/`mepc`-settle
machinery for no functional gain, since both events are always delivered.

**Where to look**: `irq_detect & ~excp_detect` in `arv_csr_traps.v`; `trap_excp_late_fault_irq`.

### CM.PUSH is not restartable if its last posted store faults after retirement

**Firmware impact**: after a bus error on a `cm.push`'s last store, `marv_estat.restartable`
reads 0 — replaying from `marv_epc` would decrement `sp` a second time. A plain `mnret`
resumes past the push.

**Behaviour**: the push SP-update is not gated on the last store's AHB data phase
(`arv_uop_sequencer.v` gates the pop variants only). A bus error on that store arrives as the
RNMI with `marv_epc` naming the `cm.push` and `restartable=0`, because `sp` is already
decremented. The pop/popret variants are fully gated (ra/`sp` ordering guaranteed).

**Spec basis**: Zcmp specifies the push sequence with `sp` updated last so that re-execution
after a precise fault is idempotent; here the fault is not precise (see the data-bus entry).

**Where to look**: the `uop_sp_upd_active` / `uop_ldst_wait` gate (pop variants only);
`trap_zcmp_popret_partial_atomic` (pop side), `trap_excp_zcmp_push_fault` (push side).

### Non-existent CSRs in known banks read as 0 (RAZ/WI), do not trap

**Firmware impact**: a mistyped CSR address *inside* an implemented window reads 0 and drops
writes instead of trapping. An address above a window's highest implemented offset, and a
register a build parameter removes, do raise illegal-instruction.

**Behaviour**: `any_bank_known` (`arv_csr_top.v`) range-checks each 64-CSR window up to its
highest implemented offset; holes below the bound are RAZ/WI:

| Window | Bound | Holes below the bound? |
|---|---|---|
| 0x140 (sscratch..sip) | <= 0x04 | none — exact; whole window traps at `SU_MODE_EN=0`. `stimecmp`/`stimecmph` (Sstc, 0x14D/0x15D) trap as the spec requires |
| 0x180 (satp) | == 0x00 | none — exact; whole window traps at `SU_MODE_EN=0` |
| 0xF00 (mvendorid..mconfigptr) | 0x11..0x15 | none in range |
| 0x100 (sstatus..senvcfg) | <= 0x0A | yes; whole window traps at `SU_MODE_EN=0` |
| 0x340 (mscratch..mtval2) | <= 0x0B | yes |
| 0x740 (NMI) | <= 0x04 | yes |
| 0x300 (mhpmevent), 0xB00/0xB80/0xC00/0xC80 (counters) | per register | `hpm_csr_absent` — two-case rule, see below |

A register a build parameter removes traps rather than reading 0 — the bank term drops with
it, or `any_bank_known` carries an explicit carve-out:

| register / bank | removed when | behaviour when absent |
|---|---|---|
| 0x100 / 0x140 / 0x180 (S-mode banks) | `SU_MODE_EN = 0` | illegal-instruction |
| 0x302 `medeleg`, 0x303 `mideleg`, 0x306 `mcounteren`, 0x30A `menvcfg`, 0x31A `menvcfgh` | `SU_MODE_EN = 0` | illegal-instruction (each exists only to serve a lower privilege; `medeleg[5]`/`[7]` are also read-only 0 at `PMP_NR = 0`) |
| 0x3A0-0x3BF (`pmpcfg*`/`pmpaddr*`), 0x747/0x757 (`mseccfg`) | `PMP_NR = 0` | illegal-instruction |
| 0xB00/0xB80/0xC00/0xC80 counter windows | `ZICNTR_EN = 0` and `ZIHPM_NR = 0` | illegal-instruction (`rdcycle` traps on `light`). With `ZICNTR_EN = 0` but `ZIHPM_NR > 0` the windows exist for the HPM counters, so `cycle`/`time`/`instret`, `mcycle`/`minstret` and their high halves are holes in a known window: RAZ/WI |
| 0x017 `jvt` | `C_EXTENSION < 4` | illegal-instruction |
| 0x7A0-0x7A5 `tselect`..`tcontrol` | `DM_TRIGGER_NR = 0` | illegal-instruction |
| 0x7B0-0x7B3 `dcsr`/`dpc`/`dscratch*` | always, from the hart | illegal-instruction (debugger-only) |
| 0x800-0xDFF CCSR banks | `CCSR_EN = 0` | illegal-instruction; 0xFFC-0xFFF (`marv_epc`/`marv_eaddr`/`reset_vector`/`marv_cfg`) are always present |

Two exceptions to the range check. **0x7C0-0x7FF is never range-checked**: it is the
architecturally designated custom region; `marv_nmvec` (0x7FD), `marv_estat` (0x7FE) and
`marv_ctl` (0x7FF) are implemented and the remaining 61 addresses read 0 / drop writes, so an
integrator may probe it freely. **The Zihpm ranges follow a two-case rule** (`hpm_csr_absent`,
gated on `ZIHPM_NR == 0`): at `ZIHPM_NR == 0` the extension is absent and
`mhpmcounter3–31`/`mhpmevent3–31` raise illegal-instruction; at `ZIHPM_NR > 0` the whole set
exists and the registers this build does not provide are **read-only zero, not absent** (the
read mux returns 0 and `arv_csr_hpm.v` masks writes with `HPM_WARL_MASK`). Firmware can
therefore probe `mhpmcounter3` upward and read zeros past the implemented set. Lower-privilege
access is policed separately by `mcounteren` / `scounteren`.

**Spec basis**: Priv §2.1 — access to a non-existent CSR is reserved (illegal-instruction);
§3.1.8 — without S-mode *"the `medeleg` and `mideleg` registers should not exist"*; §3.1.11 —
`mcounteren` exists only if U-mode is implemented; §3.1.10 — *"a legal implementation is to
make both the counter and its corresponding event selector be read-only 0"*. The RAZ/WI holes
are within an implemented register's window, where bank-level decode is simpler and well-behaved
firmware never looks; where the set is parameterizable (Zihpm) the check is per register.

**Where to look**: `any_bank_known`, `hpm_csr_absent`, `HPM_WARL_MASK` in `arv_csr_top.v`;
riscv-arch-test `ultra` (`Sm_mcsr-00`) locks the HPM read-only-zero rule.
