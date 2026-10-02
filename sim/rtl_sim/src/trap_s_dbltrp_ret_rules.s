#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_s_dbltrp_ret_rules
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP S DBLTRP RET RULES (Ssdbltrp xRET / SIE-SDT interlock)
#   Requires SU_MODE_EN==1. Deterministic (sync exceptions only, no IRQs).
#
#   Directed checks of the Ssdbltrp sstatus.SDT (bit 24) rules:
#   Priv 3.1.6.2: "The MRET and SRET instructions, when executed in M-mode,
#     set the MDT bit to 0. If the new privilege mode is U, VS, or VU, then
#     sstatus.SDT is also set to 0." / "The MNRET instruction ... sets the
#     MDT bit to 0 if the new privilege mode is not M. If it is U, VS, or
#     VU, then sstatus.SDT is also set to 0."
#   Priv 12.1.1.5: "When the SDT bit is set to 1 by an explicit CSR write,
#     the SIE bit is cleared to 0. This clearing occurs regardless of the
#     value written, if any, to the SIE bit by the same write. The SIE bit
#     can only be set to 1 by an explicit CSR write if the SDT bit is being
#     set to 0 by the same write or is already 0." / "An SRET instruction
#     sets the SDT bit to 0." (unconditionally)
#
#   (a) M, SDT=1, MRET MPP=S            -> SDT still 1 (read in S)
#   (b) M, SDT=1, MRET MPP=U            -> SDT 0 (U ecalls to M, read there)
#   (c) delegated ecall from S enters the S handler (HW sets SDT=1),
#       SRET back to S                  -> SDT 0
#   (d) csrs sstatus, SDT|SIE           -> SIE 0, SDT 1
#   (e) csrs SIE / csrw with SIE=1 while SDT stays 1 -> SIE still 0
#   (f) single csrw clearing SDT and setting SIE     -> SIE 1
#   (g) SDT already 0, csrs SIE         -> SIE 1
#   (d') same as (d) through the mstatus alias (same physical bits)
#   (h) M, SDT=1, MNRET MNPP=S          -> SDT still 1 (read in S)
#       M, SDT=1, MNRET MNPP=U          -> SDT 0 (U ecalls to M, read there)
#
#   Flow control: S/U code returns to M through an UNDELEGATED trap (ecall
#   from U = cause 8, illegal instruction = cause 2); the M handler is a
#   trampoline that resumes at a0 with mstatus.MPP = a1. Only ecall-from-S
#   (cause 9) is delegated, and only from (c) onward. A trap into M never
#   touches SDT, so reading sstatus in the M handler right after a U-mode
#   ecall observes the post-xRET value. The M handler flags mcause=16
#   (double trap) as a hard failure.
#
#   Scratchpad layout (base 0x80000000):
#   0x00: SDT in M after csrs mstatus      (expect 0x01000000: sanity)
#   0x04: (a) SDT in S after MRET MPP=S    (expect 0x01000000)
#   0x08: (a) SDT in M after S->M ecall + MRET MPP=M (expect 0x01000000)
#   0x0C: (b) SDT in M after MRET MPP=U -> U ecall  (expect 0)
#   0x10: (c) SDT in S handler on delegated ecall entry (expect 0x01000000)
#   0x14: (c) SDT in S after SRET          (expect 0)
#   0x18: (c) s_trap_count                 (expect 1)
#   0x1C: (d) sstatus & (SDT|SIE) after csrs both   (expect 0x01000000)
#   0x20: (e) after csrs SIE with SDT=1             (expect 0x01000000)
#   0x24: (e) after csrw with SIE=1, SDT=1          (expect 0x01000000)
#   0x28: (f) csrw clearing SDT + setting SIE       (expect 0x00000002)
#   0x2C: (g) SDT=0, csrc SIE then csrs SIE         (expect 0x00000002)
#   0x30: (d') mstatus & (SDT|SIE) after csrs mstatus both (expect 0x01000000)
#   0x34: (h) SDT in S after MNRET MNPP=S  (expect 0x01000000)
#   0x38: (h) SDT in M after MNRET MNPP=U -> U ecall (expect 0)
#   0x3C: m_trap_count                     (expect 5)
#   0x40: m last mcause                    (expect 8: final U ecall)
#   0x44: final flag                       (expect 0xAA)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSTATUS, 0x744
.equ MNEPC,    0x741
.equ SDT,      0x01000000
.equ SIE,      0x00000002
.equ SDT_SIE,  0x01000002

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE HANDLER (direct mode): trampoline.
    #   mcause == 16 -> double trap -> FAIL.
    #   otherwise    -> resume at a0 with mstatus.MPP = a1.
    #=================================================================
    .align 2
    .option push
    .option norvc

m_handler:
    csrw mstatush, x0          # clear MDT (Smdbltrp) on entry

    csrr t0, mcause
    li   t1, 16
    beq  t0, t1, m_dbltrap_fail

    lw   t2, 0x3C(s1)
    addi t2, t2, 1
    sw   t2, 0x3C(s1)          # m_trap_count
    sw   t0, 0x40(s1)          # last mcause

    csrw mepc, a0
    li   t0, 0x1800
    csrc mstatus, t0
    slli t1, a1, 11
    csrs mstatus, t1           # MPP = a1
    mret

m_dbltrap_fail:
    sw   t0, 0x40(s1)
    li   x31, 0x0BADBADB       # FAIL: unexpected double trap
m_fail_loop:
    j    m_fail_loop


    #=================================================================
    # S-MODE HANDLER (direct mode): only the (c) delegated ecall lands
    # here. HW must have set SDT on entry; SRET must clear it.
    #=================================================================
    .align 2

s_handler:
    lw   t2, 0x18(s1)
    addi t2, t2, 1
    sw   t2, 0x18(s1)          # s_trap_count
    li   t0, 1
    bne  t2, t0, s_unexpected

    csrr t0, sstatus
    li   t1, SDT
    and  t0, t0, t1
    sw   t0, 0x10(s1)          # expect 0x01000000 (set by HW on entry)

    csrr t1, sepc
    addi t1, t1, 4             # past the 4-byte ecall
    csrw sepc, t1
    sret                       # SPP=S -> back to s_c; SDT -> 0

s_unexpected:
    li   x31, 0x0BADBADB       # FAIL: unexpected S handler entry
s_unexpected_loop:
    j    s_unexpected_loop

    .option pop


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
    .align 4
_start:
    li   sp, 0x80010000
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)
    sw   t0, 0x3C(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)

    # Install M and S handlers (direct mode)
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0

    # Smrnmi/Smdbltrp boot order: arm NMIE first, then clear MDT
    csrsi MNSTATUS, 8
    csrw  mstatush, x0

    #-------------------------------------------------------------
    # (a) SDT=1 in M, MRET with MPP=S -> SDT must survive
    #-------------------------------------------------------------
    li   t1, SDT
    csrs mstatus, t1           # SDT through the mstatus alias
    csrr t0, mstatus
    and  t0, t0, t1
    sw   t0, 0x00(s1)          # expect 0x01000000 (sanity)

    li   x31, 0x11111111

    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = S
    la   t0, s_a
    csrw mepc, t0
    mret

    .align 2
s_a:                           # S-mode
    csrr t0, sstatus
    li   t1, SDT
    and  t0, t0, t1
    sw   t0, 0x04(s1)          # expect 0x01000000 (MRET to S keeps SDT)

    la   a0, m_b
    li   a1, 3
    .option push
    .option norvc
    ecall                      # cause 9, NOT delegated yet -> M trampoline
    .option pop

    .align 2
m_b:                           # M-mode (MRET with MPP=M kept SDT)
    csrr t0, mstatus
    li   t1, SDT
    and  t0, t0, t1
    sw   t0, 0x08(s1)          # expect 0x01000000

    #-------------------------------------------------------------
    # (b) SDT=1 in M, MRET with MPP=U -> SDT must be cleared
    #-------------------------------------------------------------
    csrs mstatus, t1           # SDT=1 (already, keep explicit)
    li   t0, 0x1800
    csrc mstatus, t0           # MPP = U
    la   t0, u_b
    csrw mepc, t0
    mret

    .align 2
u_b:                           # U-mode: cannot read sstatus, go to M
    la   a0, m_b2
    li   a1, 3
    .option push
    .option norvc
    ecall                      # cause 8 -> M trampoline
    .option pop

    .align 2
m_b2:
    csrr t0, mstatus
    li   t1, SDT
    and  t0, t0, t1
    sw   t0, 0x0C(s1)          # expect 0 (MRET to U cleared SDT)
    lw   t0, 0x0C(s1)          # drain

    li   x31, 0x22222222

    #-------------------------------------------------------------
    # (c) delegated ecall from S enters the S handler with SDT=0
    #     (HW sets it), SRET back to S clears it unconditionally
    #-------------------------------------------------------------
    li   t0, 0x200
    csrs medeleg, t0           # delegate ecall-from-S (cause 9)

    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = S
    la   t0, s_c
    csrw mepc, t0
    mret                       # SDT already 0 (cleared in (b))

    .align 2
s_c:                           # S-mode
    .option push
    .option norvc
    ecall                      # cause 9, delegated -> S handler
    .option pop

    # S handler advanced sepc past the ecall and SRETed back here
    csrr t0, sstatus
    li   t1, SDT
    and  t0, t0, t1
    sw   t0, 0x14(s1)          # expect 0 (SRET cleared SDT)

    la   a0, m_d
    li   a1, 3
    .word 0xFFFFFFFF           # illegal (cause 2, undelegated) -> M

    .align 2
m_d:
    li   x31, 0x33333333

    #-------------------------------------------------------------
    # (d) explicit write setting SDT=1 and SIE=1 together: SIE cleared
    #-------------------------------------------------------------
    li   t1, SDT_SIE
    csrc sstatus, t1           # start from SDT=0, SIE=0
    csrs sstatus, t1
    csrr t0, sstatus
    and  t0, t0, t1
    sw   t0, 0x1C(s1)          # expect 0x01000000

    #-------------------------------------------------------------
    # (e) SIE=1 written while SDT stays 1: SIE remains 0
    #-------------------------------------------------------------
    li   t2, SIE
    csrs sstatus, t2
    csrr t0, sstatus
    and  t0, t0, t1
    sw   t0, 0x20(s1)          # expect 0x01000000

    csrr t0, sstatus
    ori  t0, t0, SIE
    csrw sstatus, t0           # csrw with SDT=1 and SIE=1
    csrr t0, sstatus
    and  t0, t0, t1
    sw   t0, 0x24(s1)          # expect 0x01000000

    #-------------------------------------------------------------
    # (f) single write clearing SDT and setting SIE: SIE=1
    #-------------------------------------------------------------
    csrr t0, sstatus
    li   t2, ~SDT
    and  t0, t0, t2
    ori  t0, t0, SIE
    csrw sstatus, t0
    csrr t0, sstatus
    and  t0, t0, t1
    sw   t0, 0x28(s1)          # expect 0x00000002

    #-------------------------------------------------------------
    # (g) SDT already 0: csrs SIE -> SIE=1
    #-------------------------------------------------------------
    li   t2, SIE
    csrc sstatus, t2           # SIE=0, SDT still 0
    csrs sstatus, t2
    csrr t0, sstatus
    and  t0, t0, t1
    sw   t0, 0x2C(s1)          # expect 0x00000002

    #-------------------------------------------------------------
    # (d') same interlock through the mstatus alias
    #-------------------------------------------------------------
    csrc mstatus, t1           # SDT=0, SIE=0
    csrs mstatus, t1           # SDT=1 and SIE=1 in one write
    csrr t0, mstatus
    and  t0, t0, t1
    sw   t0, 0x30(s1)          # expect 0x01000000
    lw   t0, 0x30(s1)          # drain

    li   t2, SIE
    csrc sstatus, t2           # leave SIE=0 for the rest

    li   x31, 0x44444444

    #-------------------------------------------------------------
    # (h) MNRET with MNPP=S -> SDT survives
    #-------------------------------------------------------------
    li   t1, SDT
    csrs sstatus, t1           # SDT=1
    li   t0, 0x1800
    csrc MNSTATUS, t0
    li   t0, 0x0800
    csrs MNSTATUS, t0          # MNPP = S
    csrsi MNSTATUS, 8          # NMIE = 1
    la   t0, s_h
    csrw MNEPC, t0
    .word 0x70200073           # mnret -> s_h in S-mode

    .align 2
s_h:                           # S-mode
    csrr t0, sstatus
    li   t1, SDT
    and  t0, t0, t1
    sw   t0, 0x34(s1)          # expect 0x01000000 (MNRET to S keeps SDT)

    la   a0, m_h2
    li   a1, 3
    .word 0xFFFFFFFF           # illegal (cause 2, undelegated) -> M

    .align 2
m_h2:
    #-------------------------------------------------------------
    # (h) MNRET with MNPP=U -> SDT cleared
    #-------------------------------------------------------------
    li   t1, SDT
    csrs sstatus, t1           # SDT=1
    li   t0, 0x1800
    csrc MNSTATUS, t0          # MNPP = U
    la   t0, u_h
    csrw MNEPC, t0
    .word 0x70200073           # mnret -> u_h in U-mode

    .align 2
u_h:                           # U-mode: cannot read sstatus, go to M
    la   a0, m_h3
    li   a1, 3
    .option push
    .option norvc
    ecall                      # cause 8 -> M trampoline
    .option pop

    .align 2
m_h3:
    csrr t0, mstatus
    li   t1, SDT
    and  t0, t0, t1
    sw   t0, 0x38(s1)          # expect 0 (MNRET to U cleared SDT)

    li   t0, 0xAA
    sw   t0, 0x44(s1)
    lw   t0, 0x44(s1)          # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
