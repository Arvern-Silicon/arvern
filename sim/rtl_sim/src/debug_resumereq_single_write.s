#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_resumereq_single_write
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ONE dmcontrol write {haltreq=0, resumereq=1} resumes a halted hart
#   (Debug Spec 1.0, dmcontrol). The hart spins in a counted loop. The testbench
#   halts it, then resumes it with a SINGLE dmcontrol write that clears haltreq
#   and sets resumereq in the same transaction. The firmware only provides a
#   loop counter that is provably frozen while halted and advancing after the
#   resume, and a post-loop marker that proves the loop really completed.
#
#   Registers:
#     x5  : loop counter (frozen while halted, advancing after each resume)
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
    li   x6,  0x00000800        # loop bound (long enough for two halt/resume rounds)

    li   x31, 0x11111111        # sync: about to spin (TB halts us here)
spin:
    addi x5,  x5, 1
    blt  x5,  x6, spin          # count up to the bound (paused while halted)

    li   x20, 0x0000D09E        # reached only after the resumes completed the loop
    li   x31, 0x22222222        # sync: loop finished after resume
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)
