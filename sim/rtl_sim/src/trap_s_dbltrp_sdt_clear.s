#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_s_dbltrp_sdt_clear
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP S DBLTRP SDT CLEAR (Ssdbltrp re-entrancy contract)
#   Requires SU_MODE_EN==1. Deterministic (sync exceptions only, no IRQs).
#
#   An S handler that saves its state may clear sstatus.SDT (bit 24) to
#   re-arm horizontal (S->S) trap delegation. This test verifies:
#   1. Hardware sets SDT on trap entry into S (outer handler records 1).
#   2. Software csrc of sstatus.SDT works (records 0 after clear).
#   3. With SDT cleared, a nested delegated illegal inside the handler is
#      taken HORIZONTALLY in S again (scause=2, sepc=&illegal2), and that
#      nested entry sets SDT=1 again.
#   4. SRET clears SDT: after the nested sret the outer handler reads
#      SDT=0; after the outer sret, s_main reads SDT=0 and a third trap is
#      again taken horizontally in S (no double trap anywhere: the M-mode
#      trap count must stay 0).
#
#   Handler dispatch uses a depth counter (0x04): 0=outer, 1=nested,
#   2=third entry, else fail.
#
#   Scratchpad layout (base 0x80000000):
#   0x00: m_trap_count           (expect 0: no trap may reach M)
#   0x04: depth counter          (expect 3 at end)
#   0x08: outer: SDT at entry    (expect 0x01000000, set by HW)
#   0x0C: outer: SDT after csrc  (expect 0, SW clear works)
#   0x10: nested: scause         (expect 2, horizontal S trap)
#   0x14: nested: sepc           (expect &illegal2, compare with 0x18)
#   0x18: nested: expected sepc  (&illegal2)
#   0x1C: nested: SDT at entry   (expect 0x01000000, set again by HW)
#   0x20: outer resumed flag     (expect 0xAA)
#   0x24: outer: SDT after nested sret (expect 0: SRET clears SDT)
#   0x28: saved outer return sepc
#   0x2C: s_main: SDT after outer sret (expect 0)
#   0x30: third: scause          (expect 2, horizontal again -> SDT was 0)
#   0x34: third: SDT at entry    (expect 0x01000000)
#   0x38: final flag             (expect 0xBB)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE HANDLER (direct mode) -- must never run in this test
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

    # Increment m_trap_count (any M trap is a failure, recorded for the TB)
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    # Recover anyway: advance MEPC past the 4-byte faulting instruction
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

    lw   t2, 0x04(s1)          # depth
    beqz t2, s_outer
    li   t0, 1
    beq  t2, t0, s_nested
    li   t0, 2
    beq  t2, t0, s_third
    j    s_unexpected

    # ---- OUTER entry (depth 0): first trap from s_main ----
s_outer:
    # Save the return address (past illegal1) -- the nested trap will
    # clobber sepc, so we must restore it ourselves before our sret.
    csrr t1, sepc
    addi t1, t1, 4
    sw   t1, 0x28(s1)

    # SDT must have been set by hardware on this trap entry
    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x08(s1)          # expect 0x01000000

    # Software clears SDT (state saved -> handler is re-entrant again)
    li   t0, 0x01000000
    csrc sstatus, t0

    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x0C(s1)          # expect 0

    # depth = 1
    li   t0, 1
    sw   t0, 0x04(s1)

    # Record expected sepc of the nested horizontal trap
    la   t0, illegal2
    sw   t0, 0x18(s1)

    # Nested illegal with SDT=0 -> horizontal S->S trap (NOT a double trap)
illegal2:
    .word 0xFFFFFFFF

    # Nested handler sret'ed back here
    li   t0, 0xAA
    sw   t0, 0x20(s1)          # outer resumed flag

    # SRET (the nested one) must have cleared SDT
    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x24(s1)          # expect 0

    # Restore sepc (clobbered by nested trap) and SPP=1 (S) -- the nested
    # sret cleared SPP to U.
    lw   t1, 0x28(s1)
    csrw sepc, t1
    li   t0, 0x100
    csrs sstatus, t0

    # depth = 2
    li   t0, 2
    sw   t0, 0x04(s1)
    j    s_handler_done

    # ---- NESTED entry (depth 1): horizontal S trap inside the handler ----
s_nested:
    csrr t0, scause
    sw   t0, 0x10(s1)          # expect 2

    csrr t1, sepc
    sw   t1, 0x14(s1)          # expect &illegal2

    # This trap entry must have set SDT=1 again
    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x1C(s1)          # expect 0x01000000

    # Advance sepc past illegal2 and return into the outer handler
    addi t1, t1, 4
    csrw sepc, t1
    j    s_handler_done

    # ---- THIRD entry (depth 2): trap from s_main after full unwind ----
s_third:
    csrr t0, scause
    sw   t0, 0x30(s1)          # expect 2 (horizontal: SDT was 0 pre-trap)

    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x34(s1)          # expect 0x01000000

    csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1

    # depth = 3
    li   t0, 3
    sw   t0, 0x04(s1)
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

    # Install M and S handlers (direct mode)
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0

    # Delegate illegal-instruction (cause 2) to S-mode
    li   t0, 0x4
    csrs medeleg, t0

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
    .word 0xFFFFFFFF           # outer trap: delegated to the S handler

    # Back after the outer sret -- SRET must have cleared SDT
    csrr t0, sstatus
    li   t1, 0x01000000
    and  t0, t0, t1
    sw   t0, 0x2C(s1)          # expect 0
    lw   t0, 0x2C(s1)          # drain

    li   x31, 0x33333333

illegal3:
    .word 0xFFFFFFFF           # third trap: must again be horizontal in S

    li   t0, 0xBB
    sw   t0, 0x38(s1)
    lw   t0, 0x38(s1)          # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
