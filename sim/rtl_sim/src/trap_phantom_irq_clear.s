#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_phantom_irq_clear
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PHANTOM IRQ TRAP ON csrw mip
#   Reproducer for review item #17.
#
#   `csr_irq_config_wr` gated irq_detect during mstatus/sstatus/mie/sie writes
#   but NOT during mip/sip writes. Result: software clearing a pending IRQ
#   via csrw mip,0 on the SAME cycle that the IRQ would have first been
#   detected (e.g. just after csrs mstatus enabled MIE) would phantom-fire
#   the trap, because irq_vector_cause is combinational and sees the OLD
#   (still-pending) mip while the write effects only take place at posedge.
#
#   Sequence:
#   1. mtvec installed; mstatus.MIE=0.
#   2. csrw mie, 0x10000          # enable platform IRQ 0 (mie_mpie[0])
#   3. csrw mip, 0x10000          # set ip_pip[0] pending (still suppressed)
#   4. csrs mstatus, 0x8          # enable MIE         (cycle Y-1)
#   5. csrw mip, 0                # clear pending     (cycle Y -- RACE!)
#
#   Pre-fix: phantom MEI trap fires (trap_count = 1).
#   Post-fix: trap_count = 0 -- the mip_wr gate suppresses irq_detect.
#
#   No random IRQ injection / no random timing variants (race is timing-
#   sensitive).
#----------------------------------------------------------------------------

.section .text
.global main

.equ MSTATUS,        0x300
.equ MIE,            0x304
.equ MIP,            0x344
.equ MTVEC,          0x305

main:
    li   sp, 0x80010000
    li   s1, 0x80000000
    # DO NOT call _random_irq_init (no_random_irq test)

    # Scratchpad layout
    #   0x00: trap_count
    #   0x04: last mcause
    #   0x08: progress marker
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)

    # Pre-load CSR-write data into saved registers, so no `li` sits between
    # the back-to-back csrs mstatus / csrw mip pair (an extra cycle there
    # would let the trap fire normally and mask the race).
    li   s2, 0x10000               # platform-IRQ-0 enable / pending bit
    li   s3, 0x8                   # mstatus.MIE bit
    li   s4, 0                     # csrw mip clear value

    la   t0, trap_handler
    csrw MTVEC, t0

    li   x31, 0x11111111


    #=========================================================================
    # Arm: enable mie[16], set mip[16], but keep MIE=0 (suppressed).
    #=========================================================================
    csrw MIE, s2                   # enable platform IRQ 0
    csrw MIP, s2                   # set ip_pip[0] pending


    #=========================================================================
    # RACE: enable MIE, then clear pending IRQ in back-to-back instructions.
    # Pre-fix: irq_detect fires combinationally at the csrw mip cycle because
    # csr_irq_config_wr doesn't include mip_wr. Phantom MEI trap.
    # Post-fix: csr_irq_config_wr includes mip_wr -> suppressed, no phantom.
    #=========================================================================
    csrs MSTATUS, s3               # cycle Y-1: enable MIE (mstatus_wr=1 -> suppress)
    csrw MIP, s4                   # cycle Y:   clear pending (RACE without fix)

    # Drain a few cycles to let any phantom trap actually take.
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop


    #=========================================================================
    # Re-arm protection: turn off MIE and disable mie before exiting,
    # so the trailing instructions don't accidentally re-fire something.
    #=========================================================================
    csrw MIE, x0                   # disable everything
    csrw MIP, x0                   # ensure no pending
    csrci MSTATUS, 0x8             # MIE=0

    # Final progress marker; testbench reads trap_count to detect phantom.
    li   t0, 1
    sw   t0, 0x08(s1)
    lw   t0, 0x08(s1)              # drain

    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test


    .align 2
trap_handler:
    addi sp, sp, -16
    sw   s10, 12(sp)
    sw   s11,  8(sp)

    lw   s10, 0x00(s1)
    addi s10, s10, 1
    sw   s10, 0x00(s1)

    csrr s10, mcause
    sw   s10, 0x04(s1)

    # Defensive: clear MIE so we don't loop on phantom IRQs.
    csrci mstatus, 0x8
    csrw mie, x0
    csrw mip, x0

    lw   s11,  8(sp)
    lw   s10, 12(sp)
    addi sp, sp, 16
    mret
