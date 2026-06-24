#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ifault
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IFAULT EXCEPTION
#   Instruction access fault triggered by IF-stage fetch to unmapped address:
#   - JAL to unmapped ROM address (MCAUSE = 1)
#   - JALR to unmapped address via register (MCAUSE = 1)
#   - Handler redirects MEPC to recovery label for each case
#   - Register preservation across exceptions
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MTVAL
#   0x0C: last MEPC
#   0x10: trap_handled flag
#   0x14: recovery address (set before triggering IF exception)
#
# Phase 2 (JALR to unmapped address 0x30000000):
#   0x20: MCAUSE             (expect 1)
#   0x24: MEPC               (expect 0x30000000)
#   0x28: MTVAL              (expect 0x30000000)
#
# Phase 3 (JALR to unmapped address 0x40000000):
#   0x30: MCAUSE             (expect 1)
#   0x34: MEPC               (expect 0x40000000)
#   0x38: MTVAL              (expect 0x40000000)
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
    csrr t2, mtval

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Save to working area
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    sw   t1, 0x0C(s1)

    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)

    # Check if interrupt (MSB = 1)
    bltz t0, handle_interrupt

    # Check for instruction fetch exceptions (cause 0 or 1)
    # For these, MEPC points to an invalid/unmapped address,
    # so we can't read the instruction. Use recovery address.
    beqz t0, use_recovery_addr     # cause 0: inst addr misaligned
    li   t3, 1
    beq  t0, t3, use_recovery_addr # cause 1: inst access fault

    # For other exceptions: advance MEPC past faulting instruction
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, advance_4
    addi t1, t1, 2
    j    exc_done
advance_4:
    addi t1, t1, 4
    j    exc_done

use_recovery_addr:
    lw   t1, 0x14(s1)             # load recovery address from scratchpad

exc_done:
    csrw mepc, t1
    j    handler_done

handle_interrupt:
    andi t3, t0, 0x1F
    li   t4, 7
    beq  t3, t4, disable_mtie
    j    handler_done
disable_mtie:
    li   t4, 0x80
    csrc mie, t4

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
    sw   t0, 0x14(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)

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
    # PHASE 2: Instruction access fault via JALR to 0x30000000
    #          (MCAUSE = 1)
    #=================================================================

    # Store recovery address
    la   t0, recovery_p2
    sw   t0, 0x14(s1)

    # JALR to unmapped address -> instruction access fault
    li   t0, 0x30000000
    jalr x0, t0, 0

recovery_p2:
    # Handler should redirect here
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)         # MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x24(s1)         # MEPC
    lw   t0, 0x08(s1)
    sw   t0, 0x28(s1)         # MTVAL (archived per-phase, last slot)
    lw   t1, 0x28(s1)         # load-back (sentinel-race guard)

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Instruction access fault via JALR to 0x40000000
    #          (MCAUSE = 1)
    #=================================================================

    # Store recovery address
    la   t0, recovery_p3
    sw   t0, 0x14(s1)

    # JALR to different unmapped address -> instruction access fault
    li   t0, 0x40000000
    jalr x0, t0, 0

recovery_p3:
    # Handler should redirect here
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)         # MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x34(s1)         # MEPC
    lw   t0, 0x08(s1)
    sw   t0, 0x38(s1)         # MTVAL (archived per-phase, last slot)
    lw   t1, 0x38(s1)         # load-back (sentinel-race guard)

    li   x31, 0x33333333


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
