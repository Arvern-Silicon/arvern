#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_selector_rw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT SELECTOR READ/WRITE
#   Sweeps all 32 mhpmevent3 codes (0x00-0x1F) with write/readback.
#   Each code is written to mhpmevent3 (0x323) and read back.
#   Expected readback: code[4:0] only (bits[31:5] must be zero).
#
#   Scratchpad layout (base 0x80000000):
#   0x00 + i*4: readback_i for event code i (i=0..31)
#   (word index 0..31, 128 bytes total)
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MHPMEVENT3,    0x323
.equ MCOUNTINHIBIT, 0x320


main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero 32 scratchpad words (codes 0x00-0x1F)
    li   t0, 32
    li   t2, 0x80000000
zero_loop:
    sw   x0, 0(t2)
    addi t2, t2, 4
    addi t0, t0, -1
    bnez t0, zero_loop

    # Inhibit counter3 during the sweep (not counting, just write/readback)
    li   t0, 0x8                     # mcountinhibit bit 3
    csrrs x0, MCOUNTINHIBIT, t0

    #=================================================================
    # Sweep: write code i to mhpmevent3, read back, store to spad[i]
    # Loop: s2 = current code (0..31), s3 = scratchpad pointer
    #=================================================================
    li   s2, 0                       # s2 = code
    li   s3, 0x80000000              # s3 = &spad[0]

sweep_loop:
    csrw MHPMEVENT3, s2              # write code
    csrr t0, MHPMEVENT3              # read back
    sw   t0, 0(s3)                   # store readback
    lw   t3, 0(s3)                   # AHB fence
    addi s2, s2, 1
    addi s3, s3, 4
    li   t0, 32
    blt  s2, t0, sweep_loop

    # Restore: clear mhpmevent3 and release inhibit
    csrw MHPMEVENT3, x0
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
