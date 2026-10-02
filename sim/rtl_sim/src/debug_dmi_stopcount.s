#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_stopcount
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DMI dcsr.stopcount freezes mcycle while halted (Debug Spec 1.0)
#   The hart spins in a counted loop in M-mode. The testbench halts it over the
#   DMI bus (frozen-hart), then drives the entire dcsr.stopcount experiment
#   purely from the testbench using the Debug Module abstract "Access Register"
#   command — the firmware itself plays no part in the freeze/advance check.
#
#   While the hart is halted in Debug Mode the testbench:
#     - sets   dcsr.stopcount (bit 10) and proves mcycle is FROZEN across a delay
#     - clears dcsr.stopcount             and proves mcycle is ADVANCING again
#   then resumes the hart. Reaching 0xdeadbeef after resume only proves the hart
#   actually resumed and ran (dcsr.prv was preserved by the read-modify-write, so
#   it returns to M-mode); the headline freeze/advance assertions live in the .v.
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
