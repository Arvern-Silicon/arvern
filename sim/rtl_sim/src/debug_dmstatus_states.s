#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmstatus_states
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: dmstatus exactly-one-state coverage (Debug Spec 1.0). The hart
#   spins in a counted loop; the testbench walks it through RUNNING -> HALTED
#   -> resumed RUNNING -> UNAVAILABLE (dmcontrol.ndmreset held: hart in reset,
#   DM alive) -> released RUNNING, checking at each stop that dmstatus reports
#   EXACTLY ONE of {running, halted, unavail} (any*/all* pairs), plus the
#   anyhavereset/ackhavereset choreography after the ndmreset.
#
#   NOTE: the ndmreset RESTARTS this firmware from the reset vector - it is
#   written to be safely re-runnable from scratch (no SRAM state; the loop and
#   markers simply run again to completion after the reset is released).
#
#   Registers:
#     x5  : loop counter (frozen while halted; restarts after ndmreset)
#     x6  : loop bound
#     x18 : sentinel marker                          (expect 0xA5A5A5A5)
#     x20 : post-loop marker                         (expect 0x0000D09E)
#     x31 : sync (11111111=spinning, 22222222=loop done, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # sentinel marker
    li   x20, 0                 # post-loop marker
    li   x5,  0                 # loop counter (frozen while halted)
    li   x6,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)

    li   x31, 0x11111111        # sync: about to spin (TB halts / ndmresets us here)
spin:
    addi x5,  x5, 1
    blt  x5,  x6, spin          # count up to the bound

    li   x20, 0x0000D09E        # loop completed (after the final release/resume)
    li   x31, 0x22222222        # sync: loop finished
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)
