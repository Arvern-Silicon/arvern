#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_reset_vector
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: reset-vector read-only CSR (0xFFE).
#
#   aRVern exposes the integrator-driven reset vector through an internal
#   read-only custom CSR at 0xFFE, so firmware can discover its own reset PC.
#   This CSR is internal (always present, independent of CCSR_EN/NMI_EN).
#
#   The firmware reads it twice (CSR readback + a PC-relative auipc at the
#   reset entry) and stores both so the TB can check the CSR value matches the
#   driven reset_vector_i and the actual reset PC.
#
# SRAM scratchpad (base 0x80000000):
#   0x00: reset_vector CSR (0xFFE) read-back  (expect = driven reset vector)
#   0x04: auipc-derived reset PC              (expect = same)
#----------------------------------------------------------------------------

.section .text
.global main

main:
reset_entry:
    auipc t1, 0                 # t1 = PC of the reset entry = reset vector
    j _start

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Read the reset-vector CSR (0xFFE).
    csrr t0, 0xffe
    sw   t0, 0x00(s1)

    # Store the auipc-derived reset PC for cross-check.
    sw   t1, 0x04(s1)
    lw   t0, 0x04(s1)           # load-back fence

    li   x31, 0x11111111

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
