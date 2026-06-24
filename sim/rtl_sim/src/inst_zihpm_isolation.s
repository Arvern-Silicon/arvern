#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_isolation
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM COUNTER ISOLATION
#   Verifies that two HPM counters with different event selectors count
#   independently — no cross-wiring between event mux outputs.
#
#   counter3 = event 0x05 (branch-taken)    → expect 7
#   counter4 = event 0x06 (branch-not-taken) → expect 5
#
#   Branch sequence (both counting windows open simultaneously):
#   Countdown loop: li t0,8; addi t0,t0,-1; bne t0,x0,loop
#   — BNE taken 7 times (t0=7..1), not-taken 1 time (t0=0, loop exit)
#   Then 4 guaranteed not-taken branches: bne x0,x0,target (always false)
#   Total: taken=7, not-taken=1+4=5.
#
#   Requires: ZIHPM_NR >= 2
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: taken_count    — counter3 (branch-taken, event 0x05), expect 7
#   0x04: nottaken_count — counter4 (branch-not-taken, event 0x06), expect 5
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MHPMEVENT3,    0x323
.equ MHPMEVENT4,    0x324
.equ MHPMCOUNTER3,  0xB03
.equ MHPMCOUNTER4,  0xB04

# mcountinhibit bits
.equ INH3,  0x8       # bit 3: counter3
.equ INH4,  0x10      # bit 4: counter4
.equ INH34, 0x18      # bits 3+4: both counters


main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad result words
    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    lw   t3, 0x04(s1)                # AHB fence


    #=================================================================
    # Configure counter3 = branch-taken (0x05)
    #=================================================================
    li   t0, 5
    csrw MHPMEVENT3, t0

    # Configure counter4 = branch-not-taken (0x06)
    li   t0, 6
    csrw MHPMEVENT4, t0

    # Zero both counters
    csrw MHPMCOUNTER3, x0
    csrw MHPMCOUNTER4, x0

    # Inhibit both counters
    li   t0, INH34
    csrrs x0, MCOUNTINHIBIT, t0

    # Clear inhibit on both — counting window opens for both simultaneously
    li   t0, INH34
    csrrc x0, MCOUNTINHIBIT, t0


    #=================================================================
    # Branch sequence: 7 taken + 5 not-taken (counted simultaneously)
    #
    # Step A: countdown loop — 7 taken, 1 not-taken (exit)
    #=================================================================
    li   t0, 8
branch_loop:
    addi t0, t0, -1
    bne  t0, x0, branch_loop        # taken 7x (t0=7..1), not-taken 1x (t0=0)

    # Step B: 4 more not-taken branches (bne x0, x0 is always not-taken)
    bne  x0, x0, branch_nt_skip     # NOT taken (x0==x0, condition false)
    bne  x0, x0, branch_nt_skip     # NOT taken
    bne  x0, x0, branch_nt_skip     # NOT taken
    bne  x0, x0, branch_nt_skip     # NOT taken
branch_nt_skip:
    # Total: 7 taken, 1+4=5 not-taken

    #=================================================================
    # Close counting windows simultaneously
    #=================================================================
    li   t0, INH34
    csrrs x0, MCOUNTINHIBIT, t0

    #=================================================================
    # Read and store both counter results (inhibit active)
    #=================================================================
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x00(s1)               # taken_count
    csrr t0, MHPMCOUNTER4
    sw   t0, 0x04(s1)               # nottaken_count
    lw   t3, 0x04(s1)               # AHB fence

    # Clear inhibit
    li   t0, INH34
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
