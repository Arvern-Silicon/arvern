#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_bus_err_pin_edge
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: data-bus RNMI vs an nmi_i pin edge around its delivery
#   Each round, sw zero, 0(zero) takes an AHB ERROR (bus-error RNMI) and the
#   testbench raises the nmi_i pin k = round cycles (0..11) after the error.
#   Both sources must be delivered exactly once per round, in either order:
#   one RNMI with mncause 0x80000003 and one with 0x80000002. The handler asks
#   the testbench to drop the pin (a5 = 1) when it services a pin RNMI.
#
#   Scratchpad (base 0x80000000):
#     0x100 + id*8 : w0 bus-error RNMIs, w1 pin RNMIs   (0x10 bus, 0x14 pin: current round)
#----------------------------------------------------------------------------

.equ SBASE,          0x80000000
.equ MNCAUSE,        0x742

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j _start

    .align 2
nmi_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    sw   t2, 0x04(t0)
    csrr t1, MNCAUSE
    li   t2, 0x80000002
    bne  t1, t2, 1f
    lw   t1, 0x14(t0)               # pin
    addi t1, t1, 1
    sw   t1, 0x14(t0)
    li   a5, 1                      # ask the testbench to drop nmi_i
    li   t1, 20
2:
    addi t1, t1, -1
    bnez t1, 2b
    li   a5, 0
    j    3f
1:
    lw   t1, 0x10(t0)               # bus error (or anything else)
    addi t1, t1, 1
    sw   t1, 0x10(t0)
    li   t1, 0x5
    csrw 0x7FE, t1                  # marv_estat W1C
3:
    lw   zero, 0x14(t0)
    lw   t1, 0x00(t0)
    lw   t2, 0x04(t0)
    csrr t0, mscratch
    .word 0x70200073                # mnret

.macro ROUND id
    li   s1, SBASE
    sw   zero, 0x10(s1)
    sw   zero, 0x14(s1)
    lw   zero, 0x14(s1)
    li   a2, \id                    # round id for the testbench
    sw   zero, 0(zero)              # AHB ERROR -> bus-error RNMI
    li   t0, 60
99:
    addi t0, t0, -1
    bnez t0, 99b
    lw   t0, 0x10(s1)
    sw   t0, 0x100 + \id*8(s1)
    lw   t0, 0x14(s1)
    sw   t0, 0x104 + \id*8(s1)
    lw   zero, 0x104 + \id*8(s1)
.endm

_start:
    li   sp, 0x80010000
    la   t0, nmi_handler
    csrw 0x7FD, t0                  # marv_nmvec
    csrsi 0x744, 8                  # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0              # ...then MDT=0
    li   a5, 0
    li   a2, 0xFF

    li   x31, 0x11111111            # Sync: configured

    ROUND 0
    ROUND 1
    ROUND 2
    ROUND 3
    ROUND 4
    ROUND 5
    ROUND 6
    ROUND 7
    ROUND 8
    ROUND 9
    ROUND 10
    ROUND 11

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
