#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_wfi_platform_hang
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: WFI wake on a latched platform interrupt (mip[16], ip_pip[0]).
#
#   ip_pip is a STICKY accumulator (arv_csr_traps.v:1110-1114): a one-cycle
#   EDGE on the irq_platform_i pin latches the pending bit, which then holds
#   until a CSR clear -- the design explicitly supports edge sources. But the
#   combinational live-wakeup that ungates hclk during WFI sleep reads the raw
#   irq_platform_i PIN, not the sticky register. So an external device that
#   pulses-then-drops a platform IRQ line arms a wake condition that the live
#   path can no longer see -> a later WFI (with that bit enabled, MIE=0) can
#   gate the clock and never wake.
#
#   This firmware enables mie[16], asks the TB to pulse irq_platform[0], polls
#   mip[16] until the sticky bit has latched (by which time the TB has dropped
#   the pin), then WFI. Per spec WFI must wake on the enabled+pending bit.
#
# SRAM scratchpad (base 0x80000000):
#   0x00: post-WFI sentinel (0xCAFEBABE proves firmware resumed)
#   0x04: mip read-back showing bit16 latched
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

    # Global interrupts DISABLED (mstatus.MIE = 0).
    li   t0, 0x8
    csrc mstatus, t0

    # Enable platform IRQ 0: mie[16].
    li   t0, 0x10000
    csrs mie, t0

    # Ask the TB to pulse irq_platform[0] (one-cycle edge, then drop).
    li   x31, 0x21212121

    # Poll mip until the sticky ip_pip[0] (mip[16]) has latched. By the time
    # we observe it, the TB has already dropped the pin -- so the live-wakeup
    # path can no longer see this source.
    li   t1, 0x10000
poll_pending:
    csrr t0, mip
    and  t2, t0, t1
    beqz t2, poll_pending

    sw   t0, 0x04(s1)            # record the latched mip
    lw   t0, 0x04(s1)            # load-back fence

    # Per spec, WFI must wake immediately (mip[16] & mie[16] pending, MIE=0).
    wfi

after_wfi:
    li   t0, 0xCAFEBABE
    sw   t0, 0x00(s1)
    lw   t0, 0x00(s1)

    li   x31, 0x22222222
    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
