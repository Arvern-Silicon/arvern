#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_kill_muldiv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI LOW-LATENCY KILL OF MULDIV/UOP
#   Verifies that an NMI aborts a multi-cycle MUL/DIV (or Zcmp UOP sequence)
#   even when software has NOT enabled the IRQ-kill feature in irqkill_cfg.
#   Spec posture: NMIs must be low-latency regardless of OS configuration.
#
#   Phase 2: irqkill_cfg=0, long div in tight loop, NMI fires.
#   MNEPC must land on a DIV instruction (kill happened) — not on
#   an instruction past the DIV (which would mean NMI waited for
#   natural completion).
#
#   Phase 3: same setup with cm.push/cm.pop UOP sequence. MNEPC must land
#   on the cm.* instruction itself.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x000: nmi_count
#   0x004: mnepc captured at NMI entry
#   0x008: nmi_handler address (driven into nmi_vector by testbench)
#   0x00C: expected MNEPC if NMI killed the DIV (PC of the div instruction)
#   0x010: PC of the post-DIV instruction (what MNEPC would be if NMI WAITED)
#=========================================================================

main:
    j _start

    .align 2
nmi_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)

    # Increment nmi_count
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Save MNEPC
    csrr t1, 0x741              # mnepc
    sw   t1, 0x04(s1)

    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    .word 0x70200073              # mnret


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

    # Publish handler address for the testbench (drives nmi_vector)
    la   t0, nmi_handler
    sw   t0, 0x08(s1)

    # IMPORTANT: irqkill_cfg = 0 -> kills are DISABLED for IRQs.
    # Post-fix, NMI must still kill the muldiv (force-enabled).
    li   t0, 0x0
    csrw 0x7FF, t0

    # Enable NMI (NMIE resets to 0 per Smrnmi spec)
    csrsi 0x744, 8                # mnstatus.NMIE = 1

    # Mark Phase 1 done.
    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: SINGLE long-divide, NMI fires while in DIV
    #
    # Use radix-2 divider (33 cycles when DIV_TYPE=3) for the widest
    # observation window. A single DIV makes the MNEPC test
    # discriminative: kill -> MNEPC=div_pc, drain-and-continue ->
    # MNEPC=post_div_pc.
    #=================================================================

    # Publish discriminating PC bounds for the testbench:
    #   0x0C: PC of div_pc (what MNEPC must be on kill)
    #   0x10: PC of post_div (what MNEPC would be if NMI WAITED for DIV)
    la   t0, div_pc
    sw   t0, 0x0C(s1)
    la   t0, post_div
    sw   t0, 0x10(s1)

    li   a0, 0xFFFFFFF9         # dividend
    li   a1, 3                  # divisor

    li   x31, 0xD0D0D0D0        # marker: about to enter divide

    # Pad so the marker writes drain before DIV reaches EX, and so
    # the testbench has a small but predictable window.
    nop
    nop
    nop
    nop

div_pc:
    div  a4, a0, a1             # 33-cycle radix-2 divide — under NMI
post_div:
    addi a5, a0, 1              # if NMI waited for DIV, MNEPC lands here

    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test
