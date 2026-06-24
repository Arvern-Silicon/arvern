#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_mcounteren
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZICNTR MCOUNTEREN GATING
#   mcounteren + scounteren behavioral gating of counter shadow CSRs.
#
#   This core implements S-mode (misa.S=1) and U-mode (misa.U=1). Per the
#   RISC-V Privileged spec (§3.1.20 mcounteren / §3.1.21 scounteren):
#
#   U-mode read of a counter is permitted ONLY IF mcounteren[i]=1
#   AND scounteren[i]=1.
#   S-mode read of a counter is permitted ONLY IF mcounteren[i]=1
#   (scounteren does NOT gate S-mode itself).
#   M-mode is always permitted.
#
#   Bit layout (identical in mcounteren 0x306 and scounteren 0x106):
#   bit 0 = CY (cycle/cycleh)  bit 1 = TM (time/timeh)
#   bit 2 = IR (instret/instreth).  The high (...h) variant uses the same
#   enable bit as its low counterpart.
#
#   Per counter CSR three U-mode sub-phases plus shared S-mode/Phase-4 cases:
#   DENY-A : U-mode  mcounteren[i]=0, scounteren[i]=1  -> mcause=2
#   (proves mcounteren gates independently of scounteren)
#   DENY-B : U-mode  mcounteren[i]=1, scounteren[i]=0  -> mcause=2
#   (the spec rule that was previously implemented wrong)
#   ALLOW  : U-mode  mcounteren[i]=1, scounteren[i]=1  -> read succeeds
#
#   Phase S : S-mode  mcounteren[0]=1, scounteren[0]=0 reading cycle/cycleh
#   is ALLOWED (locks in the scounteren-doesn't-gate-S asymmetry).
#   Phase 4 : M-mode write to a read-only shadow CSR -> mcause=2.
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTEREN, 0x306
.equ SCOUNTEREN, 0x106
.equ CYCLE,      0xC00
.equ CYCLEH,     0xC80
.equ TIME,       0xC01
.equ TIMEH,      0xC81
.equ INSTRET,    0xC02
.equ INSTRETH,   0xC82

main:
    j    _start


    #-------------------------------------------------------------------
    # M-MODE TRAP HANDLER
    #
    # Counts illegal-instruction exceptions (mcause=2) only.
    # For all synchronous exceptions: sets MPP=11 (return to M-mode)
    # and advances MEPC by 4.  This handles both the U-mode csrr trap
    # (mcause=2) and the ECALL escape from U-mode/S-mode allow blocks
    # (mcause=8 / mcause=9, not counted).  mideleg=0 so every trap —
    # including from S-mode — comes here.
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
    # U-MODE CODE FRAGMENTS
    #
    # Each "deny" block: single csrr that traps (mcause=2); the next
    # instruction is a jump back into M-mode _start flow (the handler
    # advances MEPC to that jump, then mrets in M-mode).
    #
    # Each "allow" block: csrr succeeds → store value → snapshot the
    # trap-count DELTA (must be 0) → AHB fence → ecall (returns to
    # M-mode via handler) → jump back to M-mode.
    #
    # On the wrongly-allowed DENY-B (buggy mcounteren-only RTL) the
    # csrr does NOT trap; control falls into the j ...return; the
    # return-label sequence records DELTA=0 (canary fails) before the
    # next sub-phase's M-CSR setup traps in U-mode (cascade noise).
    #-------------------------------------------------------------------

    # ---- Phase 1: cycle ----
p1_cycle_denyA_umode:           # mcen=0, scen=1
    csrr t0, CYCLE
    j    p1_cycle_denyA_return
p1_cycle_denyB_umode:           # mcen=1, scen=0
    csrr t0, CYCLE
    j    p1_cycle_denyB_return
p1_cycle_allow_umode:           # mcen=1, scen=1
    csrr t0, CYCLE
    sw   t0, 0x1C(s1)          # p1_cyc_al_val
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x18(s1)          # p1_cyc_al_delta (expect 0)
    lw   t3, 0x18(s1)          # AHB fence
    ecall
    j    p1_cycle_allow_return

    # ---- Phase 1: cycleh ----
p1_cycleh_denyA_umode:
    csrr t0, CYCLEH
    j    p1_cycleh_denyA_return
p1_cycleh_denyB_umode:
    csrr t0, CYCLEH
    j    p1_cycleh_denyB_return
p1_cycleh_allow_umode:
    csrr t0, CYCLEH
    sw   t0, 0x34(s1)          # p1_cyh_al_val
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x30(s1)          # p1_cyh_al_delta (expect 0)
    lw   t3, 0x30(s1)          # AHB fence
    ecall
    j    p1_cycleh_allow_return

    # ---- Phase 2: instret ----
p2_instret_denyA_umode:
    csrr t0, INSTRET
    j    p2_instret_denyA_return
p2_instret_denyB_umode:
    csrr t0, INSTRET
    j    p2_instret_denyB_return
p2_instret_allow_umode:
    csrr t0, INSTRET
    sw   t0, 0x4C(s1)          # p2_ir_al_val
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x48(s1)          # p2_ir_al_delta (expect 0)
    lw   t3, 0x48(s1)          # AHB fence
    ecall
    j    p2_instret_allow_return

    # ---- Phase 2: instreth ----
p2_instreth_denyA_umode:
    csrr t0, INSTRETH
    j    p2_instreth_denyA_return
p2_instreth_denyB_umode:
    csrr t0, INSTRETH
    j    p2_instreth_denyB_return
p2_instreth_allow_umode:
    csrr t0, INSTRETH
    sw   t0, 0x64(s1)          # p2_irh_al_val
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x60(s1)          # p2_irh_al_delta (expect 0)
    lw   t3, 0x60(s1)          # AHB fence
    ecall
    j    p2_instreth_allow_return

    # ---- Phase 3: time ----
p3_time_denyA_umode:
    csrr t0, TIME
    j    p3_time_denyA_return
p3_time_denyB_umode:
    csrr t0, TIME
    j    p3_time_denyB_return
p3_time_allow_umode:
    csrr t0, TIME
    sw   t0, 0x7C(s1)          # p3_tm_al_val
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x78(s1)          # p3_tm_al_delta (expect 0)
    lw   t3, 0x78(s1)          # AHB fence
    ecall
    j    p3_time_allow_return

    # ---- Phase 3: timeh ----
p3_timeh_denyA_umode:
    csrr t0, TIMEH
    j    p3_timeh_denyA_return
p3_timeh_denyB_umode:
    csrr t0, TIMEH
    j    p3_timeh_denyB_return
p3_timeh_allow_umode:
    csrr t0, TIMEH
    sw   t0, 0x94(s1)          # p3_tmh_al_val
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x90(s1)          # p3_tmh_al_delta (expect 0)
    lw   t3, 0x90(s1)          # AHB fence
    ecall
    j    p3_timeh_allow_return

    # ---- Phase S: S-mode ALLOW (mcen=1, scen=0) ----
    # scounteren=0 must NOT gate S-mode; both reads succeed and add
    # NO illegal trap (pS_delta must be 0).
pS_smode_code:
    csrr t0, CYCLE
    sw   t0, 0x9C(s1)          # pS_cyc_val
    csrr t0, CYCLEH
    sw   t0, 0xA0(s1)          # pS_cyh_val
    lw   t3, 0x00(s1)
    sub  t3, t3, s2
    sw   t3, 0x98(s1)          # pS_delta (expect 0)
    lw   t3, 0x98(s1)          # AHB fence
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

    # Zero scratchpad (0x00 - 0xA8 inclusive => stop at 0xAC).
    # Covers every snapshot/value/mcause slot so a stale value from a
    # prior phase can never make a later phase false-pass.
    li   t0, 0
    li   t1, 0x00
zero_loop:
    add  t2, s1, t1
    sw   t0, 0(t2)
    addi t1, t1, 4
    li   t3, 0xAC
    bne  t1, t3, zero_loop

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Start with both enables fully clear
    li   t0, 0x0
    csrw MCOUNTEREN, t0
    csrw SCOUNTEREN, t0


    #===================================================================
    # PHASE 1: CY bit (mcounteren[0]/scounteren[0]) — cycle & cycleh
    #===================================================================

    #--- 1a: cycle DENY-A  (mcen=0, scen=1) ---
    li   t0, 0x1
    csrc MCOUNTEREN, t0        # CY = 0
    csrs SCOUNTEREN, t0        # scen[0] = 1  (prove mcen gates alone)
    la   t0, p1_cycle_denyA_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0           # MPP = 00 (U-mode)
    lw   s2, 0x00(s1)          # "before": LAST insn before mret
    mret
p1_cycle_denyA_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x08(s1)          # p1_cyc_dA_delta (expect 1)
    lw   t0, 0x04(s1)
    sw   t0, 0x0C(s1)          # p1_cyc_dA_mc (expect 2)

    #--- 1b: cycle DENY-B  (mcen=1, scen=0) ---  NEW spec rule (canary)
    li   t0, 0x1
    csrs MCOUNTEREN, t0        # CY = 1
    csrc SCOUNTEREN, t0        # scen[0] = 0
    la   t0, p1_cycle_denyB_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p1_cycle_denyB_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x10(s1)          # p1_cyc_dB_delta (expect 1; 0 on buggy RTL)
    lw   t0, 0x04(s1)
    sw   t0, 0x14(s1)          # p1_cyc_dB_mc (expect 2; stale 2 on buggy)

    #--- 1c: cycle ALLOW  (mcen=1, scen=1) ---
    li   t0, 0x1
    csrs MCOUNTEREN, t0        # CY = 1
    csrs SCOUNTEREN, t0        # scen[0] = 1
    la   t0, p1_cycle_allow_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p1_cycle_allow_return:
    # p1_cyc_al_val + p1_cyc_al_delta already stored by U-mode code

    #--- 1d: cycleh DENY-A  (mcen=0, scen=1) ---
    li   t0, 0x1
    csrc MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p1_cycleh_denyA_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p1_cycleh_denyA_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x20(s1)          # p1_cyh_dA_delta (expect 1)
    lw   t0, 0x04(s1)
    sw   t0, 0x24(s1)          # p1_cyh_dA_mc (expect 2)

    #--- 1e: cycleh DENY-B  (mcen=1, scen=0) ---  canary
    li   t0, 0x1
    csrs MCOUNTEREN, t0
    csrc SCOUNTEREN, t0
    la   t0, p1_cycleh_denyB_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p1_cycleh_denyB_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x28(s1)          # p1_cyh_dB_delta (expect 1; 0 on buggy RTL)
    lw   t0, 0x04(s1)
    sw   t0, 0x2C(s1)          # p1_cyh_dB_mc (expect 2; stale 2 on buggy)

    #--- 1f: cycleh ALLOW  (mcen=1, scen=1) ---
    li   t0, 0x1
    csrs MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p1_cycleh_allow_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p1_cycleh_allow_return:
    # p1_cyh_al_val + p1_cyh_al_delta already stored by U-mode code

    # Clean state entering next phase
    li   t0, 0x1
    csrc MCOUNTEREN, t0
    csrc SCOUNTEREN, t0

    lw   t3, 0x30(s1)          # AHB fence
    li   x31, 0x11111111       # Sync: Phase 1 done


    #===================================================================
    # PHASE 2: IR bit (mcounteren[2]/scounteren[2]) — instret & instreth
    #===================================================================

    #--- 2a: instret DENY-A  (mcen=0, scen=1) ---
    li   t0, 0x4
    csrc MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p2_instret_denyA_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p2_instret_denyA_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x38(s1)          # p2_ir_dA_delta (expect 1)
    lw   t0, 0x04(s1)
    sw   t0, 0x3C(s1)          # p2_ir_dA_mc (expect 2)

    #--- 2b: instret DENY-B  (mcen=1, scen=0) ---  canary
    li   t0, 0x4
    csrs MCOUNTEREN, t0
    csrc SCOUNTEREN, t0
    la   t0, p2_instret_denyB_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p2_instret_denyB_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x40(s1)          # p2_ir_dB_delta (expect 1; 0 on buggy RTL)
    lw   t0, 0x04(s1)
    sw   t0, 0x44(s1)          # p2_ir_dB_mc (expect 2; stale 2 on buggy)

    #--- 2c: instret ALLOW  (mcen=1, scen=1) ---
    li   t0, 0x4
    csrs MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p2_instret_allow_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p2_instret_allow_return:
    # p2_ir_al_val + p2_ir_al_delta already stored by U-mode code

    #--- 2d: instreth DENY-A  (mcen=0, scen=1) ---
    li   t0, 0x4
    csrc MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p2_instreth_denyA_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p2_instreth_denyA_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x50(s1)          # p2_irh_dA_delta (expect 1)
    lw   t0, 0x04(s1)
    sw   t0, 0x54(s1)          # p2_irh_dA_mc (expect 2)

    #--- 2e: instreth DENY-B  (mcen=1, scen=0) ---  canary
    li   t0, 0x4
    csrs MCOUNTEREN, t0
    csrc SCOUNTEREN, t0
    la   t0, p2_instreth_denyB_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p2_instreth_denyB_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x58(s1)          # p2_irh_dB_delta (expect 1; 0 on buggy RTL)
    lw   t0, 0x04(s1)
    sw   t0, 0x5C(s1)          # p2_irh_dB_mc (expect 2; stale 2 on buggy)

    #--- 2f: instreth ALLOW  (mcen=1, scen=1) ---
    li   t0, 0x4
    csrs MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p2_instreth_allow_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p2_instreth_allow_return:
    # p2_irh_al_val + p2_irh_al_delta already stored by U-mode code

    # Clean state
    li   t0, 0x4
    csrc MCOUNTEREN, t0
    csrc SCOUNTEREN, t0

    lw   t3, 0x60(s1)          # AHB fence
    li   x31, 0x22222222       # Sync: Phase 2 done


    #===================================================================
    # PHASE 3: TM bit (mcounteren[1]/scounteren[1]) — time & timeh
    #===================================================================

    #--- 3a: time DENY-A  (mcen=0, scen=1) ---
    li   t0, 0x2
    csrc MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p3_time_denyA_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p3_time_denyA_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x68(s1)          # p3_tm_dA_delta (expect 1)
    lw   t0, 0x04(s1)
    sw   t0, 0x6C(s1)          # p3_tm_dA_mc (expect 2)

    #--- 3b: time DENY-B  (mcen=1, scen=0) ---  canary
    li   t0, 0x2
    csrs MCOUNTEREN, t0
    csrc SCOUNTEREN, t0
    la   t0, p3_time_denyB_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p3_time_denyB_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x70(s1)          # p3_tm_dB_delta (expect 1; 0 on buggy RTL)
    lw   t0, 0x04(s1)
    sw   t0, 0x74(s1)          # p3_tm_dB_mc (expect 2; stale 2 on buggy)

    #--- 3c: time ALLOW  (mcen=1, scen=1) ---
    li   t0, 0x2
    csrs MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p3_time_allow_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p3_time_allow_return:
    # p3_tm_al_val + p3_tm_al_delta already stored by U-mode code

    #--- 3d: timeh DENY-A  (mcen=0, scen=1) ---
    li   t0, 0x2
    csrc MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p3_timeh_denyA_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p3_timeh_denyA_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x80(s1)          # p3_tmh_dA_delta (expect 1)
    lw   t0, 0x04(s1)
    sw   t0, 0x84(s1)          # p3_tmh_dA_mc (expect 2)

    #--- 3e: timeh DENY-B  (mcen=1, scen=0) ---  canary
    li   t0, 0x2
    csrs MCOUNTEREN, t0
    csrc SCOUNTEREN, t0
    la   t0, p3_timeh_denyB_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p3_timeh_denyB_return:
    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0x88(s1)          # p3_tmh_dB_delta (expect 1; 0 on buggy RTL)
    lw   t0, 0x04(s1)
    sw   t0, 0x8C(s1)          # p3_tmh_dB_mc (expect 2; stale 2 on buggy)

    #--- 3f: timeh ALLOW  (mcen=1, scen=1) ---
    li   t0, 0x2
    csrs MCOUNTEREN, t0
    csrs SCOUNTEREN, t0
    la   t0, p3_timeh_allow_umode
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    lw   s2, 0x00(s1)          # "before"
    mret
p3_timeh_allow_return:
    # p3_tmh_al_val + p3_tmh_al_delta already stored by U-mode code

    # Clean state
    li   t0, 0x2
    csrc MCOUNTEREN, t0
    csrc SCOUNTEREN, t0

    lw   t3, 0x90(s1)          # AHB fence
    li   x31, 0x33333333       # Sync: Phase 3 done


    #===================================================================
    # PHASE S: S-mode ALLOW with mcounteren[0]=1, scounteren[0]=0
    #
    # scounteren does NOT gate S-mode itself: with CY set in mcounteren
    # but CLEAR in scounteren, an S-mode read of cycle/cycleh must
    # SUCCEED.  (The same configuration denies U-mode — Phase 1 DENY-B.)
    # This locks in the spec asymmetry.  pS_delta must be 0 (no new
    # trap); ECALL from S-mode -> mcause=9 (handled, not counted).
    #===================================================================

    li   t0, 0x1
    csrs MCOUNTEREN, t0        # CY = 1 in mcounteren
    csrc SCOUNTEREN, t0        # CY = 0 in scounteren (must not gate S)

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
    # pS_cyc_val, pS_cyh_val, pS_delta already stored by S-mode code

    # Clean state
    li   t0, 0x1
    csrc MCOUNTEREN, t0
    csrc SCOUNTEREN, t0

    lw   t3, 0x98(s1)          # AHB fence
    li   x31, 0x44444444       # Sync: Phase S done


    #===================================================================
    # PHASE 4: Write to shadow CSRs from M-mode → illegal instruction
    # Shadow CSRs (0xC00-0xC82) have addr bits[11:10]=11 (read-only).
    # Any write attempt from any privilege level raises mcause=2.
    # 6 csrw instructions → trap_count increases by 6 (delta == 6).
    #===================================================================

    lw   s2, 0x00(s1)          # "before" Phase 4 (expect 12 on correct RTL)

    li   t1, 0                 # write value (irrelevant, always traps)
    csrw CYCLE,    t1          # traps (write to read-only, mcause=2)
    csrw CYCLEH,   t1          # traps
    csrw INSTRET,  t1          # traps
    csrw INSTRETH, t1          # traps
    csrw TIME,     t1          # traps
    csrw TIMEH,    t1          # traps

    lw   t0, 0x00(s1)
    sub  t0, t0, s2
    sw   t0, 0xA4(s1)          # p4_delta (expect 6)
    lw   t0, 0x04(s1)
    sw   t0, 0xA8(s1)          # p4_last_mcause (expect 2)
    lw   t3, 0xA8(s1)          # AHB fence

    li   x31, 0x55555555       # Sync: Phase 4 done


    #===================================================================
    # END OF TEST
    #===================================================================
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
