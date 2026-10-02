#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_instret_write
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: minstret right after a CSR write to it
#   Priv 3.1.11: "Any CSR write takes effect after the writing instruction has
#   otherwise completed." The writing instruction is not counted; every
#   instruction after it is. csrw minstret, X ; k NOPs ; csrr -> X + k.
#   Last probe: minstreth = 5, minstret = 0xFFFFFFFF, one NOP -> 6 : 0x0.
#
#   Scratchpad (base 0x80000000): 0x00 + 4*k = read-back of probe k,
#   0x10 minstret / 0x14 minstreth of the carry probe
#----------------------------------------------------------------------------

.equ SBASE,          0x80000000

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j _start

.macro PROBE k
    li   t1, 0x1000
    csrw minstret, t1
    .rept \k
    nop
    .endr
    csrr t2, minstret
    sw   t2, \k * 4(s1)
.endm

_start:
    li   s1, SBASE
    li   x31, 0x11111111            # Sync: start

    PROBE 0
    PROBE 1
    PROBE 2
    PROBE 3

    li   t1, 5
    csrw minstreth, t1
    li   t1, 0xFFFFFFFF
    csrw minstret, t1
    nop
    csrr t2, minstret
    csrr t3, minstreth
    sw   t2, 0x10(s1)
    sw   t3, 0x14(s1)

    lw   zero, 0x14(s1)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
