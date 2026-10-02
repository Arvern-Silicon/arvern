#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_mstatush_warl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: mstatush (0x310) WARL surface
#
#   mstatush is a legal M-mode CSR: accesses must NOT trap, and every bit
#   currently reads 0 whatever is written. This test pins that surface so a
#   change to any individual bit is visible from both sides -- the CSR is
#   otherwise completely uncovered.
#
#   MDT (bit 10) is the Smdbltrp M-mode double-trap bit: WARL, software
#   writable, and it RESETS TO 1 (protection by default). Every other bit
#   reads 0.
#
#   Checked:
#     - the reset value is 0x800 -- read before any write touches it
#     - write all-ones  -> only MDT sticks
#     - write zero      -> MDT clears
#     - a CSRRS of all-ones sets MDT (set path, distinct from write path)
#     - no access traps (mtvec is a negative control)
#
# Scratchpad (base 0x80000000):
#   0x00 trap_count (must remain 0)   0x04 last mcause
#   0x0C mstatush reset value (read before any write)
#   0x10 mstatush after writing all-ones
#   0x14 mstatush after writing zero
#   0x18 mstatush after csrrs of all-ones
#----------------------------------------------------------------------------

.equ MSTATUSH, 0x310

.section .text
.global main

main:
    j _start

    .align 2
trap_handler:                      # NEGATIVE CONTROL -- must never run
    addi sp, sp, -8
    sw   t0, 4(sp)
    sw   t1, 0(sp)
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)
    csrr t1, mcause
    sw   t1, 0x04(s1)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    lw   t1, 0(sp)
    lw   t0, 4(sp)
    addi sp, sp, 8
    mret

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)

    la   t0, trap_handler
    csrw mtvec, t0

    #---------------------------------------------------------------
    # Reset value FIRST -- nothing above touches mstatush
    #---------------------------------------------------------------
    csrr t0, MSTATUSH
    sw   t0, 0x0C(s1)
    lw   zero, 0x0C(s1)

    li   x31, 0x11111111

    #---------------------------------------------------------------
    # Write all-ones
    #---------------------------------------------------------------
    li   t1, 0xFFFFFFFF
    csrw MSTATUSH, t1
    csrr t0, MSTATUSH
    sw   t0, 0x10(s1)
    lw   zero, 0x10(s1)

    #---------------------------------------------------------------
    # Write zero
    #---------------------------------------------------------------
    csrw MSTATUSH, x0
    csrr t0, MSTATUSH
    sw   t0, 0x14(s1)
    lw   zero, 0x14(s1)

    #---------------------------------------------------------------
    # Set-path: csrrs of all-ones
    #---------------------------------------------------------------
    li   t1, 0xFFFFFFFF
    csrs MSTATUSH, t1
    csrr t0, MSTATUSH
    sw   t0, 0x18(s1)
    lw   zero, 0x18(s1)

    li   x31, 0x22222222

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
