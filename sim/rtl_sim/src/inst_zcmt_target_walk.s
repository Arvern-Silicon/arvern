#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmt_target_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.JT / CM.JALT target-address walk
#
#   60 jump targets A walk every target bit 2..31: walking ones (bits 2..11
#   over a bit-30 background, bits 12..31 alone; bit 20 added where the
#   address would hit the ACLINT (bit 25) or the ROM (bit 29)) and walking
#   zeros over 0xFFFFEFFC (bit 12 is the background's own zero). The bench
#   alias (ahb_bus_system_inst.sram_x_alias_en, armed by the .v) maps every
#   otherwise-unmapped address >= 0x1000 onto the executable SRAM, which
#   decodes its low 16 bits; the landing routine is copied to (A & 0xFFFF)
#   first. Each target is reached once through cm.jt (index i%32) and once
#   through cm.jalt (index 32..61 for walking ones, 255..226 for walking
#   zeros), both table entries written with A; FENCE.I after the stores.
#
#   Unpriv Zcmt (cm.jt): "table_address[XLEN-1:0] = jvt.base + (index<<2);"
#   "target_address[XLEN-1:0] = InstMemory[table_address][XLEN-1:0];"
#   "j target_address[XLEN-1:0]&~0x1;"
#   Unpriv Zcmt (cm.jalt): "jal ra, target_address[XLEN-1:0]&~0x1;"
#   Unpriv Zcmt: "The memory pointed to by jvt.base is treated as instruction
#   memory for the purpose of executing table jump instructions".
#   Unpriv AUIPC: "AUIPC forms a 32-bit offset from the U-immediate, filling
#   in the lowest 12 bits with zeros, adds this offset to the address of the
#   AUIPC instruction, then places the result in register rd."
#
#   Landing routine (pinned encodings), a0 = A, a2 = return address:
#     +0x0  auipc a1, 0
#     +0x4  bne   a1, a0, +8      wrong address: do not count
#     +0x8  addi  a3, a3, 1
#     +0xC  jalr  x0, 0(a2)
#   Per call: a1 == A and a3 == 1; for cm.jalt also ra == address after it.
#
#   Results: s0 = landings (120), s4 = compares (300), s1 = mismatches (0),
#   s2 = first failing code (target*16 + check), s8 = traps (0),
#   s9/s10 = first trap mcause/mepc, s7 = jvt read-back.
#----------------------------------------------------------------------------

.equ JVT_BASE,      0x80003000
.equ ROUTINE_WORDS, 4
.equ MNSTATUS,      0x744
.equ MSTATUSH,      0x310

.section .text
.global main

main:
    j    _start

    .align 2
m_handler:
    bnez s8, 1f
    csrr s9, mcause
    csrr s10, mepc
1:  addi s8, s8, 1
    csrw mepc, a2                   # resume at the call's return point
    mret

# t1 = destination; clobbers t0, t2, t3, t4
    .align 2
copy_routine:
    la   t2, routine
    li   t3, ROUTINE_WORDS
    mv   t4, t1
1:  lw   t0, 0(t2)
    sw   t0, 0(t4)
    addi t2, t2, 4
    addi t4, t4, 4
    addi t3, t3, -1
    bnez t3, 1b
    jr   s11

.macro CHK i, code, ra_, rb_
    addi s4, s4, 1
    beq  \ra_, \rb_, 9f
    addi s1, s1, 1
    bnez s2, 9f
    li   s2, (\i << 4) | \code
9:
.endm

.macro TGT i, addr, jt, jalt
    li   a0, \addr
    li   t0, 0xFFFF
    and  t1, a0, t0
    li   t0, 0x80000000
    or   t1, t1, t0
    jal  s11, copy_routine
    li   t0, JVT_BASE + 4 * \jt
    sw   a0, 0(t0)
    li   t0, JVT_BASE + 4 * \jalt
    sw   a0, 0(t0)
    fence.i

    li   a1, 0
    li   a3, 0
    la   a2, 1f
    cm.jt \jt
1:  add  s0, s0, a3
    li   t0, 1
    CHK  \i, 1, a1, a0
    CHK  \i, 2, a3, t0

    li   a1, 0
    li   a3, 0
    li   ra, 0
    la   a2, 2f
    cm.jalt \jalt
2:  add  s0, s0, a3
    li   t0, 1
    CHK  \i, 3, a1, a0
    CHK  \i, 4, a3, t0
    CHK  \i, 5, ra, a2
.endm

_start:
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE = 1 first
    csrw MSTATUSH, x0               # then MDT = 0
    la   t0, m_handler
    csrw mtvec, t0

    li   s0, 0
    li   s1, 0
    li   s2, 0
    li   s4, 0
    li   s8, 0
    li   s9, 0
    li   s10, 0
    li   t0, JVT_BASE
    csrw 0x017, t0
    csrr s7, 0x017

    li   x31, 0x11111111            # sync: alias armed by the .v from here

    TGT  0, 0x40000004,  0,  32   # walking one,  bit 2
    TGT  1, 0x40000008,  1,  33   # walking one,  bit 3
    TGT  2, 0x40000010,  2,  34   # walking one,  bit 4
    TGT  3, 0x40000020,  3,  35   # walking one,  bit 5
    TGT  4, 0x40000040,  4,  36   # walking one,  bit 6
    TGT  5, 0x40000080,  5,  37   # walking one,  bit 7
    TGT  6, 0x40000100,  6,  38   # walking one,  bit 8
    TGT  7, 0x40000200,  7,  39   # walking one,  bit 9
    TGT  8, 0x40000400,  8,  40   # walking one,  bit 10
    TGT  9, 0x40000800,  9,  41   # walking one,  bit 11
    TGT 10, 0x00001000, 10,  42   # walking one,  bit 12
    TGT 11, 0x00002000, 11,  43   # walking one,  bit 13
    TGT 12, 0x00004000, 12,  44   # walking one,  bit 14
    TGT 13, 0x00008000, 13,  45   # walking one,  bit 15
    TGT 14, 0x00010000, 14,  46   # walking one,  bit 16
    TGT 15, 0x00020000, 15,  47   # walking one,  bit 17
    TGT 16, 0x00040000, 16,  48   # walking one,  bit 18
    TGT 17, 0x00080000, 17,  49   # walking one,  bit 19
    TGT 18, 0x00100000, 18,  50   # walking one,  bit 20
    TGT 19, 0x00200000, 19,  51   # walking one,  bit 21
    TGT 20, 0x00400000, 20,  52   # walking one,  bit 22
    TGT 21, 0x00800000, 21,  53   # walking one,  bit 23
    TGT 22, 0x01000000, 22,  54   # walking one,  bit 24
    TGT 23, 0x02100000, 23,  55   # walking one,  bit 25
    TGT 24, 0x04000000, 24,  56   # walking one,  bit 26
    TGT 25, 0x08000000, 25,  57   # walking one,  bit 27
    TGT 26, 0x10000000, 26,  58   # walking one,  bit 28
    TGT 27, 0x20100000, 27,  59   # walking one,  bit 29
    TGT 28, 0x40000000, 28,  60   # walking one,  bit 30
    TGT 29, 0x80000000, 29,  61   # walking one,  bit 31
    TGT 30, 0xFFFFEFF8, 30, 255   # walking zero, bit 2
    TGT 31, 0xFFFFEFF4, 31, 254   # walking zero, bit 3
    TGT 32, 0xFFFFEFEC,  0, 253   # walking zero, bit 4
    TGT 33, 0xFFFFEFDC,  1, 252   # walking zero, bit 5
    TGT 34, 0xFFFFEFBC,  2, 251   # walking zero, bit 6
    TGT 35, 0xFFFFEF7C,  3, 250   # walking zero, bit 7
    TGT 36, 0xFFFFEEFC,  4, 249   # walking zero, bit 8
    TGT 37, 0xFFFFEDFC,  5, 248   # walking zero, bit 9
    TGT 38, 0xFFFFEBFC,  6, 247   # walking zero, bit 10
    TGT 39, 0xFFFFE7FC,  7, 246   # walking zero, bit 11
    TGT 40, 0xFFFFEFFC,  8, 245   # walking zero, bit 12
    TGT 41, 0xFFFFCFFC,  9, 244   # walking zero, bit 13
    TGT 42, 0xFFFFAFFC, 10, 243   # walking zero, bit 14
    TGT 43, 0xFFFF6FFC, 11, 242   # walking zero, bit 15
    TGT 44, 0xFFFEEFFC, 12, 241   # walking zero, bit 16
    TGT 45, 0xFFFDEFFC, 13, 240   # walking zero, bit 17
    TGT 46, 0xFFFBEFFC, 14, 239   # walking zero, bit 18
    TGT 47, 0xFFF7EFFC, 15, 238   # walking zero, bit 19
    TGT 48, 0xFFEFEFFC, 16, 237   # walking zero, bit 20
    TGT 49, 0xFFDFEFFC, 17, 236   # walking zero, bit 21
    TGT 50, 0xFFBFEFFC, 18, 235   # walking zero, bit 22
    TGT 51, 0xFF7FEFFC, 19, 234   # walking zero, bit 23
    TGT 52, 0xFEFFEFFC, 20, 233   # walking zero, bit 24
    TGT 53, 0xFDFFEFFC, 21, 232   # walking zero, bit 25
    TGT 54, 0xFBFFEFFC, 22, 231   # walking zero, bit 26
    TGT 55, 0xF7FFEFFC, 23, 230   # walking zero, bit 27
    TGT 56, 0xEFFFEFFC, 24, 229   # walking zero, bit 28
    TGT 57, 0xDFFFEFFC, 25, 228   # walking zero, bit 29
    TGT 58, 0xBFFFEFFC, 26, 227   # walking zero, bit 30
    TGT 59, 0x7FFFEFFC, 27, 226   # walking zero, bit 31

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test

    .align 2
.option push
.option norvc
routine:
    auipc a1, 0
    bne   a1, a0, 1f
    addi  a3, a3, 1
1:  jalr  x0, 0(a2)
.option pop
