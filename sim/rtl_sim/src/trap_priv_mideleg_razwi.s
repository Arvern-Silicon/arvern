#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_mideleg_razwi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SU_MODE PRIV - mideleg/medeleg RAZ/WI under SU_MODE_EN=0
#   With S+U disabled, the delegation registers must accept no writes.
#   Per spec deviation #2 (RAZ/WI in known banks): neither access traps.
#
#   Phase 2: write 0xFFFFFFFF to mideleg (0x303), read back -> expect 0.
#   Phase 3: write 0xFFFFFFFF to medeleg (0x302), read back -> expect 0.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count (must remain 0)
#   0x04: last MCAUSE
#
# Phase 2 capture:
#   0x20: mideleg readback after writing 0xFFFFFFFF (expect 0)
#
# Phase 3 capture:
#   0x30: medeleg readback after writing 0xFFFFFFFF (expect 0)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER (defensive; not expected to fire)
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
    sw   t0, 0x30(s1)

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
    # PHASE 2: mideleg (0x303) RAZ/WI
    #=================================================================

    li   t1, 0xFFFFFFFF
    csrw 0x303, t1             # mideleg
    csrr t0, 0x303
    sw   t0, 0x20(s1)
    lw   t0, 0x20(s1)         # load-back fence

    li   a5, 0x22222222


    #=================================================================
    # PHASE 3: medeleg (0x302) RAZ/WI
    #=================================================================

    li   t1, 0xFFFFFFFF
    csrw 0x302, t1             # medeleg
    csrr t0, 0x302
    sw   t0, 0x30(s1)
    lw   t0, 0x30(s1)         # load-back fence

    li   a5, 0xdeadbeef


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
