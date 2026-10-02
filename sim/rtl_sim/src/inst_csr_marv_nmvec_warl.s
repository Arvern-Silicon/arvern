#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_marv_nmvec_warl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: marv_nmvec (0x7FD) -- RNMI vector CSR
#
#   PHASE A  reset value is reset_vector + 4, the slot right after the reset
#            entry, ahead of mtvec (+8) and stvec (+12). Firmware reads
#            reset_vector from CSR 0xFFE and the
#            vector from 0x7FD, and the testbench checks the relationship --
#            so the test does not hardcode a link address.
#
#   PHASE B  the RESET value is actually USED. marv_nmvec is deliberately NOT
#            written; the RNMI must land at reset_vector+4, where this file
#            places `j rnmi_handler`. Every other RNMI test writes the CSR
#            first, so nothing else covers the untouched-vector case.
#
#   PHASE C  WARL: full 32-bit round trip, and [1:0] read back as zero.
#
#   PHASE D  a WRITTEN vector relocates delivery -- the second RNMI lands in a
#            different handler.
#
#   The reset-region layout this relies on is the documented convention:
#       reset_vector +0 reset entry  +4 RNMI  +8 mtvec  +12 stvec
#
# Scratchpad (base 0x80000000):
#   0x00 marv_nmvec at reset   0x04 reset_vector    0x08 readback after write
#   0x0C readback of a misaligned write             0x10 handler-A entries
#   0x14 handler-B entries     0x18 alt handler address
#----------------------------------------------------------------------------

.equ MARV_NMVEC,   0x7FD
.equ RESET_VECTOR, 0xFFE
.equ MNSTATUS,     0x744

.section .text
.global main

main:
    # 4-byte slots regardless of -march (a c.j would halve them)
    .option push
    .option norvc
    j _start                   # reset_vector + 0
    j rnmi_handler             # reset_vector + 4   (marv_nmvec resets here)
    j m_handler                # reset_vector + 8   (mtvec resets here)
    j m_handler                # reset_vector + 12  (stvec resets here)
    .option pop

    #=================================================================
    # Handlers
    #=================================================================
    .align 2
m_handler:
    mret                       # not exercised; present so the slot is valid

    .align 2
rnmi_handler:
    lw   t0, 0x10(s1)
    addi t0, t0, 1
    sw   t0, 0x10(s1)
    .word 0x70200073           # mnret

    .align 2
alt_rnmi_handler:
    lw   t0, 0x14(s1)
    addi t0, t0, 1
    sw   t0, 0x14(s1)
    .word 0x70200073           # mnret

    #=================================================================
    # MAIN
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    sw   x0, 0x08(s1)
    sw   x0, 0x0C(s1)
    sw   x0, 0x10(s1)
    sw   x0, 0x14(s1)
    sw   x0, 0x18(s1)

    #--- PHASE A: reset value, read BEFORE anything writes it -------
    csrr t0, MARV_NMVEC
    sw   t0, 0x00(s1)
    csrr t1, RESET_VECTOR
    sw   t1, 0x04(s1)

    la   t0, alt_rnmi_handler
    sw   t0, 0x18(s1)          # published so the testbench can check phase D
    lw   zero, 0x18(s1)        # fence: drain the posted stores before the sync

    csrsi MNSTATUS, 8          # NMIE = 1 so an RNMI can be delivered

    li   x31, 0x11111111       # Sync: reset value captured; TB fires RNMI #1

    #--- PHASE B: the untouched vector must be used ------------------
    # marv_nmvec deliberately NOT written. RNMI #1 lands at reset_vector+4.
1:  lw   t0, 0x10(s1)
    beqz t0, 1b                # wait until rnmi_handler has run

    li   x31, 0x22222222       # Sync: RNMI #1 delivered via the reset vector

    #--- PHASE C: WARL round trip and alignment ---------------------
    la   t0, alt_rnmi_handler
    csrw MARV_NMVEC, t0
    csrr t1, MARV_NMVEC
    sw   t1, 0x08(s1)          # must equal alt_rnmi_handler

    ori  t0, t0, 3             # set the two low bits
    csrw MARV_NMVEC, t0
    csrr t1, MARV_NMVEC
    sw   t1, 0x0C(s1)          # [1:0] must read back zero
    lw   zero, 0x0C(s1)        # fence: the sync must not overtake the posted store

    li   x31, 0x33333333       # Sync: TB fires RNMI #2

    #--- PHASE D: the written vector relocates delivery --------------
2:  lw   t0, 0x14(s1)
    beqz t0, 2b                # wait until alt_rnmi_handler has run

    li   x31, 0xdeadbeef
3:  j 3b
