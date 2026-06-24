<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern — Spec Compliance Notes (full reference)
  <br clear="all">
</h1>

> This document records places where the RISC-V spec is UNSPECIFIED, implementation-defined, or
> permissive — aRVern's deliberate choices in those regions — and a small set of acknowledged gray-area
> decisions where the spec's intent is ambiguous. **It is not a list of spec violations.**
>
> Entries are grouped into two categories:
>
> - **Implementation Choices** — the spec explicitly delegates the behavior to the implementor, or doesn't
>   address the case at all. aRVern picked a sensible, deterministic choice. Not a deviation.
> - **Acknowledged Spec Gray Areas** — the spec's intent is ambiguous, and aRVern's behavior matches
>   industry-standard implementations (Rocket / Ariane / CV32E). Documented for transparency.

---

## Implementation Choices

Entries below are spec-permissible by virtue of being UNSPECIFIED or explicitly implementation-defined. aRVern made a deliberate choice; it is not a deviation.

### Reserved OP / OP-IMM funct7 (and reserved shift imm[11:5]) execute as the nearest defined op

**Spec posture** (RISC-V Unprivileged ISA §2.2): *"The behavior upon decoding a reserved
instruction is UNSPECIFIED."* §1.6 adds that reserved encodings *"may cause a fatal trap"* —
**may**, not must. These encodings are *reserved*, not HINTs (HINTs are a specifically-listed
rd=x0 subspace of *defined* instructions; reserved funct7 is not in the HINT table). The base
ISA therefore does **not** require an illegal-instruction exception here; a platform/profile
standard may impose stricter behavior.

**aRVern behavior**: `arv_decode.v` decodes OP / OP-IMM ALU operations purely by `funct3`
(`id_standard_ops = (id_opcode_op | id_opcode_opimm) ? (8'h01 << id_funct3) : ...`). `funct7`
is consulted only to pick ADD-vs-SUB and SRL-vs-SRA and to enable M / Zbb / Zba / Zbs / Zbc
ops. A `funct7` (or shift `imm[11:5]`) value that is reserved — i.e. not one of the defined
base / M / B encodings — is **not trapped**; the instruction executes as the nearest defined
op (e.g. an unknown OP funct7 with funct3=000 behaves as ADD). M/B-extension absence *is*
trapped separately (`id_m_invalid`, the B-subext param gates); this deviation is only about
*reserved* funct7 within the implemented extension set.

**Rationale**: spec-permissible (UNSPECIFIED), and consistent with this project's posture of
documenting permissible deviations rather than adding non-mandated logic to the Fmax-critical
decode path. Well-behaved toolchains never emit reserved encodings.

### Non-existent CSRs in known banks read as 0 (RAZ/WI), do not trap

**Spec requirement** (RISC-V Privileged spec §2.1): An access to a CSR that is not implemented
should raise an illegal-instruction exception.

**Actual behavior**: aRVern traps only when the *bank* (CSR address [11:6]) is unknown. Within
any bank that contains at least one implemented CSR, unimplemented addresses contribute 0 to the
read mux (RAZ) and silently drop writes (WI) — no illegal-instruction trap. Affected banks
include 0x100 (S-mode trap setup/handling), 0x180 (satp), 0x300 (M-mode trap setup), 0x320
(mcountinhibit), 0xB00/0xB80 (mcycle/minstret/mhpmcounter), 0xF10 (machine ID).

**Rationale**: simpler decode (bank-level rather than per-CSR known-set), and the practical
impact is null — well-behaved firmware does not poke at unimplemented CSRs, and the WARL-stub
class permits implementations to interpret writes liberally.

### minstret counts trapping instructions (Zicntr)

**Spec requirement** (RISC-V Privileged spec, §3.1.11): Instructions that cause synchronous
exceptions — including illegal instructions, privilege-level CSR violations, ECALL, EBREAK,
load/store address misalignment, and access faults — must **not** be counted by `minstret`.

**Actual behavior**: aRVern **does** count them. Every instruction counted at dispatch time
(`id_inst_retired_o = id_instruction_request_o & id_instruction_valid_i & (id_use_std_path | id_use_c_path)`
in `arv_decode.v`), which fires in the decode stage. CSR privilege exceptions are detected
one cycle later in the execute stage (`ex_excp_illegal_inst` consumed at `arv_csr_top.v` to
gate `ex_csr_reg_dest_wr_o`, derived from the registered `ex_operand2[11:0]`). The resulting
`fetch_stall_from_trap` suppresses the *next*
instruction's dispatch, but the faulting instruction itself has already been counted.

**Root cause**: Dispatch-stage counting rather than commit/WB-stage counting. Fixing this would require
either moving the `minstret` increment to the WB stage or adding a retroactive decrement when
`excp_detect_in_ex` or `excp_detect_in_wb` fires — a adding complexity for something which is in not a problem in practice.


### mcycle freezes during WFI sleep (Zicntr)

**Spec posture**: The RISC-V Privileged spec leaves the behavior of `mcycle` during WFI
implementation-defined. Implementations may either keep `mcycle` running (treating it as
real-time-anchored) or freeze it (treating it as a literal count of *clocked* machine cycles).

**aRVern behavior**: `mcycle` **freezes** during WFI sleep. The top-level `hclk_en_o` drops
when the core enters WFI with both AHB masters fully drained, and the SoC-level ICG gates the
internal `hclk`. All FFs inside the core -- including `mcycle` -- stop ticking until a wakeup
event combinatorially re-enables `hclk_en_o`.


### RV32E reserved registers x16–x31 read 0 / writes dropped, no trap (RV32E_EN=1)

**Spec posture** (RISC-V Unprivileged ISA §3.2, RV32E/RV64E): *"All encodings specifying
the other registers x16–x31 are reserved."* Reserved ⇒ behavior **UNSPECIFIED** (same class
as the reserved-funct7 deviation above; the base ISA does **not** mandate an
illegal-instruction exception, and the wording makes no source-vs-destination distinction).
A platform/profile standard may impose stricter behavior.

**aRVern behavior**: when RV32E is selected (`RV32E_EN=1`), the RV32E narrowing lives
**in the `arv_int_registers.v` flop array** (the `RV32E_MODE` generate: x16–x31 flops are
not instantiated, their reads are tied to constant 0, their writes are dropped). The
decode stage is **RV32E-unaware and therefore bit-identical between RV32I and RV32E**.
The JALR-shadow sub-system in `arv_int_registers.v` (`shadow_sel` / `shadow_wr_from_ex` /
`shadow_wr_from_wb` and the `id_jalr_shadow_rdata_o` load path) carries its own narrowing
gate (`rv32e_shadow_sel_upper` / `rv32e_load_zero`) so a non-conforming JALR with rs1 in
x16–x31 reads 0 from the shadow (matching the regfile contract) and subsequent writes to
non-existent upper destinations can't leak `ex_reg_dest_wdata` / `wb_reg_dest_wdata` into
the shadow flop via the `==` comparator. Net: a reference to x16–x31 reads 0 / has its
write discarded (fail-safe), and never raises illegal-instruction (`trap_count` stays 0).
A conforming RV32E program never names x16–x31, so this is unobservable in practice.

**Verification-locality principle (keep this property).** Because decode is intentionally
identical across RV32I/RV32E, the full RV32I regression already verifies the entire decode
stage for RV32E. RV32E-specific verification therefore reduces to exactly two localized
targets: (a) `arv_int_registers.v` x16–x31 read-0/write-dropped behavior, and (b) the `misa`
register reflecting the reduced base. Any future RV32E change must preserve decode
RV32I/RV32E bit-identity so this coverage property holds.


## Acknowledged Spec Gray Areas

Entries below stretch the spec's intent in ways that match industry-standard implementations. Documented for transparency rather than because compliance is in question.

### Instruction-bus address phase not held stable across wait states (single-cycle branch)

**Spec posture** (ARM IHI 0033 AHB-Lite, address-phase stability): once a master
presents a non-IDLE transfer it must hold HADDR/HTRANS/HSIZE/HWRITE/HBURST byte-stable
until the slave accepts it (HREADY high). This is a *producer-side* rule on the master.

**aRVern behavior**: the instruction master does **not** hold HADDR/HTRANS stable
across wait states when a single-cycle branch resolves during the previous fetch's
data-phase wait. The single-cycle-branch path is the combinational loop
`inst_hrdata_i → [branch decode] → inst_haddr_o`: the branch target is a combinational
function of the branch instruction's own fetch data, which is only valid on the cycle
`inst_hready_i` is high for that fetch — simultaneously the last cycle of the
(wait-extended) address phase of the speculative follow-on fetch and the last cycle of
the branch-instruction fetch's data phase (AHB overlaps these on the same HREADY-high
edge). During every preceding wait cycle the core can only present the speculative
sequential address; the target appears on `inst_haddr_o` exactly on the accept edge.
So `inst_haddr_o`/`inst_htrans_o` are not stable across the wait — they settle to the
architecturally-correct value precisely on the HREADY-high cycle.

**Rationale**: this violation is **intrinsic** to combining speculative pipelined fetch
with a single-cycle `inst_hrdata→inst_haddr` branch (the `SINGLE_CYCLE_BRANCH` Fmax/IPC
feature — see "Critical Timing Path"). The correct post-branch address is a
combinational function of data that does not exist until the wait ends, so it cannot be
presented stably earlier *by construction*. Conformance would force either dropping
speculative prefetch (a per-fetch IPC penalty on the common path) or
registering/multi-cycling the branch plus a wrong-path-discard FSM (surrenders the
single-cycle-branch feature and adds state depth to the Fmax-critical loop — an
output-side hold-mux fix was implemented and empirically broke fetch under wait states,
confirming the FSM coupling). It has **no functional consequence for any conformant
AHB-Lite consumer**: conformant slaves and interconnect commit the address phase only on
the HREADY-high cycle (`HSEL & HTRANS!=IDLE & HREADY`), and combinational HSEL
instability during the wait is a non-event because the in-flight transfer's HREADYOUT is
routed by the *registered* data-phase select, not the current-cycle combinational HSEL.
At the accept edge the presented address is always architecturally correct — empirically
corroborated: the entire wait-state regression passes with the testbench's accept-edge
slaves; this has only ever been a protocol-checker (transient-stability) finding, never
a functional failure. Posture is analogous to the reserved-funct7 deviation
(spec-permissible-in-effect; conformant consumers never observe it). The one honest
caveat: a *non-conformant* consumer that commits an address without HREADY gating would
mishandle it — but such IP is broken AHB-Lite independent of aRVern.

**Integration requirement**: instruction-bus slaves and interconnect must be conformant
AHB-Lite (HREADY-gated address-phase capture) — the standard requirement for any
AHB-Lite IP. No special single-slave or accept-edge-registered-decoder requirement.


### Store-access-fault may be lost if an NMI/IRQ preempts an in-flight posted store

**Spec posture** (RISC-V Privileged spec, synchronous exceptions): a store that takes an
access fault should raise a precise store/AMO access-fault exception (mcause=7). The spec
assumes a precise pipeline; it does not legislate posted/decoupled store-buffer behavior,
which is implementation-defined.

**aRVern behavior**: the data bus is pipelined AHB-Lite — a store's address is accepted,
then the slave's error response (`HRESP`) can arrive several cycles later (wait-stated
erroring store). If an NMI or IRQ is taken during that in-flight window, the pipeline
redirects to the trap handler before the bus error is observed. The store was already
*issued* to the slave (its write may already have committed), so the in-flight
**store-access-fault exception is dropped** — the async trap (NMI/IRQ) is taken and serviced
correctly, but the store's own fault is never reported, and the store is not replayed by
`MNRET`/`MRET` (replaying it would double a posted write's side effects).

**Severity**: Low, and only under abnormal conditions. It requires a *faulting* store (itself
an abnormal event — software hitting an illegal/erroring address) to race an async trap
within the narrow multi-cycle bus-error window. No silent data corruption of a correct
program; the only loss is the precise fault *report* for that store, in a rare race. The
async trap's own resumability is correct (the saved-PC cascade order is handled separately).

**Rationale**: "Posted-store-issued = committed" is the standard treatment in pipelined
cores with buffered / posted store paths — once a store has been accepted by the slave,
the bus has no transaction-level rollback, so unwinding it on a trap and replaying it on
`MNRET` / `MRET` would double-apply the write, which is worse than the dropped fault
report. The matching late-bus-error report is therefore either dropped (aRVern's choice)
or escalated as an imprecise non-maskable interrupt. Same pattern in
[CV32E40S](https://docs.openhwgroup.org/projects/cv32e40s-user-manual/en/latest/exceptions_interrupts.html),
[NEORV32](https://stnolting.github.io/neorv32/), and
[Rocket Chip](https://github.com/chipsalliance/rocket-chip/blob/master/src/main/scala/rocket/DCache.scala).
The spec-strict alternative — a non-posted / blocking store path that stalls the pipe
until the store's data phase completes before allowing trap redirect — is available if a
target platform requires precise store-fault reporting under async-trap preemption, but it
costs IPC on every store.
