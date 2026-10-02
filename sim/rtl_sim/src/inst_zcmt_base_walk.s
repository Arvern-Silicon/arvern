#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmt_base_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.JT / CM.JALT jump-table BASE walk over address bits 16..31
#
#   Unpriv Zcmt (cm.jt): "table_address[XLEN-1:0] = jvt.base + (index<<2);"
#   "target_address[XLEN-1:0] = InstMemory[table_address][XLEN-1:0];"
#   Unpriv Zcmt (jvt): "the lower six bits of base are filled with zeroes to
#   obtain an XLEN-bit jump-table base address jvt.base which is always
#   aligned on a 64-byte boundary"; arvern_instructions.md: MODE[5:0] reads 0.
#   Unpriv Zcmt (cm.jalt): "jal ra, target_address[XLEN-1:0]&~0x1".
#
#   One physical table (256 words) at executable-SRAM offset 0x3000. With the
#   bench alias (ahb_bus_system_inst.sram_x_alias_en, armed by the .v) every
#   otherwise-unmapped address >= 0x1000 reaches the executable SRAM on its
#   low 16 bits, so jvt = X | 0x3000 reads that same table for any upper X:
#     walking ones  (1<<k) | 0x3000, k = 16..31 (k = 25 -> 0x0210_3000 clear
#                   of the ACLINT, k = 29 -> 0x2100_3000 clear of the ROM,
#                   k = 31 = the real table at 0x8000_3000)
#     walking zeros (~(1<<k) & 0xFFFF0000) | 0x3000, k = 16..31
#   Every table address (base + 4*index, index 0..255) was checked against
#   bench/verilog/ahb_decoder.v to alias (or be the real SRAM).
#
#   The table is filled with land_wrong (a3 += 16). Per base: jvt written
#   with base | 0x3F and read back (expect base); entries jt = i%32 and
#   jalt = 255-i set to land_ok (a3 += 1), FENCE.I (the table is instruction
#   memory), cm.jt jt and cm.jalt jalt; a3 == 1 after each, ra == address
#   after the cm.jalt; entries restored to land_wrong afterwards. Landing
#   routines live in ROM and return through a2.
#
#   Results: s0 = landings (64), s4 = compares (128), s1 = mismatches (0),
#   s2 = first failing code (step*16 + check), s8 = traps (0),
#   s9/s10 = first trap mcause/mepc.
#----------------------------------------------------------------------------

.equ TABLE,         0x80003000
.equ MNSTATUS,      0x744
.equ MSTATUSH,      0x310
.equ JVT,           0x017

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

    .align 2
land_ok:
    addi a3, a3, 1
    jalr x0, 0(a2)

    .align 2
land_wrong:
    addi a3, a3, 16
    jalr x0, 0(a2)

.macro CHK i, code, ra_, rb_
    addi s4, s4, 1
    beq  \ra_, \rb_, 9f
    addi s1, s1, 1
    bnez s2, 9f
    li   s2, (\i << 4) | \code
9:
.endm

.macro BASE_STEP i, base, jt, jalt
    li   a0, \base
    ori  t0, a0, 0x3F
    csrw JVT, t0
    csrr t0, JVT
    CHK  \i, 1, t0, a0

    li   t0, TABLE + 4 * \jt
    sw   s5, 0(t0)
    li   t0, TABLE + 4 * \jalt
    sw   s5, 0(t0)
    fence.i

    li   a3, 0
    la   a2, 1f
    cm.jt \jt
1:  add  s0, s0, a3
    li   t0, 1
    CHK  \i, 2, a3, t0

    li   a3, 0
    li   ra, 0
    la   a2, 2f
    cm.jalt \jalt
2:  add  s0, s0, a3
    li   t0, 1
    CHK  \i, 3, a3, t0
    CHK  \i, 4, ra, a2

    li   t0, TABLE + 4 * \jt
    sw   s6, 0(t0)
    li   t0, TABLE + 4 * \jalt
    sw   s6, 0(t0)
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
    la   s5, land_ok
    la   s6, land_wrong

    li   t0, TABLE                  # every entry -> land_wrong
    li   t1, 256
1:  sw   s6, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, 1b

    li   x31, 0x11111111            # sync: alias armed by the .v from here
    li   t0, 10                     # let the bench arm it
1:  addi t0, t0, -1
    bnez t0, 1b

    BASE_STEP  0, 0x00013000,  0, 255   # walking one,  bit 16
    BASE_STEP  1, 0x00023000,  1, 254   # walking one,  bit 17
    BASE_STEP  2, 0x00043000,  2, 253   # walking one,  bit 18
    BASE_STEP  3, 0x00083000,  3, 252   # walking one,  bit 19
    BASE_STEP  4, 0x00103000,  4, 251   # walking one,  bit 20
    BASE_STEP  5, 0x00203000,  5, 250   # walking one,  bit 21
    BASE_STEP  6, 0x00403000,  6, 249   # walking one,  bit 22
    BASE_STEP  7, 0x00803000,  7, 248   # walking one,  bit 23
    BASE_STEP  8, 0x01003000,  8, 247   # walking one,  bit 24
    BASE_STEP  9, 0x02103000,  9, 246   # walking one,  bit 25 (ACLINT -> +bit 20)
    BASE_STEP 10, 0x04003000, 10, 245   # walking one,  bit 26
    BASE_STEP 11, 0x08003000, 11, 244   # walking one,  bit 27
    BASE_STEP 12, 0x10003000, 12, 243   # walking one,  bit 28
    BASE_STEP 13, 0x21003000, 13, 242   # walking one,  bit 29 (ROM -> +bit 24)
    BASE_STEP 14, 0x40003000, 14, 241   # walking one,  bit 30
    BASE_STEP 15, 0x80003000, 15, 240   # walking one,  bit 31 (the real table)
    BASE_STEP 16, 0xFFFE3000, 16, 239   # walking zero, bit 16
    BASE_STEP 17, 0xFFFD3000, 17, 238   # walking zero, bit 17
    BASE_STEP 18, 0xFFFB3000, 18, 237   # walking zero, bit 18
    BASE_STEP 19, 0xFFF73000, 19, 236   # walking zero, bit 19
    BASE_STEP 20, 0xFFEF3000, 20, 235   # walking zero, bit 20
    BASE_STEP 21, 0xFFDF3000, 21, 234   # walking zero, bit 21
    BASE_STEP 22, 0xFFBF3000, 22, 233   # walking zero, bit 22
    BASE_STEP 23, 0xFF7F3000, 23, 232   # walking zero, bit 23
    BASE_STEP 24, 0xFEFF3000, 24, 231   # walking zero, bit 24
    BASE_STEP 25, 0xFDFF3000, 25, 230   # walking zero, bit 25
    BASE_STEP 26, 0xFBFF3000, 26, 229   # walking zero, bit 26
    BASE_STEP 27, 0xF7FF3000, 27, 228   # walking zero, bit 27
    BASE_STEP 28, 0xEFFF3000, 28, 227   # walking zero, bit 28
    BASE_STEP 29, 0xDFFF3000, 29, 226   # walking zero, bit 29
    BASE_STEP 30, 0xBFFF3000, 30, 225   # walking zero, bit 30
    BASE_STEP 31, 0x7FFF3000, 31, 224   # walking zero, bit 31

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
