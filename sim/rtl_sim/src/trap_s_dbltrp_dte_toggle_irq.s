#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_s_dbltrp_dte_toggle_irq
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: S DBLTRP DTE TOGGLE IRQ - doubled delegated interrupt
#   Requires SU_MODE_EN==1. Deterministic (no external IRQ, STIP set by M).
#
#   With DTE=1, SDT=1 and SIE=1 cannot coexist in S-mode: a trap into S sets
#   SDT and clears SIE, SRET clears SDT, and (Priv §12.1.1.5)
#     "The SIE bit can only be set to 1 by an explicit CSR write if the
#     SDT bit is being set to 0 by the same write or is already 0".
#   The only route to a delegated interrupt that is doubled is a DTE 0->1
#   toggle:
#   - Priv §3.1.18: "When menvcfg.DTE is zero, the implementation behaves
#     as though Ssdbltrp is not implemented", so SDT reads 0 and SIE is
#     writable in the S handler.
#   - The spec leaves the value of SDT after DTE goes 0->1 undefined.
#     aRVern documents it (traps_and_interrupts.md §10, Opt-out): "The SDT
#     flop keeps being set by S-mode trap entries while DTE = 0 (it is only
#     masked), so when re-enabling DTE later, clear sstatus.SDT with the
#     same or the following write, or the next delegated trap is doubled."
#   Double-trap delivery (Priv §12.1.1.5): "the hart writes registers,
#   except mcause and mtval2, with the same information that the unexpected
#   trap would have written if it was taken into M-mode. The mtval2 register
#   is then set to what would be otherwise written into the mcause register
#   by the unexpected trap. The mcause register is set to 16". aRVern writes
#   mtval2 = cause code without the interrupt bit (spec_compliance_notes.md
#   "Ssdbltrp WARL choices"), so a doubled STI gives mtval2 = 5.
#
#   Flow:
#   1. M: medeleg[2]=1, mideleg[5]=1, menvcfgh.DTE=0, mtvec VECTORED
#      (the double trap is an exception class: it must use the base).
#   2. S: illegal1 -> S handler (DTE=0): SDT reads 0; csrsi sstatus.SIE
#      reads back 1; ecall -> M (cause 9, not delegated).
#   3. M: DTE=1; mstatus must now show SDT=1 and SIE=1 (else fail code
#      0x0BADBAD6); mie.STIE=1, mip.STIP=1; mtval = marker 0x7EEDBEEF;
#      mret to S at s_pre (j s_land).
#   4. STI is delegated, pending, enabled, and the hart is in S with
#      SIE=1 -> routed to S while SDT&DTE -> double trap into M:
#      mcause=16, mtval2=5, mtval=0, mepc=&s_land, MPP=S, scause/sepc still
#      those of illegal1 (S bank untouched), via the mtvec base.
#   s_land is a self-loop so mepc does not depend on how many instructions
#   dispatch after mret. mret targets s_pre, not s_land, so mepc=&s_land
#   proves the double trap wrote mepc: marv_ctl[2] (livelock_prot_en,
#   reset 1) lets one instruction (j s_land) dispatch after mret before
#   any IRQ is taken.
#
#   Fail codes in x31: 0x0BADBADB unexpected M trap or wrong vector slot,
#   0x0BADBAD6 SDT/SIE precondition not met, 0x0BADBAD7 IRQ taken in S.
#
#   Scratchpad (base 0x80000000):
#   0x00: M trap count                     (expect 2)
#   0x04: unexpected mcause                (expect 0)
#   0x08: DTE after clear                  (expect 0)
#   0x0C: S entry scause                   (expect 2)
#   0x10: S entry sstatus & SDT            (expect 0)
#   0x14: S sstatus & SIE after csrsi      (expect 0x2)
#   0x18: M ecall mstatus & (SDT|SIE)      (expect 0x01000002)
#   0x1C: M ecall DTE after set            (expect 0x08000000)
#   0x20: dbl mcause                       (expect 0x10)
#   0x24: dbl mtval2                       (expect 5)
#   0x28: dbl mtval                        (expect 0)
#   0x2C: dbl mepc                         (== 0x30)
#   0x30: &s_land
#   0x34: dbl MPP                          (expect 1)
#   0x38: dbl scause                       (expect 2)
#   0x3C: dbl sepc                         (== 0x40)
#   0x40: &illegal1
#   0x44: S handler entries                (expect 1)
#   0x48: scause of an unexpected S entry  (expect 0)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ SPAD,       0x80000000
.equ SDT_BIT,    0x01000000
.equ SIE_BIT,    0x00000002
.equ DTE_BIT,    0x08000000
.equ STI_BIT,    0x00000020

.section .text
.global main

main:
    j _start

    .option push
    .option norvc

    #=================================================================
    # VECTORED mtvec TABLE: slot 0 = exceptions (incl. double trap),
    # every interrupt slot is a failure.
    #=================================================================
    .align 7
vec_table:
    j    m_handler
    .rept 31
    j    vec_fail
    .endr

vec_fail:
    csrr t3, mcause
    sw   t3, 0x04(s1)
    li   x31, 0x0BADBADB
vec_fail_loop:
    j    vec_fail_loop

    #=================================================================
    # M-MODE HANDLER
    #=================================================================
    .align 2
m_handler:
    lw   t4, 0x00(s1)
    addi t4, t4, 1
    sw   t4, 0x00(s1)
    csrr t3, mcause
    li   t4, 9
    beq  t3, t4, m_ecall
    li   t4, 16
    beq  t3, t4, m_dbl
    sw   t3, 0x04(s1)
    li   x31, 0x0BADBADB
m_fail_loop:
    j    m_fail_loop

m_ecall:
    li   t4, DTE_BIT
    csrs 0x31A, t4                  # menvcfgh.DTE = 1
    csrr t5, 0x31A
    and  t5, t5, t4
    sw   t5, 0x1C(s1)

    csrr t5, mstatus
    li   t4, (SDT_BIT | SIE_BIT)
    and  t5, t5, t4
    sw   t5, 0x18(s1)
    bne  t5, t4, m_precond_fail

    li   t4, STI_BIT
    csrs mie, t4                    # STIE
    csrs mip, t4                    # STIP (software-writable from M)

    # MPP is already S (the ECALL came from S). No mstatus write here: with SDT=1,
    # any explicit write of mstatus/sstatus carries SDT=1 and clears SIE (Ssdbltrp:
    # "When the SDT bit is set to 1 by an explicit CSR write, the SIE bit is cleared").
    la   t4, s_land
    sw   t4, 0x30(s1)               # expected mepc of the double trap
    la   t4, s_pre
    csrw mepc, t4                   # stale mepc differs from the expected one
    li   t4, 0x7EEDBEEF
    csrw mtval, t4                  # marker: the double trap must write mtval
    mret

m_precond_fail:
    li   x31, 0x0BADBAD6
m_precond_loop:
    j    m_precond_loop

m_dbl:
    sw   t3, 0x20(s1)
    csrr t5, 0x34B                  # mtval2
    sw   t5, 0x24(s1)
    csrr t5, mtval
    sw   t5, 0x28(s1)
    csrr t5, mepc
    sw   t5, 0x2C(s1)
    csrr t5, mstatus
    srli t5, t5, 11
    andi t5, t5, 3
    sw   t5, 0x34(s1)
    csrr t5, scause
    sw   t5, 0x38(s1)
    csrr t5, sepc
    sw   t5, 0x3C(s1)

    li   t4, STI_BIT
    csrc mip, t4                    # retire the STI source
    li   t4, 0x1800
    csrs mstatus, t4                # MPP = M
    la   t4, m_final
    csrw mepc, t4
    mret

    #=================================================================
    # S-MODE HANDLER (direct)
    #=================================================================
    .align 2
s_handler:
    lw   t4, 0x44(s1)
    addi t4, t4, 1
    sw   t4, 0x44(s1)
    li   t5, 1
    bne  t4, t5, s_unexpected

    csrr t5, scause
    sw   t5, 0x0C(s1)
    csrr t5, sstatus
    li   t4, SDT_BIT
    and  t5, t5, t4
    sw   t5, 0x10(s1)               # SDT reads 0 while DTE=0

    csrsi sstatus, SIE_BIT          # allowed: Ssdbltrp behaves as absent
    csrr t5, sstatus
    andi t5, t5, SIE_BIT
    sw   t5, 0x14(s1)

    ecall                           # cause 9 -> M, SDT flop left set

s_unexpected:
    csrr t5, scause
    sw   t5, 0x48(s1)
    li   x31, 0x0BADBAD7
s_unexpected_loop:
    j    s_unexpected_loop

    #=================================================================
    # S-MODE CODE
    #=================================================================
    .align 2
s_main:
    li   x31, 0x22222222
    la   t0, illegal1
    sw   t0, 0x40(s1)
illegal1:
    .word 0xFFFFFFFF                # delegated illegal -> S handler
    li   x31, 0x0BADBAD8            # never reached (S handler ecalls to M)
s_main_loop:
    j    s_main_loop

    .align 2
s_pre:
    j    s_land                     # dispatches before the IRQ (marv_ctl[2])
s_land:
    j    s_land                     # doubled STI is taken here

    .option pop

    #=================================================================
    # MAIN
    #=================================================================
    .align 2
_start:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1 (first)
    csrw  mstatush, x0              # mstatus.MDT = 0 (second)

    PMP_ALLOW_ALL
    li   s1, SPAD
    li   t0, 0
    li   t1, 0x4C
clr_loop:
    add  t2, s1, t0
    sw   zero, 0(t2)
    addi t0, t0, 4
    bltu t0, t1, clr_loop

    la   t0, vec_table
    ori  t0, t0, 1                  # MODE = vectored
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0

    csrw mie, zero
    csrw mip, zero
    li   t0, 0x4
    csrw medeleg, t0                # illegal instruction -> S
    li   t0, STI_BIT
    csrw mideleg, t0                # STI -> S

    li   t0, DTE_BIT
    csrc 0x31A, t0                  # menvcfgh.DTE = 0
    csrr t1, 0x31A
    and  t1, t1, t0
    sw   t1, 0x08(s1)

    li   t0, SIE_BIT
    csrc mstatus, t0                # SIE = 0 entering S

    li   x31, 0x11111111

    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0                # MPP = S
    la   t0, s_main
    csrw mepc, t0
    mret

m_final:
    lw   t0, 0x00(s1)               # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
