#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_ssip_hw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: irq_s_software_i hardware-input path for SSIP (MIP[1]).
#
#   Verifies the spec-compliant ACLINT-1.0-rc4 edge-set HW input. The DUT
#   signal `irq_s_software_i` (driven by the ACLINT SSWI as a 1-cycle edge,
#   or by a stim-held level for this block-level test) is LATCHED into the
#   sip_ssip flop with priority over a same-cycle CSR clear -- so while the
#   HW pin is high, `csrc mip,(1<<1)` cannot drop the flop. Once the HW pin
#   is low, `csrc mip,(1<<1)` clears the flop normally. Effective SSIP must:
#     (1) trap to M-mode when mideleg.SSI=0 (cause 1)
#     (2) trap to S-mode when mideleg.SSI=1 (cause 1, top bit set)
#
#   Synchronisation:
#     - Each phase signals the TB via x31. The TB drives `irq_s_software` to
#       1 at the start of the phase and back to 0 once the handler has
#       captured the cause (signalled by an x31 advance).
#     - The handler masks the relevant *IE bit in mie/sie before MRET/SRET
#       to prevent re-trap while the TB races to drop the HW pin.
#     - Between phases, the firmware does `csrc mip,(1<<1)` AFTER the
#       drop-wait delay -- the HW pin is low by then, so the CSR clear
#       wins and the latched flop is reset before the next phase enables
#       SSIE again. Without this, the stale 1 would cause an immediate
#       phantom trap on `csrw mie,SSIE`, breaking the WFI-wake / phase-3
#       no-spurious checks.
#----------------------------------------------------------------------------

.equ SCRATCH,         0x80000000
.equ COUNT_M_OFF,     0x00      # M-mode trap count
.equ COUNT_S_OFF,     0x04      # S-mode trap count
.equ CAUSE_M_OFF,     0x08      # last M-mode mcause captured
.equ CAUSE_S_OFF,     0x0C      # last S-mode scause captured
.equ MIP_POST_CLR_OFF,0x10      # MIP read-back AFTER csrc mip,(1<<1) in handler (HW-OR check)

.section .text
.global main
main:
    /* ----- One-time setup ----- */
    li   sp, 0x80010000
    li   s1, SCRATCH
    sw   zero, COUNT_M_OFF(s1)
    sw   zero, COUNT_S_OFF(s1)
    sw   zero, CAUSE_M_OFF(s1)
    sw   zero, CAUSE_S_OFF(s1)
    sw   zero, MIP_POST_CLR_OFF(s1)

    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0

    csrw mideleg, zero
    csrw mie,     zero
    csrw sie,     zero

    /* Enable MIE / SIE globally */
    li   t0, 0x8                /* mstatus.MIE */
    csrs mstatus, t0
    li   t0, 0x2                /* sstatus.SIE */
    csrs sstatus, t0

    li   x31, 0xFFFFFFFF        /* TB sync: setup complete */

    /* ===================================================================== */
    /* Phase 1: HW SSIP -> M-mode (mideleg.SSI=0)                            */
    /* ===================================================================== */
    csrw mideleg, zero
    li   t0, (1 << 1)           /* mie.SSIE */
    csrw mie, t0

    lw   t1, COUNT_M_OFF(s1)    /* count_before */

    li   x31, 0x10101010        /* TB sync: ready, please assert irq_s_software */

    /* Spin until handler's count-store releases us */
    li   t4, 100000
phase1_spin:
    lw   t5, COUNT_M_OFF(s1)
    bne  t5, t1, phase1_done
    addi t4, t4, -1
    bnez t4, phase1_spin
phase1_done:

    lw   t2, COUNT_M_OFF(s1)
    sub  t2, t2, t1             /* x7  = delta = 1 */
    mv   a0, t2
    lw   t3, CAUSE_M_OFF(s1)    /* x28 = last mcause (= 1) */
    mv   a1, t3

    li   x31, 0x11111111        /* TB sync: phase1 done, expects delta=1 cause=1 */

    /* ===================================================================== */
    /* Phase 2: WFI wake via irq_s_software_i                                */
    /* Re-enable SSIE (handler masked it), drop into WFI, expect the TB-asserted
     * HW SSIP to wake the core and deliver the trap; verify count+1 + cause=1.
     *
     * IMPORTANT: before re-enabling SSIE, give the TB time to react to the
     * 0x11111111 sync and drop irq_s_software back to 0, then for the 2-FF
     * synchroniser inside the core to propagate that drop to
     * irq_s_software_r. Otherwise the still-high HW pin + freshly re-enabled
     * SSIE causes a spurious re-trap that masks SSIE again before we reach
     * WFI, and WFI then sleeps forever (compressed-mode timing exposes this).
     * ===================================================================== */
    li   t4, 100
phase1_to_phase2_drop_wait:
    addi t4, t4, -1
    bnez t4, phase1_to_phase2_drop_wait

    /* The sip_ssip flop is still 1 from phase 1 (HW priority blocked the
     * handler's csrc). HW is now low, so this csrc clears the flop before
     * we re-enable SSIE -- otherwise the next csrw mie would phantom-trap. */
    li   t0, (1 << 1)
    csrc mip, t0

    li   t0, (1 << 1)           /* re-enable mie.SSIE */
    csrw mie, t0

    lw   t1, COUNT_M_OFF(s1)    /* count_before */

    li   x31, 0x20202020        /* TB sync: about to WFI, please assert irq_s_software */

    wfi                         /* sleep until enabled IRQ; on wake the trap fires */

    /* After the handler returns, fall through here -- spin until the count
     * actually advanced (the trap-and-return takes a few cycles). */
    li   t4, 100000
phase2_spin:
    lw   t5, COUNT_M_OFF(s1)
    bne  t5, t1, phase2_done
    addi t4, t4, -1
    bnez t4, phase2_spin
phase2_done:

    lw   t2, COUNT_M_OFF(s1)
    sub  t2, t2, t1
    mv   a2, t2                 /* a2 = delta = 1 (woke + trapped) */
    lw   t3, CAUSE_M_OFF(s1)
    mv   a3, t3                 /* a3 = mcause = 1 (SSI) */

    li   x31, 0x22222222        /* TB sync: phase2 done */

    /* ===================================================================== */
    /* Phase 3: HW priority over csrc + post-drop clear                      */
    /* With HW SSIP held by the TB, the handler does `csrc mip,(1<<1)` and
     * captures the post-clear MIP value -- the spec says MIP[1] stays 1
     * because the HW edge rule has priority over a same-cycle CSR clear.
     * After the handler returns and re-enables SSIE, the flop is still 1
     * (HW still held), so a second trap fires immediately. Then firmware
     * asks the TB to drop the HW pin, csrc's the flop clean (HW low now),
     * re-enables SSIE and verifies NO further trap fires.
     * ===================================================================== */
    /* Same drop-wait + csrc dance as the phase1->phase2 boundary -- the
     * phase-2 WFI-wake trap also left sip_ssip latched at 1. */
    li   t4, 100
phase2_to_phase3_drop_wait:
    addi t4, t4, -1
    bnez t4, phase2_to_phase3_drop_wait

    li   t0, (1 << 1)
    csrc mip, t0

    li   t0, (1 << 1)
    csrw mie, t0                /* re-enable SSIE */

    mv   s2, t5                 /* s2 = count_phase3_before (preserved across traps) */

    li   x31, 0x30303030        /* TB sync: hold irq_s_software=1 for the whole phase */

    /* --- Wait for first trap (handler does csrc + capture) --- */
    li   t4, 100000
phase3_spin1:
    lw   t5, COUNT_M_OFF(s1)
    bne  t5, s2, phase3_done1
    addi t4, t4, -1
    bnez t4, phase3_spin1
phase3_done1:

    /* Handler masked SSIE. Re-enable; HW still high => second trap must fire. */
    li   t0, (1 << 1)
    csrw mie, t0

    addi s3, s2, 1              /* s3 = count after first trap */
    li   t4, 100000
phase3_spin2:
    lw   t5, COUNT_M_OFF(s1)
    bne  t5, s3, phase3_done2
    addi t4, t4, -1
    bnez t4, phase3_spin2
phase3_done2:

    sub  t2, t5, s2
    mv   a4, t2                 /* a4 = total Phase-3 traps so far (expect 2 = re-fire happened) */

    lw   t3, MIP_POST_CLR_OFF(s1)
    andi t3, t3, (1 << 1)
    mv   a5, t3                 /* a5 = post-csrc MIP[1] (expect 2 = bit still asserted) */

    /* --- Ask TB to drop the HW pin --- */
    li   x31, 0x33333333        /* TB sync: please drop irq_s_software */

    /* Wait long enough for the TB-side assignment + 2-FF sync to settle.
     * (~100 iterations * ~4 cyc/iter * 50 ns = 20 us is plenty.) */
    li   t4, 100
phase3_drop_wait:
    addi t4, t4, -1
    bnez t4, phase3_drop_wait

    /* Clear the now-stale sip_ssip flop (HW priority no longer blocks the
     * CSR clear). Without this, the next csrw mie would phantom-trap. */
    li   t0, (1 << 1)
    csrc mip, t0

    /* Re-enable SSIE; HW now clear AND sip_ssip cleared => NO further trap. */
    li   t0, (1 << 1)
    csrw mie, t0

    /* Bounded no-trap window -- if a spurious trap fires here, count moves
     * and we report a different value in a6. 1000 iter * ~4 cyc/iter * 50 ns
     * = 200 us, well inside the testbench 500 us watchdog. */
    mv   s4, t5                 /* count at start of no-trap window */
    li   t4, 1000
phase3_no_trap_spin:
    lw   t5, COUNT_M_OFF(s1)
    bne  t5, s4, phase3_spurious
    addi t4, t4, -1
    bnez t4, phase3_no_trap_spin
    li   t2, 0                  /* 0 = no spurious trap */
    j    phase3_report
phase3_spurious:
    li   t2, 1                  /* 1 = spurious trap detected (fail) */
phase3_report:
    mv   a6, t2

    li   x31, 0x44444444        /* TB sync: phase3 done */

    /* ===================================================================== */
    /* Phase 4: HW SSIP -> S-mode (mideleg.SSI=1, MRET to S-mode) -- terminal */
    /* ===================================================================== */
    li   t0, (1 << 1)           /* mideleg.SSI = 1 */
    csrw mideleg, t0

    li   t0, (1 << 1)           /* sie.SSIE */
    csrw sie, t0

    /* MPP = 01 (S-mode), MPIE = 1 */
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0880
    csrs mstatus, t0

    la   t0, s_mode_entry
    csrw mepc, t0
    mret                        /* drop into S-mode */

s_mode_entry:
    lw   t1, COUNT_S_OFF(s1)

    li   x31, 0x40404040        /* TB sync: in S-mode, please assert irq_s_software */

    li   t4, 100000
phase4_spin:
    lw   t5, COUNT_S_OFF(s1)
    bne  t5, t1, phase4_done
    addi t4, t4, -1
    bnez t4, phase4_spin
phase4_done:
    /* Still in S-mode -- finalize and report directly (no need to bounce
     * back to M-mode just to mv into a2/a3 and update x31). */
    lw   t2, COUNT_S_OFF(s1)
    sub  t2, t2, t1             /* delta = 1 */
    mv   a0, t2                 /* a0 = S-mode delta (different reg from M args) */
    lw   t3, CAUSE_S_OFF(s1)
    mv   a1, t3                 /* a1 = scause = 1 (note: a0/a1 reused; TB checks at sync 0x44444445) */

    /* x31 sync for phase 4 done with S-mode register sentinel pattern */
    /* We pack S-delta into t6 too via x31 below; cleaner: report via stable a7 */
    mv   a7, t2                 /* a7 = S-mode delta */
    mv   t6, t3                 /* spare reg, not used elsewhere -- TB ignores */

    li   x31, 0x55555555        /* TB sync: phase4 done */

    /* ----- End ----- */
    li   x31, 0xdeadbeef
spin_end:
    j    spin_end


/* =========================================================================
 * M-mode trap handler
 *
 * For SSI: capture mcause, mask SSIE so the IRQ doesn't immediately re-fire
 * while the TB is dropping the HW pin, bump the M counter.
 * For ecall-from-S (cause 9): resume firmware at m_phase2_resume.
 * =======================================================================*/
m_handler:
    csrr t0, mcause
    bltz t0, m_handler_irq      /* top bit set -> interrupt */

    /* No synchronous exceptions are expected in this test -- if any arrive,
     * just MRET (re-running the offending insn would loop, but the test's
     * watchdog timeout will catch that). */
    j    m_handler_done

m_handler_irq:
    /* Use mscratch as a t1-spill so the main flow's t1 (count_before) is
     * preserved across the trap entry. */
    csrw mscratch, t1

    /* WFI-MEPC race fix-up: under heavy ROM wait states, an IRQ can fire
     * before WFI commits (id_wfi_active_i not yet set), so MEPC points at
     * the WFI instruction itself rather than WFI+4. Since the handler
     * masks SSIE below, MRET back to WFI would re-sleep forever. Detect
     * the WFI encoding at MEPC and advance MEPC by 4 so MRET resumes past
     * WFI. Spec-permitted (RISC-V says MEPC can be WFI or WFI+1; we
     * normalise to WFI+1). Use halfword loads -- in -c_mode MEPC may be
     * 2-byte aligned and a 4-byte lw would itself trap. */
    csrr t1, mepc
    lhu  t3, 0(t1)
    lhu  t4, 2(t1)
    slli t4, t4, 16
    or   t3, t3, t4
    li   t4, 0x10500073
    bne  t3, t4, m_handler_no_wfi_skip
    addi t1, t1, 4
    csrw mepc, t1
m_handler_no_wfi_skip:

    /* Persist cause (with top bit cleared for easy compare in TB) */
    slli t1, t0, 1
    srli t1, t1, 1
    sw   t1, CAUSE_M_OFF(s1)

    /* HW-OR check: attempt to clear MIP[1] via csrc, then re-read MIP and
     * persist the result. Phase 3 checks bit[1] of this value; other phases
     * just write to the buffer and ignore it. */
    li   t1, (1 << 1)
    csrc mip, t1
    csrr t1, mip
    sw   t1, MIP_POST_CLR_OFF(s1)

    /* Mask the firing source so MRET doesn't re-trap while HW pin held */
    li   t1, (1 << 1)           /* mie.SSIE */
    csrc mie, t1

    /* Bump M counter */
    lw   t1, COUNT_M_OFF(s1)
    addi t1, t1, 1
    sw   t1, COUNT_M_OFF(s1)

    csrr t1, mscratch           /* restore t1 */

m_handler_done:
    mret


/* =========================================================================
 * S-mode trap handler -- expects delegated SSI (scause = 0x80000001)
 * =======================================================================*/
s_handler:
    csrr t0, scause
    bltz t0, s_handler_irq

    /* Unexpected synchronous trap in S-mode -- end test marker */
    li   x31, 0xbadbad00
    j    s_handler

s_handler_irq:
    /* Spill t1 via sscratch so the S-mode caller's t1 is preserved. */
    csrw sscratch, t1

    /* Persist scause (with top bit cleared for easy compare) */
    slli t1, t0, 1
    srli t1, t1, 1
    sw   t1, CAUSE_S_OFF(s1)

    /* Mask sie.SSIE so SRET doesn't re-trap while HW pin held */
    li   t1, (1 << 1)
    csrc sie, t1

    /* Bump S counter */
    lw   t1, COUNT_S_OFF(s1)
    addi t1, t1, 1
    sw   t1, COUNT_S_OFF(s1)

    csrr t1, sscratch           /* restore t1 */

    sret
