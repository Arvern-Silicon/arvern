#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_sret_illegal
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SU_MODE PRIV - SRET illegal under SU_MODE_EN=0
#   When SU_MODE_EN=0 the core advertises M-mode only (misa[18]=misa[20]=0).
#   Executing sret -- even from M-mode -- must raise illegal-instruction
#   (mcause=2), with mtval holding the offending sret encoding (0x10200073).
#
#   Phase 2: execute sret -> illegal-inst trap (mcause=2, mtval=0x10200073),
#            handler advances mepc by 4, rd-free instruction so no rd-check.
#            t0 (sentinel 0xCAFEBABE) loaded before sret must survive intact.
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
#   0x0C: last MTVAL
#
# Phase 2 capture:
#   0x20: MCAUSE after sret  (expect 2)
#   0x24: MTVAL  after sret  (expect 0x10200073 = sret encoding)
#   0x28: t0 sentinel snapshot after sret (expect 0xCAFEBABE preserved)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    # NOTE: Main code holds the CAFEBABE sentinel in t0 across the trap, so
    # the handler MUST preserve t0 -- stack it like every other scratch.
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)
    sw   a4,  0(sp)

    csrr t1, mcause
    csrr t2, mepc
    csrr a4, mtval

    # Increment trap_count
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Save MCAUSE / MEPC / MTVAL into working area
    sw   t1, 0x04(s1)
    sw   t2, 0x08(s1)
    sw   a4, 0x0C(s1)

    # All faulting instructions in this test are 32-bit; advance MEPC by 4.
    addi t2, t2, 4
    csrw mepc, t2

    lw   a4,  0(sp)
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
    sw   t0, 0x0C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)

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
    # PHASE 2: sret from M-mode -> illegal-inst trap (mcause=2)
    #=================================================================

    # Pre-load t0 with sentinel so we can verify rd-class registers are
    # not corrupted by the trapped instruction.
    li   t0, 0xCAFEBABE

    # sret encoding = 0x10200073. Use raw .word so the assembler emits the
    # exact 32-bit encoding regardless of toolchain target privilege.
    .word 0x10200073

    # Snapshot t0 (must still be 0xCAFEBABE) and CSRs captured by handler.
    # Use t1 as the snapshot-mover scratch (a4 not used here -- spare).
    sw   t0, 0x28(s1)
    lw   t1, 0x04(s1)
    sw   t1, 0x20(s1)
    lw   t1, 0x0C(s1)
    sw   t1, 0x24(s1)
    lw   t1, 0x24(s1)         # load-back: drain SW under wait states

    li   a5, 0xdeadbeef


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
