#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_branch
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT BRANCH
#   Tests HPM counter event selectors for branch events.  Both phases
#   execute the SAME instruction sequence:
#   - 7 taken branches  (countdown loop: li t0,8 + bnez, taken 7×)
#   - 5 not-taken branches (1 loop-exit not-taken + 4 forward bne x0,x0)
#
#   Phase 1 — mhpmevent3 = 0x05 (branch-taken): counter3 must equal 7.
#   Negative check: not-taken events do NOT increment this counter.
#   Phase 2 — mhpmevent3 = 0x06 (branch-not-taken): counter3 must equal 5.
#   Negative check: taken events do NOT increment this counter.
#
#   The 4 explicit not-taken branches each use their own forward label so
#   that an accidentally-taken branch (RTL bug) lands on the immediately
#   next instruction rather than skipping the remaining branches.
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_taken_count    — counter3 after mixed seq with event 0x05
#   (expect 7; non-7 means taken/not-taken leak)
#   0x04: p2_nottaken_count — counter3 after mixed seq with event 0x06
#   (expect 5; non-5 means taken/not-taken leak)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MHPMEVENT3,    0x323
.equ MHPMCOUNTER3,  0xB03

# mcountinhibit bit for counter3
.equ HPM3_BIT, 0x8


main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad result words
    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    lw   t3, 0x04(s1)                # AHB fence


    #=================================================================
    # PHASE 1: mhpmevent3 = 0x05 (branch-taken)
    # Execute 7 taken + 5 not-taken branches.
    # Expected: counter3 = 7  (negative: not-taken events must NOT count)
    #=================================================================
    li   t0, 5
    csrw MHPMEVENT3, t0              # event = branch-taken (0x05)
    csrw MHPMCOUNTER3, x0            # zero counter3

    li   t0, HPM3_BIT
    csrrs x0, MCOUNTINHIBIT, t0      # ensure inhibit set before window
    li   t0, HPM3_BIT
    csrrc x0, MCOUNTINHIBIT, t0      # open counting window

    # --- 7 taken branches ---
    # Countdown loop: t0=8..2 → bne taken (7×); t0=0 → bne not-taken (exit, 1×)
    li   t0, 8
p1_taken_loop:
    addi t0, t0, -1
    bne  t0, x0, p1_taken_loop       # taken 7 times, not-taken 1 time (exit)

    # --- 4 additional not-taken branches (total not-taken = 5) ---
    # Each branch has its own forward label (next instruction).
    # If accidentally taken, execution lands on the next branch — no skip.
    bne  x0, x0, p1_nt1              # not-taken (0 != 0 is false)
p1_nt1:
    bne  x0, x0, p1_nt2              # not-taken
p1_nt2:
    bne  x0, x0, p1_nt3              # not-taken
p1_nt3:
    bne  x0, x0, p1_nt4              # not-taken
p1_nt4:

    li   t0, HPM3_BIT
    csrrs x0, MCOUNTINHIBIT, t0      # close counting window

    csrr t0, MHPMCOUNTER3
    sw   t0, 0x00(s1)                # p1_taken_count
    lw   t3, 0x00(s1)                # AHB fence

    li   t0, HPM3_BIT
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit

    li   x31, 0x11111111             # Sync: phase 1 done


    #=================================================================
    # PHASE 2: mhpmevent3 = 0x06 (branch-not-taken)
    # IDENTICAL instruction sequence: 7 taken + 5 not-taken branches.
    # Expected: counter3 = 5  (negative: taken events must NOT count)
    #=================================================================
    li   t0, 6
    csrw MHPMEVENT3, t0              # event = branch-not-taken (0x06)
    csrw MHPMCOUNTER3, x0            # zero counter3

    li   t0, HPM3_BIT
    csrrs x0, MCOUNTINHIBIT, t0      # ensure inhibit set before window
    li   t0, HPM3_BIT
    csrrc x0, MCOUNTINHIBIT, t0      # open counting window

    # --- 7 taken branches (same as phase 1) ---
    li   t0, 8
p2_taken_loop:
    addi t0, t0, -1
    bne  t0, x0, p2_taken_loop       # taken 7 times, not-taken 1 time (exit)

    # --- 4 additional not-taken branches (same pattern as phase 1) ---
    bne  x0, x0, p2_nt1              # not-taken
p2_nt1:
    bne  x0, x0, p2_nt2              # not-taken
p2_nt2:
    bne  x0, x0, p2_nt3              # not-taken
p2_nt3:
    bne  x0, x0, p2_nt4              # not-taken
p2_nt4:

    li   t0, HPM3_BIT
    csrrs x0, MCOUNTINHIBIT, t0      # close counting window

    csrr t0, MHPMCOUNTER3
    sw   t0, 0x04(s1)                # p2_nottaken_count
    lw   t3, 0x04(s1)                # AHB fence

    li   t0, HPM3_BIT
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit

    # Cleanup: disable event selector, zero counter
    csrw MHPMEVENT3, x0
    csrw MHPMCOUNTER3, x0

    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
