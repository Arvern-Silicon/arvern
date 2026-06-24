#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_ssip_su_disabled
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SU_MODE_EN=0 elision of the irq_s_software_i HW input path.
#
#   When SU_MODE_EN=0, sip_ssip_eff is gated to 0 regardless of the HW input:
#     sip_ssip_eff = sip_ssip | (irq_s_software_r & SU_MODE_EN);
#   so asserting irq_s_software_i must NOT cause any trap and MIP[1] must
#   continue to read as 0. This test:
#     - Enables mie.SSIE (the bit still exists at SU=0; we just expect no
#       pending bit to ever co-arrive).
#     - Enables mstatus.MIE.
#     - Asks the TB to drive irq_s_software=1 and hold it.
#     - Spins for a generous window and verifies the M-mode trap counter
#       stays 0 and that MIP[1] reads back 0.
#----------------------------------------------------------------------------

.equ SCRATCH,         0x80000000
.equ COUNT_M_OFF,     0x00      # M-mode trap count
.equ MIP_SNAPSHOT_OFF,0x04      # MIP captured by firmware while HW is held

.section .text
.global main
main:
    /* ----- Setup ----- */
    li   sp, 0x80010000
    li   s1, SCRATCH
    sw   zero, COUNT_M_OFF(s1)
    sw   zero, MIP_SNAPSHOT_OFF(s1)

    la   t0, m_handler
    csrw mtvec, t0

    csrw mie, zero
    li   t0, (1 << 1)               /* mie.SSIE */
    csrw mie, t0

    /* Global MIE on */
    li   t0, 0x8
    csrs mstatus, t0

    li   x31, 0xFFFFFFFF             /* TB sync: setup complete */

    /* TB drives irq_s_software=1 after observing the sync below */
    li   x31, 0x10101010

    /* Spin window: 2000 iter * ~4 cyc * 50 ns = ~400 us; well within the
     * tb_arvern 500 us watchdog. Watch for any spurious increment of the
     * trap counter -- any such increment is a fail. */
    li   t4, 2000
spin_no_trap:
    lw   t5, COUNT_M_OFF(s1)
    bnez t5, fail_trap_fired
    addi t4, t4, -1
    bnez t4, spin_no_trap

    /* Capture MIP for the report (HW is still being held by the TB). */
    csrr t0, mip
    sw   t0, MIP_SNAPSHOT_OFF(s1)

    /* Report:
     *   a0 = trap count (expect 0)
     *   a1 = MIP[1] under hold (expect 0 -- HW input gated by SU_MODE_EN=0)
     */
    lw   t1, COUNT_M_OFF(s1)
    mv   a0, t1
    andi t2, t0, (1 << 1)
    mv   a1, t2

    li   x31, 0x11111111             /* TB sync: phase done, drop HW */

    /* ----- End ----- */
    li   x31, 0xdeadbeef
spin_end:
    j    spin_end


fail_trap_fired:
    /* If we ever land here, the SSIP HW input fired a trap despite SU=0.
     * Report a sentinel and end so the TB sees the failure. */
    li   t0, 0xbadbad00
    mv   a0, t0
    mv   a1, t0
    li   x31, 0x11111111
    li   x31, 0xdeadbeef
fail_spin:
    j    fail_spin


/* =========================================================================
 * M-mode trap handler.
 *
 * In this test no IRQ should ever fire. If somehow one does, bump the
 * counter so the main flow's spin detects it. We DO mask SSIE inside the
 * handler so that re-entry doesn't loop forever before we can report.
 * =======================================================================*/
m_handler:
    /* Spill t1 via mscratch so the main flow's t1 is preserved. */
    csrw mscratch, t1

    /* Mask mie.SSIE so we don't re-trap immediately. */
    li   t1, (1 << 1)
    csrc mie, t1

    /* Bump trap counter. */
    lw   t1, COUNT_M_OFF(s1)
    addi t1, t1, 1
    sw   t1, COUNT_M_OFF(s1)

    csrr t1, mscratch
    mret
