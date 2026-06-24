#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_mpp_forced_m
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SU_MODE PRIV - mstatus.MPP hardwired to M under SU_MODE_EN=0
#   With only M-mode advertised, mstatus.MPP[12:11] is hardwired to 2'b11.
#   Any attempt to write 00/01/10 must read back as 11.
#
#   Phase 2: read mstatus at reset; MPP must already be 2'b11.
#   Phase 3: csrrc mstatus, 0x1800 (clear MPP) -> MPP still 2'b11.
#   Phase 4: csrrw mstatus with MPP field=00     -> MPP still 2'b11.
#   Phase 5: csrrw mstatus with MPP field=01     -> MPP still 2'b11.
#
#   No traps expected throughout.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count (expect 0)
#   0x04: last MCAUSE
#
# Phase captures:
#   0x20: mstatus at reset                (expect MPP=11)
#   0x24: mstatus after csrrc MPP=0x1800  (expect MPP=11)
#   0x28: mstatus after csrrw MPP=00      (expect MPP=11)
#   0x2C: mstatus after csrrw MPP=01      (expect MPP=11)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER (defensive)
    #=================================================================
    .align 2

trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    csrr t0, mcause
    csrr t1, mepc

    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)
    sw   t0, 0x04(s1)

    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Initialize callee-saved registers (RV32E-safe markers in x0-x15)
    li   s0, 0xAAAAAAAA
    li   a0, 0xBBBBBBBB
    li   a1, 0xCCCCCCCC
    li   a2, 0xDDDDDDDD
    li   a3, 0xEEEEEEEE

    li   a5, 0x11111111


    #=================================================================
    # PHASE 2: Read mstatus at reset; MPP must already be 11
    #=================================================================

    csrr t0, mstatus
    sw   t0, 0x20(s1)
    lw   t0, 0x20(s1)         # load-back fence

    li   a5, 0x22222222


    #=================================================================
    # PHASE 3: csrrc mstatus, 0x1800 (clear MPP)
    #          MPP forced to M => still 11 after the clear.
    #=================================================================

    li   t1, 0x1800            # MPP mask
    csrrc t0, mstatus, t1
    csrr t0, mstatus           # re-read fresh value
    sw   t0, 0x24(s1)
    lw   t0, 0x24(s1)

    li   a5, 0x33333333


    #=================================================================
    # PHASE 4: csrrw mstatus with MPP=00
    #          Build full-write image: clear MPP bits in [12:11], keep
    #          MIE/MPIE/MPRV-safe defaults; verify MPP reads back as 11.
    #=================================================================

    csrr t0, mstatus           # current value
    li   t1, ~0x1800           # mask out MPP bits
    and  t0, t0, t1            # MPP -> 00 in the write image
    csrw mstatus, t0           # full overwrite (csrrw alias)
    csrr t0, mstatus
    sw   t0, 0x28(s1)
    lw   t0, 0x28(s1)

    li   a5, 0x44444444


    #=================================================================
    # PHASE 5: csrrw mstatus with MPP=01
    #          Build write image with MPP=01 (S-mode); core must force 11.
    #=================================================================

    csrr t0, mstatus
    li   t1, ~0x1800
    and  t0, t0, t1            # clear MPP
    li   t1, 0x0800            # set bit 11 only -> MPP=01
    or   t0, t0, t1
    csrw mstatus, t0
    csrr t0, mstatus
    sw   t0, 0x2C(s1)
    lw   t0, 0x2C(s1)

    li   a5, 0xdeadbeef


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
