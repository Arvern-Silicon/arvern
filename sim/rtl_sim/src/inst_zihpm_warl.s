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
#   Phase 1 — mhpmevent3: write implemented 0x12, expect readback =
#   0x00000012 (implemented selectors 0x00-0x12 are stored verbatim in
#   the 5-bit field [4:0]; bits [31:5] always read 0). Then write
#   0xFFFFFF12: ANY write with bits set above [4:0] is an unimplemented
#   value and folds to 0x00000000 (strict WARL), even though [4:0]
#   holds an implemented code.
#   Phase 2 — mhpmevent3 unimplemented: write 0x13, readback = 0x00000000
#   write 0x1F, readback = 0x00000000
#   (unimplemented selectors fold to 0 (strict WARL))
#   Phase 3 — mcountinhibit: write 0xFFFFFFFF, readback has only bits
#   [2+ZIHPM_NR:3] set (HPM_WARL_MASK); all other bits are 0.
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_event_12   — mhpmevent3 readback after writing 0x12
#   (expect 0x00000012)
#   0x04: p1_event_ff12 — mhpmevent3 readback after writing 0xFFFFFF12
#   (expect 0x00000000)
#   0x08: p2_event_13   — mhpmevent3 readback after writing 0x13
#   (expect 0x00000000)
#   0x0C: p2_event_1f   — mhpmevent3 readback after writing 0x1F
#   (expect 0x00000000)
#   0x10: p3_inhibit_ff — mcountinhibit readback after writing 0xFFFFFFFF
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
    sw   x0, 0x10(s1)
    lw   t3, 0x10(s1)                # AHB fence


    #=================================================================
    # PHASE 1: mhpmevent3 WARL — only 5 bits [4:0] are implemented.
    # 1a: write implemented selector 0x12 cleanly; readback must be
    #     exactly 0x00000012 (implemented selectors stored verbatim,
    #     bits [31:5] read 0).
    # 1b: write 0xFFFFFF12 (garbage upper bits + implemented [4:0]);
    #     ANY write with bits set above [4:0] is an unimplemented
    #     value and folds to 0x00000000 (strict WARL).
    #=================================================================
    li   t0, 0x12
    csrw MHPMEVENT3, t0
    csrr t0, MHPMEVENT3
    sw   t0, 0x00(s1)                # p1_event_12
    lw   t3, 0x00(s1)                # AHB fence

    li   t0, 0xFFFFFF12
    csrw MHPMEVENT3, t0
    csrr t0, MHPMEVENT3
    sw   t0, 0x04(s1)                # p1_event_ff12
    lw   t3, 0x04(s1)                # AHB fence

    li   x31, 0x11111111             # Sync: phase 1 done


    #=================================================================
    # PHASE 2: mhpmevent3 unimplemented-selector write/readback
    # Unimplemented selectors 0x13 and 0x1F fold to 0 on write
    # (strict WARL): readback is 0x00000000, counter stays frozen.
    #=================================================================

    # Write 0x13 (unimplemented), read back
    li   t0, 0x13
    csrw MHPMEVENT3, t0
    csrr t0, MHPMEVENT3
    sw   t0, 0x08(s1)                # p2_event_13
    lw   t3, 0x08(s1)                # AHB fence

    # Write 0x1F (unimplemented), read back
    li   t0, 0x1F
    csrw MHPMEVENT3, t0
    csrr t0, MHPMEVENT3
    sw   t0, 0x0C(s1)                # p2_event_1f
    lw   t3, 0x0C(s1)                # AHB fence

    li   x31, 0x22222222             # Sync: phase 2 done


    #=================================================================
    # PHASE 3: mcountinhibit WARL — only bits [10:3] are writable, and
    # only the ZIHPM_NR lower bits within that range are implemented.
    # Write all-ones; bits outside the HPM_WARL_MASK must read as 0.
    #=================================================================
    li   t0, -1                      # 0xFFFFFFFF
    csrw MCOUNTINHIBIT, t0
    csrr t0, MCOUNTINHIBIT
    sw   t0, 0x10(s1)                # p3_inhibit_ff
    lw   t3, 0x10(s1)                # AHB fence

    # Restore mcountinhibit to 0 (all counters running)
    csrw MCOUNTINHIBIT, x0

    # Restore mhpmevent3 to 0x00 (disabled)
    csrw MHPMEVENT3, x0

    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
