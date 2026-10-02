#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ex_squash
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: EX-STAGE EXCEPTION vs THE YOUNGER INSTRUCTION IN ID
#   A load/store faults in EX (misaligned, or PMP-denied through a locked
#   entry) while the next instruction Y sits in ID. Y must leave no trace:
#   the trap reports the load/store (mcause/mepc/mtval), exactly once, and
#   the state Y would modify is unchanged when the handler runs. Y then
#   executes normally after the handler returns to it (or is skipped for the
#   cases where re-executing it would not return: mret, wfi, ecall, jalr 0).
#
#   Y covers: ALU op, JAL, JALR, JALR to address 0 (unmapped), taken and
#   not-taken branch, store, CSR write, PMP CSR write, FENCE.I, MRET, WFI,
#   ECALL and CM.PUSH. One more case faults in EX without an address (a CSR
#   write to a read-only CSR, cause 2).
#
#   With Zicntr, minstret also proves that Y did not retire: it is read at a
#   label p<k> before the pair and first thing in the handler, and the
#   difference must equal the straight-line instruction count p<k>..f<k>.
#
#   Per case k the scratchpad slot B = 0x80000100 + k*0x60 holds:
#     +00 mcause  +04 mepc  +08 mtval  +0C trap count
#     +10..+24  state before the case  (s2, ra, sp, mscratch, [s4], pmpaddr1)
#     +28..+3C  same state as seen by the handler
#     +40 expected mepc  +44 expected mcause  +48 expected mtval  +4C 1 = case ran
#     +50 pushed ra (case 19)  +54 minstret at p<k>  +58 minstret in the handler
#     +5C expected minstret difference
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.option norelax                      # the case pairs are placed with .align; keep the linker from moving them

.section .text
.global main

.equ MNSTATUS,   0x744
.equ SPAD,       0x80000100
.equ STRIDE,     0x60
.equ SAVE,       0x8000FE00
.equ WATCH,      0x80000C00          # memory word a younger store would hit
.equ MISAL,      0x80000D00          # misaligned-access base (aligned; +1/+2 used)
.equ PMP_DENY,   0x81001000          # 4 KB NAPOT, locked, no permission

main:
    j _start

#=========================================================================
# TRAP HANDLER -- uses t0..t3 only (saved to SAVE, not the stack: sp is
# watched). s7 = case index, s6 = bytes to add to mepc.
#=========================================================================
    .align 2
trap_handler:
.if CFG_ZICNTR_EN
    csrr s11, minstret               # first: no handler instruction has retired yet
.endif
    li   t0, SAVE
    sw   t1, 0x0(t0)
    sw   t2, 0x4(t0)
    sw   t3, 0x8(t0)

    # t1 = slot base
    slli t1, s7, 6                   # t1 = s7 * 0x60
    slli t2, s7, 5
    add  t1, t1, t2
    li   t2, SPAD
    add  t1, t1, t2

    lw   t2, 0x0C(t1)                # trap count
    addi t2, t2, 1
    sw   t2, 0x0C(t1)
    li   t3, 1
    bne  t2, t3, 1f                  # record the first trap of the case only
    csrr t2, mcause
    sw   t2, 0x00(t1)
    csrr t2, mepc
    sw   t2, 0x04(t1)
    csrr t2, mtval
    sw   t2, 0x08(t1)
    sw   s2, 0x28(t1)
    sw   ra, 0x2C(t1)
    sw   sp, 0x30(t1)
    csrr t2, mscratch
    sw   t2, 0x34(t1)
    li   t2, WATCH
    lw   t2, 0(t2)
    sw   t2, 0x38(t1)
.if CFG_ZICNTR_EN
    sw   s11, 0x58(t1)
.endif
.if CFG_PMP_NR > 0
    csrr t2, pmpaddr1
    sw   t2, 0x3C(t1)
.endif
1:
    csrr t2, mepc
    add  t2, t2, s6
    csrw mepc, t2

    li   t0, SAVE
    lw   t1, 0x0(t0)
    lw   t2, 0x4(t0)
    lw   t3, 0x8(t0)
    mret

#=========================================================================
# Per-case helpers
#   CASE_PRE k, skip : set sentinels, record them, s7=k, s6=skip
#   CASE_EXP fault_label, cause, tval_reg_expr : record expectations
#=========================================================================
.macro CASE_PRE k, skip
    li   s7, \k
    li   s6, \skip
    li   t1, STRIDE*\k + SPAD
    li   s2, 0x5A000000 + \k
    li   ra, 0xA0000000 + \k
    li   t0, 0x1000 + \k
    csrw mscratch, t0
    li   t0, 0x11110000 + \k
    sw   t0, 0(s4)
    sw   s2, 0x10(t1)
    sw   ra, 0x14(t1)
    sw   sp, 0x18(t1)
    csrr t0, mscratch
    sw   t0, 0x1C(t1)
    lw   t0, 0(s4)
    sw   t0, 0x20(t1)
.if CFG_PMP_NR > 0
    li   t0, 0x00440000 + \k
    csrw pmpaddr1, t0
    csrr t0, pmpaddr1
    sw   t0, 0x24(t1)
.endif
    li   t0, 1
    sw   t0, 0x4C(t1)
.endm

.macro CASE_MARK k                  # straight-line from here to f<k>; t1 = slot base
p\k:
.if CFG_ZICNTR_EN
    csrr t0, minstret
    sw   t0, 0x54(t1)
.endif
.endm

.macro CASE_NEXP k                  # after the cases: expected minstret difference
    li   t1, STRIDE*\k + SPAD
    la   t2, nexp_tbl
    lw   t0, (4*\k)(t2)
    sw   t0, 0x5C(t1)
.endm

.macro CASE_EXP k, flabel, cause, tval
    li   t1, STRIDE*\k + SPAD
    la   t0, \flabel
    sw   t0, 0x40(t1)
    li   t0, \cause
    sw   t0, 0x44(t1)
    li   t0, \tval
    sw   t0, 0x48(t1)
.endm

_start:
    # Smdbltrp boot sequence (this test owns its handler)
    csrsi MNSTATUS, 8
    csrw  mstatush, x0

    li   sp, 0x8000F000
    li   s4, WATCH
    li   s5, MISAL
    li   s9, PMP_DENY

    la   t0, trap_handler
    csrw mtvec, t0

.if CFG_PMP_NR > 0
    # Entry 0: locked NAPOT 4 KB at PMP_DENY, R=W=X=0 -> M-mode accesses fault.
    li   t0, (PMP_DENY >> 2) | 0x1FF
    csrw pmpaddr0, t0
    li   t0, 0x98                    # L | A=NAPOT
    csrw pmpcfg0, t0
.endif

    li   x31, 0x11111111             # init done

    .align 3                         # align while RVC padding is still available
    .option push
    .option norvc

#=========================================================================
# Misaligned load (cause 4) with each younger instruction
#=========================================================================
    # 0: ALU op
    CASE_PRE 0, 4
    CASE_EXP 0, f0, 4, MISAL+1
    CASE_MARK 0
    .align 3
f0: lw   t4, 1(s5)
    addi s2, s2, 1

    # 1: JAL (target just after)
    CASE_PRE 1, 4
    CASE_EXP 1, f1, 4, MISAL+1
    CASE_MARK 1
    .align 3
f1: lw   t4, 1(s5)
    jal  ra, 1f
    nop
1:
    # 2: JALR through s10 (target just after)
    CASE_PRE 2, 4
    CASE_EXP 2, f2, 4, MISAL+1
    la   s10, 1f
    CASE_MARK 2
    .align 3
f2: lw   t4, 1(s5)
    jalr ra, 0(s10)
    nop
1:
    # 3: JALR to address 0 (unmapped): its speculative fetch must not raise a
    #    second trap; Y is skipped
    CASE_PRE 3, 8
    CASE_EXP 3, f3, 4, MISAL+1
    CASE_MARK 3
    .align 3
f3: lw   t4, 1(s5)
    jalr ra, 0(zero)

    # 4: taken branch
    CASE_PRE 4, 4
    CASE_EXP 4, f4, 4, MISAL+1
    CASE_MARK 4
    .align 3
f4: lw   t4, 1(s5)
    beq  zero, zero, 1f
    addi s2, s2, 0x10                # skipped by the branch
1:
    # 5: not-taken branch
    CASE_PRE 5, 4
    CASE_EXP 5, f5, 4, MISAL+1
    CASE_MARK 5
    .align 3
f5: lw   t4, 1(s5)
    bne  zero, zero, 1f
    nop
1:
    # 6: store to the watched word
    CASE_PRE 6, 4
    CASE_EXP 6, f6, 4, MISAL+1
    li   t3, 0xBAD00006
    CASE_MARK 6
    .align 3
f6: lw   t4, 1(s5)
    sw   t3, 0(s4)

    # 7: CSR write
    CASE_PRE 7, 4
    CASE_EXP 7, f7, 4, MISAL+1
    li   t3, 0xBAD00007
    CASE_MARK 7
    .align 3
f7: lw   t4, 1(s5)
    csrw mscratch, t3

    # 8: FENCE.I
    CASE_PRE 8, 4
    CASE_EXP 8, f8, 4, MISAL+1
    CASE_MARK 8
    .align 3
f8: lw   t4, 1(s5)
    fence.i

    # 9: MRET (skipped: re-executing it would return to itself)
    CASE_PRE 9, 8
    CASE_EXP 9, f9, 4, MISAL+1
    CASE_MARK 9
    .align 3
f9: lw   t4, 1(s5)
    mret

    # 10: WFI (skipped; entering it here would hang)
    CASE_PRE 10, 8
    CASE_EXP 10, f10, 4, MISAL+1
    CASE_MARK 10
    .align 3
f10: lw  t4, 1(s5)
    wfi

    # 11: ECALL (skipped; the load fault must be the one reported)
    CASE_PRE 11, 8
    CASE_EXP 11, f11, 4, MISAL+1
    CASE_MARK 11
    .align 3
f11: lw  t4, 1(s5)
    ecall

#=========================================================================
# Misaligned store (cause 6)
#=========================================================================
    # 12: store fault + younger store
    CASE_PRE 12, 4
    CASE_EXP 12, f12, 6, MISAL+2
    li   t3, 0xBAD0000C
    CASE_MARK 12
    .align 3
f12: sw  t3, 2(s5)
    sw   t3, 0(s4)

    # 13: store fault + JAL
    CASE_PRE 13, 4
    CASE_EXP 13, f13, 6, MISAL+2
    CASE_MARK 13
    .align 3
f13: sw  t3, 2(s5)
    jal  ra, 1f
    nop
1:

#=========================================================================
# EX-stage fault without an address: write to a read-only CSR (cause 2)
#=========================================================================
    # 20: illegal CSR write + ALU
    CASE_PRE 20, 4
    CASE_EXP 20, f20, 2, 0
    li   t3, 0xBAD00014
    CASE_MARK 20
    .align 3
f20: csrw mhartid, t3
    addi s2, s2, 1

#=========================================================================
# PMP-denied load/store (causes 5/7)
#=========================================================================
.if CFG_PMP_NR > 0
    # 14: load fault + ALU
    CASE_PRE 14, 4
    CASE_EXP 14, f14, 5, PMP_DENY
    CASE_MARK 14
    .align 3
f14: lw  t4, 0(s9)
    addi s2, s2, 1

    # 15: load fault + JAL
    CASE_PRE 15, 4
    CASE_EXP 15, f15, 5, PMP_DENY
    CASE_MARK 15
    .align 3
f15: lw  t4, 0(s9)
    jal  ra, 1f
    nop
1:
    # 16: store fault + store
    CASE_PRE 16, 4
    CASE_EXP 16, f16, 7, PMP_DENY
    li   t3, 0xBAD00010
    CASE_MARK 16
    .align 3
f16: sw  t3, 0(s9)
    sw   t3, 0(s4)

    # 17: load fault + PMP CSR write (its registered refetch must not act)
    CASE_PRE 17, 4
    CASE_EXP 17, f17, 5, PMP_DENY
    li   t3, 0x00550000
    CASE_MARK 17
    .align 3
f17: lw  t4, 0(s9)
    csrw pmpaddr1, t3

    # 18: load fault + CSR write
    CASE_PRE 18, 4
    CASE_EXP 18, f18, 5, PMP_DENY
    li   t3, 0xBAD00012
    CASE_MARK 18
    .align 3
f18: lw  t4, 0(s9)
    csrw mscratch, t3
.endif

    .option pop

#=========================================================================
# Zcmp: CM.PUSH as the younger instruction (sp and the stack are watched)
#=========================================================================
.if CFG_C_EXTENSION >= 3
    li   x31, 0x33333333             # bench: pause the STD-mode instruction checker
    # 19: misaligned load + cm.push {ra}, -16
    CASE_PRE 19, 4
    CASE_EXP 19, f19, 4, MISAL+1
    li   t0, 0x77770013
    sw   t0, -4(sp)
    .align 3                         # align while RVC padding is still available
    .option push
    .option norvc
    CASE_MARK 19
    .align 3
f19: lw  t4, 1(s5)
    .half 0xB842                     # cm.push {ra}, -16
    .half 0x0001                     # c.nop (realign)
    .option pop
    lw   t0, 12(sp)                  # the pushed ra, after the handler returned
    addi sp, sp, 16
    li   t1, STRIDE*19 + SPAD
    sw   t0, 0x50(t1)                # executed push stored ra = 0xA0000013
    li   x31, 0x44444444             # bench: checker back on
.endif

.if CFG_ZICNTR_EN
    CASE_NEXP 0
    CASE_NEXP 1
    CASE_NEXP 2
    CASE_NEXP 3
    CASE_NEXP 4
    CASE_NEXP 5
    CASE_NEXP 6
    CASE_NEXP 7
    CASE_NEXP 8
    CASE_NEXP 9
    CASE_NEXP 10
    CASE_NEXP 11
    CASE_NEXP 12
    CASE_NEXP 13
    CASE_NEXP 20
.if CFG_PMP_NR > 0
    CASE_NEXP 14
    CASE_NEXP 15
    CASE_NEXP 16
    CASE_NEXP 17
    CASE_NEXP 18
.endif
.if CFG_C_EXTENSION >= 3
    CASE_NEXP 19
.endif
.endif

    li   x31, 0x22222222             # all cases done

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j end_of_test

#=========================================================================
# Expected minstret difference per case: the straight-line instruction count
# p<k>..f<k> (4-byte instructions only, see CASE_MARK)
#=========================================================================
    .align 2
nexp_tbl:
    .word (f0 - p0) / 4,   (f1 - p1) / 4,   (f2 - p2) / 4,   (f3 - p3) / 4
    .word (f4 - p4) / 4,   (f5 - p5) / 4,   (f6 - p6) / 4,   (f7 - p7) / 4
    .word (f8 - p8) / 4,   (f9 - p9) / 4,   (f10 - p10) / 4, (f11 - p11) / 4
    .word (f12 - p12) / 4, (f13 - p13) / 4
.if CFG_PMP_NR > 0
    .word (f14 - p14) / 4, (f15 - p15) / 4, (f16 - p16) / 4, (f17 - p17) / 4, (f18 - p18) / 4
.else
    .word 0, 0, 0, 0, 0
.endif
.if CFG_C_EXTENSION >= 3
    .word (f19 - p19) / 4
.else
    .word 0
.endif
    .word (f20 - p20) / 4
