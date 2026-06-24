#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_warl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM WARL
#   Verifies the WARL (Write-Any-Read-Legal) properties of HPM CSRs:
#
#   Phase 1 — mhpmevent3: write 0xFFFFFFFF, expect readback = 0x1F
#   (only 5-bit field [4:0] is implemented; upper bits are 0)
#   Phase 2 — mhpmevent3 reserved: write 0x13, readback = 0x13
#   write 0x1F, readback = 0x1F
#   (reserved codes stored as-is; counter just stays frozen)
#   Phase 3 — mcountinhibit: write 0xFFFFFFFF, readback has only bits
#   [2+ZIHPM_NR:3] set (HPM_WARL_MASK); all other bits are 0.
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_event_ff   — mhpmevent3 readback after writing 0xFFFFFFFF
#   (expect 0x1F)
#   0x04: p2_event_13   — mhpmevent3 readback after writing 0x13
#   (expect 0x13)
#   0x08: p2_event_1f   — mhpmevent3 readback after writing 0x1F
#   (expect 0x1F)
#   0x0C: p3_inhibit_ff — mcountinhibit readback after writing 0xFFFFFFFF
#   (expect bits outside [10:3] = 0; within = MASK)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MHPMEVENT3,    0x323


main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad result words
    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    sw   x0, 0x08(s1)
    sw   x0, 0x0C(s1)
    lw   t3, 0x0C(s1)                # AHB fence


    #=================================================================
    # PHASE 1: mhpmevent3 WARL — only 5 bits [4:0] are implemented
    # Write all-ones; readback must be 0x1F (upper bits discarded).
    #=================================================================
    li   t0, -1                      # 0xFFFFFFFF
    csrw MHPMEVENT3, t0
    csrr t0, MHPMEVENT3
    sw   t0, 0x00(s1)                # p1_event_ff
    lw   t3, 0x00(s1)                # AHB fence

    li   x31, 0x11111111             # Sync: phase 1 done


    #=================================================================
    # PHASE 2: mhpmevent3 reserved-code write/readback
    # Reserved codes 0x13 and 0x1F are stored as-is in the 5-bit field
    # (they just select hpm_event_pulse=0, keeping the counter frozen).
    #=================================================================

    # Write 0x13 (reserved), read back
    li   t0, 0x13
    csrw MHPMEVENT3, t0
    csrr t0, MHPMEVENT3
    sw   t0, 0x04(s1)                # p2_event_13
    lw   t3, 0x04(s1)                # AHB fence

    # Write 0x1F (reserved), read back
    li   t0, 0x1F
    csrw MHPMEVENT3, t0
    csrr t0, MHPMEVENT3
    sw   t0, 0x08(s1)                # p2_event_1f
    lw   t3, 0x08(s1)                # AHB fence

    li   x31, 0x22222222             # Sync: phase 2 done


    #=================================================================
    # PHASE 3: mcountinhibit WARL — only bits [10:3] are writable, and
    # only the ZIHPM_NR lower bits within that range are implemented.
    # Write all-ones; bits outside the HPM_WARL_MASK must read as 0.
    #=================================================================
    li   t0, -1                      # 0xFFFFFFFF
    csrw MCOUNTINHIBIT, t0
    csrr t0, MCOUNTINHIBIT
    sw   t0, 0x0C(s1)                # p3_inhibit_ff
    lw   t3, 0x0C(s1)                # AHB fence

    # Restore mcountinhibit to 0 (all counters running)
    csrw MCOUNTINHIBIT, x0

    # Restore mhpmevent3 to 0x00 (disabled)
    csrw MHPMEVENT3, x0

    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
