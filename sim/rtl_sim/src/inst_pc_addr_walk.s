#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_pc_addr_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PC ADDRESS WALK (address-walk test, part C)
#   Executes a small routine at 40 addresses: each PC bit 12..31 set alone
#   (walking ones) and cleared alone (walking zeros). The bench alias
#   (ahb_bus_system_inst.sram_x_alias_en, armed by the .v) maps every
#   otherwise-unmapped address >= 0x1000 onto the executable SRAM, which decodes
#   only its low 16 bits; the routine is copied to (A & 0xFFFF) before each call.
#   Where a walking-one address would hit a real slave (bit 25: ACLINT, bit 29:
#   ROM) bit 20 is added.
#
#   Routine at A (pinned encodings):
#     +0x00  auipc a1, 0          a1 = A                     (PC upper bits)
#     +0x04  beq   x0, x0, +8     taken branch at A          (branch target)
#     +0x08  addi  a3, x0, -1     poison, never executed
#     +0x0C  sw    a4, 64(a1)     store at A+64              (data address)
#     +0x10  lw    a5, 64(a1)     load it back
#     +0x14  ecall                mepc = A+0x14; the handler resumes at mepc+4
#     +0x18  jalr  x0, 0(ra)
#
#   Unpriv. AUIPC: "AUIPC ... adds this offset to the address of the AUIPC
#   instruction, then places the result in register rd."
#   Priv. 3.1.14: "When a trap is taken into M-mode, mepc is written with the
#   virtual address of the instruction that was interrupted or that encountered
#   the exception."
#
#   Per address: a1 == A, a5 == a4, a3 == 0, mepc == A+0x14, mcause == 11, and
#   the word at 0x80000000|((A+64)&0xFFFF) == a4. Results: s0 = rounds (40),
#   s1 = error count (0), t2 = first failing A (0).
#----------------------------------------------------------------------------

.equ ROUTINE_WORDS, 7

.section .text
.global main
main:
    j   _start

    .align 2
trap_handler:
    csrr  t1, mepc
    csrw  mscratch, t1
    addi  t1, t1, 4
    csrw  mepc, t1
    mret

_start:
    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw  mstatush, x0          # mstatus.MDT   = 0
    la    t0, trap_handler
    csrw  mtvec, t0

    li    s0, 0                 # rounds
    li    s1, 0                 # errors
    li    t2, 0                 # first failing address
    la    t0, addr_table
    la    t4, addr_table_end
    li    x31, 0x11111111       # sync: alias armed by the .v from here

round:
    lw    a0, 0(t0)             # A
    li    t5, 0xFFFF
    and   a2, a0, t5
    li    t5, 0x80000000
    or    a2, a2, t5            # real SRAM location of A
    la    a6, routine
    li    t6, ROUTINE_WORDS
    mv    t5, a2
copy:
    lw    a7, 0(a6)
    sw    a7, 0(t5)
    addi  a6, a6, 4
    addi  t5, t5, 4
    addi  t6, t6, -1
    bnez  t6, copy
    fence.i

    li    t5, 0x5A5A5A5A
    xor   a4, a0, t5            # per-round data
    li    a1, 0
    li    a3, 0
    li    a5, 0
    csrw  mscratch, x0
    csrw  mcause, x0
    jalr  ra, 0(a0)

    li    t6, 0                 # local error flag
    beq   a1, a0, 1f
    li    t6, 1
1:  beq   a5, a4, 1f
    li    t6, 1
1:  beqz  a3, 1f
    li    t6, 1
1:  csrr  t5, mscratch
    addi  a7, a0, 0x14
    beq   t5, a7, 1f
    li    t6, 1
1:  csrr  t5, mcause
    li    a7, 11
    beq   t5, a7, 1f
    li    t6, 1
1:  lw    t5, 64(a2)            # through the real address
    beq   t5, a4, 1f
    li    t6, 1
1:  beqz  t6, 2f
    addi  s1, s1, 1
    bnez  t2, 2f
    mv    t2, a0
2:  addi  s0, s0, 1
    addi  t0, t0, 4
    bltu  t0, t4, round

    li    x31, 0xdeadbeef

end_of_test:
    nop
    j end_of_test

    .align 2
.option push
.option norvc
routine:
    auipc a1, 0
    beq   x0, x0, 1f
    addi  a3, x0, -1
1:  sw    a4, 64(a1)
    lw    a5, 64(a1)
    ecall
    jalr  x0, 0(ra)
.option pop

    .align 2
addr_table:
    .word 0x40001000    # walking one,  bit 12
    .word 0x40002000    # walking one,  bit 13
    .word 0x40004000    # walking one,  bit 14
    .word 0x40008000    # walking one,  bit 15
    .word 0x0001E000    # walking one,  bit 16
    .word 0x0002E000    # walking one,  bit 17
    .word 0x0004E000    # walking one,  bit 18
    .word 0x0008E000    # walking one,  bit 19
    .word 0x0010E000    # walking one,  bit 20
    .word 0x0020E000    # walking one,  bit 21
    .word 0x0040E000    # walking one,  bit 22
    .word 0x0080E000    # walking one,  bit 23
    .word 0x0100E000    # walking one,  bit 24
    .word 0x0210E000    # walking one,  bit 25
    .word 0x0400E000    # walking one,  bit 26
    .word 0x0800E000    # walking one,  bit 27
    .word 0x1000E000    # walking one,  bit 28
    .word 0x2010E000    # walking one,  bit 29
    .word 0x4000E000    # walking one,  bit 30
    .word 0x8000E000    # walking one,  bit 31
    .word 0xFFFFE000    # walking zero, bit 12
    .word 0xFFFFD000    # walking zero, bit 13
    .word 0xFFFFB000    # walking zero, bit 14
    .word 0xFFFF7000    # walking zero, bit 15
    .word 0xFFFEF000    # walking zero, bit 16
    .word 0xFFFDF000    # walking zero, bit 17
    .word 0xFFFBF000    # walking zero, bit 18
    .word 0xFFF7F000    # walking zero, bit 19
    .word 0xFFEFF000    # walking zero, bit 20
    .word 0xFFDFF000    # walking zero, bit 21
    .word 0xFFBFF000    # walking zero, bit 22
    .word 0xFF7FF000    # walking zero, bit 23
    .word 0xFEFFF000    # walking zero, bit 24
    .word 0xFDFFF000    # walking zero, bit 25
    .word 0xFBFFF000    # walking zero, bit 26
    .word 0xF7FFF000    # walking zero, bit 27
    .word 0xEFFFF000    # walking zero, bit 28
    .word 0xDFFFF000    # walking zero, bit 29
    .word 0xBFFFF000    # walking zero, bit 30
    .word 0x7FFFF000    # walking zero, bit 31
addr_table_end:
