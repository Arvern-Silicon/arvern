#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_mtval
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP MTVAL
#   Verify MTVAL contains the correct value for each exception type:
#   - Illegal instruction    (MCAUSE=2,  MTVAL=0)
#   - Load addr misaligned   (MCAUSE=4,  MTVAL=faulting address)
#   - Store addr misaligned  (MCAUSE=6,  MTVAL=faulting address)
#   - Load access fault      (MCAUSE=5,  MTVAL=faulting address)
#   - Store access fault     (MCAUSE=7,  MTVAL=faulting address)
#   - EBREAK                 (MCAUSE=3,  MTVAL=0)
#   - ECALL from M-mode      (MCAUSE=11, MTVAL=0)
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area (overwritten each trap):
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MTVAL
#   0x0C: last MEPC
#   0x10: trap_handled flag
#
# Phase 2 (illegal instruction):
#   0x20: MCAUSE             (expect 2)
#   0x24: MTVAL              (expect 0)
#
# Phase 3 (load address misaligned):
#   0x30: MCAUSE             (expect 4)
#   0x34: MTVAL              (expect 0x80000001)
#
# Phase 4 (store address misaligned):
#   0x40: MCAUSE             (expect 6)
#   0x44: MTVAL              (expect 0x80000003)
#
# Phase 5 (load access fault):
#   0x50: MCAUSE             (expect 5)
#   0x54: MTVAL              (expect 0x10000000)
#
# Phase 6 (store access fault):
#   0x60: MCAUSE             (expect 7)
#   0x64: MTVAL              (expect 0x10000004)
#
# Phase 7 (EBREAK):
#   0x70: MCAUSE             (expect 3)
#   0x74: MTVAL              (expect 0)
#
# Phase 8 (ECALL from M-mode):
#   0x80: MCAUSE             (expect 11)
#   0x84: MTVAL              (expect 0)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    # Save context on stack
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    # Read trap CSRs
    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mtval

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Store to working area
    sw   t0, 0x04(s1)          # last MCAUSE
    sw   t2, 0x08(s1)          # last MTVAL
    sw   t1, 0x0C(s1)          # last MEPC

    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)

    # Check if interrupt (MCAUSE MSB = 1)
    bltz t0, handle_interrupt

    # ---- Exception path: advance MEPC past faulting instruction ----
    # Check for instruction fetch exceptions (cause 0 or 1)
    # For these, MEPC points to an invalid address, can't read instruction
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
    # Disable the MIE bit for the interrupt that fired
    andi t3, t0, 0x1F
    li   t4, 7
    beq  t3, t4, disable_mtie
    j    handler_done
disable_mtie:
    li   t4, 0x80
    csrc mie, t4

handler_done:
    # Restore context
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
    # Initialize stack pointer
    li   sp, 0x80010000

    # Initialize scratchpad base pointer (kept throughout test)
    li   s1, 0x80000000

    # Zero scratchpad area
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x64(s1)
    sw   t0, 0x70(s1)
    sw   t0, 0x74(s1)
    sw   t0, 0x80(s1)
    sw   t0, 0x84(s1)

    #=================================================================
    # PHASE 1: Install trap handler, initialize registers
    #=================================================================

    # Install trap handler (direct mode)
    la   t0, trap_handler
    csrw mtvec, t0

    # Enable MSTATUS.MIE (bit 3)
    li   t0, 0x8
    csrs mstatus, t0

    # Initialize callee-saved registers to known pattern
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Signal: Phase 1 init complete
    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Illegal instruction (MCAUSE=2, MTVAL=0)
    #=================================================================

illegal_inst:
    .word 0xFFFFFFFF           # illegal: opcode=0b1111111 (reserved)

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x24(s1)         # MTVAL
    lw   t1, 0x24(s1)         # load-back

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Load address misaligned (MCAUSE=4, MTVAL=0x80000001)
    #=================================================================

    li   t0, 0x80000001       # misaligned address (base + 1)

load_misaligned:
    lw   t1, 0(t0)            # word load from misaligned address

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x34(s1)         # MTVAL
    lw   t1, 0x34(s1)         # load-back

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Store address misaligned (MCAUSE=6, MTVAL=0x80000003)
    #=================================================================

    li   t0, 0x80000003       # misaligned address (base + 3)
    li   t2, 0x12345678       # data to store

store_misaligned:
    sw   t2, 0(t0)            # word store to misaligned address

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x40(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x44(s1)         # MTVAL
    lw   t1, 0x44(s1)         # load-back

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Load access fault (MCAUSE=5, MTVAL=0x10000000)
    #=================================================================

    li   t0, 0x10000000       # unmapped address

load_fault:
    lw   t1, 0(t0)            # load from unmapped address

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x50(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x54(s1)         # MTVAL
    lw   t1, 0x54(s1)         # load-back

    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: Store access fault (MCAUSE=7, MTVAL=0x10000004)
    #=================================================================

    li   t0, 0x10000004       # unmapped address
    li   t2, 0xDEADDEAD       # data to store

store_fault:
    sw   t2, 0(t0)            # store to unmapped address

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x60(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x64(s1)         # MTVAL
    lw   t1, 0x64(s1)         # load-back

    li   x31, 0x66666666


    #=================================================================
    # PHASE 7: EBREAK (MCAUSE=3, MTVAL=0)
    #=================================================================

    ebreak

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x70(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x74(s1)         # MTVAL
    lw   t1, 0x74(s1)         # load-back

    li   x31, 0x77777777


    #=================================================================
    # PHASE 8: ECALL from M-mode (MCAUSE=11, MTVAL=0)
    #=================================================================

    ecall

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x80(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x84(s1)         # MTVAL
    lw   t1, 0x84(s1)         # load-back

    li   x31, 0x88888888


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
