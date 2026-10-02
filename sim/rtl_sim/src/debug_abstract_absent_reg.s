#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_abstract_absent_reg
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: abstract Access Register on registers the hart does not have
#   The testbench halts the spinning hart and accesses dscratch0/1 and x16
#   (see the .v). x0-x15 only, x15 (a5) sync, so it also runs on RV32E.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main
main:
    j    _start

_start:
    li   a5, 0x11111111        # sync: spinning
spin:
    addi a4, a4, 1
    j    spin
