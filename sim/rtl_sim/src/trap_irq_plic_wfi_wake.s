#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_plic_wfi_wake
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PLIC -> WFI wake-up
#   The core enters WFI sleep with MIE.MEIE + MSTATUS.MIE enabled. The
#   testbench then asserts plic_irq_src[1]. The PLIC's hclk_en_o has
#   `|irq_src_i` in its OR -- the source rising re-enables the system
#   clock, the PLIC gateway latches pending, the target arbiter fires
#   irq_m_external_o, the core wakes and the MEI trap is taken.
#
#   Phases:
#     1. Program PLIC (src 1, priority 5, ctx-0 enable, threshold 0).
#     2. Enable MEIE + MIE, signal TB and execute WFI.
#     3. After wake + trap, mainline resumes; verifies trap_count == 1.
#----------------------------------------------------------------------------

.section .text
.global main

.equ PLIC_PRI1,      0x0C000004
.equ PLIC_EN_M,      0x0C002000
.equ PLIC_TH_M,      0x0C200000
.equ PLIC_CLAIM_M,   0x0C200004

#=========================================================================
# Scratchpad (base 0x80000000)
#   0x00: trap_count
#   0x04: last MCAUSE  (expect 0x8000000B)
#   0x0C: last claimed source ID  (expect 1)
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

    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    li   t3, 0x8000000B
    bne  t0, t3, handler_done

    li   t3, PLIC_CLAIM_M
    lw   t4, 0(t3)
    sw   t4, 0x0C(s1)
    sw   t4, 0x80(s1)

    li   t2, 100
plic_drop_wait:
    addi t2, t2, -1
    bnez t2, plic_drop_wait

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

    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x80(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    # Configure PLIC: priority[1]=5, enable src 1 in ctx 0, threshold=0
    li   t0, 5
    li   t1, PLIC_PRI1
    sw   t0, 0(t1)
    li   t0, 0x00000002
    li   t1, PLIC_EN_M
    sw   t0, 0(t1)
    li   t0, 0
    li   t1, PLIC_TH_M
    sw   t0, 0(t1)

    # Enable MIE.MEIE + MSTATUS.MIE
    li   t0, 0x800
    csrs mie, t0
    li   t0, 0x8
    csrs mstatus, t0

    li   x31, 0x11111111

    # Brief delay so the TB can latch x31 before we go to sleep
    li   t2, 40
arm_wait:
    addi t2, t2, -1
    bnez t2, arm_wait

    li   x31, 0x21212121            # signal TB: about to WFI

    wfi                             # sleep; PLIC source rising will wake us

    # Wake + trap landed and returned to here.
    li   x31, 0x33333333

wait_count:
    lw   t0, 0x00(s1)
    li   t1, 1
    bne  t0, t1, wait_count

    li   x31, 0x44444444

end_of_test:
    j    end_of_test
