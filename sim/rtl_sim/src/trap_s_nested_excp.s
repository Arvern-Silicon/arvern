#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_s_nested_excp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP S NESTED EXCP (IRQ then EXCP)
#   Reproducer for RTL review #7 (excp_ignore_deleg too broad).
#
#   Scenario: a delegable exception (illegal inst, cause 2) is raised while
#   the CPU is already executing an S-mode IRQ handler (S-timer, cause 5).
#   With mideleg[5]=medeleg[2]=1, the spec allows hardware to delegate the
#   nested exception back to S-mode (software is responsible for saving
#   sepc/scause). The pre-fix RTL uses in_s_trap (any S-trap, IRQ or excp)
#   in excp_ignore_deleg, so the nested exception is forced to M-mode -- a
#   real S-mode compatibility issue for kernels that take faults inside IRQ
#   handlers (e.g. demand-paging during a timer tick).
#
#   Expected post-fix: the illegal inst is delegated to S-mode handler.
#   Expected pre-fix : the illegal inst goes to M-mode handler.
#
#   Scratchpad layout (base 0x80000000):
#   0x00: m_trap_count       (M-mode trap counter)
#   0x04: m_last_cause       (last MCAUSE)
#   0x08: m_last_epc         (last MEPC)
#   0x0C: s_trap_count_irq   (S-mode IRQ counter)
#   0x10: s_trap_count_excp  (S-mode exception counter)
#   0x14: s_last_excp_cause  (last SCAUSE for exception)
#   0x18: s_irq_done         (set to 0xAA when s_irq_handler returns past
#   the illegal instruction)
#   0x1C: result             (0xAA = excp delegated; 0xBB = forced to M)
#----------------------------------------------------------------------------

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

    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)

    # IRQ vs exception
    bltz t0, m_handler_done

    # Exception: advance MEPC by 4 (illegal inst is 4 bytes)
    addi t1, t1, 4
    csrw mepc, t1

m_handler_done:
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


    #=================================================================
    # S-MODE HANDLER (direct mode)
    #=================================================================
    .align 2

s_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)
    sw   t3,  0(sp)

    csrr t0, scause
    csrr t1, sepc

    bltz t0, s_irq_path

    # ---- Exception path ----
    lw   t2, 0x10(s1)
    addi t2, t2, 1
    sw   t2, 0x10(s1)

    sw   t0, 0x14(s1)

    # Advance SEPC past illegal (4 bytes)
    addi t1, t1, 4
    csrw sepc, t1
    j s_handler_done

s_irq_path:
    # Save the IRQ's sepc to scratchpad -- a nested S-mode exception (post-fix
    # path) will overwrite sepc, so we must save and restore it ourselves
    # for the outer sret to return to s_main.
    sw   t1, 0x20(s1)              # IRQ's sepc

    lw   t2, 0x0C(s1)
    addi t2, t2, 1
    sw   t2, 0x0C(s1)

    # Disable SIE.STIE so the timer doesn't refire after sret
    li   t3, 0x20
    csrc sie, t3

    # ---- Trigger nested illegal instruction inside the S-IRQ handler ----
illegal_nested:
    .word 0xFFFFFFFF

    # Either path (M or S) advances PC past the illegal; we resume here.
post_illegal:
    li   t3, 0xAA
    sw   t3, 0x18(s1)
    lw   t3, 0x18(s1)              # drain

    # Restore the IRQ's sepc (a nested S-mode exception clobbered it).
    lw   t3, 0x20(s1)
    csrw sepc, t3
    # Restore SSTATUS.SPP = 1 (S) -- nested sret cleared it to U.
    li   t3, 0x100
    csrs sstatus, t3

s_handler_done:
    lw   t3,  0(sp)
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    sret

    .option pop


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
    .align 4
_start:
    li   sp, 0x80010000
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

    # Install M and S handlers (direct mode)
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0

    # Delegate S-timer (mideleg[5]) and illegal-instruction (medeleg[2])
    li   t0, 0x20
    csrs mideleg, t0
    li   t0, 0x4
    csrs medeleg, t0

    # Enable SIE.STIE (bit 5)
    li   t0, 0x20
    csrs sie, t0

    # Enable SSTATUS.SIE (bit 1)
    li   t0, 0x2
    csrs sstatus, t0

    # Set MIP.STIP (bit 5) -- the source of the S-timer IRQ
    li   t0, 0x20
    csrs mip, t0

    li   x31, 0x11111111

    # MPP=01 (S-mode), MPIE=1 -- mret will enter S-mode with sstatus.sie=1
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0
    li   t0, 0x80
    csrs mstatus, t0

    la   t0, s_main
    csrw mepc, t0
    mret

    .align 2
s_main:
    # On entry, S-timer IRQ is pending and enabled -- should fire immediately.
    nop
    nop
    nop

s_wait_done:
    lw   t0, 0x18(s1)
    beqz t0, s_wait_done

    # Determine which path the nested exception took
    lw   t0, 0x10(s1)              # s_trap_count_excp
    bnez t0, took_s_path

took_m_path:
    li   t0, 0xBB
    sw   t0, 0x1C(s1)
    lw   t0, 0x1C(s1)              # drain
    li   x31, 0x0BADBADB           # FAIL: exception forced to M
    j end_of_test

took_s_path:
    li   t0, 0xAA
    sw   t0, 0x1C(s1)
    lw   t0, 0x1C(s1)              # drain
    li   x31, 0xdeadbeef           # PASS: exception delegated to S

end_of_test:
    nop
    j end_of_test
