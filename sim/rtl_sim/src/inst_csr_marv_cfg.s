#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_marv_cfg
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: marv_cfg (0xFFF) -- build-configuration discovery CSR
#
#   Firmware only reads the register and publishes it; the testbench does the
#   work, checking every field against the ELABORATED parameters. That is the
#   point of the test: a field wired to the wrong parameter, or left at zero,
#   is invisible to any check that compares the register against a constant.
#
#   Also covers:
#     - mimpid is now a pure version register ({major,minor,patch,reserved});
#       none of the configuration remains in it.
#     - marv_cfg is read-only: a write must not change it.
#
# Scratchpad (base 0x80000000):
#   0x00 marv_cfg   0x04 mimpid   0x08 marv_cfg after an attempted write
#----------------------------------------------------------------------------

.equ MARV_CFG, 0xFFF
.equ MIMPID,   0xF13

.section .text
.global main

main:
    j _start

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    sw   x0, 0x08(s1)

    csrr t0, MARV_CFG
    sw   t0, 0x00(s1)

    csrr t1, MIMPID
    sw   t1, 0x04(s1)

    # marv_cfg sits at a read-only CSR address ([11:10]=11), so a write must
    # raise illegal-instruction rather than land. mtvec points at a handler
    # that simply skips the offending instruction.
    la   t2, m_handler
    csrw mtvec, t2
    csrw 0x310, x0             # MDT=0 so the illegal-instruction trap is ordinary
    csrsi 0x744, 8             # NMIE=1: a trap in M with NMIE=0 is a double trap

    li   t2, 0xFFFFFFFF
    csrw MARV_CFG, t2          # must trap; must NOT modify the register

    csrr t0, MARV_CFG
    sw   t0, 0x08(s1)          # must still equal the value read at 0x00
    lw   zero, 0x08(s1)        # fence: drain before the sync

    li   x31, 0xdeadbeef
1:  j 1b

    #=================================================================
    # Trap handler: step over the faulting instruction and continue.
    #=================================================================
    .align 2
m_handler:
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
