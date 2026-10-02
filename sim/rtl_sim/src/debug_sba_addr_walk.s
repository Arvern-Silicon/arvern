#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_sba_addr_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: System Bus Access address walk (walking ones / zeros inside
#   the mapped SRAMs, sbaddress0 auto-increment, unmapped address)
#   The debugger (the .v) halts the hart at `wait`, performs the whole SBA
#   walk, writes x29 = 1 and resumes. The firmware then reads two of the
#   SBA-written words back, proving the SBA writes reached memory at the
#   addresses the bus decoded.
#
#   Registers: x20 = [0x80008000] (expect 0xDA5A25A5 = addr ^ 0x5A5AA5A5),
#   x21 = [0x81000004] (expect 0xDB5AA5A1), x29 release flag,
#   x31 sync (11111111 = waiting, deadbeef = done).
#----------------------------------------------------------------------------

.section .text
.global main

.option norvc

main:
    li   x29, 0
    li   x20, 0
    li   x21, 0
    li   x31, 0x11111111
wait:
    beq  x29, x0, wait

    li   t0, 0x80008000
    lw   x20, 0(t0)
    li   t0, 0x81000004
    lw   x21, 0(t0)
    or   x22, x20, x21             # consume both loads before the final sync

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
