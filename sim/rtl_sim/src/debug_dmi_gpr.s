#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_gpr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DMI abstract GPR access (Debug Module, Access Register command)
#   The hart spins in a counted loop. The testbench halts it over the DMI bus
#   (frozen-hart), then uses the Debug Module's abstract "Access Register"
#   command to READ x18 and to WRITE x20 directly from/to the register file
#   while the hart is halted.
#
#   READ : x18 carries a known sentinel (0xA5A5A5A5); the abstract read must
#          return exactly that value via data0.
#   WRITE: x20 starts at 0; the TB injects 0xCAFE0000 via an abstract write
#          while halted. After resume the firmware adds 0x123 to x20, so the
#          final x20 = 0xCAFE0123 proves BOTH the injected write reached the
#          register file AND the hart actually resumed and executed.
#
#   Registers:
#     x5  : loop counter (frozen while halted)                 (t0)
#     x6  : loop bound
#     x18 : sentinel to be READ over DMI   (expect 0xA5A5A5A5)
#     x20 : value injected over DMI, then +0x123 after resume  (expect 0xCAFE0123)
#     x31 : sync (11111111=spinning, 22222222=loop done, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # sentinel to be read back over the DMI abstract cmd
    li   x20, 0                 # pre-value, will be OVERWRITTEN by an abstract write
    li   x5,  0                 # loop counter (frozen while halted)
    li   x6,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)

    li   x31, 0x11111111        # sync: about to spin (TB halts us here)
spin:
    addi x5,  x5, 1
    blt  x5,  x6, spin          # count up to the bound (paused while halted)

    addi x20, x20, 0x123        # post-resume add => final x20 = injected + 0x123
    li   x31, 0x22222222        # sync: loop finished after resume
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)
