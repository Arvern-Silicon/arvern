# Local patches to the vendored riscv-arch-test suite

`sim/arch_test/run/riscv-arch-test/` is a **gitignored clone** of upstream
(`github.com/riscv/riscv-arch-test`), pinned by `bin/fetch_suite.sh`. A hand edit
there is silently lost the next time that script runs, so every local change to
the suite lives here instead and is re-applied automatically on fetch.

## What belongs here

Only fixes for **genuine upstream defects** — bugs that would affect any
implementation, not just aRVern. Each patch must:

- carry a commit message good enough to submit as an upstream PR unchanged
- explain the failure mechanism, not just the symptom
- be reported upstream, and deleted from here once it lands

## What does NOT belong here

**Changes to test bodies (`tests/**/*.S`).** Those are the certification vectors;
their whole value is that they are identical for everyone. A suite that passes
because we edited the test proves nothing. Only `tests/env/` harness code — the
part the framework itself treats as portable glue — is in scope.

**Anything that makes a test pass by masking our own behaviour.** If aRVern
differs from the reference, that belongs in `doc/spec_compliance_notes.md` or in
the RTL, not here.

## How they are applied

`bin/fetch_suite.sh` applies every `*.patch` in this directory, in name order,
immediately after checkout, and fails loudly if one does not apply — which is the
signal that upstream has changed and the patch needs refreshing against the new
pinned SHA.

To apply by hand against an existing tree:

    git -C run/riscv-arch-test apply patches/<name>.patch

## Current patches

| Patch | Upstream status |
|---|---|
| `0001-mscratch-zero-window-goto-lower-mode.patch` | not yet submitted |
| `0002-rv32e-clean-failure-and-trap-diag-path.patch` | not yet submitted |

### 0001 — mscratch left invalid across `RVTEST_GOTO_LOWER_MODE`

The macro swaps the caller's `T3` into `mscratch` for four instructions to obtain
the save-area pointer. A trap in that window makes the trap prologue's own
`csrrw sp, mscratch, sp` adopt an arbitrary caller value as its save pointer.
Callers reach the macro with an MMIO base in `T3` (`InterruptsSSm-00` still holds
the CLINT/ACLINT base from arming the timer), so the handler writes its context
into device registers and jumps to zero — an unrecoverable trap loop.

Deterministic, not a race: the interrupt is the timer armed two instructions
earlier, so on any implementation whose store reaches the device a cycle or two
later it hits the window every run. Shrinking the window is not sufficient; the
interrupt was measured landing on the single remaining instruction.

Fixed by never displacing `mscratch` (stash `T1` in `mtval`, which is dead here).
Without this, `InterruptsSSm-00` times out after ~100k traps; with it the
performance persona is 152/152.

### 0002 — `tests/env/rvtest_failure_code.h` uses x16–x31 on RV32E

The entire `tests/rv32e/` suite fails to **assemble**: every test pulls in
`rvtest_failure_code.h` via `RVTEST_BEGIN`, and that file saves x16–x31 to the
failure scratch and then uses `x16` as a scratch address register in the
trap-diagnostic path — none of it guarded. Under `-march=rv32e_* -mabi=ilp32e`
GAS stops at "illegal operands" and no ELF is produced, for any RV32E
implementation.

The tests themselves are RV32E-clean; this is purely harness code. Fixed by
guarding the x16–x31 save with `#ifndef E_SUPPORTED` (the guard
`rvtest_setup.h` already uses for its own x16–x31 block) and by replacing the
seven `x16` scratch uses with the assembler's symbol-addressing forms.

Without this the light persona cannot be built at all; with it, 69/69.
