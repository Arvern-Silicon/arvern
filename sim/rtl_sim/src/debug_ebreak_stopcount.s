#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_ebreak_stopcount
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: minstret around an ebreak that enters Debug Mode (see the .v)
#   Each pass: wait for the debugger's release (x29), read minstret, ebreak (32-bit,
#   pinned), read minstret, store the difference. x31 sync: 11111111 pass 1 ready,
#   22222222 pass 2 ready, deadbeef done.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ SBASE, 0x80000000

.section .text
.global main
main:
    j    _start

.macro PASS slot, sync
    li   x29, 0
    li   x31, \sync
1:  beqz x29, 1b                    # wait for the debugger
    .option push
    .option norvc
    la   s6, 2f
    csrr a0, minstret
2:  .word 0x00100073                # ebreak (32-bit)
    csrr a1, minstret
    .option pop
    sub  a2, a1, a0
    li   s1, SBASE
    sw   a2, \slot(s1)
.endm

_start:
    PASS 0, 0x11111111
    PASS 4, 0x22222222
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
