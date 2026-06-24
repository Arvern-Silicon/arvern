#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_plic_drain
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PLIC drains a 4-deep pending set in strict priority order
#   Four sources (1..4) are programmed with strictly increasing priorities
#   (1, 3, 5, 7). The testbench asserts all four together; the PLIC must
#   deliver them to the M-context one at a time in descending-priority
#   order (4, 3, 2, 1). The handler logs each claim ID; the testbench
#   verifies the log against the expected sequence.
#
#   This exercises:
#     - pending[] latching for several sources concurrently,
#     - target arbiter picking the unique highest-priority pending source,
#     - in-service[] correctly clearing on complete so the next-highest
#       can win arbitration on the following cycle.
#----------------------------------------------------------------------------

.section .text
.global main

.equ PLIC_PRI_BASE,  0x0C000000
.equ PLIC_EN_M,      0x0C002000
.equ PLIC_TH_M,      0x0C200000
.equ PLIC_CLAIM_M,   0x0C200004

#=========================================================================
# Scratchpad (base 0x80000000)
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x0C: last claimed source ID
#   0x20..0x2C: per-trap claim log: claim[n] @ 0x20 + (n-1)*4
#   0x80: TB drop-source signal
#=========================================================================

main:
    j _start

    .align 2
m_trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    sw   t0, 0x04(s1)

    # trap_count++
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    li   t3, 0x8000000B
    bne  t0, t3, handler_done

    # Claim
    li   t3, PLIC_CLAIM_M
    lw   t4, 0(t3)
    sw   t4, 0x0C(s1)

    # Log: scratchpad[0x20 + (count-1)*4] = claim ID
    addi t0, t2, -1
    slli t0, t0, 2
    add  t0, t0, s1
    sw   t4, 0x20(t0)

    # Signal TB to drop the claimed source
    sw   t4, 0x80(s1)

    # Busy-loop ~100 cycles so TB has time to drop the level
    li   t2, 100
plic_drop_wait:
    addi t2, t2, -1
    bnez t2, plic_drop_wait

    # Complete
    li   t3, PLIC_CLAIM_M
    sw   t4, 0(t3)

    sw   zero, 0x80(s1)

handler_done:
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
    mret


_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x20(s1)
    sw   zero, 0x24(s1)
    sw   zero, 0x28(s1)
    sw   zero, 0x2C(s1)
    sw   zero, 0x80(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    # Priorities: src1=1, src2=3, src3=5, src4=7
    li   t0, 1
    li   t1, PLIC_PRI_BASE + 4*1
    sw   t0, 0(t1)
    li   t0, 3
    li   t1, PLIC_PRI_BASE + 4*2
    sw   t0, 0(t1)
    li   t0, 5
    li   t1, PLIC_PRI_BASE + 4*3
    sw   t0, 0(t1)
    li   t0, 7
    li   t1, PLIC_PRI_BASE + 4*4
    sw   t0, 0(t1)

    # Enable sources 1..4 in ctx 0 (bits [4:1])
    li   t0, 0x0000001E
    li   t1, PLIC_EN_M
    sw   t0, 0(t1)

    # Threshold = 0 (priority 1 fires)
    li   t0, 0
    li   t1, PLIC_TH_M
    sw   t0, 0(t1)

    # Enable MIE.MEIE + MSTATUS.MIE
    li   t0, 0x800
    csrs mie, t0
    li   t0, 0x8
    csrs mstatus, t0

    li   x31, 0x11111111

    # Wait for 4 traps to drain (testbench asserts all 4 sources together)
phase2_wait:
    lw   t0, 0x00(s1)
    li   t1, 4
    bne  t0, t1, phase2_wait

    li   x31, 0x44444444

end_of_test:
    j    end_of_test
