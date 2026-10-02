#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_wfi_halt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DEBUG HALTREQ during WFI sleep (Sdext)
#   A WFI-sleeping hart has gated its clock (hclk_en_o low). An external halt
#   request must wake it into Debug Mode with the clock kept alive (the debug
#   term added to wfi_wakeup_live_o). Per the RISC-V Debug Spec (Sdext), a halt
#   during WFI MANDATES the WFI complete: "the hart must leave the stalled state,
#   completing this instruction's execution, and then enter Debug Mode," and
#   "dpc is set to the next instruction that should be executed." So on resume
#   the hart must proceed PAST the WFI — NOT re-enter it.
#
#   There is deliberately NO interrupt enabled here: the ONLY wake is the debug
#   halt, so reaching the post-WFI marker proves dpc = WFI+4 (the spec rule),
#   not a re-executed WFI. (Before the dpc=WFI+4 fix this firmware hung, the
#   hart re-sleeping on resume.)
#
#   Registers:
#     x20 : past-WFI marker, set after resume  (expect 0x0000D09E)
#     x18 : sentinel marker                    (expect 0xA5A5A5A5)
#     x31 : sync (11111111=about to sleep, 22222222=past WFI, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x20, 0                 # past-WFI marker

    li   x31, 0x11111111        # sync: about to enter WFI sleep
    wfi                          # no wake source enabled -> only the debug halt
                                 # wakes it; resume must proceed PAST the WFI
    li   x20, 0x0000D09E        # reached only if dpc pointed past the WFI (spec)
    li   x31, 0x22222222        # sync: past WFI after debug resume
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)
