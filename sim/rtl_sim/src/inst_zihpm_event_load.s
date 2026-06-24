#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_load
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT LOAD
#   Tests HPM counter event selector for load dispatched event:
#   Phase 1 — mhpmevent3 = 0x07 (load): expects counter3 = 8
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_load_count — counter3 after 8 load instructions (expect 8)
#
#   Note: load-use hazards between consecutive lw instructions cause LSU
#   stalls, but the load-dispatched event (0x07) fires at decode regardless
#   of whether the load stalls. Count is still exactly 8.
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320

main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad word 0x00
    sw   x0, 0x00(s1)
    lw   t3, 0x00(s1)                # AHB fence


    #=================================================================
    # PHASE 1: load-dispatched event (mhpmevent3 = 0x07)
    # Execute exactly 8 lw instructions between inhibit clear and
    # inhibit set.  The load event fires at decode for each lw
    # regardless of load-use stalls.
    #=================================================================

    # Set mhpmevent3 = 0x07 (load dispatched)
    li   t0, 7
    csrw 0x323, t0

    # Zero counter3
    csrw 0xB03, x0

    # Set inhibit bit for counter3 (bit 3 = 0x8)
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Clear inhibit — counting window opens
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    # Execute exactly 8 load instructions
    lw   t0, 0x00(s1)
    lw   t0, 0x00(s1)
    lw   t0, 0x00(s1)
    lw   t0, 0x00(s1)
    lw   t0, 0x00(s1)
    lw   t0, 0x00(s1)
    lw   t0, 0x00(s1)
    lw   t0, 0x00(s1)

    # Close counting window immediately after 8th load
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Read and store counter3 result (inhibit active — no extra events)
    csrr t0, 0xB03
    sw   t0, 0x00(s1)
    lw   t3, 0x00(s1)               # AHB fence

    # Clear inhibit
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0xdeadbeef            # Sync: all done

end_of_test:
    j    end_of_test
