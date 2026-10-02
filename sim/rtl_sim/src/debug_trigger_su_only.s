#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_su_only
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: mcontrol6 execute trigger with only the s and/or u bits set
#   fires in S / U and never in M
#   Debug 1.0 mcontrol6: "m: When set, enable this trigger in M-mode." /
#   "s: When set, enable this trigger in S/HS-mode. This bit is hard-wired to
#   0 if the hart does not support S-mode." / "u: When set, enable this
#   trigger in U-mode. This bit is hard-wired to 0 if the hart does not
#   support U-mode."
#   debug_interface.md §8: "m/s/u[6/4/3] (s/u read 0 when SU_MODE_EN=0)";
#   "action=0 -> breakpoint exception: mcause=3, mepc = matching PC,
#   mtval=0. For M-mode triggers, tcontrol.mte gates firing" (so S/U
#   triggers fire with tcontrol.mte left at 0 here).
#
#   Firmware passes (trigger 0, action=0, execute, tdata2 = &tgt):
#     pass 0: s only    pass 1: u only    pass 2: s and u
#   In each pass tgt_fn is called in M, then in S, then in U (S/U only when
#   CFG_SU_MODE_EN; each S/U call ends with an ecall back to M). The M
#   handler counts breakpoints per pass and per MPP, checks mepc == &tgt and
#   mtval == 0, and returns past the (pinned, 4-byte) tgt instruction, so x20
#   counts only the tgt executions that did not fire.
#   Debugger pass (CFG_SU_MODE_EN only): the .v arms trigger 0 with
#   action=1, dmode=1, s only; tgt_fn runs in M, U (no fire) then S -> Debug
#   Mode with dcsr.cause=2, dcsr.prv=1, dpc=&tgt; the .v disarms and resumes.
#
#   Scratchpad (0x80000000): 0x40*pass + 4*MPP = breakpoint count
#   (MPP 0=U, 1=S, 3=M); 0x100 bad-mepc count, 0x104 bad-mtval count,
#   0x108 unexpected-trap count, 0x10C + 4*pass tdata1 read-back.
#   Registers: s1 scratch base, s2 pass slot base, x8 &tgt, x20 non-fired
#   tgt executions, x29 release flag, x31 sync (11111111 = waiting for the
#   debugger, deadbeef = done).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ SBASE, 0x80000000

.section .text
.global main

.option norvc

.macro ARM pattern, pass
    csrw 0x7a0, x0
    csrw 0x7a1, x0
    la   t0, tgt
    csrw 0x7a2, t0
    li   t0, \pattern
    csrw 0x7a1, t0
    csrr t0, 0x7a1
    sw   t0, 0x10C+4*\pass(s1)
    addi s2, s1, 0x40*\pass
    nop
    nop
    nop
    nop
.endm

# call tgt_fn in the privilege selected by \mpp (0x800 = S, 0 = U), ecall back
.macro CALL_LOW mpp
    la   t0, 1f
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, \mpp
    csrs mstatus, t0
    mret
1:  jal  ra, tgt_fn
    ecall
.endm

.macro PASS pattern, pass
    ARM  \pattern, \pass
    jal  ra, tgt_fn
.if CFG_SU_MODE_EN
    CALL_LOW 0x800
    CALL_LOW 0x000
.endif
    csrw 0x7a1, x0
.endm

main:
    j    _start

    .align 2
m_handler:
    csrr t0, mcause
    li   t1, 3
    bne  t0, t1, m_not_bkpt
    csrr t1, mstatus
    srli t1, t1, 11
    andi t1, t1, 3
    slli t1, t1, 2
    add  t1, t1, s2
    lw   t2, 0(t1)
    addi t2, t2, 1
    sw   t2, 0(t1)
    csrr t0, mepc
    la   t2, tgt
    beq  t0, t2, 1f
    lw   t2, 0x100(s1)
    addi t2, t2, 1
    sw   t2, 0x100(s1)
1:  csrr t0, mtval
    beq  t0, x0, 2f
    lw   t2, 0x104(s1)
    addi t2, t2, 1
    sw   t2, 0x104(s1)
2:  csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret                           # same privilege, past tgt
m_not_bkpt:
    addi t0, t0, -8
    li   t1, 1
    bleu t0, t1, m_ecall           # mcause 8 (U) or 9 (S)
    lw   t2, 0x108(s1)
    addi t2, t2, 1
    sw   t2, 0x108(s1)
m_ecall:
    li   t2, 0x1800
    csrs mstatus, t2               # back to M
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

    .align 2
tgt_fn:
tgt:
    .word 0x001a0a13               # addi x20, x20, 1 (pinned 32-bit)
    jalr x0, 0(ra)

_start:
    li   sp, 0x8000F000
    li   s1, SBASE
    mv   s2, s1
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0
.if CFG_SU_MODE_EN
    PMP_ALLOW_ALL
    csrw medeleg, x0
    csrw mideleg, x0
.endif
    li   x20, 0
    li   x29, 0
    la   x8, tgt
    mv   t0, s1
    addi t1, s1, 0x120
clr:
    sw   zero, 0(t0)
    addi t0, t0, 4
    bne  t0, t1, clr

    PASS 0x60000014, 0             # type 6 | s | execute
    PASS 0x6000000C, 1             # type 6 | u | execute
    PASS 0x6000001C, 2             # type 6 | s | u | execute

.if CFG_SU_MODE_EN
    li   x31, 0x11111111
wait:
    beq  x29, x0, wait
    jal  ra, tgt_fn                # M: no fire
    CALL_LOW 0x000                 # U: no fire
    CALL_LOW 0x800                 # S: enters Debug Mode at tgt
.endif

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
