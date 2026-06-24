#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_no_delegation
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SU_MODE PRIV - Trap delegation inert under SU_MODE_EN=0
#   Under SU_MODE_EN=0, mideleg/medeleg are RAZ/WI; even firmware that
#   attempts to delegate cannot redirect traps to S-mode. Verify by:
#     - writing 0xFFFFFFFF to mideleg (silently ignored, reads 0)
#     - asserting timer IRQ
#     - confirming the M-mode handler (at mtvec) runs (not stvec)
#       and mcause = 0x80000007 (Machine Timer Interrupt)
#
#   Phase 2: deleg-write + timer IRQ -> M-mode handler runs, mcause MTI.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count          (incremented by handler)
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x10: trap_handled flag   (set to 1 by handler)
#
# Phase 2 captures:
#   0x20: mideleg readback after write 0xFFFFFFFF (expect 0)
#   0x24: trap_count after IRQ (expect 1)
#   0x28: MCAUSE              (expect 0x80000007)
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER (at mtvec)
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
    sw   t1, 0x08(s1)

    # Disable MIE.MTIE so the IRQ does not immediately re-fire after MRET.
    li   t2, 0x80              # MIE.MTIE = bit 7
    csrc mie, t2

    # Set trap_handled flag
    li   t2, 1
    sw   t2, 0x10(s1)
    lw   t2, 0x10(s1)         # load-back fence

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
    sw   t0, 0x08(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)

    # Install M-mode trap handler
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
    # PHASE 2: Attempt to delegate, then take a timer IRQ.
    #=================================================================

    # Try to delegate ALL interrupts AND exceptions to S-mode.
    li   t0, 0xFFFFFFFF
    csrw 0x303, t0             # mideleg -- silently dropped (RAZ/WI)
    li   t0, 0xFFFFFFFF
    csrw 0x302, t0             # medeleg -- silently dropped

    # Snapshot mideleg readback (expect 0)
    csrr t0, 0x303
    sw   t0, 0x20(s1)
    lw   t0, 0x20(s1)         # load-back fence

    # Enable MIE.MTIE (bit 7)
    li   t0, 0x80
    csrs mie, t0

    # Enable MSTATUS.MIE (bit 3)
    li   t0, 0x8
    csrs mstatus, t0

    # Clear handled flag
    sw   zero, 0x10(s1)
    lw   t0, 0x10(s1)         # load-back

    # Signal: TB should now assert irq_m_timer
    li   a5, 0x21212121

    # Spin-wait for handler to set trap_handled flag
wait_trap:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap

    # Snapshot final results
    lw   t0, 0x00(s1)
    sw   t0, 0x24(s1)          # trap_count
    lw   t0, 0x04(s1)
    sw   t0, 0x28(s1)          # MCAUSE
    lw   t0, 0x28(s1)         # load-back fence

    li   a5, 0xdeadbeef


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
