#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_step_fault_target
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: single-step of a jalr into unmapped memory (see the .v)
#   The hart spins on a self-jalr; the testbench halts it, points x12 at the
#   unmapped address 0 and steps. The handler records the fault and returns to
#   the end of the test.
#----------------------------------------------------------------------------

.equ MSTATUSH,        0x310
.equ MNSTATUS,        0x744

.include "firmware_config.inc"

.section .text
.global main
main:
    j    _start

.option push
.option norvc
    .align 2
m_handler:
    csrr x20, mcause
    csrr x22, mepc
    addi x23, x23, 1
    la   x9, done
    csrw mepc, x9
    mret
.option pop

_start:
    li   x20, 0
    li   x22, 0xFFFFFFFF
    li   x23, 0

    la   x10, m_handler
    csrw mtvec, x10
    csrsi MNSTATUS, 8           # mnstatus.NMIE = 1 first ...
    csrw  MSTATUSH, x0          # ... then MDT = 0

    la   x12, spin_self         # jalr base = self -> spin; TB rewrites x12 to 0

    li   x31, 0x11111111        # sync: spinning
spin_self:
    jalr x0, 0(x12)

done:
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
