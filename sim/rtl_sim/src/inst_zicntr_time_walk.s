#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_time_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MTIME walking-ones write, read back through time/timeh and MMIO
#
#   Priv 3.1.11: "The time CSR is a read-only shadow of the memory-mapped mtime
#   register. [...] When XLEN=32, the timeh CSR is a read-only shadow of the
#   upper 32 bits of the memory-mapped mtime register".
#   ACLINT MTIMER: MTIME is a 64-bit read-write register (see
#   inst_zicntr_aclint_mtime_write).
#   doc/software_guide.md (FENCE and memory-mapped registers): "The drain makes
#   a store to a memory-mapped register visible to a subsequent read of a CSR
#   that aliases it -- sw to ACLINT MTIME followed by csrr time, for instance."
#   doc/integration_guide.md: "A +-1-tick read uncertainty is architecturally
#   fine -- time only requires a monotonic wall clock."
#
#   For k = 0..63, MTIME is written with 1<<k (HI first, then LO), a bare FENCE
#   drains the stores, then:
#     - time/timeh read with the timeh / time / timeh retry idiom
#       (doc/software_guide.md, "64-bit read pattern")
#     - MTIME read back over MMIO with the same idiom
#   MTIME keeps counting, so the bench checks each value as a window: never
#   below 1<<k, at most a small drift above it, and MMIO (read later) never
#   below the CSR value. Walking ZEROS is not used: a low half near 0xFFFFFFFF
#   would carry into the high half within the drift window.
#
#   After k = 63, MTIME is written back to 0 (HI = 0 first, then LO = 0,
#   FENCE): timeh must drop back to 0 -- bit 63 cleared again (ACLINT: MTIME is
#   "a 64-bit read-write register"). Stored as step k = 64.
#
#   Scratchpad (0x80000100 + 16*k, k = 0..64):
#     +0 time   +4 timeh   +8 MTIME_LO (MMIO)   +12 MTIME_HI (MMIO)
#
#   Interrupts stay disabled (mie = 0): large MTIME values raise MTIP.
#
# Requires ZICNTR_EN == 1 (the bench routes the time port to the ACLINT).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ ACLINT_MTIME_LO, 0x0200BFF8
.equ ACLINT_MTIME_HI, 0x0200BFFC
.equ RES_BASE,        0x80000100

main:
    j _start

_start:
    li   sp, 0x80010000
    csrci mstatus, 8
    csrw mie, zero

    li   s1, RES_BASE
    li   s2, 0                      # k
    li   s3, 64
    li   s4, 1
    li   s5, ACLINT_MTIME_LO
    li   s6, ACLINT_MTIME_HI

    li   x31, 0x11111111            # Sync: start

step:
    li   t0, 32
    bgeu s2, t0, high_half
    sll  a2, s4, s2                 # lo = 1 << k
    li   a3, 0
    j    write
high_half:
    li   a2, 0
    sll  a3, s4, s2                 # hi = 1 << (k - 32): sll uses rs2[4:0]
write:
    sw   a3, 0(s6)                  # HI first
    sw   a2, 0(s5)                  # then LO
    fence

read_csr:
    csrr t2, timeh
    csrr t3, time
    csrr t4, timeh
    bne  t2, t4, read_csr

read_mmio:
    lw   t5, 0(s6)
    lw   a0, 0(s5)
    lw   a1, 0(s6)
    bne  t5, a1, read_mmio

    sw   t3,  0(s1)
    sw   t2,  4(s1)
    sw   a0,  8(s1)
    sw   t5, 12(s1)

    addi s1, s1, 16
    addi s2, s2, 1
    bne  s2, s3, step

    # k = 64: clear bit 63 again -- MTIME back to 0
    sw   zero, 0(s6)                # HI first
    sw   zero, 0(s5)                # then LO
    fence
read_csr0:
    csrr t2, timeh
    csrr t3, time
    csrr t4, timeh
    bne  t2, t4, read_csr0
read_mmio0:
    lw   t5, 0(s6)
    lw   a0, 0(s5)
    lw   a1, 0(s6)
    bne  t5, a1, read_mmio0
    sw   t3,  0(s1)
    sw   t2,  4(s1)
    sw   a0,  8(s1)
    sw   t5, 12(s1)
    addi s1, s1, 16

    lw   zero, -4(s1)               # last result store has landed
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
