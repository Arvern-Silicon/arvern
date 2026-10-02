#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_cerr_hpm_event
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: the critical-error entry is not counted by the HPM exception event
#   mhpmcounter3 counts event 0x09 (exception). NMIE is never armed and MDT is
#   still 1 from reset, so the ECALL is an unexpected trap with NMIE=0: the hart
#   enters the critical-error state "without updating any architectural state"
#   (Priv 3.1.6.2). The debugger then halts it and reads mhpmcounter3: it must
#   still be 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main
main:
    j    _start

_start:
    li   t0, 0x09
    csrw 0x323, t0              # mhpmevent3 = exception
    csrw 0xB03, x0              # mhpmcounter3 = 0
    csrw 0xB83, x0              # mhpmcounter3h = 0
    li   x31, 0x11111111        # sync
    ecall                       # unexpected trap, NMIE=0 -> critical error
    li   x31, 0xBAD00BAD        # never reached
end_of_test:
    j    end_of_test
