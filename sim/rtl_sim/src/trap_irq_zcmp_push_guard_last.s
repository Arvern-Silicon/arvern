#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_zcmp_push_guard_last
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ landing on the last killable micro-op of a Zcmp push/pop whose
#   LAST access faults.
#   COMP-only (Zcmp), PMP_NR > 0.
#
#   Entry 0 is a LOCKED NAPOT guard (16 bytes, R=W=X=0). Rounds 0-11:
#   cm.push {ra, s0-s1}, -16 from sp = GUARD+24 stores at sp-4, sp-8 (allowed) and
#   sp-12 (inside the guard: store access fault, mtval = GUARD+12) -- only the last
#   store faults. Rounds 12-23: cm.pop {ra, s0-s1}, 16 from sp = GUARD+8 loads
#   sp+12, sp+8 (allowed) and sp+4 (guard: load access fault, mtval = GUARD+12).
#   A machine software interrupt (self-IPI) is posted 0-11 instructions before the
#   macro-op, so across the rounds it lands on every micro-op, including the last one
#   the sequencer may still kill.
#
#   Both events must be delivered, in either order: the access fault exactly once
#   with mepc = &macro-op and mtval = GUARD+12, the interrupt exactly once. sp must
#   be unchanged (Zcmp updates sp last).
#
#   Bug signature: the interrupt is taken with mepc past the macro-op and the access
#   fault is never reported (fault count 0).
#
#   Scratchpad (base 0x80000000):
#     0x10 irq  0x14 fault  0x18 other  0x1C recovery  0x20 mepc  0x24 mtval
#     0x100 + id*32 : w0 irq, w1 fault, w2 mepc, w3 mtval, w4 other, w5 sp, w6 &push
#----------------------------------------------------------------------------

.equ ACLINT_MSIP0,   0x02000000
.equ MNSTATUS,       0x744
.equ SBASE,          0x80000000
.equ OFF_IRQ,        0x010
.equ OFF_FAULT,      0x014
.equ OFF_OTHER,      0x018
.equ OFF_RECOVER,    0x01C
.equ OFF_MEPC,       0x020
.equ OFF_MTVAL,      0x024
.equ OFF_RES,        0x100
.equ GUARD,          0x80003000
.equ SP_PUSH,        GUARD + 24
.equ SP_POP,         GUARD + 8

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    .align 4
mtvec_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    sw   t2, 0x04(t0)
    csrr t1, mcause
    bltz t1, is_irq
    li   t2, 7
    beq  t1, t2, is_fault
    li   t2, 5
    bne  t1, t2, is_other
is_fault:
    lw   t1, OFF_FAULT(t0)          # cause 5/7: load/store access fault
    addi t1, t1, 1
    sw   t1, OFF_FAULT(t0)
    csrr t1, mepc
    sw   t1, OFF_MEPC(t0)
    csrr t1, mtval
    sw   t1, OFF_MTVAL(t0)
    lw   t1, OFF_RECOVER(t0)
    csrw mepc, t1
    j    h_exit
is_other:
    lw   t1, OFF_OTHER(t0)
    addi t1, t1, 1
    sw   t1, OFF_OTHER(t0)
    lw   t1, OFF_RECOVER(t0)
    csrw mepc, t1
    j    h_exit
is_irq:
    li   t1, ACLINT_MSIP0
    sw   zero, 0(t1)                # drop the self-IPI
    lw   zero, 0(t1)
    lw   t1, OFF_IRQ(t0)
    addi t1, t1, 1
    sw   t1, OFF_IRQ(t0)
h_exit:
    lw   zero, OFF_IRQ(t0)
    lw   t1, 0x00(t0)
    lw   t2, 0x04(t0)
    csrr t0, mscratch
    mret

.macro ROUND id, nops, pop, sp0
    li   s1, SBASE
    sw   zero, OFF_IRQ(s1)
    sw   zero, OFF_FAULT(s1)
    sw   zero, OFF_OTHER(s1)
    sw   zero, OFF_MEPC(s1)
    sw   zero, OFF_MTVAL(s1)
    la   t0, recover_\id
    sw   t0, OFF_RECOVER(s1)
    la   t0, push_\id
    sw   t0, OFF_RES + \id*32 + 24(s1)
    lw   zero, OFF_RES + \id*32 + 24(s1)
    li   sp, \sp0
    li   t0, 1
    li   t1, ACLINT_MSIP0
    sw   t0, 0(t1)                  # self-IPI: pending a few cycles from now
    .rept \nops
    nop
    .endr
push_\id:
    .if \pop
    cm.pop  {ra, s0-s1}, 16
    .else
    cm.push {ra, s0-s1}, -16
    .endif
    li   s1, SBASE                  # fell through: must never happen (other += 0x100)
    li   t0, 0x100
    sw   t0, OFF_OTHER(s1)
recover_\id:
    li   t0, 40
99:
    addi t0, t0, -1
    bnez t0, 99b
    mv   t2, sp
    li   sp, 0x80010000
    li   s1, SBASE
    lw   t0, OFF_IRQ(s1)
    sw   t0, OFF_RES + \id*32 + 0(s1)
    lw   t0, OFF_FAULT(s1)
    sw   t0, OFF_RES + \id*32 + 4(s1)
    lw   t0, OFF_MEPC(s1)
    sw   t0, OFF_RES + \id*32 + 8(s1)
    lw   t0, OFF_MTVAL(s1)
    sw   t0, OFF_RES + \id*32 + 12(s1)
    lw   t0, OFF_OTHER(s1)
    sw   t0, OFF_RES + \id*32 + 16(s1)
    sw   t2, OFF_RES + \id*32 + 20(s1)
    lw   zero, OFF_RES + \id*32 + 20(s1)
.endm

_start:
    li   sp, 0x80010000
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0              # ...then MDT=0
    la   t0, mtvec_handler
    csrw mtvec, t0

    li   t0, (GUARD >> 2) | 1       # NAPOT, 16 bytes
    csrw pmpaddr0, t0
    li   t0, 0x98                   # entry 0: L | NAPOT | R=W=X=0 (binds M-mode)
    csrw pmpcfg0, t0

    li   t0, 0x8                    # mie.MSIE
    csrs mie, t0
    csrsi mstatus, 0x8              # mstatus.MIE

    li   x31, 0x11111111            # Sync: set up

    ROUND 0, 0, 0, SP_PUSH
    ROUND 1, 1, 0, SP_PUSH
    ROUND 2, 2, 0, SP_PUSH
    ROUND 3, 3, 0, SP_PUSH
    ROUND 4, 4, 0, SP_PUSH
    ROUND 5, 5, 0, SP_PUSH
    ROUND 6, 6, 0, SP_PUSH
    ROUND 7, 7, 0, SP_PUSH
    ROUND 8, 8, 0, SP_PUSH
    ROUND 9, 9, 0, SP_PUSH
    ROUND 10, 10, 0, SP_PUSH
    ROUND 11, 11, 0, SP_PUSH
    ROUND 12, 0, 1, SP_POP
    ROUND 13, 1, 1, SP_POP
    ROUND 14, 2, 1, SP_POP
    ROUND 15, 3, 1, SP_POP
    ROUND 16, 4, 1, SP_POP
    ROUND 17, 5, 1, SP_POP
    ROUND 18, 6, 1, SP_POP
    ROUND 19, 7, 1, SP_POP
    ROUND 20, 8, 1, SP_POP
    ROUND 21, 9, 1, SP_POP
    ROUND 22, 10, 1, SP_POP
    ROUND 23, 11, 1, SP_POP

    csrci mstatus, 0x8
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
