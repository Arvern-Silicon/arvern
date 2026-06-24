#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_mcounteren
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM MCOUNTEREN GATING
#   mcounteren[10:3] WARL and HPM counter access gating via mcounteren[3] and
#   scounteren[3] (counter3 bit).
#
#   This core implements S-mode (misa.S=1) and U-mode (misa.U=1). Per the
#   RISC-V Privileged spec (§3.1.20 mcounteren / §3.1.21 scounteren):
#   U-mode hpmcounter3 read permitted iff mcounteren[3]=1 AND scounteren[3]=1.
#   S-mode hpmcounter3 read permitted iff mcounteren[3]=1 (scounteren
#   does NOT gate S-mode itself).
#   M-mode is always permitted.
#
#   - Phase 0 : mcounteren WARL — write 0xFFFFFFFF, verify bits[31:11]=0
#   - Phase 1 : hpmcounter3
#   1a DENY-A  U-mode mcen=0,scen=1 → mcause=2
#   1b DENY-B  U-mode mcen=1,scen=0 → mcause=2  (new spec rule)
#   1c ALLOW   U-mode mcen=1,scen=1 → reads frozen value (==M-mode)
#   - Phase 2 : hpmcounterh3
#   2a DENY-A  U-mode mcen=0,scen=1 → mcause=2
#   2b DENY-B  U-mode mcen=1,scen=0 → mcause=2  (new spec rule)
#   2c ALLOW   U-mode mcen=1,scen=1 → reads 0xCAFEBABE (==M-mode)
#   - Phase S : S-mode mcen=1,scen=0 reading hpmcounter3/h3 is ALLOWED
#   (locks in scounteren-does-not-gate-S asymmetry)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTEREN,    0x306
.equ SCOUNTEREN,    0x106
.equ MCOUNTINHIBIT, 0x320
.equ HPMCOUNTER3,   0xC03
.equ HPMCOUNTERH3,  0xC83

# enable/inhibit bit for counter3 (bit 3)
.equ HPM3_BIT,      0x8


main:
    j    _start


    #-------------------------------------------------------------------
    # M-MODE TRAP HANDLER
    #
    # Counts illegal-instruction exceptions (mcause=2) only.
    # For all synchronous exceptions: sets MPP=11 (return to M-mode)
    # and advances MEPC by 4.  Handles the U-mode csrr trap (mcause=2),
    # the U-mode ECALL escape (mcause=8) and the S-mode ECALL escape
    # (mcause=9).  mideleg=0 so every trap — including from S-mode —
    # is taken here in M-mode.
    # For interrupts: returns to the interrupted mode unchanged
    # (no IRQs expected in this test, but handled gracefully).
    #
    # Spills only t0..t4.  s1 (scratch base) and s2 (the per-sub-phase
    # "before" trap-count snapshot) are callee-saved and preserved.
    #-------------------------------------------------------------------
    .align 2
m_trap_handler:
    addi sp, sp, -20
    sw   t0, 16(sp)
    sw   t1, 12(sp)
    sw   t2,  8(sp)
    sw   t3,  4(sp)
    sw   t4,  0(sp)

    csrr t0, mcause
    csrr t1, mepc

    # Interrupt (bit 31 set): return to interrupted mode unchanged
    bltz t0, handler_done

    # Synchronous exception: always return to M-mode
    li   t2, 0x1800
    csrs mstatus, t2           # MPP = 11 (M-mode)

    # Illegal instruction (mcause = 2): increment counter, save cause
    li   t2, 2
    bne  t0, t2, handler_advance_mepc

    lw   t3, 0x00(s1)          # trap_count
    addi t3, t3, 1
    sw   t3, 0x00(s1)
    sw   t0, 0x04(s1)          # last_mcause

handler_advance_mepc:
    addi t1, t1, 4             # advance past faulting instruction
    csrw mepc, t1

handler_done:
    lw   t4,  0(sp)
    lw   t3,  4(sp)
    lw   t2,  8(sp)
    lw   t1, 12(sp)
    lw   t0, 16(sp)
    addi sp, sp, 20
    mret


    #-------------------------------------------------------------------
    # U-MODE / S-MODE CODE FRAGMENTS
    #
    # Each "deny" block: single csrr that traps (mcause=2); the next
    # instruction is a jump back into M-mode _start flow (the handler
    # advances MEPC to that jump, then mrets in M-mode).
    #
    # Each "allow" block: csrr succeeds → store U-mode value → snapshot
    # the trap-count DELTA (must be 0, computed in U-mode BEFORE the
    # M-mode mhpm read) → AHB fence → ecall → jump back to M-mode.
    #
    # On the wrongly-allowed DENY-B (buggy mcounteren-only RTL) the
    # csrr does NOT trap; control falls into the j ...return; the
    # return-label sequence records DELTA=0 (canary fails) before the
    # next sub-phase's M-CSR setup traps in U-mode (cascade noise).
    #-------------------------------------------------------------------

    # ---- Phase 1: hpmcounter3 ----
p1_hpm3_denyA_umode:            # mcen=0, scen=1
    csrr t0, HPMCOUNTER3
    j    p1_hpm3_denyA_return
p1_hpm3_denyB_umode:            # mcen=1, scen=0
    csrr t0, HPMCOUNTER3
    j    p1_hpm3_denyB_return
p1_hpm3_allow_umode:            # mcen=1, scen=1
    csrr t0, HPMCOUNTER3
    sw   t0, 0x28(s1)          # p1_hpm3_al_u (U-mode value)
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x24(s1)          # p1_hpm3_al_delta (expect 0)
    lw   t3, 0x24(s1)          # AHB fence
    ecall                      # → M-mode (mcause=8, not counted)
    j    p1_hpm3_allow_return

    # ---- Phase 2: hpmcounterh3 ----
p2_hpm3h_denyA_umode:
    csrr t0, HPMCOUNTERH3
    j    p2_hpm3h_denyA_return
p2_hpm3h_denyB_umode:
    csrr t0, HPMCOUNTERH3
    j    p2_hpm3h_denyB_return
p2_hpm3h_allow_umode:
    csrr t0, HPMCOUNTERH3
    sw   t0, 0x44(s1)          # p2_hpm3h_al_u (U-mode value)
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x40(s1)          # p2_hpm3h_al_delta (expect 0)
    lw   t3, 0x40(s1)          # AHB fence
    ecall
    j    p2_hpm3h_allow_return

    # ---- Phase S: S-mode ALLOW (mcen=1, scen=0) ----
    # scounteren=0 must NOT gate S-mode; both reads succeed and add
    # NO illegal trap (pS_delta must be 0).
pS_smode_code:
    csrr t0, HPMCOUNTER3
    sw   t0, 0x50(s1)          # pS_hpm3_val
    csrr t0, HPMCOUNTERH3
    sw   t0, 0x54(s1)          # pS_hpm3h_val
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x4C(s1)          # pS_delta (expect 0)
    lw   t3, 0x4C(s1)          # AHB fence
    ecall                      # → M-mode (mcause=9, ECALL from S-mode)
    j    pS_smode_return


    #===================================================================
    # MAIN TEST CODE
    #===================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base
    li   s2, 0                 # "before" trap-count snapshot register
    # DO NOT call _random_irq_init (no_random_irq test)

    # Zero scratchpad (0x00 - 0x54 inclusive => stop at 0x58).
    # Covers every snapshot/value/mcause slot so a stale value from a
    # prior phase can never make a later phase false-pass.
    li   t0, 0
    li   t1, 0x00
zero_loop:
    add  t2, s1, t1
    sw   t0, 0(t2)
    addi t1, t1, 4
    li   t3, 0x58
    bne  t1, t3, zero_loop

    # Pre-load a known non-zero value into mhpmcounterh3 so the
    # hpmcounterh3 shadow comparison (phase 2c) is meaningful.
    li   t0, 0xCAFEBABE
    csrw 0xB83, t0              # mhpmcounterh3 = 0xCAFEBABE

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Start with both enables fully clear
    li   t0, 0x0
    csrw SCOUNTEREN, t0


    #===================================================================
    # PHASE 0: mcounteren WARL — write 0xFFFFFFFF, verify bits[31:11]=0
    # (M-mode access, no gating involved.)
    #===================================================================

    li   t0, -1
    csrw MCOUNTEREN, t0        # write all ones
    csrr t0, MCOUNTEREN        # read back
    sw   t0, 0x10(s1)          # p0_mcounteren_warl
    lw   t3, 0x10(s1)          # AHB fence

    # Clear mcounteren for clean state entering Phase 1
    li   t0, -1
    csrc MCOUNTEREN, t0

    li   x31, 0x11111111       # Sync: Phase 0 done


    #===================================================================
    # PHASE 1: hpmcounter3 (mcounteren[3] / scounteren[3])
    #===================================================================

    #--- 1a: hpmcounter3 DENY-A  (mcen=0, scen=1) ---
    li   t0, HPM3_BIT
    csrc MCOUNTEREN, t0        # bit 3 = 0
    csrs SCOUNTEREN, t0        # scen[3] = 1 (prove mcen gates alone)
    la   t0, p1_hpm3_denyA_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0           # MPP = 00 (U-mode)
    lw   s2, 0x00(s1)          # "before": LAST insn before mret
    mret
p1_hpm3_denyA_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x14(s1)          # p1_hpm3_dA_delta (expect 1)
    lw   t0, 0x04(s1)
    sw   t0, 0x18(s1)          # p1_hpm3_dA_mc (expect 2)

    #--- 1b: hpmcounter3 DENY-B  (mcen=1, scen=0) ---  canary
    li   t0, HPM3_BIT
    csrs MCOUNTEREN, t0        # bit 3 = 1
    csrc SCOUNTEREN, t0        # scen[3] = 0
    la   t0, p1_hpm3_denyB_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p1_hpm3_denyB_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x1C(s1)          # p1_hpm3_dB_delta (expect 1; 0 on buggy RTL)
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)          # p1_hpm3_dB_mc (expect 2; stale 2 on buggy)

    #--- 1c: hpmcounter3 ALLOW  (mcen=1, scen=1) ---
    # Freeze counter3 so U-mode and M-mode reads see the same value.
    li   t0, HPM3_BIT
    csrs MCOUNTEREN, t0        # bit 3 = 1
    csrs SCOUNTEREN, t0        # scen[3] = 1
    li   t0, HPM3_BIT
    csrrs x0, MCOUNTINHIBIT, t0  # freeze counter3 before U-mode access
    la   t0, p1_hpm3_allow_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0           # MPP = 00 (U-mode)
    lw   s2, 0x00(s1)          # "before"
    mret
p1_hpm3_allow_return:
    # p1_hpm3_al_u + p1_hpm3_al_delta already stored by U-mode code
    csrr t0, 0xB03             # mhpmcounter3 (inhibit still active)
    sw   t0, 0x2C(s1)          # p1_hpm3_al_m (M-mode value)
    li   t0, HPM3_BIT
    csrrc x0, MCOUNTINHIBIT, t0  # clear inhibit

    lw   t3, 0x2C(s1)          # AHB fence
    li   x31, 0x22222222       # Sync: Phase 1 done


    #===================================================================
    # PHASE 2: hpmcounterh3 (mcounteren[3] / scounteren[3])
    #===================================================================

    #--- 2a: hpmcounterh3 DENY-A  (mcen=0, scen=1) ---
    li   t0, HPM3_BIT
    csrc MCOUNTEREN, t0        # bit 3 = 0
    csrs SCOUNTEREN, t0        # scen[3] = 1
    la   t0, p2_hpm3h_denyA_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p2_hpm3h_denyA_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x30(s1)          # p2_hpm3h_dA_delta (expect 1)
    lw   t0, 0x04(s1)
    sw   t0, 0x34(s1)          # p2_hpm3h_dA_mc (expect 2)

    #--- 2b: hpmcounterh3 DENY-B  (mcen=1, scen=0) ---  canary
    li   t0, HPM3_BIT
    csrs MCOUNTEREN, t0        # bit 3 = 1
    csrc SCOUNTEREN, t0        # scen[3] = 0
    la   t0, p2_hpm3h_denyB_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p2_hpm3h_denyB_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x38(s1)          # p2_hpm3h_dB_delta (expect 1; 0 on buggy RTL)
    lw   t0, 0x04(s1)
    sw   t0, 0x3C(s1)          # p2_hpm3h_dB_mc (expect 2; stale 2 on buggy)

    #--- 2c: hpmcounterh3 ALLOW  (mcen=1, scen=1) ---
    # Freeze counter3 so U-mode and M-mode high-word reads agree
    # (both 0xCAFEBABE preset).
    li   t0, HPM3_BIT
    csrs MCOUNTEREN, t0        # bit 3 = 1
    csrs SCOUNTEREN, t0        # scen[3] = 1
    li   t0, HPM3_BIT
    csrrs x0, MCOUNTINHIBIT, t0  # freeze counter3 before U-mode access
    la   t0, p2_hpm3h_allow_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0           # MPP = 00 (U-mode)
    lw   s2, 0x00(s1)          # "before"
    mret
p2_hpm3h_allow_return:
    # p2_hpm3h_al_u + p2_hpm3h_al_delta already stored by U-mode code
    csrr t0, 0xB83             # mhpmcounterh3 (inhibit still active)
    sw   t0, 0x48(s1)          # p2_hpm3h_al_m (M-mode value)
    li   t0, HPM3_BIT
    csrrc x0, MCOUNTINHIBIT, t0  # clear inhibit

    lw   t3, 0x48(s1)          # AHB fence
    li   x31, 0x33333333       # Sync: Phase 2 done


    #===================================================================
    # PHASE S: S-mode read with mcounteren[3]=1, scounteren[3]=0.
    # scounteren must NOT gate S-mode → both hpmcounter3 and
    # hpmcounterh3 reads succeed and add NO illegal trap (pS_delta=0).
    # (Same config denies U-mode — Phase 1b/2b DENY-B.)
    #===================================================================

    li   t0, HPM3_BIT
    csrs MCOUNTEREN, t0        # bit 3 = 1 in mcounteren
    csrc SCOUNTEREN, t0        # bit 3 = 0 in scounteren (must not gate S)

    la   t0, pS_smode_code
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = 01 (S-mode)
    li   t0, 0x80
    csrc mstatus, t0           # Clear MPIE (keep MIE=0 after mret)
    lw   s2, 0x00(s1)          # "before"
    mret                       # → S-mode at pS_smode_code
pS_smode_return:
    # pS_hpm3_val, pS_hpm3h_val, pS_delta already stored by S-mode code

    lw   t3, 0x4C(s1)          # AHB fence
    li   x31, 0x44444444       # Sync: Phase S done

    # Restore mcounteren to 0x7 (CY+TM+IR) for clean exit
    li   t0, 0x7
    csrw MCOUNTEREN, t0

    li   x31, 0xdeadbeef       # Sync: all done


end_of_test:
    j    end_of_test
