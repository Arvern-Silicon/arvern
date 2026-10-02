#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_fetch_straddle
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP fetch checker -- instruction straddling a region boundary
#
#   With C enabled a 32-bit instruction may sit at a 2-byte-aligned address and
#   span two words. At G=0 the smallest region is 4 bytes, so those two halves
#   can land in different PMP regions. The instruction must then fault on the
#   half it cannot fetch, and MTVAL must name THAT half rather than the
#   instruction's own address.
#
#   Layout built in executable SRAM:
#
#       0x8000030C   c.nop            (2 bytes, fetchable)
#       0x8000030E   32-bit NOP       <-- low half here, high half at 0x80000310
#       0x80000310   ...              locked region, no X: the high half
#
#   Executing from 0x8000030C therefore retires the c.nop, then needs the word
#   at 0x80000310 to complete the instruction at 0x8000030E.
#
#   Expected: MCAUSE=1, MEPC=0x8000030E (the instruction), MTVAL=0x80000310
#   (the portion that could not be fetched).
#
# Requires PMP_NR > 0 and C_EXTENSION >= 1 (a 2-byte-aligned 32-bit instruction
# is only reachable with compressed instructions present).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ CODE,   0x80000300         # executable scratch
.equ DENIED, 0x80000310         # the locked, non-executable half

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mtval

    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    csrw mepc, s10              # resume at the armed recovery label

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

#=========================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    la   t0, m_trap_handler
    csrw mtvec, t0

    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw mstatush, x0           # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    li   s4, CODE

    #-----------------------------------------------------------------
    # Build the straddling pair while the region is still unprotected.
    #
    #   word @ 0x8000030C = { 0x0013 , 0x0001 }
    #                         ^low half of the 32-bit NOP at 0x8000030E
    #                                   ^c.nop at 0x8000030C
    #   word @ 0x80000310 = 0x00000000
    #                         ^high half of that NOP
    #
    # 32-bit NOP is 0x00000013, so its halves are 0x0013 then 0x0000.
    #-----------------------------------------------------------------
    li   t1, 0x00130001
    sw   t1, 0x0C(s4)
    sw   x0, 0x10(s4)

    fence.i                     # the stores above are about to be executed

    #=================================================================
    # Lock the HIGH half only: read permitted, execute refused.
    # The low half at 0x8000030C stays unconstrained, so the c.nop runs.
    #=================================================================
    li   t0, DENIED
    srli t0, t0, 2
    ori  t0, t0, 1              # NAPOT, 16 bytes -> 0x80000310..0x8000031F
    csrw pmpaddr0, t0
    li   t0, 0x99               # L | A=NAPOT | R   (no X)
    csrw pmpcfg0, t0

    la   s10, recover
    addi t0, s4, 0x0C
    jalr x0, t0, 0              # enters at the c.nop, faults on the next fetch

recover:
    lw   a0, 0x04(s1)           # MCAUSE -- expect 1
    lw   a1, 0x08(s1)           # MEPC   -- expect 0x8000030E (the instruction)
    lw   a2, 0x0C(s1)           # MTVAL  -- expect 0x80000310 (the missing half)
    lw   a3, 0x00(s1)           # trap count -- expect 1
    addi t0, a3, 0              # consume the load: hold the sync until it retires

    li   x31, 0x11111111

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
1:  j    1b
