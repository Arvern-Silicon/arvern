#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_aclint_time
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Zicntr time CSR routed through ACLINT's Zicntr port
#   The arvern core's time_req_o / time_gnt_i / time_val_i side-band port
#   is wired to the ACLINT (use_aclint=1 in the TB). A `csrr time` then
#   delivers MTIME directly from the ACLINT instead of the legacy
#   randomised TB mtime model.
#
#   Test: read time twice with a delay between, verify it is non-zero and
#         strictly increasing (mtime ticks on the always-on LF clock).
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad
#   0x00: t0_lo
#   0x04: t0_hi
#   0x08: t1_lo
#   0x0C: t1_hi
#=========================================================================

main:
    j _start

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)

    # First time read (LO-then-HI is the canonical RV32 sequence)
read_t0:
    csrr t0, timeh                  # snapshot high half first
    csrr t1, time                   # then low half
    csrr t2, timeh                  # high again; retry if it changed
    bne  t0, t2, read_t0

    sw   t1, 0x00(s1)               # t0_lo
    sw   t0, 0x04(s1)               # t0_hi

    li   x31, 0x11111111            # signal: first sample taken

    # Delay long enough for time to advance
    li   t5, 256
delay:
    addi t5, t5, -1
    bnez t5, delay

    # Second time read
read_t1:
    csrr t3, timeh
    csrr t4, time
    csrr t5, timeh
    bne  t3, t5, read_t1

    sw   t4, 0x08(s1)               # t1_lo
    sw   t3, 0x0C(s1)               # t1_hi

    li   x31, 0xdeadbeef
    j end_of_test

end_of_test:
    nop
    j end_of_test
