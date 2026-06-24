#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_no_event
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM NO-EVENT / RESERVED
#   Verifies that event selector 0x00 (disabled) and reserved selectors
#   0x13 and 0x1F keep the counter frozen even when other events fire.
#
#   Three phases, each with 7 taken branches:
#   Phase 1 — mhpmevent3 = 0x00 (no event): expects counter3 = 0
#   Phase 2 — mhpmevent3 = 0x13 (reserved): expects counter3 = 0
#   Phase 3 — mhpmevent3 = 0x1F (reserved): expects counter3 = 0
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_disabled_count   — counter3 with event 0x00 (expect 0)
#   0x04: p2_reserved13_count — counter3 with event 0x13 (expect 0)
#   0x08: p3_reserved1f_count — counter3 with event 0x1F (expect 0)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MHPMEVENT3,    0x323
.equ MHPMCOUNTER3,  0xB03


#=======================================================================
# MACRO: COUNT_BRANCHES_WITH_EVENT
# Configures mhpmevent3 = \event_code, opens a counting window,
# executes 7 taken branches, closes the window, reads the counter,
# and stores the result at \spad_offset(s1).
#
# Expected result is always 0 (event disabled or reserved).
#=======================================================================
.macro COUNT_BRANCHES_WITH_EVENT event_code, spad_offset

    # Set event selector
    li   t0, \event_code
    csrw MHPMEVENT3, t0

    # Zero counter3
    csrw MHPMCOUNTER3, x0

    # Set inhibit
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Clear inhibit — counting window opens
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    # Execute exactly 7 taken branches (countdown loop: 8 → 1)
    li   t0, 8
1:  addi t0, t0, -1
    bne  t0, x0, 1b              # taken 7 times, not-taken 1 time (exit)

    # Close counting window
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Read and store result (inhibit active)
    csrr t0, MHPMCOUNTER3
    sw   t0, \spad_offset(s1)
    lw   t3, \spad_offset(s1)    # AHB fence

    # Clear inhibit
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

.endm


main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad result words
    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    sw   x0, 0x08(s1)
    lw   t3, 0x08(s1)                # AHB fence


    #=================================================================
    # PHASE 1: event selector 0x00 (no event / disabled)
    # Counter must stay at 0 regardless of branch activity.
    #=================================================================
    COUNT_BRANCHES_WITH_EVENT 0x00, 0x00

    li   x31, 0x11111111             # Sync: phase 1 done


    #=================================================================
    # PHASE 2: event selector 0x13 (reserved — frozen like 0x00)
    #=================================================================
    COUNT_BRANCHES_WITH_EVENT 0x13, 0x04

    li   x31, 0x22222222             # Sync: phase 2 done


    #=================================================================
    # PHASE 3: event selector 0x1F (reserved — frozen like 0x00)
    #=================================================================
    COUNT_BRANCHES_WITH_EVENT 0x1F, 0x08

    # Restore mhpmevent3 to 0x00 (disabled) after test
    csrw MHPMEVENT3, x0

    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
