#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_fetch
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT FETCH
#   Tests HPM counter event selector for fetch-stall event (0x01).
#
#   Phase 1 — mhpmevent3 = 0x01 (fetch stall = ~id_instruction_valid):
#   Executes 7 taken branches via a countdown loop.  The testbench injects
#   3 fixed ROM wait states (s_rom_number_ws = 3) before the counting
#   window opens, so each backward branch redirect creates at least 3
#   cycles where id_instruction_valid_o=0 (fetch stall events).
#   Expected: counter3 >= 7 (at least 1 fetch stall per taken branch).
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_fetch_count — counter3 after 7 taken branches (expect >= 7)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MHPMEVENT3,    0x323
.equ MHPMCOUNTER3,  0xB03

main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero the scratchpad word used for results
    sw   x0, 0x00(s1)
    lw   t3, 0x00(s1)                # AHB fence

    #=================================================================
    # PHASE 1: fetch-stall event (mhpmevent3 = 0x01)
    # Execute 7 taken branches via a countdown loop.
    # The testbench injects 3 fixed ROM wait states so each backward
    # branch redirect creates 3 fetch stall cycles (the branch target
    # instruction arrives 3 cycles late, leaving the decode stage
    # empty for 3 cycles per redirect).
    #=================================================================

    # Set mhpmevent3 = 0x01 (fetch stall)
    li   t0, 1
    csrw MHPMEVENT3, t0

    # Zero counter3
    csrw MHPMCOUNTER3, x0

    # Set inhibit bit for counter3 (bit 3 = 0x8)
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Clear inhibit — counting window opens
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    # Execute exactly 7 taken branches (countdown loop: 8 → 1, bne taken 7 times)
    li   t0, 8
fetch_branch_loop:
    addi t0, t0, -1
    bne  t0, x0, fetch_branch_loop   # taken 7 times (t0=7..1), not-taken once (t0=0)

    # Close counting window
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Read and store counter3 result (inhibit active — no extra events)
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x00(s1)
    lw   t3, 0x00(s1)               # AHB fence

    # Clear inhibit
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0xdeadbeef             # Sync: test done

end_of_test:
    j    end_of_test
