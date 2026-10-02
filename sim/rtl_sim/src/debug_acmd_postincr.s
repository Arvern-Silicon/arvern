#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_acmd_postincr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Access Register aarpostincrement (command bit 19) is SUPPORTED
#   The hart spins in a counted loop while the testbench acts as the debugger
#   over the DMI bus. This DM implements the OPTIONAL aarpostincrement variant of
#   the Access Register abstract command: after a successful transfer the
#   effective regno increments by 1, so combined with abstractauto.autoexecdata0
#   a debugger can STREAM consecutive GPRs by repeatedly touching data0.
#
#   The firmware's only job is to park distinctive sentinels in x5/x6/x7 so the
#   testbench can (a) stream-READ them back in order (x5,x6,x7) via post-increment
#   and (b) stream-WRITE fresh values into them in order, then spin (WFI-free) so
#   the halt is clean, and finish normally after resume. All action is
#   debugger-driven over DMI; the debug-written GPR values survive resume.
#
#   Registers:
#     x5  : first streamed register  (init 0x55555555 -> debug-written 0xA5A5A5A5)
#     x6  : second streamed register (init 0x66666666 -> debug-written 0xB6B6B6B6)
#     x7  : third streamed register  (init 0x77777777 -> debug-written 0xC7C7C7C7)
#     x8  : loop counter (frozen while halted)
#     x9  : loop bound
#     x31 : sync (11111111=spinning, 22222222=loop done, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x5,  0x55555555        # first  streamed-read sentinel
    li   x6,  0x66666666        # second streamed-read sentinel
    li   x7,  0x77777777        # third  streamed-read sentinel
    li   x8,  0                 # loop counter (frozen while halted)
    li   x9,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)

    li   x31, 0x11111111        # sync: about to spin (TB halts us here)
spin:
    addi x8,  x8, 1
    blt  x8,  x9, spin          # count up to the bound (paused while halted)

    li   x31, 0x22222222        # sync: loop finished after resume
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)
