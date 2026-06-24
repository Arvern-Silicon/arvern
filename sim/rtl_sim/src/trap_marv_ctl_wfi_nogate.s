#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_marv_ctl_wfi_nogate
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: marv_ctl[4] (wfi_clkgate_dis) -- disable WFI clock-gating.
#
#   The arvern feature-control CSR (custom, 0x7FF) bit [4] forces the live
#   wakeup high so hclk_en_o stays asserted: the core does NOT clock-gate
#   during WFI sleep. WFI must still STALL and then WAKE normally on an
#   enabled interrupt -- only the clock gating is suppressed.
#
#   Firmware sets marv_ctl[4], enables mie.MTIE (MIE=0, no trap), then WFI.
#   The TB verifies dut_hclk_en stays 1 during the WFI stall, then asserts
#   irq_m_timer to wake the core; firmware resumes past WFI.
#
# SRAM scratchpad (base 0x80000000):
#   0x00: post-WFI sentinel (0xCAFEBABE proves firmware resumed)
#   0x04: marv_ctl read-back (must have bit[4] set)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    .align 2
trap_handler:
    li   x31, 0xbadbad00         # no trap expected (MIE=0); flag if one fires
park_handler:
    j    park_handler

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)

    la   t0, trap_handler
    csrw mtvec, t0

    # Global interrupts DISABLED (mstatus.MIE = 0) -> WFI wakes without trapping.
    li   t0, 0x8
    csrc mstatus, t0

    # Enable machine-timer interrupt: mie.MTIE = bit7 (the wake source, a pin).
    li   t0, 0x80
    csrs mie, t0

    # Set marv_ctl[4] = disable WFI clock-gating (keep default bits[2:0]).
    li   t0, 0x10
    csrs 0x7ff, t0

    # Read back marv_ctl so the TB can confirm bit[4] latched.
    csrr t0, 0x7ff
    sw   t0, 0x04(s1)
    lw   t0, 0x04(s1)            # load-back fence

    # Signal ready: TB checks the clock stays ON during sleep, then wakes us.
    li   x31, 0x21212121

    wfi

after_wfi:
    li   t0, 0xCAFEBABE
    sw   t0, 0x00(s1)
    lw   t0, 0x00(s1)

    li   x31, 0x22222222
    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
