#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_haltsum0
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: haltsum0 (DM 0x40) with the hart running, halted, held in
#   ndmreset and halted out of reset
#   debug_interface.md §6: "0x40 haltsum0 RO Halt Summary 0 (Debug Spec 1.0):
#   bit 0 = this hart halted; bits [31:1] = 0."
#   Debug 1.0 3.14.18: "Unavailable/nonexistent harts are not considered to
#   be halted."
#
#   The firmware clears a release flag in SRAM, then spins storing a counter
#   until the flag becomes non-zero. SRAM survives the ndmreset of the test,
#   so after the reset-halt the debugger releases the loop by an SBA write of
#   the flag while the hart runs.
#
#   SRAM: 0x80000100 release flag (written by SBA), 0x80000104 loop counter.
#   Registers: s1 SRAM base, t1 loop counter, x31 sync
#   (11111111 = spinning, deadbeef = done).
#----------------------------------------------------------------------------

.section .text
.global main

.option norvc

main:
    li   s1, 0x80000000
    sw   zero, 0x100(s1)          # release flag = 0
    li   t1, 0
    li   x31, 0x11111111
spin:
    addi t1, t1, 1
    sw   t1, 0x104(s1)            # posted store in the loop: exercises the halt drain
    lw   t0, 0x100(s1)
    beq  t0, x0, spin

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
