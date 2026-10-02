#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_runctrl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DMI run-control (Debug Module)
#   The hart spins in a counted loop. The testbench drives the hclk-domain DMI
#   bus directly (no DTM): it sets dmcontrol.dmactive, halts via dmcontrol.haltreq
#   while polling dmstatus.allhalted, verifies the loop counter (x5) is frozen
#   while halted, then resumes via dmcontrol.resumereq while polling allresumeack/
#   allrunning. After resume the loop completes and the post-resume marker is set,
#   proving the hart actually resumed.
#
#   Registers:
#     x5  : loop counter (observed FROZEN while halted)         (t0)
#     x6  : loop bound
#     x18 : sentinel marker, must survive untouched  (expect 0xA5A5A5A5)
#     x20 : post-resume marker, set after the loop   (expect 0x0000D09E)
#     x31 : sync (11111111=spinning, 22222222=loop done, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x20, 0                 # post-resume marker
    li   x5,  0                 # loop counter (frozen while halted)
    li   x6,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)

    li   x31, 0x11111111        # sync: about to spin (TB halts us here)
spin:
    addi x5,  x5, 1
    blt  x5,  x6, spin          # count up to the bound (paused while halted)

    li   x20, 0x0000D09E        # reached only after a real resume completes the loop
    li   x31, 0x22222222        # sync: loop finished after resume
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)
