#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trig_warl_info
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sdtrig tinfo value + mcontrol6 chain-bit WARL (Debug Spec 1.0).
#   The hart just spins in a counted loop; ALL the trigger-CSR work is done by
#   the testbench over the DM abstract-CSR path while the hart is halted:
#     - tinfo (0x7A4) must read exactly 0x01000040 (version=1, mcontrol6);
#     - tdata1 (0x7A1) written with the mcontrol6 chain bit (bit 11) set must
#       read back chain=0 (WARL read-only zero) with the other legal fields
#       (execute=1) retained.
#   After resume the loop completes and the post-resume marker is set, proving
#   the hart survived the abstract trigger-CSR accesses.
#
#   Registers:
#     x5  : loop counter (frozen while halted)
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
    j    end_of_test            # infinite loop (testbench ends the simulation)
