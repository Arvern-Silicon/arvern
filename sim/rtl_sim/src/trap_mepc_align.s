#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_mepc_align
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP MEPC ALIGNMENT
#   Verify MEPC[0] is always forced to 0 for all exception types:
#   - EBREAK (4-byte instruction)
#   - C.EBREAK (2-byte compressed instruction)
#   - ECALL (4-byte instruction)
#   - Illegal instruction at 2-byte aligned address
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x0C: last MSTATUS
#   0x10: trap_handled flag
#
# Phase 2 (EBREAK - 4-byte):
#   0x20: MEPC
#
# Phase 3 (C.EBREAK - 2-byte compressed):
#   0x30: MEPC
#
# Phase 4 (ECALL - 4-byte):
#   0x40: MEPC
#
# Phase 5 (illegal instruction at 2-byte aligned):
#   0x50: MEPC
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mstatus

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Save to working area
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)

    # Check if interrupt
    bltz t0, handler_done

    # Exception path: advance MEPC past faulting instruction
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, advance_4
    addi t1, t1, 2
    j    exc_done
advance_4:
    addi t1, t1, 4
exc_done:
    csrw mepc, t1

handler_done:
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24

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
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x50(s1)

    #=================================================================
    # PHASE 1: Install trap handler, initialize registers
    #=================================================================

    la   t0, trap_handler
    csrw mtvec, t0

    # Enable MSTATUS.MIE
    li   t0, 0x8
    csrs mstatus, t0

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: EBREAK (4-byte instruction)
    #          Check MEPC[1:0] == 00
    #=================================================================

    .align 2                       # ensure 4-byte alignment
    ebreak

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x08(s1)
    sw   t0, 0x20(s1)             # MEPC
    lw   t1, 0x20(s1)             # load-back

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: C.EBREAK (2-byte compressed instruction)
    #          Check MEPC[0] == 0
    #=================================================================

    .align 2                       # ensure alignment
    .hword 0x9002                  # c.ebreak (raw encoding, avoids need for -march with C)

    # Handler advances MEPC by 2, returns here
    lw   t0, 0x08(s1)
    sw   t0, 0x30(s1)             # MEPC
    lw   t1, 0x30(s1)             # load-back

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: ECALL (4-byte instruction)
    #          Check MEPC[0] == 0
    #=================================================================

    .align 2
    ecall

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x08(s1)
    sw   t0, 0x40(s1)             # MEPC
    lw   t1, 0x40(s1)             # load-back

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Illegal instruction at 2-byte aligned address
    #          Use .hword 0x0000 (16-bit illegal compressed instruction)
    #          Check MEPC[0] == 0
    #=================================================================

    .align 2                       # ensure 4-byte alignment first
    nop                            # 4-byte NOP to move to next position
    .hword 0x0000                  # 16-bit illegal instruction (at 2-byte aligned addr)

    # Handler advances MEPC by 2, returns here
    lw   t0, 0x08(s1)
    sw   t0, 0x50(s1)             # MEPC
    lw   t1, 0x50(s1)             # load-back

    li   x31, 0x55555555


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
