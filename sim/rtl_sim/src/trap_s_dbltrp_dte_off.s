#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_s_dbltrp_dte_off
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP S DBLTRP DTE OFF (Ssdbltrp opt-out via menvcfgh.DTE)
#   Requires SU_MODE_EN==1. Deterministic (sync exceptions only, no IRQs).
#
#   menvcfg.DTE is bit 59 => on RV32 it lives in menvcfgh (0x31A) bit 27.
#   When DTE=0 the hart behaves as if Ssdbltrp were absent: sstatus.SDT
#   reads 0 (RAZ), writes to it are ignored (WI), and there is no
#   double-trap redirect -- nested delegated traps are taken horizontally
#   in S-mode (spec-literal behavior).
#
#   Phase 1 (DTE=0): M clears menvcfgh.DTE, enters S. illegal1 traps to the
#     S handler; the handler verifies SDT reads 0 even immediately after
#     trap entry, that a csrs of SDT is ignored, and that a nested illegal2
#     is taken horizontally in S (scause=2) -- no mcause=16 anywhere.
#   Phase 2: s_main issues ECALL (cause 9, not delegated) -> M handler sets
#     DTE back to 1 (and clears SDT to a known state, see note below).
#   Phase 3 (DTE=1): illegal3 traps to the S handler (SDT now set by HW,
#     recorded); a nested illegal4 WITHOUT clearing SDT must double-trap to
#     M with mcause=16, mtval2=2, mepc=&illegal4.
#
#   Note: after re-enabling DTE, the M handler explicitly clears
#   sstatus.SDT (csrc from M). The spec does not define the underlying SDT
#   storage across a DTE=0 window, so the test forces a known-0 state to
#   stay implementation-independent.
#
#   Scratchpad layout (base 0x80000000):
#   0x00: m_trap_count           (expect 2: 1 ecall + 1 double trap)
#   0x04: m_ecall_count          (expect 1)
#   0x08: m_dbl_count            (expect 1)
#   0x0C: m_last_mcause          (expect 16, the double trap comes last)
#   0x10: m mtval2 at dbl trap   (expect 2)
#   0x14: DTE readback after boot clear      (expect 0)
#   0x18: SDT at S entry, DTE=0              (expect 0: RAZ after trap)
#   0x1C: SDT after attempted csrs, DTE=0    (expect 0: WI)
#   0x20: nested scause, DTE=0               (expect 2: horizontal)
#   0x24: depth counter          (expect 3 at end)
#   0x28: SDT at S entry, DTE=1              (expect 0x01000000)
#   0x2C: phase 1 resumed flag   (expect 0xAA)
#   0x30: phase 3 resumed flag   (expect 0xBB)
#   0x34: saved outer return sepc
#   0x38: DTE readback after re-set          (expect 0x08000000)
#   0x3C: expected mepc of double trap       (&illegal4)
#   0x40: m mepc at double trap  (compare with 0x3C)
#   0x44: nested SDT at entry, DTE=0         (expect 0)
#   0x48: final flag             (expect 0xCC)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE HANDLER (direct mode)
    #=================================================================
    .align 2
    .option push
    .option norvc

m_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    csrr t0, mcause
    csrr t1, mepc

    # Increment m_trap_count
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    sw   t0, 0x0C(s1)          # m_last_mcause

    li   t2, 9
    beq  t0, t2, m_ecall       # ECALL from S-mode
    li   t2, 16
    beq  t0, t2, m_dbl         # double trap
    j    m_advance             # unexpected: recover anyway

m_ecall:
    lw   t2, 0x04(s1)
    addi t2, t2, 1
    sw   t2, 0x04(s1)

    # Re-enable Ssdbltrp: menvcfgh.DTE (bit 27) = 1
    li   t2, 0x08000000
    csrs 0x31A, t2

    csrr t2, 0x31A
    li   t0, 0x08000000
    and  t2, t2, t0
    sw   t2, 0x38(s1)          # DTE readback, expect 0x08000000

    # Force SDT to a known-0 state (underlying storage across the DTE=0
    # window is not architecturally defined -- see header note)
    li   t2, 0x01000000
    csrc sstatus, t2
    j    m_advance

m_dbl:
    lw   t2, 0x08(s1)
    addi t2, t2, 1
    sw   t2, 0x08(s1)

    # mtval2 (0x34B) holds the original cause of the double trap
    csrr t2, 0x34B
    sw   t2, 0x10(s1)          # expect 2

    sw   t1, 0x40(s1)          # mepc, expect &illegal4

m_advance:
    # ECALL and .word illegals are all 4-byte instructions
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


    #=================================================================
    # S-MODE HANDLER (direct mode) -- dispatch on depth counter
    #=================================================================
    .align 2

s_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    lw   t2, 0x24(s1)          # depth
    beqz t2, s_outer_dte0
    li   t0, 1
    beq  t2, t0, s_nested_dte0
    li   t0, 2
    beq  t2, t0, s_outer_dte1
    j    s_unexpected

    # ---- Phase 1 OUTER entry (depth 0, DTE=0) ----
s_outer_dte0:
    # Save return address (past illegal1); nested trap clobbers sepc
    csrr t1, sepc
    addi t1, t1, 4
    sw   t1, 0x34(s1)

    # With DTE=0, SDT must read 0 even immediately after a trap into S
    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x18(s1)          # expect 0

    # Writes to SDT must be ignored while DTE=0
    li   t0, 0x01000000
    csrs sstatus, t0
    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x1C(s1)          # expect 0

    # depth = 1
    li   t0, 1
    sw   t0, 0x24(s1)

    # Nested illegal with DTE=0 -> horizontal S->S trap (spec-literal)
illegal2:
    .word 0xFFFFFFFF

    # Nested handler sret'ed back here
    li   t0, 0xAA
    sw   t0, 0x2C(s1)          # phase 1 resumed flag

    # Restore sepc and SPP=1 (S) -- nested sret cleared SPP to U
    lw   t1, 0x34(s1)
    csrw sepc, t1
    li   t0, 0x100
    csrs sstatus, t0

    # depth = 2
    li   t0, 2
    sw   t0, 0x24(s1)
    j    s_handler_done

    # ---- Phase 1 NESTED entry (depth 1, DTE=0) ----
s_nested_dte0:
    csrr t0, scause
    sw   t0, 0x20(s1)          # expect 2 (taken in S, not M)

    # SDT still reads 0 (DTE=0)
    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x44(s1)          # expect 0

    csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    j    s_handler_done

    # ---- Phase 3 OUTER entry (depth 2, DTE=1) ----
s_outer_dte1:
    # Save return address (past illegal3)
    csrr t1, sepc
    addi t1, t1, 4
    sw   t1, 0x34(s1)

    # With DTE=1 again, hardware must set SDT on this trap entry
    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x28(s1)          # expect 0x01000000

    # depth = 3
    li   t0, 3
    sw   t0, 0x24(s1)

    # Record expected MEPC of the upcoming double trap
    la   t0, illegal4
    sw   t0, 0x3C(s1)

    # Nested illegal WITHOUT clearing SDT -> double trap to M (mcause=16)
illegal4:
    .word 0xFFFFFFFF

    # M handler advanced MEPC past illegal4 and MRETed back here
    li   t0, 0xBB
    sw   t0, 0x30(s1)          # phase 3 resumed flag

    # Restore sepc (untouched by the M round trip, but restore anyway for
    # symmetry with phase 1)
    lw   t1, 0x34(s1)
    csrw sepc, t1
    j    s_handler_done

s_handler_done:
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    sret

s_unexpected:
    li   x31, 0x0BADBADB       # FAIL: unexpected S handler entry
s_unexpected_loop:
    j    s_unexpected_loop

    .option pop


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
    .align 4
_start:
    li   sp, 0x80010000
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)
    sw   t0, 0x3C(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x48(s1)

    # Install M and S handlers (direct mode)
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0

    # Delegate illegal-instruction (cause 2) to S-mode.
    # ECALL-from-S (cause 9) is deliberately NOT delegated -> goes to M.
    li   t0, 0x4
    csrs medeleg, t0

    # Opt out of Ssdbltrp: clear menvcfgh.DTE (bit 27) and read back
    li   t0, 0x08000000
    csrc 0x31A, t0
    csrr t0, 0x31A
    li   t1, 0x08000000
    and  t0, t0, t1
    sw   t0, 0x14(s1)          # expect 0
    lw   t0, 0x14(s1)          # drain

    li   x31, 0x11111111

    # MPP=01 (S-mode), mret into s_main
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0
    la   t0, s_main
    csrw mepc, t0
    mret

    .align 2
s_main:
    li   x31, 0x22222222

illegal1:
    .word 0xFFFFFFFF           # phase 1: DTE=0, nested traps stay in S

    # Phase 2: ask M-mode to set DTE=1 (ECALL from S, cause 9, not delegated)
    li   x31, 0x33333333
    ecall

    # Back with DTE=1 and SDT forced to 0 by the M handler
    li   x31, 0x44444444

illegal3:
    .word 0xFFFFFFFF           # phase 3: DTE=1, nested illegal4 double-traps

    li   t0, 0xCC
    sw   t0, 0x48(s1)
    lw   t0, 0x48(s1)          # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
