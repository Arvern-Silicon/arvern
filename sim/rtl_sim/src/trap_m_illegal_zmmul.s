#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_m_illegal_zmmul
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZMMUL  -> DIV/REM ILLEGAL
#   Requires M_EXTENSION==1 (Zmmul). MUL/MULH/MULHSU/MULHU must execute
#   normally. DIV/DIVU/REM/REMU must raise an illegal-instruction exception.
#   Encoded as .word because the assembler refuses M instructions when the
#   -march string does not include 'm'.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#
# Phase 2: MUL result   (legal under Zmmul)
#   0x20: a4 = MUL(0x12345678, 0x87654321)
#
# Phase 3..6 (illegal under Zmmul):
#   0x30: t4 after DIV  -- expect preserved 0xEEEEEEE5
#   0x40: t5 after DIVU -- expect preserved 0xFFFFFFF6
#   0x50: a3 after REM  -- expect preserved 0x11111117
#   0x60: a2 after REMU -- expect preserved 0x22222228
#=========================================================================

main:
    j _start

    .align 2
trap_handler:
    addi sp, sp, -16
    sw   s10,12(sp)
    sw   s11, 8(sp)

    csrr s10, mcause
    csrr s11, mepc

    lw   s10, 0x00(s1)
    addi s10, s10, 1
    sw   s10, 0x00(s1)

    csrr s10, mcause
    sw   s10, 0x04(s1)

    addi s11, s11, 4
    csrw mepc, s11

    lw   s11, 8(sp)
    lw   s10,12(sp)
    addi sp, sp, 16
    mret


 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x60(s1)

    la   t0, trap_handler
    csrw mtvec, t0

    li   a0, 0x12345678        # rs1
    li   a1, 0x87654321        # rs2

    li   t4, 0xEEEEEEE5        # rd seed phase 3 (DIV)
    li   t5, 0xFFFFFFF6        # rd seed phase 4 (DIVU)
    li   a3, 0x11111117        # rd seed phase 5 (REM)
    li   a2, 0x22222228        # rd seed phase 6 (REMU)

    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: MUL a4, a0, a1  (LEGAL under Zmmul)
    # = 0000001 01011 01010 000 01110 0110011 = 0x02B50733
    # Expected: lower 32 bits of 0x12345678 * 0x87654321 = 0x70B88D78
    #=================================================================
    .word 0x02B50733              # MUL a4, a0, a1
    sw   a4, 0x20(s1)
    lw   a4, 0x20(s1)
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: DIV t4, a0, a1   (ILLEGAL under Zmmul, funct3=100)
    # = 0000001 01011 01010 100 11101 0110011 = 0x02B54EB3
    #=================================================================
    .word 0x02B54EB3              # DIV t4, a0, a1
    sw   t4, 0x30(s1)
    lw   t4, 0x30(s1)
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: DIVU t5, a0, a1  (ILLEGAL, funct3=101)
    # = 0000001 01011 01010 101 11110 0110011 = 0x02B55F33
    #=================================================================
    .word 0x02B55F33              # DIVU t5, a0, a1
    sw   t5, 0x40(s1)
    lw   t5, 0x40(s1)
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: REM a3, a0, a1   (ILLEGAL, funct3=110)
    # = 0000001 01011 01010 110 01101 0110011 = 0x02B566B3
    #=================================================================
    .word 0x02B566B3              # REM a3, a0, a1
    sw   a3, 0x50(s1)
    lw   a3, 0x50(s1)
    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: REMU a2, a0, a1  (ILLEGAL, funct3=111)
    # = 0000001 01011 01010 111 01100 0110011 = 0x02B57633
    #=================================================================
    .word 0x02B57633              # REMU a2, a0, a1
    sw   a2, 0x60(s1)
    lw   a2, 0x60(s1)

    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test
