#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmstatus_drain
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: dmstatus during the halt-entry drain (see the .v)
#   The hart loops on back-to-back divides and stores, so a halt request lands
#   while a multi-cycle operation or a posted store is still draining.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main
main:
    j    _start

_start:
    li   s1, 0x80000000
    li   a1, 0x7FFFFFFF
    li   a2, 3
    li   x31, 0x11111111        # sync: looping
loop:
.if CFG_M_EXTENSION >= 2
    div  a0, a1, a2
    divu a3, a1, a2
.else
    addi a0, a1, 1
    addi a3, a1, 2
.endif
    sw   a0, 0(s1)
    sw   a3, 4(s1)
    addi a4, a4, 1
    j    loop
