#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_post_mnret_irq
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: POST-MNRET IRQ SUPPRESS
#   irq_suppress_post_mret must arm on mnret_taken just as it does on
#   mret_taken. Without the fix an IRQ pending at mnret completion traps on
#   the same PC the mnret resumed to; with the fix one post-mnret instruction
#   dispatches first, and the IRQ traps on the *next* PC. MEPC captured by
#   the IRQ handler is the discriminator.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: nmi_count
#   0x04: irq_count
#   0x08: nmi_handler address (testbench drives nmi_vector from this)
#   0x0C: MEPC captured by IRQ handler
#   0x10: PC the fix expects (next_after_target)
#   0x14: PC the bug yields (mnret_target)
#=========================================================================

main:
    j _start

    .align 2
nmi_handler:
    # Disable MIE so the timer IRQ does not fire during the handler itself.
    csrci mstatus, 8

    addi sp, sp, -16
    sw   s10,12(sp)
    sw   s11, 8(sp)

    # Increment nmi_count
    lw   s10, 0x00(s1)
    addi s10, s10, 1
    sw   s10, 0x00(s1)

    # Force mnret to resume at a known label (mnret_target) so MEPC after
    # the IRQ trap is a clean discriminator.
    la   s10, mnret_target
    csrw 0x741, s10                 # mnepc

    lw   s11, 8(sp)
    lw   s10,12(sp)
    addi sp, sp, 16

    # Enable M-mode interrupts immediately before mnret — only the mnret
    # itself sits between MIE=1 and the post-mnret instruction. IRQ
    # detection is blocked while mnret_taken is asserted, so the IRQ
    # becomes pending the cycle after mnret completes.
    csrsi mstatus, 8
    .word 0x70200073                # mnret


    .align 2
irq_handler:
    addi sp, sp, -16
    sw   s10,12(sp)
    sw   s11, 8(sp)

    # Increment irq_count
    lw   s10, 0x04(s1)
    addi s10, s10, 1
    sw   s10, 0x04(s1)

    # Capture MEPC — discriminator.
    csrr s11, mepc
    sw   s11, 0x0C(s1)

    # Disable MTIE and MIE so no further IRQ traps.
    li   s10, 0x80
    csrc mie, s10
    csrci mstatus, 8

    lw   s11, 8(sp)
    lw   s10,12(sp)
    addi sp, sp, 16
    mret


 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)

    # Publish NMI handler addr for the testbench's nmi_vector drive.
    la   t0, nmi_handler
    sw   t0, 0x08(s1)

    # mtvec = IRQ trap entry point.
    la   t0, irq_handler
    csrw mtvec, t0

    # Enable MTIE (timer). mstatus.MIE stays 0 until NMI handler enables it.
    li   t0, 0x80
    csrw mie, t0

    # Enable NMI (mnstatus.NMIE = 1)
    csrsi 0x744, 8

    # Enable post-trap suppression (bit 2 of irqkill_cfg). This is the
    # mechanism whose arming we are verifying.
    li   t0, 0x4
    csrw 0x7FF, t0

    # Publish discriminator PC bounds.
    la   t0, mnret_target
    sw   t0, 0x14(s1)               # bug-mode MEPC
    la   t0, next_after_target
    sw   t0, 0x10(s1)               # fix-mode MEPC

    li   x31, 0x11111111            # init done

    # Spin loop — testbench asserts NMI + irq_m_timer here. NMI handler
    # rewrites mnepc so mnret jumps to mnret_target regardless of where
    # in the spin loop the NMI lands.
    li   x31, 0xC0DEC0DE
spin:
    j    spin


    # ----------------------------------------------------------------
    # mnret resumes here. With fix: addi a0 retires, then the IRQ traps
    # on the addi a1 → MEPC == next_after_target.
    # Without fix: IRQ traps immediately → MEPC == mnret_target.
    # ----------------------------------------------------------------
    .align 2
mnret_target:
    addi a0, zero, 1
next_after_target:
    addi a1, zero, 2
    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test
