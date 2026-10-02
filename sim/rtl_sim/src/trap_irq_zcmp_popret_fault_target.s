#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_zcmp_popret_fault_target
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ arriving while cm.popret returns to an UNFETCHABLE address
#   COMP-only (Zcmp).
#
#   cm.popret {ra}, 16 pops ra = 0x00000000 (unmapped: instruction-bus ERROR,
#   synchronous cause 1) and jumps there. A machine software interrupt (self-IPI
#   through ACLINT MSIP, posted just before the popret) becomes pending while the
#   sequence runs. Both events must be delivered -- in either order -- and the hart
#   must reach the round's recovery label: the interrupt once, the instruction
#   access fault once with mepc = mtval = 0.
#
#   The store-to-popret distance is swept (0..7 NOPs) to move the interrupt across
#   the sequence.
#
#   Scratchpad (base 0x80000000):
#     0x10 irq_count  0x14 fault_count  0x18 other_count  0x1C recovery address
#     0x100 + id*16 : w0 irq, w1 fault, w2 fault mepc, w3 other (0x100 = fell through)
#----------------------------------------------------------------------------

.equ ACLINT_MSIP0,   0x02000000
.equ MNSTATUS,       0x744
.equ SBASE,          0x80000000
.equ OFF_IRQ,        0x010
.equ OFF_FAULT,      0x014
.equ OFF_OTHER,      0x018
.equ OFF_RECOVER,    0x01C
.equ OFF_FMEPC,      0x020
.equ OFF_RES,        0x100
.equ SP0,            0x80002000
.equ BAD_TARGET,     0x00000000

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
    li   t2, 1
    bne  t1, t2, is_other
    lw   t1, OFF_FAULT(t0)          # cause 1: instruction access fault
    addi t1, t1, 1
    sw   t1, OFF_FAULT(t0)
    csrr t1, mepc
    sw   t1, OFF_FMEPC(t0)
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

# w0..w3 = per-round deltas of irq / fault / (fault mepc) / other
.macro ROUND id, nops
    li   s1, SBASE
    sw   zero, OFF_IRQ(s1)
    sw   zero, OFF_FAULT(s1)
    sw   zero, OFF_OTHER(s1)
    li   t0, 0xFFFFFFFF
    sw   t0, OFF_FMEPC(s1)
    la   t0, recover_\id
    sw   t0, OFF_RECOVER(s1)
    li   t0, SP0
    li   t1, BAD_TARGET
    sw   t1, -4(t0)                 # ra slot of the popped frame
    lw   zero, -4(t0)
    li   sp, SP0 - 16
    li   ra, 0x12345678
    li   t0, 1
    li   t1, ACLINT_MSIP0
    sw   t0, 0(t1)                  # self-IPI: pending a few cycles from now
    .rept \nops
    nop
    .endr
    cm.popret {ra}, 16
    li   s1, SBASE                  # fell through: must never happen (other += 0x100)
    li   t0, 0x100
    sw   t0, OFF_OTHER(s1)
recover_\id:
    li   t0, 40
99:
    addi t0, t0, -1
    bnez t0, 99b
    li   s1, SBASE
    lw   t0, OFF_IRQ(s1)
    sw   t0, OFF_RES + \id*16 + 0(s1)
    lw   t0, OFF_FAULT(s1)
    sw   t0, OFF_RES + \id*16 + 4(s1)
    lw   t0, OFF_FMEPC(s1)
    sw   t0, OFF_RES + \id*16 + 8(s1)
    lw   t0, OFF_OTHER(s1)
    sw   t0, OFF_RES + \id*16 + 12(s1)
    lw   zero, OFF_RES + \id*16 + 12(s1)
.endm

_start:
    li   sp, SP0
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0              # ...then MDT=0
    la   t0, mtvec_handler
    csrw mtvec, t0
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

    csrci mstatus, 0x8
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
