#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_instret_nmi_excp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: minstret when a data-bus RNMI coincides with a synchronous fault
#   sw zero, 0(zero) takes an AHB ERROR (resumable RNMI, the store itself
#   retired). 0..3 NOPs later a misaligned lw faults. When the RNMI is latched
#   in the same cycle as the lw's exception, the RNMI is taken first, mnepc
#   names the lw, and the lw faults again after mnret. The lw never retires,
#   whatever the interleaving: at the misaligned-load handler, minstret has
#   advanced by exactly csrr + sw + NOPs, plus what the RNMI handler itself
#   retired (the handler measures and reports that in s6).
#
#   Scratchpad (base 0x80000000): 0x00 + 4*n = delta of round n, 0x20 rnmi count
#----------------------------------------------------------------------------

.equ SBASE,          0x80000000

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j _start

    .align 2
m_trap_handler:
    csrr s3, minstret              # <-- must stay first
    sub  s4, s3, s2
    sub  s4, s4, s6                # minus what the RNMI handler retired
    sw   s4, 0(s5)
    lw   zero, 0(s5)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

    .align 2
nmi_handler:
    csrr a3, minstret              # <-- must stay first
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x24(t0)
    lw   t1, 0x20(t0)
    addi t1, t1, 1
    sw   t1, 0x20(t0)
    lw   t1, 0x24(t0)
    csrr t0, mscratch
    csrr a4, minstret
    sub  a4, a4, a3                # retired since the entry read, entry csrr included
    addi a4, a4, 5                 # + csrr a4, sub, addi, add, mnret
    add  s6, s6, a4
    .word 0x70200073               # mnret

# delta = csrr + sw + nops (the misaligned lw never retires)
.macro ROUND id, nops
    addi s5, s1, \id * 4
    li   s6, 0                     # instructions retired by the RNMI handler this round
    li   t1, 0x80000801            # odd address
    csrr s2, minstret
    sw   zero, 0(zero)             # AHB ERROR -> RNMI
    .rept \nops
    nop
    .endr
    lw   t2, 0(t1)                 # misaligned
    li   t0, 40
99:
    addi t0, t0, -1
    bnez t0, 99b
.endm

_start:
    li   sp, 0x80010000
    li   s1, SBASE
    la   t0, m_trap_handler
    csrw mtvec, t0
    la   t0, nmi_handler
    csrw 0x7FD, t0                 # marv_nmvec
    csrsi 0x744, 8                 # Smdbltrp boot: NMIE=1 first...
    csrw mstatush, x0              # ...then MDT=0
    sw   zero, 0x20(s1)

    li   x31, 0x11111111           # Sync: configured

    ROUND 0, 0
    ROUND 1, 1
    ROUND 2, 2
    ROUND 3, 3

    lw   zero, 0x20(s1)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
