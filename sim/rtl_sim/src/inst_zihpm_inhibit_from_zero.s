#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_inhibit_from_zero
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM INHIBIT FROM ZERO
#   Verifies that mcountinhibit correctly gates counting from a zero
#   baseline:
#
#   Phase 1 — inhibit active + counter zeroed + 7 branch-taken events:
#   counter3 must remain exactly 0.
#   Phase 2 — inhibit cleared + counter zeroed + 7 branch-taken events:
#   counter3 must equal exactly 7.
#
#   This directly tests the RTL gate:
#   hpm_count_en = hpm_event_pulse & ~hpm_inhibit_live
#
#   Branch counting: li t0, 8 + bnez loop gives 7 taken (t0=8..2) +
#   1 not-taken exit (t0=0). Only bnez counts as a branch.
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_inhibited_count  — counter3 after 7 branches with inhibit on
#   (expect 0)
#   0x04: p2_running_count    — counter3 after 7 branches with inhibit off
#   (expect 7)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MHPMEVENT3,    0x323
.equ MHPMCOUNTER3,  0xB03

# mcountinhibit bit for counter3
.equ HPM3_BIT,      0x8

# branch-taken event selector
.equ EVT_BRANCH_TAKEN, 0x05


main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad result words
    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    lw   t3, 0x04(s1)                # AHB fence


    #=================================================================
    # PHASE 1: inhibit active, counter zeroed from 0, then 7 branch-taken
    # Expected: counter3 stays exactly 0
    #=================================================================

    # Step 1a: configure event selector for branch-taken
    li   t0, EVT_BRANCH_TAKEN
    csrw MHPMEVENT3, t0

    # Step 1b: inhibit counter3
    li   t0, HPM3_BIT
    csrrs x0, MCOUNTINHIBIT, t0

    # Step 1c: zero counter3 (while inhibited — clean baseline)
    csrw MHPMCOUNTER3, x0

    # Step 1d: 7 branch-taken events with inhibit ON
    # li t0, 8 + bnez loop: t0=8..2 → bnez taken (7 times), t0=0 → not taken (exit)
    li   t0, 8
p1_loop:
    addi t0, t0, -1
    bnez t0, p1_loop                 # taken 7 times, exits on t0=0

    # Read and store counter3 (must still be 0)
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x00(s1)                # p1_inhibited_count
    lw   t3, 0x00(s1)                # AHB fence

    li   x31, 0x11111111             # Sync: phase 1 done


    #=================================================================
    # PHASE 2: clear inhibit, re-zero counter, 7 branch-taken events
    # Expected: counter3 == 7
    #=================================================================

    # Step 2a: zero counter3 (still inhibited — clean baseline)
    csrw MHPMCOUNTER3, x0

    # Step 2b: clear inhibit — counting now active
    li   t0, HPM3_BIT
    csrrc x0, MCOUNTINHIBIT, t0

    # Step 2c: 7 branch-taken events with inhibit OFF
    li   t0, 8
p2_loop:
    addi t0, t0, -1
    bnez t0, p2_loop                 # taken 7 times, exits on t0=0

    # Read and store counter3 (must be 7)
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x04(s1)                # p2_running_count
    lw   t3, 0x04(s1)                # AHB fence

    # Cleanup: disable event, zero counter
    csrw MHPMEVENT3, x0
    csrw MHPMCOUNTER3, x0

    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
