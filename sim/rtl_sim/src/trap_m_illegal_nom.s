#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_m_illegal_nom
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: M EXTENSION ABSENT -> ILLEGAL
#   Requires M_EXTENSION==0. With no multiplier/divider, every OP-REG
#   instruction with funct7=0000001 (MUL, MULH, MULHSU, MULHU, DIV, DIVU,
#   REM, REMU) must raise an illegal-instruction exception. Per spec, the
#   faulting instruction shall not retire, so rd must keep its prior value.
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
# Phase 2..9: pre-seeded rd value (expect preserved across illegal trap)
#   0x20: t0 after MUL    rd=t0, rs1=a0, rs2=a1
#   0x30: t1 after MULH
#   0x40: t2 after MULHSU
#   0x50: t3 after MULHU
#   0x60: t4 after DIV
#   0x70: t5 after DIVU
#   0x80: a3 after REM
#   0x90: a2 after REMU
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

    # Increment trap_count
    lw   s10, 0x00(s1)
    addi s10, s10, 1
    sw   s10, 0x00(s1)

    # Save MCAUSE
    csrr s10, mcause
    sw   s10, 0x04(s1)

    # Advance MEPC past faulting 32-bit instruction
    addi s11, s11, 4
    csrw mepc, s11

    lw   s11, 8(sp)
    lw   s10,12(sp)
    addi sp, sp, 16
    mret


 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x70(s1)
    sw   t0, 0x80(s1)
    sw   t0, 0x90(s1)

    # Install handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Seed values that must be preserved across each illegal trap.
    li   a0, 0x12345678        # rs1 for all ops
    li   a1, 0x87654321        # rs2 for all ops

    li   t0, 0xAAAAAAA1        # rd seed phase 2: MUL
    li   t1, 0xBBBBBBB2        # rd seed phase 3: MULH
    li   t2, 0xCCCCCCC3        # rd seed phase 4: MULHSU
    li   t3, 0xDDDDDDD4        # rd seed phase 5: MULHU
    li   t4, 0xEEEEEEE5        # rd seed phase 6: DIV
    li   t5, 0xFFFFFFF6        # rd seed phase 7: DIVU
    li   a3, 0x11111117        # rd seed phase 8: REM   (NOT t6 — t6==x31 is the sync reg)
    li   a2, 0x22222228        # rd seed phase 9: REMU

    # Callee-saved markers (must survive every trap)
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: MUL t0, a0, a1   funct7=0000001 funct3=000 -> ILLEGAL
    # Encoding:  funct7=0000001 rs2=a1(11) rs1=a0(10) f3=000 rd=t0(5) op=0110011
    #          = 0000001 01011 01010 000 00101 0110011 = 0x02B50_2B3
    #=================================================================
    .word 0x02B502B3              # MUL t0, a0, a1
    sw   t0, 0x20(s1)
    lw   t0, 0x20(s1)             # load-back to drain SW
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: MULH t1, a0, a1   funct3=001
    # = 0000001 01011 01010 001 00110 0110011 = 0x02B51333
    #=================================================================
    .word 0x02B51333              # MULH t1, a0, a1
    sw   t1, 0x30(s1)
    lw   t1, 0x30(s1)
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: MULHSU t2, a0, a1   funct3=010
    # = 0000001 01011 01010 010 00111 0110011 = 0x02B523B3
    #=================================================================
    .word 0x02B523B3              # MULHSU t2, a0, a1
    sw   t2, 0x40(s1)
    lw   t2, 0x40(s1)
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: MULHU t3, a0, a1   funct3=011
    # = 0000001 01011 01010 011 11100 0110011 = 0x02B53E33
    #=================================================================
    .word 0x02B53E33              # MULHU t3, a0, a1
    sw   t3, 0x50(s1)
    lw   t3, 0x50(s1)
    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: DIV t4, a0, a1   funct3=100
    # = 0000001 01011 01010 100 11101 0110011 = 0x02B54EB3
    #=================================================================
    .word 0x02B54EB3              # DIV t4, a0, a1
    sw   t4, 0x60(s1)
    lw   t4, 0x60(s1)
    li   x31, 0x66666666


    #=================================================================
    # PHASE 7: DIVU t5, a0, a1   funct3=101
    # = 0000001 01011 01010 101 11110 0110011 = 0x02B55F33
    #=================================================================
    .word 0x02B55F33              # DIVU t5, a0, a1
    sw   t5, 0x70(s1)
    lw   t5, 0x70(s1)
    li   x31, 0x77777777


    #=================================================================
    # PHASE 8: REM a3, a0, a1   funct3=110   (a3 used because t6==x31 is sync reg)
    # = 0000001 01011 01010 110 01101 0110011 = 0x02B566B3
    #=================================================================
    .word 0x02B566B3              # REM a3, a0, a1
    sw   a3, 0x80(s1)
    lw   a3, 0x80(s1)
    li   x31, 0x88888888


    #=================================================================
    # PHASE 9: REMU a2, a0, a1   funct3=111
    # = 0000001 01011 01010 111 01100 0110011 = 0x02B57633
    #=================================================================
    .word 0x02B57633              # REMU a2, a0, a1
    sw   a2, 0x90(s1)
    lw   a2, 0x90(s1)

    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test
