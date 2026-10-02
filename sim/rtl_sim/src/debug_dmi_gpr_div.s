#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_gpr_div
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DMI abstract GPR read of a DRAINING hart (drain-qualified halted)
#   Discriminating companion to debug_dmi_gpr: that test's firmware is a single-
#   cycle loop (always already drained), so it cannot prove that an abstract GPR
#   read waits for an in-flight multi-cycle op to retire. Here the hart spins in a
#   loop whose body is a SLOW 33-cycle radix-2 DIVIDE writing the destination
#   register x9. The testbench halts mid-loop (an in-flight divide present) and
#   abstract-reads x9.
#
#   Drain-qualification property under test: dmstatus.allhalted must only assert
#   AFTER the in-flight divide writes back, so the abstract read returns the
#   COMPLETED quotient. x9 is pre-loaded with a distinctive POISON value
#   (0xDEAD0000) before the loop; if drain-qualification were broken, halting
#   mid-divide would expose the destination register's STALE pre-divide value and
#   the abstract read would return the poison instead of the quotient.
#
#   Divide: 0x09CCFF16 / 0x0000000D = 0x00C0FFEE (exact, remainder 0). The
#   quotient 0x00C0FFEE is distinct from the poison 0xDEAD0000, the dividend, and
#   the divisor, so a stale read is unmistakable.
#
#   Registers:
#     x9  : divide destination (poison 0xDEAD0000 -> quotient 0x00C0FFEE)
#     x18 : dividend  0x09CCFF16
#     x11 : divisor   0x0000000D
#     x8  : loop counter i
#     x6  : loop bound
#     x20 : post-divide marker, set after the loop  (expect 0x0000D09E)
#     x31 : sync (11111111=spinning in div loop, 22222222=loop done, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x9,  0xDEAD0000        # POISON: divide destination pre-value (stale-read marker)
    li   x20, 0                 # post-divide marker
    li   x18, 0x09CCFF16        # dividend
    li   x11, 0x0000000D        # divisor  (0x09CCFF16 / 0xD = 0x00C0FFEE, remainder 0)
    li   x8,  0                 # loop counter i
    li   x6,  0x00000040        # loop bound (64 iterations -> wide mid-DIV halt window)

    li   x31, 0x11111111        # sync: about to spin in the divide loop (TB halts here)
spin:
    div  x9,  x18, x11          # 33-cycle op; must drain before allhalted asserts
    addi x8,  x8,  1
    blt  x8,  x6, spin          # keep a divide in flight across the halt window

    li   x20, 0x0000D09E        # reached only after a real resume completes the loop
    li   x31, 0x22222222        # sync: loop finished after resume
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)
