#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_csr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DMI abstract CSR access (Debug Module, Access Register command)
#   The hart spins in a counted loop in M-mode. The testbench halts it over the
#   DMI bus (frozen-hart), then uses the Debug Module's abstract "Access
#   Register" command to READ/WRITE CSRs (regno = the 12-bit CSR address) of the
#   frozen hart while it sits in Debug Mode. GPR abstract access is covered by
#   debug_dmi_gpr; this test exercises the CSR routing of the same command.
#
#   The firmware never touches mscratch itself: the testbench abstract-writes
#   mscratch=0xC5A17E5C while halted, and after resume the firmware reads it back
#   (csrr mscratch -> x20). x20 == 0xC5A17E5C proves the DM write truly landed in
#   the architectural mscratch CSR (the strongest end-to-end check) AND that the
#   hart actually resumed and executed.
#
#   Registers:
#     x5  : loop counter (frozen while halted)                 (t0)
#     x6  : loop bound
#     x18 : sentinel marker, must survive untouched (expect 0xA5A5A5A5)
#     x20 : mscratch read back after resume         (expect 0xC5A17E5C)
#     x31 : sync (11111111=spinning, 22222222=read back, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x20, 0                 # will hold the post-resume mscratch read-back
    li   x5,  0                 # loop counter (frozen while halted)
    li   x6,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)

    li   x31, 0x11111111        # sync: about to spin (TB halts us here)
spin:
    addi x5,  x5, 1
    blt  x5,  x6, spin          # count up to the bound (paused while halted)

    # --- after resume: read the DM-written mscratch out of the architectural CSR ---
    csrr x20, mscratch          # x20 = mscratch (the value the DM injected while halted)
    li   x31, 0x22222222        # sync: mscratch read back
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)
