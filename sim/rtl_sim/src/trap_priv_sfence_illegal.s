#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_sfence_illegal
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SU_MODE PRIV - SFENCE.VMA illegal under SU_MODE_EN=0
#   aRVern has no MMU, so sfence.vma is illegal in all configs; this test
#   pins down that behavior under SU_MODE_EN=0 specifically.
#
#   Phase 2: execute sfence.vma x0, x0 -> illegal-inst trap (mcause=2).
#            Handler advances mepc by 4.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#
# Phase 2 capture:
#   0x20: MCAUSE after sfence.vma (expect 2)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    csrr t0, mcause
    csrr t1, mepc

    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)

    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x20(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Initialize callee-saved registers (RV32E-safe markers in x0-x15)
    li   s0, 0xAAAAAAAA
    li   a0, 0xBBBBBBBB
    li   a1, 0xCCCCCCCC
    li   a2, 0xDDDDDDDD
    li   a3, 0xEEEEEEEE

    li   a5, 0x11111111


    #=================================================================
    # PHASE 2: sfence.vma x0, x0 -> illegal-inst (mcause=2)
    #=================================================================

    # sfence.vma x0, x0 encoding = 0x12000073.
    # Use .word to ensure exact emission regardless of toolchain target.
    .word 0x12000073

    # Snapshot MCAUSE recorded by handler
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)
    lw   t0, 0x20(s1)         # load-back fence

    li   a5, 0xdeadbeef


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
