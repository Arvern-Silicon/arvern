#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_kill_zcmp_sweep
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ swept across every micro-op of a 13-register push/pop/popret
#   COMP-only (Zcmp).
#
#   The testbench raises the machine software interrupt line N = id % 16
#   cycles after the round's cm.push / cm.pop / cm.popret {ra, s0-s11} starts
#   (a2 = round id), so it becomes pending at every point of the sequence, and
#   drops it when the interrupt is taken. Wherever it lands, the macro-op must complete
#   exactly once (killed and restarted from scratch, or completed first):
#   stack contents, loaded registers, sp and the popret landing are checked by
#   the firmware; the interrupt is taken exactly once per round.
#
#   Pass A: marv_ctl[1]=1 (IRQ kill enabled). Pass B: marv_ctl[1]=0 (the
#   interrupt waits for the sequence). The testbench counts actual kills.
#
#   Scratchpad (base 0x80000000):
#     0x10 irq count (per round)  0x14 failures  0x18 rounds  0x1C first failing round id
#----------------------------------------------------------------------------

.equ MNSTATUS,       0x744
.equ MARV_CTL,       0x7FF
.equ SBASE,          0x80000000
.equ SP_PUSH,        0x80002000
.equ SP_POP,         0x80003000

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
    csrr t1, mcause
    bgez t1, h_unexp                # synchronous: unexpected, count as failure
    lw   t1, 0x10(t0)
    addi t1, t1, 1
    sw   t1, 0x10(t0)
    j    h_exit
h_unexp:
    lw   t1, 0x14(t0)
    addi t1, t1, 1
    sw   t1, 0x14(t0)
    csrr t1, mepc
    addi t1, t1, 2
    csrw mepc, t1
h_exit:
    lw   zero, 0x10(t0)
    lw   t1, 0x00(t0)
    csrr t0, mscratch
    mret

# failure bookkeeping: a2 = round id, return through t5; uses a0/a1 only
fail:
    li   a0, SBASE
    lw   a1, 0x14(a0)
    bnez a1, 1f
    sw   a2, 0x1C(a0)               # first failing round
1:
    addi a1, a1, 1
    sw   a1, 0x14(a0)
    jr   t5

.macro CHK reg, val
    li   t3, \val
    beq  \reg, t3, 98f
    jal  t5, fail
98:
.endm

.macro SET_REGS base
    li   ra,  \base + 1
    li   s0,  \base + 2
    li   s1,  \base + 3
    li   s2,  \base + 4
    li   s3,  \base + 5
    li   s4,  \base + 6
    li   s5,  \base + 7
    li   s6,  \base + 8
    li   s7,  \base + 9
    li   s8,  \base + 10
    li   s9,  \base + 11
    li   s10, \base + 12
    li   s11, \base + 13
.endm

.macro CHK_REGS base
    CHK  s0,  \base + 2
    CHK  s1,  \base + 3
    CHK  s2,  \base + 4
    CHK  s3,  \base + 5
    CHK  s4,  \base + 6
    CHK  s5,  \base + 7
    CHK  s6,  \base + 8
    CHK  s7,  \base + 9
    CHK  s8,  \base + 10
    CHK  s9,  \base + 11
    CHK  s10, \base + 12
    CHK  s11, \base + 13
.endm

.macro ZERO_REGS
    li   ra, 0
    li   s0, 0
    li   s1, 0
    li   s2, 0
    li   s3, 0
    li   s4, 0
    li   s5, 0
    li   s6, 0
    li   s7, 0
    li   s8, 0
    li   s9, 0
    li   s10, 0
    li   s11, 0
.endm


.macro SETTLE
    li   t3, 40
97:
    addi t3, t3, -1
    bnez t3, 97b
.endm

# round prologue / epilogue: irq count must be exactly 1
.macro ROUND_BEGIN id
    li   a2, \id
    li   t3, SBASE
    sw   zero, 0x10(t3)
    lw   t4, 0x18(t3)
    addi t4, t4, 1
    sw   t4, 0x18(t3)
.endm
.macro ROUND_END
    li   sp, 0x80010000
    li   t3, SBASE
    lw   t4, 0x10(t3)
    li   t3, 1
    beq  t4, t3, 96f
    jal  t5, fail
96:
.endm

# PUSH: s11 at sp-4 ... ra at sp-52, sp -= 64
.macro PUSH_ROUND id
    ROUND_BEGIN \id
    li   t3, SP_PUSH - 64
    li   t4, 16
95:
    sw   zero, 0(t3)
    addi t3, t3, 4
    addi t4, t4, -1
    bnez t4, 95b
    lw   zero, -4(t3)
    li   sp, SP_PUSH
    SET_REGS 0x10000000 + (\id << 8)
    cm.push {ra, s0-s11}, -64
    SETTLE
    li   t3, SP_PUSH - 64
    beq  sp, t3, 94f
    jal  t5, fail
94:
    li   t3, SP_PUSH - 4            # t3 walks the frame downwards, t4 = expected
    li   t4, 0x10000000 + (\id << 8) + 13
    li   t0, 13
93:
    lw   t1, 0(t3)
    beq  t1, t4, 92f
    jal  t5, fail
92:
    addi t3, t3, -4
    addi t4, t4, -1
    addi t0, t0, -1
    bnez t0, 93b
    ROUND_END
.endm

# frame preload for pop: [SP_POP+60-4k] = base+13-k
.macro PRELOAD_POP base
    li   t3, SP_POP + 60
    li   t4, \base + 13
    li   t0, 13
91:
    sw   t4, 0(t3)
    addi t3, t3, -4
    addi t4, t4, -1
    addi t0, t0, -1
    bnez t0, 91b
    lw   zero, 4(t3)
.endm

.macro POP_ROUND id
    ROUND_BEGIN \id
    PRELOAD_POP 0x20000000 + (\id << 8)
    ZERO_REGS
    li   sp, SP_POP
    cm.pop {ra, s0-s11}, 64
    SETTLE
    li   t3, SP_POP + 64
    beq  sp, t3, 90f
    jal  t5, fail
90:
    CHK  ra, 0x20000000 + (\id << 8) + 1
    CHK_REGS 0x20000000 + (\id << 8)
    ROUND_END
.endm

# POPRET: ra slot holds the landing label
.macro POPRET_ROUND id
    ROUND_BEGIN \id
    PRELOAD_POP 0x30000000 + (\id << 8)
    li   t3, SP_POP + 12
    la   t4, 88f
    sw   t4, 0(t3)                  # ra slot
    lw   zero, 0(t3)
    ZERO_REGS
    li   sp, SP_POP
    cm.popret {ra, s0-s11}, 64
    jal  t5, fail                   # fell through
88:
    SETTLE
    li   t3, SP_POP + 64
    beq  sp, t3, 89f
    jal  t5, fail
89:
    CHK_REGS 0x30000000 + (\id << 8)
    ROUND_END
.endm

.macro SWEEP base
    PUSH_ROUND   \base + 0
    PUSH_ROUND   \base + 1
    PUSH_ROUND   \base + 2
    PUSH_ROUND   \base + 3
    PUSH_ROUND   \base + 4
    PUSH_ROUND   \base + 5
    PUSH_ROUND   \base + 6
    PUSH_ROUND   \base + 7
    PUSH_ROUND   \base + 8
    PUSH_ROUND   \base + 9
    PUSH_ROUND   \base + 10
    PUSH_ROUND   \base + 11
    PUSH_ROUND   \base + 12
    PUSH_ROUND   \base + 13
    PUSH_ROUND   \base + 14
    PUSH_ROUND   \base + 15
    POP_ROUND    \base + 16
    POP_ROUND    \base + 17
    POP_ROUND    \base + 18
    POP_ROUND    \base + 19
    POP_ROUND    \base + 20
    POP_ROUND    \base + 21
    POP_ROUND    \base + 22
    POP_ROUND    \base + 23
    POP_ROUND    \base + 24
    POP_ROUND    \base + 25
    POP_ROUND    \base + 26
    POP_ROUND    \base + 27
    POP_ROUND    \base + 28
    POP_ROUND    \base + 29
    POP_ROUND    \base + 30
    POP_ROUND    \base + 31
    POPRET_ROUND \base + 32
    POPRET_ROUND \base + 33
    POPRET_ROUND \base + 34
    POPRET_ROUND \base + 35
    POPRET_ROUND \base + 36
    POPRET_ROUND \base + 37
    POPRET_ROUND \base + 38
    POPRET_ROUND \base + 39
    POPRET_ROUND \base + 40
    POPRET_ROUND \base + 41
    POPRET_ROUND \base + 42
    POPRET_ROUND \base + 43
    POPRET_ROUND \base + 44
    POPRET_ROUND \base + 45
    POPRET_ROUND \base + 46
    POPRET_ROUND \base + 47
.endm

_start:
    li   sp, 0x80010000
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0              # ...then MDT=0
    la   t0, mtvec_handler
    csrw mtvec, t0
    li   t3, SBASE
    sw   zero, 0x14(t3)
    sw   zero, 0x18(t3)
    li   t3, 0xFFFFFFFF
    li   t4, SBASE
    sw   t3, 0x1C(t4)
    li   t0, 0x8                    # mie.MSIE
    csrs mie, t0
    csrsi mstatus, 0x8              # mstatus.MIE

    csrsi MARV_CTL, 2               # pass A: IRQ kill of UOP sequences enabled
    li   x31, 0x11111111            # Sync: pass A
    SWEEP 0

    csrci MARV_CTL, 2               # pass B: kill disabled -- the IRQ waits
    li   x31, 0x22222222            # Sync: pass B
    SWEEP 64

    csrci mstatus, 0x8
    li   t3, SBASE
    lw   zero, 0x14(t3)
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
