#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_basic
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: EXCEPTIONS
#   Synchronous exception verification:
#   - Instruction access fault (MCAUSE = 1)
#   - Illegal instruction (MCAUSE = 2)
#   - Load address misaligned (MCAUSE = 4)
#   - Store address misaligned (MCAUSE = 6)
#   - Load access fault (MCAUSE = 5)
#   - Store access fault (MCAUSE = 7)
#   - MEPC, MSTATUS save/restore for each
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
#   0x08: last MEPC
#   0x0C: last MSTATUS
#   0x10: last MTVAL
#
# Phase 2 (illegal instruction):
#   0x20: MCAUSE             (expect 2)
#   0x24: MEPC
#   0x28: expected MEPC
#
# Phase 3 (load misaligned):
#   0x30: MCAUSE             (expect 4)
#   0x34: MEPC
#   0x38: expected MEPC
#
# Phase 4 (store misaligned):
#   0x40: MCAUSE             (expect 6)
#   0x44: MEPC
#   0x48: expected MEPC
#
# Phase 5 (load access fault):
#   0x50: MCAUSE             (expect 5)
#   0x54: MEPC
#   0x58: expected MEPC
#
# Phase 6 (store access fault):
#   0x60: MCAUSE             (expect 7)
#   0x64: MEPC
#   0x68: expected MEPC
#
# Phase 7 (instruction access fault via JALR to 0x00000000):
#   0x14: recovery address   (set before triggering IF exception)
#   0x70: MCAUSE             (expect 1)
#   0x74: MEPC               (expect target of JALR = unmapped addr)
#   0x78: expected MEPC
#
# Phase 8 (instruction access fault via JALR to 0x40000000):
#   0x80: MCAUSE             (expect 1)
#   0x84: MEPC
#   0x88: expected MEPC
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
    csrr t3, mtval

    # Increment trap_count
    lw   t4, 0x00(s1)
    addi t4, t4, 1
    sw   t4, 0x00(s1)

    # Save to working area
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)
    sw   t3, 0x10(s1)

    # Check if interrupt or exception
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
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x48(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)
    sw   t0, 0x58(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x64(s1)
    sw   t0, 0x68(s1)
    sw   t0, 0x70(s1)
    sw   t0, 0x74(s1)
    sw   t0, 0x78(s1)
    sw   t0, 0x80(s1)
    sw   t0, 0x84(s1)
    sw   t0, 0x88(s1)
    sw   t0, 0x14(s1)

    #=================================================================
    # PHASE 1: Install trap handler
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
    # PHASE 2: Illegal instruction (MCAUSE = 2)
    #=================================================================

    la   t0, illegal_inst
    sw   t0, 0x28(s1)         # expected MEPC

illegal_inst:
    .word 0xFFFFFFFF           # illegal: opcode=0b1111111 (reserved)

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x24(s1)         # MEPC
    lw   t1, 0x24(s1)         # load-back

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Load address misaligned (MCAUSE = 4)
    #=================================================================

    la   t0, load_misaligned
    sw   t0, 0x38(s1)         # expected MEPC

    li   t2, 0x80000100       # aligned base address in SRAM

load_misaligned:
    lh   t0, 1(t2)            # halfword load from odd address -> misaligned

    # Handler advances MEPC, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x34(s1)         # MEPC
    lw   t1, 0x34(s1)         # load-back

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Store address misaligned (MCAUSE = 6)
    #=================================================================

    la   t0, store_misaligned
    sw   t0, 0x48(s1)         # expected MEPC

    li   t2, 0x80000100       # aligned base
    li   t3, 0x12345678       # data to store

store_misaligned:
    sw   t3, 1(t2)            # word store to non-aligned address -> misaligned

    # Handler advances MEPC, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x40(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x44(s1)         # MEPC
    lw   t1, 0x44(s1)         # load-back

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Load access fault (MCAUSE = 5)
    #=================================================================

    la   t0, load_fault
    sw   t0, 0x58(s1)         # expected MEPC

    li   t2, 0               # unmapped address

load_fault:
    lw   t0, 0(t2)            # load from unmapped address -> access fault

    # Handler advances MEPC, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x50(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x54(s1)         # MEPC
    lw   t1, 0x54(s1)         # load-back

    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: Store access fault (MCAUSE = 7)
    #=================================================================

    la   t0, store_fault
    sw   t0, 0x68(s1)         # expected MEPC

    li   t2, 0               # unmapped address
    li   t3, 0xDEADDEAD      # data to store

store_fault:
    sw   t3, 0(t2)            # store to unmapped address -> access fault

    # Handler advances MEPC, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x60(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x64(s1)         # MEPC
    lw   t1, 0x64(s1)         # load-back

    li   x31, 0x66666666


    #=================================================================
    # PHASE 7: Instruction access fault (MCAUSE = 1)
    #          JALR to unmapped address 0x00000000
    #=================================================================

    # Store recovery address
    la   t0, recovery_7
    sw   t0, 0x14(s1)

    # Store expected MEPC (the unmapped target address)
    li   t0, 0x00000000
    sw   t0, 0x78(s1)

    # JALR to unmapped address -> instruction access fault
    li   t0, 0x00000000
    jalr x0, t0, 0

recovery_7:
    # Handler should redirect here
    lw   t0, 0x04(s1)
    sw   t0, 0x70(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x74(s1)         # MEPC
    lw   t1, 0x74(s1)         # load-back (force store completion before trigger)

    li   x31, 0x77777777


    #=================================================================
    # PHASE 8: Instruction access fault (MCAUSE = 1)
    #          JALR to different unmapped address 0x40000000
    #=================================================================

    # Store recovery address
    la   t0, recovery_8
    sw   t0, 0x14(s1)

    # Store expected MEPC (the unmapped target address)
    li   t0, 0x40000000
    sw   t0, 0x88(s1)

    # JALR to unmapped address -> instruction access fault
    li   t0, 0x40000000
    jalr x0, t0, 0

recovery_8:
    # Handler should redirect here
    lw   t0, 0x04(s1)
    sw   t0, 0x80(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x84(s1)         # MEPC
    lw   t1, 0x84(s1)         # load-back (force store completion before trigger)

    li   x31, 0x88888888


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
