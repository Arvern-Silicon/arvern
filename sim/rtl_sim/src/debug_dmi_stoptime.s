#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_stoptime
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DMI dcsr.stoptime drives the dbg_stoptime SoC pin (Debug Spec 1.0)
#   The hart spins in a counted loop in M-mode. The testbench halts it over the
#   DMI bus (frozen-hart) and toggles dcsr.stoptime (bit 9) via the Debug Module
#   abstract "Access Register" command, observing the external pin dbg_stoptime_o
#   (TB wire dbg_stoptime), which is (in Debug Mode) & dcsr.stoptime. There is no
#   internal time counter in this core; stoptime only exports the freeze request.
#
#   The firmware is a passive spinner; the whole experiment runs from the .v.
#   Reaching 0xdeadbeef after resume proves the hart resumed and ran (dcsr.prv was
#   preserved by the read-modify-write, so it returns to M-mode).
#
#   Registers:
#     x5  : loop counter (frozen while halted)                 (t0)
#     x6  : loop bound
#     x18 : sentinel marker, must survive untouched (expect 0xA5A5A5A5)
#     x31 : sync (11111111=spinning, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x5,  0                 # loop counter (frozen while halted)
    li   x6,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)

    li   x31, 0x11111111        # sync: about to spin (TB halts us here)
spin:
    addi x5,  x5, 1
    blt  x5,  x6, spin          # count up to the bound (paused while halted)

    # --- after resume: the hart simply finishes and signals done ---
    li   x31, 0xdeadbeef        # final sync: test done (proves resume executed)
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)
