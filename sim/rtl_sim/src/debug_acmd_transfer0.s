#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_acmd_transfer0
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Access Register command with transfer=0 is a LEGAL NO-OP
#   (Debug Spec 1.0: with transfer=0 the DM must not perform the register
#   transfer, and the command must still complete with cmderr=0).
#   The hart spins in a counted loop. The testbench halts it, primes data0 with
#   garbage and issues an Access Register command with transfer=0 / write=1 /
#   regno=0x1005 (x5): the write must NOT land, so x5 must still hold its
#   sentinel. A control command with transfer=1 then writes x6 normally.
#
#   Registers:
#     x5  : sentinel, target of the transfer=0 no-op write (expect 0x5AFE0005
#           untouched)
#     x6  : target of the control transfer=1 write (DM injects 0xCAFE0000);
#           after resume the firmware adds 0x111 -> final 0xCAFE0111 proves the
#           control write reached the regfile AND the hart truly resumed
#     x8  : loop counter (frozen while halted)
#     x9  : loop bound
#     x18 : sentinel marker, must survive untouched  (expect 0xA5A5A5A5)
#     x31 : sync (11111111=spinning, 22222222=loop done, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x5,  0x5AFE0005        # sentinel: transfer=0 "write" must NOT change this
    li   x6,  0                 # control target, OVERWRITTEN by a transfer=1 write
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x8,  0                 # loop counter (frozen while halted)
    li   x9,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)

    li   x31, 0x11111111        # sync: about to spin (TB halts us here)
spin:
    addi x8,  x8, 1
    blt  x8,  x9, spin          # count up to the bound (paused while halted)

    addi x6,  x6, 0x111         # post-resume add => final x6 = injected + 0x111
    li   x31, 0x22222222        # sync: loop finished after resume
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)
