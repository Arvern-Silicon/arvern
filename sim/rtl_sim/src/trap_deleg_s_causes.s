#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_deleg_s_causes
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: medeleg routing of causes 0/1/3/5/7 from U and S, and from M
#
#   Priv §3.1.8: "setting a bit in medeleg or mideleg will delegate the
#   corresponding trap, when occurring in S-mode or U-mode, to the S-mode trap
#   handler." ... "When a trap is delegated to S-mode, the scause register is
#   written with the trap cause; the sepc register is written with the
#   virtual address of the instruction that took the trap; the stval register
#   is written with an exception-specific datum; the SPP field of mstatus is
#   written with the active privilege mode at the time of the trap".
#   Priv §3.1.8: "Traps never transition from a more-privileged mode to a
#   less-privileged mode."
#   traps_and_interrupts.md §2 mtval table: "0, 4, 6: The faulting
#   (mis-aligned) address"; "1, 5, 7: The faulting (access-faulting)
#   address"; "3: 0 for EBREAK/C.EBREAK".
#   traps_and_interrupts.md §6 "PMP faults and delegation": "Causes 1, 5 and
#   7 are produced by the PMP checkers and are ordinary delegatable
#   exceptions: medeleg[1], [5] and [7] route them to S-mode like any other."
#   traps_and_interrupts.md §2 cause 0: "Only reachable with C_EXTENSION = 0".
#
#   PMP (PMP_NR > 0), entries 0..2, none locked:
#     0  NAPOT 0x80004000/64 B, R only   -> U/S fetch = cause 1, store = cause 7
#     1  NAPOT 0x80004040/64 B, no perms -> U/S load  = cause 5
#     2  NAPOT whole space, RWX           -> everything else
#
#   Case slot index = org*10 + nodeleg*5 + c  (org 0 = U, 1 = S;
#   c 0 = cause 0, 1 = cause 1, 2 = cause 3, 3 = cause 5, 4 = cause 7);
#   M-origin cases (all causes delegated): slot 20 (cause 0), 22 (cause 3).
#   Slot at 0x80000100 + 64*index:
#     +0 handler id (1 = M, 2 = S)  +4 cause  +8 epc  +12 tval
#     +16 previous privilege (MPP or SPP)   +20 expected epc
#     +24 expected tval   +28 medeleg read back after the write
#     +32 trap count for that case (handler-incremented)
#   0x80000000: unexpected cause count
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSTATUS,  0x744
.equ MSTATUSH,  0x310
.equ SLOTS,     0x80000100
.equ NOX_ADDR,  0x80004000
.equ STORE_ADDR, 0x80004008
.equ NOR_ADDR,  0x80004044

.section .text
.global main

main:
    j    _start

#=========================================================================
# M handler. ECALL from U/S (8/9): return to M at s10. Anything else is a
# case trap: record into the slot at s9 and resume at s11 in the same mode.
#=========================================================================
    .align 2
m_handler:
    csrr t0, mcause
    li   t1, 8
    beq  t0, t1, m_to_m
    li   t1, 9
    beq  t0, t1, m_to_m
    bltz t0, m_unexpected
    li   t1, 1
    sw   t1, 0(s9)
    sw   t0, 4(s9)
    csrr t1, mepc
    sw   t1, 8(s9)
    csrr t1, mtval
    sw   t1, 12(s9)
    csrr t1, mstatus
    srli t1, t1, 11
    andi t1, t1, 3
    sw   t1, 16(s9)
    lw   t1, 32(s9)
    addi t1, t1, 1
    sw   t1, 32(s9)
    csrw mepc, s11
    mret
m_unexpected:
    lw   t1, 0(s1)
    addi t1, t1, 1
    sw   t1, 0(s1)
    csrw mepc, s11
    mret
m_to_m:
    li   t1, 0x1800
    csrs mstatus, t1
    csrw mepc, s10
    mret

#=========================================================================
# S handler: record, resume at s11 in the trapping mode
#=========================================================================
    .align 2
s_handler:
    csrr t0, scause
    li   t1, 2
    sw   t1, 0(s9)
    sw   t0, 4(s9)
    csrr t1, sepc
    sw   t1, 8(s9)
    csrr t1, stval
    sw   t1, 12(s9)
    csrr t1, sstatus
    srli t1, t1, 8
    andi t1, t1, 1
    sw   t1, 16(s9)
    lw   t1, 32(s9)
    addi t1, t1, 1
    sw   t1, 32(s9)
    csrw sepc, s11
    sret

#=========================================================================
# Fault routines: publish expected epc/tval at +20/+24, set the resume
# point s11, fault, return with ret.
#=========================================================================
    .align 2
f_misalign:                         # cause 0 (C_EXTENSION == 0 only)
    la   t0, 3f
    addi t0, t0, 2
    sw   t0, 24(s9)
    la   t1, 1f
    sw   t1, 20(s9)
    la   s11, 2f
1:  jalr x0, 0(t0)
2:  ret
    .align 2
3:  nop
    nop
    ret

    .align 2
f_ifetch:                           # cause 1: fetch from a PMP no-X region
    li   t0, NOX_ADDR
    sw   t0, 20(s9)
    sw   t0, 24(s9)
    la   s11, 2f
    jalr x0, 0(t0)
2:  ret

    .align 2
f_ebreak:                           # cause 3
    la   t0, 1f
    sw   t0, 20(s9)
    sw   x0, 24(s9)
    la   s11, 2f
1:  .word 0x00100073                # 32-bit ebreak
2:  ret

    .align 2
f_load:                             # cause 5: load from a PMP no-R region
    li   a5, NOR_ADDR
    sw   a5, 24(s9)
    la   t0, 1f
    sw   t0, 20(s9)
    la   s11, 2f
1:  lw   t0, 0(a5)
2:  ret

    .align 2
f_store:                            # cause 7: store to a PMP R-only region
    li   a5, STORE_ADDR
    sw   a5, 24(s9)
    la   t0, 1f
    sw   t0, 20(s9)
    la   s11, 2f
1:  sw   t0, 0(a5)
2:  ret

#=========================================================================
# Lower-mode runner: entered by MRET with a2 = fault routine
#=========================================================================
    .align 2
lower_entry:
    jalr ra, 0(a2)
    ecall                           # back to M at s10

# a0 = 0 (U) / 1 (S)
    .align 2
enter_lower:
    li   t0, (1 << 24)
    csrc mstatus, t0                # sstatus.SDT = 0 (horizontal S traps)
    li   t0, 0x1800
    csrc mstatus, t0
    slli t0, a0, 11
    csrs mstatus, t0
    la   t0, lower_entry
    csrw mepc, t0
    mret

#-------------------------------------------------------------------------
# One case from U or S. org: 0 U / 1 S; nodeleg: 0 delegated / 1 not;
# c: slot column; bit: cause code; fn: fault routine
#-------------------------------------------------------------------------
.macro LCASE org, nodeleg, c, bit, fn
    li   s9, SLOTS + ((\org*10 + \nodeleg*5 + \c) * 64)
.if \nodeleg == 0
    li   t0, (1 << \bit)
.else
    li   t0, 0
.endif
    csrw medeleg, t0
    csrr t0, medeleg
    sw   t0, 28(s9)
    la   a2, \fn
    li   a0, \org
    la   s10, 9f
    j    enter_lower
9:
.endm

.macro LCASES org, nodeleg
.if CFG_C_EXTENSION == 0
    LCASE \org, \nodeleg, 0, 0, f_misalign
.endif
.if CFG_PMP_NR > 0
    LCASE \org, \nodeleg, 1, 1, f_ifetch
.endif
    LCASE \org, \nodeleg, 2, 3, f_ebreak
.if CFG_PMP_NR > 0
    LCASE \org, \nodeleg, 3, 5, f_load
    LCASE \org, \nodeleg, 4, 7, f_store
.endif
.endm

#=========================================================================
_start:
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE = 1 first
    csrw MSTATUSH, x0               # then MDT = 0

    li   sp, 0x80010000
    li   s1, 0x80000000
    mv   t0, s1
    li   t1, 0x80000700
1:  sw   x0, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b

    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0
    csrw mideleg, x0

.if CFG_PMP_NR > 0
    li   t0, (NOX_ADDR >> 2) | 0x7
    csrw pmpaddr0, t0
    li   t0, ((NOX_ADDR + 0x40) >> 2) | 0x7
    csrw pmpaddr1, t0
    li   t0, -1
    csrw pmpaddr2, t0
    li   t0, 0x001F1819             # e2 NAPOT RWX | e1 NAPOT --- | e0 NAPOT R--
    csrw pmpcfg0, t0
.endif

    li   x31, 0x11111111            # sync: init done

    LCASES 0, 0                     # U, delegated     -> S
    LCASES 0, 1                     # U, not delegated -> M
    li   x31, 0x22222222
    LCASES 1, 0                     # S, delegated     -> S (horizontal)
    LCASES 1, 1                     # S, not delegated -> M
    li   x31, 0x33333333

    # M-origin: every cause delegated, traps stay in M
.if CFG_C_EXTENSION == 0
    li   t0, (1 << 0) | (1 << 3)
.else
    li   t0, (1 << 3)
.endif
.if CFG_PMP_NR > 0
    ori  t0, t0, (1 << 1) | (1 << 5) | (1 << 7)
.endif
    csrw medeleg, t0
.if CFG_C_EXTENSION == 0
    li   s9, SLOTS + 20*64
    csrr t0, medeleg
    sw   t0, 28(s9)
    call f_misalign
.endif
    li   s9, SLOTS + 22*64
    csrr t0, medeleg
    sw   t0, 28(s9)
    call f_ebreak
    csrw medeleg, x0

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
