#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_ldst_uop
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sdtrig LOAD WATCHPOINT (action=1, enter Debug) on accesses that
#   are not a plain load
#   P  the stack slot a CM.POPRET pops: the hart must enter Debug Mode with
#      dcsr.cause=2 and dpc=&cm.popret; after the debugger disarms and resumes,
#      the whole CM.POPRET re-executes and returns (s0/sp restored).
#   J  (Zcmt) the jump-table entry a CM.JT reads: same, dpc=&cm.jt, and the
#      jump lands on the table target after resume.
#   M  a misaligned load at the watched address: the watchpoint outranks the
#      address-misaligned exception, so the hart enters Debug Mode (cause 2)
#      instead of trapping; after resume the load traps as misaligned.
#   Each sequence first runs once without the watchpoint as a reference. With
#   Zicntr, the watched run must retire exactly as many instructions as the
#   reference: the instruction that entered Debug Mode is not retired twice.
#
#   The debugger (the .v) halts the spinning hart before each watched run, arms
#   trigger 0 (load | action=1 | dmode | m), resumes, checks the automatic halt,
#   disarms and resumes. The firmware provides tdata2 and x6 = expected dpc.
#
#   Scratchpad (byte offsets from 0x80000000):
#     0x00 trap count   0x04 last mcause
#     0x10/0x14 P minstret delta (reference / watched)  0x18 P s0  0x1C P sp
#     0x20/0x24 J minstret delta (reference / watched)  0x28 J landed (1)
#     0x30/0x34 M minstret delta (reference / watched)
#   x31: 0x11111111 / 0x22222222 / 0x33333333 = P / J / M armed-spin,
#        0xBAD0BAD0 = a sequence fell through (the bug), 0xdeadbeef = done
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ STACK_TOP,  0x8000E000
.equ MISAL,      0x80000D00

main:
    j _start

#=========================================================================
# Trap handler: counts, records mcause, skips the 4-byte faulting instruction
#=========================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)
    csrr t0, mcause
    sw   t0, 0x04(s1)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

#=========================================================================
# Watched sequences (each called twice: reference, then watched)
#=========================================================================
    # P: push {ra, s0}, clobber s0, popret {ra, s0}. The popret loads s0 from
    #    STACK_TOP-8 (the watched address).
    .align 2
seq_popret:
.if CFG_ZICNTR_EN
    csrr s3, minstret
.endif
    .half 0xB852                     # cm.push   {ra, s0}, -16
    li   s0, 0x0DEAD000
p_popret:
    .half 0xBE52                     # cm.popret {ra, s0}, 16
    li   x31, 0xBAD0BAD0             # reached only if the popret fell through
1:  j    1b

.if CFG_C_EXTENSION >= 4
    # J: cm.jt 0 jumps through jt_tbl[0] (the watched address).
    .align 2
seq_jt:
.if CFG_ZICNTR_EN
    csrr s3, minstret
.endif
p_jt:
    .half 0xA002                     # cm.jt 0
    li   x31, 0xBAD0BAD0             # reached only if the cm.jt fell through
1:  j    1b
jt_target0:
.if CFG_ZICNTR_EN
    csrr s4, minstret
.endif
    ret
.endif

    # M: misaligned word load at MISAL+1 (the watched address).
    .align 2
seq_misal:
.if CFG_ZICNTR_EN
    csrr s3, minstret
.endif
    .option push
    .option norvc
p_misal:
    lw   t4, 1(a3)
    .option pop
.if CFG_ZICNTR_EN
    csrr s4, minstret
.endif
    ret

#=========================================================================
# Spin long enough for the debugger to halt the hart and arm the trigger
#=========================================================================
spin:
    li   a0, 0
    li   a1, 0x00001000
1:  addi a0, a0, 1
    blt  a0, a1, 1b
    ret

_start:
    csrsi 0x744, 8                   # Smdbltrp boot: NMIE first,
    csrw  mstatush, x0               # then clear MDT
    li   sp, STACK_TOP
    li   s1, 0x80000000
    li   a3, MISAL
    la   t0, trap_handler
    csrw mtvec, t0
    sw   zero, 0x00(s1)
    li   t0, 0x08
    csrw 0x7a5, t0                   # tcontrol.mte = 1
    li   t0, 0
    csrw 0x7a0, t0                   # tselect = 0
    csrw 0x7a1, x0                   # disarmed until the debugger arms it

    #=====================================================================
    # P: CM.POPRET pop load
    #=====================================================================
    li   s0, 0x50505050
    jal  ra, seq_popret              # reference
.if CFG_ZICNTR_EN
    csrr s4, minstret
    sub  t0, s4, s3
    sw   t0, 0x10(s1)
.endif
    li   t0, STACK_TOP - 8
    csrw 0x7a2, t0                   # tdata2 = the s0 slot popped by cm.popret
    la   x6, p_popret                # expected dpc
    li   x31, 0x11111111
    jal  ra, spin
    li   s0, 0x50505050
    jal  ra, seq_popret              # watched
.if CFG_ZICNTR_EN
    csrr s4, minstret
    sub  t0, s4, s3
    sw   t0, 0x14(s1)
.endif
    sw   s0, 0x18(s1)
    sw   sp, 0x1C(s1)

    #=====================================================================
    # J: CM.JT table read
    #=====================================================================
.if CFG_C_EXTENSION >= 4
    la   t0, jt_tbl
    csrw 0x017, t0                   # jvt = table base, mode 0
    jal  ra, seq_jt                  # reference
.if CFG_ZICNTR_EN
    sub  t0, s4, s3
    sw   t0, 0x20(s1)
.endif
    la   t0, jt_tbl
    csrw 0x7a2, t0                   # tdata2 = jt_tbl[0]
    la   x6, p_jt
    li   x31, 0x22222222
    jal  ra, spin
    jal  ra, seq_jt                  # watched
.if CFG_ZICNTR_EN
    sub  t0, s4, s3
    sw   t0, 0x24(s1)
.endif
    li   t0, 1
    sw   t0, 0x28(s1)
.endif

    #=====================================================================
    # M: misaligned load at the watched address
    #=====================================================================
    jal  ra, seq_misal               # reference (traps as misaligned, skipped)
.if CFG_ZICNTR_EN
    sub  t0, s4, s3
    sw   t0, 0x30(s1)
.endif
    li   t0, MISAL + 1
    csrw 0x7a2, t0                   # tdata2 = the misaligned address
    la   x6, p_misal
    li   x31, 0x33333333
    jal  ra, spin
    jal  ra, seq_misal               # watched
.if CFG_ZICNTR_EN
    sub  t0, s4, s3
    sw   t0, 0x34(s1)
.endif

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j end_of_test

.if CFG_C_EXTENSION >= 4
    .align 6
jt_tbl:
    .word jt_target0
.endif
