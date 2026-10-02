#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_critical_error
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: debugging a hart in the Smdbltrp critical-error state
#
#   Reached from the RESET state: mnstatus.NMIE resets to 0 and is
#   software-set-only, so a hart that takes an M-mode trap before arming it
#   hits an unexpected trap on its FIRST trap. This is the failure mode real
#   firmware is most likely to meet, and no handler ever runs.
#
#   Everything interesting happens in the testbench afterwards, over the DMI:
#   dcsr.cetrig is 0, so the hart must assert lockup_o and NOT enter Debug
#   Mode by itself. The debugger must still be able to halt it, read the
#   post-mortem, and resume it back into the same state.
#
# Scratchpad (base 0x80000000):
#   0x00 handler_entries -- must stay 0, the M handler must never run
#   0x0C written ONLY if execution wrongly continued past the trap
#   0x10 PC of the faulting instruction, for the dpc comparison
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # M TRAP HANDLER -- must never be entered.
    #=================================================================
    .align 2
m_handler:
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)
    mret

    #=================================================================
    # MAIN
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   x0, 0x00(s1)
    sw   x0, 0x0C(s1)
    sw   x0, 0x10(s1)

    la   t0, m_handler
    csrw mtvec, t0

    # mnstatus.NMIE deliberately left at its reset value of 0, so the ECALL
    # below is an unexpected trap with no RNMI handler to divert to.

    la   t0, h_fault_pc
    sw   t0, 0x10(s1)          # publish the PC that will fault, for the dpc check

    li   x31, 0x11111111       # Sync: about to provoke the critical error

h_fault_pc:
    ecall                      # unexpected trap (NMIE=0) -> critical error

    # Unreachable. If the core kept going, this store is the evidence.
    li   t0, 0xBAD
    sw   t0, 0x0C(s1)
1:  j 1b
