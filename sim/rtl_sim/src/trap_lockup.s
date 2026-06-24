#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_lockup
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: LOCKUP
#   Lockup state verification:
#   - Exception from M-mode context -> enters M-mode handler
#   - Second exception inside M-mode handler (in_m_excp_trap=1)
#   -> go_to_lockup fires -> in_lockup=1 -> fetch permanently stalled
#   - Verifies lockup_o is asserted and CPU is frozen
#
#   Scratchpad layout (base 0x80000000):
#   0x000: m_trap_count   (expect 1: handler entered once before lockup)
#   0x004: last MCAUSE    (expect 2: illegal instruction)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    # Entered on first illegal instruction from M-mode.
    # Increments m_trap_count, saves MCAUSE, then executes a second
    # illegal instruction which triggers go_to_lockup -> in_lockup=1.
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)

    # Increment M-mode trap count
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Save MCAUSE (expect 2 = illegal instruction)
    csrr t1, mcause
    sw   t1, 0x04(s1)

    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16

    # Second illegal instruction while in M-mode exception handler.
    # in_m_excp_trap=1 -> go_to_lockup=1 -> in_lockup=1 -> fetch stalled.
    .word 0xFFFFFFFF

    mret                       # Never reached

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)          # m_trap_count
    sw   t0, 0x04(s1)          # last MCAUSE

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    li   x31, 0x11111111       # Sync: init done, trap handler installed

    # Trigger first M-mode exception from M-mode context.
    # -> m_trap_handler entered, in_m_excp_trap set.
    # -> handler executes second .word 0xFFFFFFFF -> lockup.
    .word 0xFFFFFFFF

    # Never reached: CPU is stalled in lockup state.
end_of_test:
    j    end_of_test
