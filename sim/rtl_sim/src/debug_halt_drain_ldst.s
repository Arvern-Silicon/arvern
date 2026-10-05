#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_halt_drain_ldst
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: HALTED REPORTED ONLY ONCE THE LOAD/STORE STREAM HAS DRAINED
#   The firmware runs back-to-back loads and stores to SRAM; the debugger (the
#   .v) halts it repeatedly at shifting offsets. Once the hart reports halted,
#   the status must not drop before a resume request: an access issued in the
#   halt-entry cycle must have completed first. Run with SRAM wait states.
#----------------------------------------------------------------------------

.section .text
.global main
main:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw  mstatush, x0              # mstatus.MDT   = 0
    li    s0, 0x80000100
    li    s1, 0x80000000            # 0x00: stop flag, set by the debugger over SBA
    sw    x0, 0(s1)
    li    t0, 0
    li    x31, 0x11111111
loop:
    sw    t0, 0(s0)
    lw    t1, 4(s0)
    sw    t1, 8(s0)
    lw    t2, 0(s0)
    sw    t2, 12(s0)
    lw    t1, 8(s0)
    addi  t0, t0, 1
    lw    t2, 0(s1)
    beqz  t2, loop
    li    x31, 0xdeadbeef
end_of_test:
    j     end_of_test
