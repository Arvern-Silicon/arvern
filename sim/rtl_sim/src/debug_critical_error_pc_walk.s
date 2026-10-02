#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_critical_error_pc_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: critical-error PC reported for walking PC address bits
#   One sample per boot. The .v arms the executable-SRAM alias
#   (ahb_bus_system_inst.sram_x_alias_en) for the whole test: every address
#   >= 0x1000 that selects no slave reaches the executable SRAM, decoded on
#   its low 16 bits.
#
#   Each boot reads the sample index from SRAM (survives the ndmreset, 0 at
#   power-on). While samples remain it copies an ECALL stub to the physical
#   SRAM location of the target PC (0x80000000 | (PC & 0xFFFF)), publishes the
#   target, bumps the index, signals x31 = 0x11110000 | index and jumps to the
#   target. mnstatus.NMIE is still at its reset value 0, so the ECALL is an
#   unexpected trap: critical-error state. The .v halts the hart, checks dpc
#   against the target, pulses ndmreset. Once every sample is done the boot
#   runs the Smdbltrp boot sequence and ends with x31 = deadbeef.
#
#   Samples (index 0..30 walking ones, k = 1..31; 31..61 walking zeros):
#     walking one  k = 12..31 : 1<<k, except k=25 -> 0x02010000 (ACLINT) and
#                               k=29 -> 0x21000000 (beyond the ROM window)
#     walking one  k = 1..11  : 0x00010000 | 1<<k (bit 16 lifts it out of the
#                               low 4 KB, which the alias does not cover)
#     walking zero k = 9..15  : ~(1<<k) & ~1
#     walking zero k = 1..8, 16..31 : ~(1<<k) & ~1 & ~(1<<15) (keeps the stub
#                               below the reserved 0x8000FF00+ area)
#   Without C (IALIGN=32) bit 1 is cleared at run time, as in the .v.
#
#   SRAM (0x80000000): 0xC00 sample index, 0xC04 published target PC. No stub
#   (4 bytes at PC & 0xFFFF) overlaps them.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ NSAMPLES, 62

.section .text
.global main

.option norvc

main:
    j    _start

    .align 2
m_handler:
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

_start:
    li   s1, 0x80000C00
    lw   t0, 0x00(s1)              # sample index
    li   t1, NSAMPLES
    bgeu t0, t1, final_boot

    #=================================================================
    # SAMPLE BOOT
    #=================================================================
    la   t3, pc_table
    slli t2, t0, 2
    add  t3, t3, t2
    lw   a0, 0(t3)                 # target PC
.if CFG_C_EXTENSION == 0
    andi a0, a0, -4                # IALIGN=32: no bit-1 targets
.endif
    sw   a0, 0x04(s1)              # publish the target for the .v
    addi t1, t0, 1
    sw   t1, 0x00(s1)              # bump the index

    li   t5, 0xFFFF
    and  a2, a0, t5
    li   t5, 0x80000000
    or   a2, a2, t5                # physical SRAM location of the target
    li   t4, 0x0073                # ecall = 0x00000073, as two halfwords
    sh   t4, 0(a2)
    sh   x0, 2(a2)

    lw   t5, 0x00(s1)              # every store has landed
    lw   t5, 0x04(s1)
    lhu  t5, 0(a2)
    lhu  t5, 2(a2)
    fence.i

    li   t6, 0x11110000
    or   t6, t6, t0
    mv   x31, t6                   # sync: sample t0 about to die at a0
    jalr x0, 0(a0)                 # ecall at a0, NMIE=0 -> critical error

1:  j    1b

    #=================================================================
    # FINAL BOOT: normal Smdbltrp boot
    #=================================================================
final_boot:
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0

    ecall                          # an ordinary, handled trap

    li   x31, 0x22222222
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test

    .align 2
pc_table:
    # walking ones, k = 1..31
    .word 0x00010002, 0x00010004, 0x00010008, 0x00010010
    .word 0x00010020, 0x00010040, 0x00010080, 0x00010100
    .word 0x00010200, 0x00010400, 0x00010800, 0x00001000
    .word 0x00002000, 0x00004000, 0x00008000, 0x00010000
    .word 0x00020000, 0x00040000, 0x00080000, 0x00100000
    .word 0x00200000, 0x00400000, 0x00800000, 0x01000000
    .word 0x02010000, 0x04000000, 0x08000000, 0x10000000
    .word 0x21000000, 0x40000000, 0x80000000
    # walking zeros, k = 1..31
    .word 0xFFFF7FFC, 0xFFFF7FFA, 0xFFFF7FF6, 0xFFFF7FEE
    .word 0xFFFF7FDE, 0xFFFF7FBE, 0xFFFF7F7E, 0xFFFF7EFE
    .word 0xFFFFFDFE, 0xFFFFFBFE, 0xFFFFF7FE, 0xFFFFEFFE
    .word 0xFFFFDFFE, 0xFFFFBFFE, 0xFFFF7FFE, 0xFFFE7FFE
    .word 0xFFFD7FFE, 0xFFFB7FFE, 0xFFF77FFE, 0xFFEF7FFE
    .word 0xFFDF7FFE, 0xFFBF7FFE, 0xFF7F7FFE, 0xFEFF7FFE
    .word 0xFDFF7FFE, 0xFBFF7FFE, 0xF7FF7FFE, 0xEFFF7FFE
    .word 0xDFFF7FFE, 0xBFFF7FFE, 0x7FFF7FFE
pc_table_end:
