#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_sba_alias_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: System Bus Access over the high address bits (bench SRAM alias)
#   The debugger (the .v) halts the hart at `wait`, walks sbaddress0 over
#   address bits 12..30 through the bench executable-SRAM alias, writes
#   x29 = 1 and resumes. The firmware then reads [0x80000800], the word the
#   last aliased SBA write landed on.
#
#   Registers: x20 = [0x80000800], x29 release flag,
#   x31 sync (11111111 = waiting, deadbeef = done).
#----------------------------------------------------------------------------

.section .text
.global main

.option norvc

main:
    li   x29, 0
    li   x20, 0
    li   x31, 0x11111111
wait:
    beq  x29, x0, wait

    li   t0, 0x80000800
    lw   x20, 0(t0)
    addi x21, x20, 0               # consume the load before the final sync

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
