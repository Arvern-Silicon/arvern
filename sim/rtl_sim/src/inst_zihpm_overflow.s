#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_overflow
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM OVERFLOW
#   Zihpm HPM counter 64-bit overflow and CSR write/readback verification:
#   Phase 1 — mhpmcounterh3 write and readback
#   Phase 2 — hpmcounterh3 (shadow) reflects mhpmcounterh3 when inhibited
#   Phase 3 — 64-bit counter overflow: lo wraps to 0, hi increments to 1
#
#   Scratchpad layout (base 0x80000000):
#   0x00: phase1_hi_rb      — mhpmcounterh3 readback (expect 0xABCDEF12)
#   0x04: phase2_shadow_rb  — hpmcounterh3 shadow readback (expect
#   0x12345678)
#   0x08: phase3_hi_after   — mhpmcounterh3 after overflow (expect 1)
#   0x0C: phase3_lo_after   — mhpmcounter3  after overflow (expect 0)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT,  0x320
.equ MHPMCOUNTER3,   0xB03
.equ MHPMCOUNTERH3,  0xB83
.equ MHPMEVENT3,     0x323
.equ HPMCOUNTERH3,   0xC83

# mcountinhibit bit for counter 3 (bit 3)
.equ INHIBIT_CTR3,   0x8


main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad (0x00 - 0x0C)
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)


    #===================================================================
    # PHASE 1: mhpmcounterh3 write and readback
    # Write 0xABCDEF12, read back, store to scratchpad[0x00]
    #===================================================================
    li   t0, 0xABCDEF12
    csrw MHPMCOUNTERH3, t0           # write hi word
    csrr t0, MHPMCOUNTERH3           # read back
    sw   t0, 0x00(s1)                # phase1_hi_rb
    lw   t3, 0x00(s1)                # AHB fence

    li   x31, 0x11111111             # Sync: Phase 1 done


    #===================================================================
    # PHASE 2: hpmcounterh3 shadow reflects mhpmcounterh3
    # Write 0x12345678 to mhpmcounterh3, inhibit counter3,
    # then read hpmcounterh3 (U-mode shadow) — must match.
    #===================================================================
    li   t0, 0x12345678
    csrw MHPMCOUNTERH3, t0           # set hi word to known value

    # Inhibit counter3 to freeze it before reading shadow
    li   t0, INHIBIT_CTR3
    csrrs x0, MCOUNTINHIBIT, t0

    csrr t0, HPMCOUNTERH3            # read U-mode shadow (0xC83)
    sw   t0, 0x04(s1)                # phase2_shadow_rb
    lw   t3, 0x04(s1)                # AHB fence

    # Clear inhibit
    li   t0, INHIBIT_CTR3
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0x22222222             # Sync: Phase 2 done


    #===================================================================
    # PHASE 3: 64-bit overflow
    # Set mhpmevent3 = 5 (branch-taken), preset lo=0xFFFFFFFF hi=0,
    # execute exactly 1 taken branch, verify hi wraps to 1 and lo to 0.
    #===================================================================

    # Set event selector = 5 (branch-taken)
    li   t0, 5
    csrw MHPMEVENT3, t0

    # Inhibit counter3 while presetting the 64-bit value
    li   t0, INHIBIT_CTR3
    csrrs x0, MCOUNTINHIBIT, t0

    # Preset lo = 0xFFFFFFFF
    li   t0, -1
    csrw MHPMCOUNTER3, t0

    # Preset hi = 0
    csrw MHPMCOUNTERH3, x0

    # Clear inhibit — counter starts counting from 0xFFFFFFFF_FFFFFFFF
    li   t0, INHIBIT_CTR3
    csrrc x0, MCOUNTINHIBIT, t0

    # Execute exactly 1 taken branch:
    #   t0 = 2; first iteration: addi→1, bne taken (count); second: addi→0, bne not taken
    li   t0, 2
overflow_loop:
    addi t0, t0, -1
    bne  t0, x0, overflow_loop       # taken once (t0=2→1), not taken (t0=1→0)

    # Inhibit counter3 to freeze results
    li   t0, INHIBIT_CTR3
    csrrs x0, MCOUNTINHIBIT, t0

    csrr t0, MHPMCOUNTERH3
    sw   t0, 0x08(s1)                # phase3_hi_after (expect 1)
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x0C(s1)                # phase3_lo_after (expect 0)
    lw   t3, 0x0C(s1)                # AHB fence

    # Clear inhibit
    li   t0, INHIBIT_CTR3
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0xdeadbeef             # Sync: all done


end_of_test:
    j    end_of_test
