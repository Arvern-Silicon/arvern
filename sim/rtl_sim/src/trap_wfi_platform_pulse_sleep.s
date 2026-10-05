#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_wfi_platform_pulse_sleep
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ONE-CYCLE PLATFORM IRQ PULSE WHILE THE CLOCK IS GATED IN WFI
#   Phase 1: mie[16] = 1, mstatus.MIE = 0, wfi. Once the core has gated its
#   clock the bench pulses irq_platform_i[0] for exactly one free_clk cycle.
#   WFI must resume (the pulse latches mip[16], enabled and pending).
#   Phase 2: mie = 1<<17 only, wfi. During sleep the bench pulses
#   irq_platform_i[0] for one cycle (masked: must still latch mip[16], no
#   wake), then holds irq_platform_i[1] for three cycles to wake the hart.
#   mip[16] must read 1 after the wake.
# SRAM scratchpad (base 0x80000000):
#   0x00: mip after the phase-1 wake
#   0x04: mip after the phase-2 wake
#----------------------------------------------------------------------------

.section .text
.global main

main:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw  mstatush, x0              # mstatus.MDT   = 0
    la    t0, trap_handler
    csrw  mtvec, t0
    li    t0, 0x8
    csrc  mstatus, t0               # MIE = 0: WFI resumes without a trap
    li    s1, 0x80000000
    sw    x0, 0x00(s1)
    sw    x0, 0x04(s1)
    li    t1, 0x00010000            # mip/mie[16]
    li    t2, 0x00020000            # mip/mie[17]

    # Phase 1
    csrw  mie, t1
    li    x31, 0x11111111
    wfi
    csrr  t0, mip
    sw    t0, 0x00(s1)
    csrc  mip, t1
    li    x31, 0x22222222

    # Phase 2
    csrw  mie, t2
    li    x31, 0x33333333
    wfi
    csrr  t0, mip
    sw    t0, 0x04(s1)
    lw    t0, 0x04(s1)
    or    t0, t1, t2
    csrc  mip, t0
    csrw  mie, x0
    li    x31, 0xdeadbeef

end_of_test:
    j     end_of_test

    .align 2
trap_handler:
    li    x31, 0xbadbad00
park:
    j     park
