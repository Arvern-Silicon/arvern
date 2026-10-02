#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dpc_value_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: dpc walking-one / walking-zero values over abstract access
#   The debugger (the .v) halts the hart at `wait`, walks dpc through
#   walking-one and walking-zero values, restores the saved dpc, writes
#   x29 = 1 and resumes. Reaching deadbeef proves the restored dpc resumed
#   the hart at the right place.
#
#   Registers: x18 sentinel (0xA5A5A5A5), x29 release flag,
#   x31 sync (11111111 = waiting, deadbeef = done).
#----------------------------------------------------------------------------

.section .text
.global main

.option norvc

main:
    li   x18, 0xA5A5A5A5
    li   x29, 0
    li   x31, 0x11111111
wait:
    beq  x29, x0, wait

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
