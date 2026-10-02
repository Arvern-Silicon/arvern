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
#   Expected readback (strict WARL):
#     - implemented codes 0x00-0x12: read back verbatim (bits[31:5] zero)
#     - unimplemented codes 0x13-0x1F: fold to 0x00000000 on write
#
#   Scratchpad layout (base 0x80000000):
#   0x00 + i*4: readback_i for event code i (i=0..31)
#   (word index 0..31, 128 bytes total)
#
#   Second sweep, every selector mhpmevent3..10 (0x323 + n): write 0x0F,
#   0x10, 0x12 (read back verbatim), 0x13, 0x80000001 (fold to 0), 0 (0).
#   Provided selectors (n < ZIHPM_NR) follow the table in
#   arvern_instructions.md; unprovided ones read 0 whatever is written
#   (spec_compliance_notes.md: read-only zero, not absent).
#   Results: 0x80000100 + 0x20*n + 4*step (steps 0..5).
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

# CSR addresses
.equ MHPMEVENT3,    0x323
.equ MCOUNTINHIBIT, 0x320

# Write/read-back sequence for selector \csr; results at 0(s3)..20(s3)
.macro SEL_SEQ csr
    li   t0, 0x0F
    csrw \csr, t0
    csrr t0, \csr
    sw   t0, 0(s3)
    li   t0, 0x10
    csrw \csr, t0
    csrr t0, \csr
    sw   t0, 4(s3)
    li   t0, 0x12
    csrw \csr, t0
    csrr t0, \csr
    sw   t0, 8(s3)
    li   t0, 0x13
    csrw \csr, t0
    csrr t0, \csr
    sw   t0, 12(s3)
    li   t0, 0x80000001
    csrw \csr, t0
    csrr t0, \csr
    sw   t0, 16(s3)
    csrw \csr, x0
    csrr t0, \csr
    sw   t0, 20(s3)
    addi s3, s3, 0x20
.endm


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

    #=================================================================
    # Every selector mhpmevent3..10 (inhibited while written)
    #=================================================================
    li   t0, 0x7F8                   # mcountinhibit bits 3..10
    csrrs x0, MCOUNTINHIBIT, t0
    li   s3, 0x80000100
    SEL_SEQ 0x323
    SEL_SEQ 0x324
    SEL_SEQ 0x325
    SEL_SEQ 0x326
    SEL_SEQ 0x327
    SEL_SEQ 0x328
    SEL_SEQ 0x329
    SEL_SEQ 0x32A
    lw   t3, -4(s3)                  # AHB fence
    li   t0, 0x7F8
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
