#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_resumeack_clear
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: dmcontrol.resumereq CLEARS THE RESUME ACK EVEN WHEN NOT HALTED
#   The firmware spins; the debugger (the .v) halts and resumes the hart, then
#   writes resumereq again while the hart runs. Debug 1.0 dmcontrol.resumereq:
#   "It also clears the resume ack bit for those harts" -- the resume itself is
#   ignored by a running hart, the ack clear is not.
#----------------------------------------------------------------------------

.section .text
.global main
main:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw  mstatush, x0              # mstatus.MDT   = 0
    li    x31, 0x11111111
    li    t1, 0x80000000
spin:
    lw    t0, 0(t1)
    beqz  t0, spin
    li    x31, 0xdeadbeef
end_of_test:
    j     end_of_test
