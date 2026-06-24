#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_store
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT STORE
#   Tests HPM counter event selector for store dispatched event:
#   Phase 1 — mhpmevent3 = 0x08 (store): expects counter3 = 6
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_store_count — counter3 after 6 store instructions (expect 6)
#   0x10-0x24: scratch area used by the 6 store instructions
#
#   Note: The counter is inhibited before reading and storing the result,
#   so the "sw t0, 0x00(s1)" that saves the count does NOT fire the store
#   event.  The 6 stores to offsets 0x10-0x24 are the only counted stores.
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320

main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad word 0x00 (result slot)
    sw   x0, 0x00(s1)
    lw   t3, 0x00(s1)                # AHB fence


    #=================================================================
    # PHASE 1: store-dispatched event (mhpmevent3 = 0x08)
    # Execute exactly 6 sw instructions between inhibit clear and
    # inhibit set.  Then inhibit counter BEFORE reading/storing the
    # result so those memory operations do not count.
    # Stores go to offsets 0x10-0x24 to avoid clobbering the result
    # slot at 0x00.
    #=================================================================

    # Set mhpmevent3 = 0x08 (store dispatched)
    li   t0, 8
    csrw 0x323, t0

    # Zero counter3
    csrw 0xB03, x0

    # Set inhibit bit for counter3 (bit 3 = 0x8)
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Clear inhibit — counting window opens
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    # Execute exactly 6 store instructions (to scratch area 0x10-0x24)
    sw   x0, 0x10(s1)
    sw   x0, 0x14(s1)
    sw   x0, 0x18(s1)
    sw   x0, 0x1C(s1)
    sw   x0, 0x20(s1)
    sw   x0, 0x24(s1)

    # Close counting window immediately after 6th store
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Read and store counter3 result with inhibit active (no store event fired)
    csrr t0, 0xB03
    sw   t0, 0x00(s1)
    lw   t3, 0x00(s1)               # AHB fence

    # Clear inhibit
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0xdeadbeef            # Sync: all done

end_of_test:
    j    end_of_test
