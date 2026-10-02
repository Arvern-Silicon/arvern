#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_resumereq_haltreq
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: dmcontrol.resumereq is IGNORED while haltreq is set (Debug
#   Spec 1.0). The hart spins in a counted loop. The testbench halts it, then
#   writes dmcontrol with BOTH haltreq=1 and resumereq=1 (twice): the hart must
#   STAY halted (allhalted=1, no allresumeack, loop counter x5 provably frozen).
#   Only after haltreq is cleared does a resumereq perform a normal resume
#   (allresumeack, allrunning, counter advancing again).
#
#   Registers:
#     x5  : loop counter (frozen while halted, advancing after the real resume)
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

    li   x20, 0x0000D09E        # reached only after a REAL resume completes the loop
    li   x31, 0x22222222        # sync: loop finished after resume
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)
