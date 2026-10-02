#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_kill_zcmp_bus_err
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ held for a Zcmp kill while the push's own store takes a bus error
#   COMP-only (Zcmp). IRQ kill enabled (marv_ctl[1] = 1, reset value).
#
#   cm.push {ra, s0-s2}, -16 runs from sp = 0x10: its first store (to 0xC,
#   unmapped) takes an AHB ERROR, a resumable data-bus RNMI with
#   marv_estat.restartable = 1 and marv_epc = &push. A machine software interrupt
#   (self-IPI) is posted 0-11 instructions before the push, so in some rounds it
#   is latched in the kill window and holds the sequencer when the error returns.
#
#   Handlers (no sp use):
#   - RNMI: points sp at the valid stack SP0. If it interrupted the program
#     (mnepc = &push + 4) it replays the push (mnepc <- marv_epc), per the
#     software_guide replay contract. If it interrupted the IRQ handler it just
#     resumes: the push then belongs to the IRQ's mepc.
#   - IRQ: drops the self-IPI, counts.
#
#   Every round the push must finally execute exactly once, at SP0: sp = SP0-16,
#   s2/s1/s0/ra at SP0-4/-8/-12/-16. Bug signature: in the coincident rounds the
#   IRQ is taken with mepc past the push and the push is lost (sp = SP0, stack
#   untouched).
#
#   Scratchpad (base 0x80000000):
#     0x10 irq  0x14 nmi  0x18 other
#     0x100 + id*32 : w0 irq, w1 nmi, w2 other, w3 sp, w4..w7 [SP0-4..SP0-16]
#----------------------------------------------------------------------------

.equ ACLINT_MSIP0,   0x02000000
.equ MNSTATUS,       0x744
.equ MNEPC,          0x741
.equ MARV_ESTAT,     0x7FE
.equ MARV_EPC,       0xFFC
.equ MARV_NMVEC,     0x7FD
.equ SBASE,          0x80000000
.equ OFF_IRQ,        0x010
.equ OFF_NMI,        0x014
.equ OFF_OTHER,      0x018
.equ OFF_RES,        0x100
.equ SP0,            0x80002000
.equ SP_BAD,         0x00000010

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    .align 2
nmi_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    sw   t2, 0x04(t0)
    lw   t1, OFF_NMI(t0)
    addi t1, t1, 1
    sw   t1, OFF_NMI(t0)
    li   sp, SP0                    # the replay (from here or from the IRQ) needs a valid stack
    csrr t1, MARV_ESTAT
    andi t1, t1, 0x8                # restartable?
    beqz t1, 1f
    la   t2, irq_handler
    csrr t1, MNEPC
    bltu t1, t2, 2f                 # mnepc below the IRQ handler: the program
    la   t2, irq_handler_end
    bltu t1, t2, 1f                 # inside the IRQ handler: resume it
2:
    csrr t1, MARV_EPC
    csrw MNEPC, t1                  # replay the faulting macro-op
1:
    li   t1, 0x5
    csrw MARV_ESTAT, t1             # W1C valid|overrun
    lw   zero, OFF_NMI(t0)
    lw   t1, 0x00(t0)
    lw   t2, 0x04(t0)
    csrr t0, mscratch
    .word 0x70200073                # mnret

    .align 4
irq_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x08(t0)
    csrr t1, mcause
    bltz t1, 3f
    lw   t1, OFF_OTHER(t0)          # unexpected synchronous trap
    addi t1, t1, 1
    sw   t1, OFF_OTHER(t0)
    j    4f
3:
    li   t1, ACLINT_MSIP0
    sw   zero, 0(t1)                # drop the self-IPI
    lw   zero, 0(t1)
    lw   t1, OFF_IRQ(t0)
    addi t1, t1, 1
    sw   t1, OFF_IRQ(t0)
4:
    lw   zero, OFF_IRQ(t0)
    lw   t1, 0x08(t0)
    csrr t0, mscratch
    mret
irq_handler_end:

.macro ROUND id, nops
    li   s1, SBASE
    sw   zero, OFF_IRQ(s1)
    sw   zero, OFF_NMI(s1)
    sw   zero, OFF_OTHER(s1)
    li   t0, SP0
    sw   zero, -4(t0)
    sw   zero, -8(t0)
    sw   zero, -12(t0)
    sw   zero, -16(t0)
    lw   zero, -16(t0)
    li   ra, 0x1A000000 + \id
    li   s0, 0x50000000 + \id
    li   s1, 0x51000000 + \id
    li   s2, 0x52000000 + \id
    li   sp, SP_BAD
    li   t0, 1
    li   t1, ACLINT_MSIP0
    sw   t0, 0(t1)                  # self-IPI: pending a few cycles from now
    .rept \nops
    nop
    .endr
    cm.push {ra, s0-s2}, -16
    li   t0, 40
99:
    addi t0, t0, -1
    bnez t0, 99b
    mv   t2, sp
    li   s1, SBASE
    lw   t0, OFF_IRQ(s1)
    sw   t0, OFF_RES + \id*32 + 0(s1)
    lw   t0, OFF_NMI(s1)
    sw   t0, OFF_RES + \id*32 + 4(s1)
    lw   t0, OFF_OTHER(s1)
    sw   t0, OFF_RES + \id*32 + 8(s1)
    sw   t2, OFF_RES + \id*32 + 12(s1)
    li   t1, SP0
    lw   t0, -4(t1)
    sw   t0, OFF_RES + \id*32 + 16(s1)
    lw   t0, -8(t1)
    sw   t0, OFF_RES + \id*32 + 20(s1)
    lw   t0, -12(t1)
    sw   t0, OFF_RES + \id*32 + 24(s1)
    lw   t0, -16(t1)
    sw   t0, OFF_RES + \id*32 + 28(s1)
    lw   zero, OFF_RES + \id*32 + 28(s1)
.endm

_start:
    li   sp, SP0
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0              # ...then MDT=0
    la   t0, irq_handler
    csrw mtvec, t0
    la   t0, nmi_handler
    csrw MARV_NMVEC, t0

    li   t0, 0x8                    # mie.MSIE
    csrs mie, t0
    csrsi mstatus, 0x8              # mstatus.MIE

    li   x31, 0x11111111            # Sync: set up

    ROUND 0, 0
    ROUND 1, 1
    ROUND 2, 2
    ROUND 3, 3
    ROUND 4, 4
    ROUND 5, 5
    ROUND 6, 6
    ROUND 7, 7
    ROUND 8, 8
    ROUND 9, 9
    ROUND 10, 10
    ROUND 11, 11

    csrci mstatus, 0x8
    li   sp, SP0
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
