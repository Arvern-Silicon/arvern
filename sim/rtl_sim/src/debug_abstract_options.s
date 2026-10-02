#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_abstract_options
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Access Register option fields (aarpostincrement streams,
#   transfer=0, postexec, aarsize, reserved bit, cmdtype, time/timeh)
#   The firmware parks sentinels in x5..x7 and x10..x17 and waits for the
#   debugger (the .v), which exercises the abstract command options while
#   the hart is halted, sets x29 = 1 and resumes.
#
#   Registers: x5 0x55550005, x6 0x66660006, x7 0x77770007,
#   x10..x17 0xA0A000nn (nn = register number), x29 release flag,
#   x31 sync (11111111 = waiting, deadbeef = done).
#----------------------------------------------------------------------------

.section .text
.global main

.option norvc

main:
    li   x5,  0x55550005
    li   x6,  0x66660006
    li   x7,  0x77770007
    li   x10, 0xA0A0000A
    li   x11, 0xA0A0000B
    li   x12, 0xA0A0000C
    li   x13, 0xA0A0000D
    li   x14, 0xA0A0000E
    li   x15, 0xA0A0000F
    li   x16, 0xA0A00010
    li   x17, 0xA0A00011
    li   x29, 0
    li   x31, 0x11111111
wait:
    beq  x29, x0, wait

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
