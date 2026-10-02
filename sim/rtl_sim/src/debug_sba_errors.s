#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_sba_errors
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SBA error paths - sbaccess=3/4 (sberror=4, no bus access) and
#   sbbusyerror (Debug 1.0 sbcs)
#   The testbench drives every SBA access while the hart is halted in `wait`
#   (see debug_sba_errors.v). After the debugger releases x29, the firmware
#   reads back two words the debugger wrote to the non-executable SRAM, as a
#   cross-check that SBA writes after the error recovery reached memory.
#
#   Registers: x20 = [NX+0x10], x21 = [NX+0x00], x29 release flag,
#   x31 sync (11111111 = waiting for the debugger, deadbeef = done).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ NX_BASE, 0x81000000

.section .text
.global main

main:
    li   x20, 0
    li   x21, 0
    li   x29, 0
    li   x31, 0x11111111
wait:
    beq  x29, x0, wait
    li   t0, NX_BASE
    lw   x20, 0x10(t0)
    lw   x21, 0x00(t0)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
