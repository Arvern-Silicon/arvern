#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_priority
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: EXCEPTION PRIORITY
#   Verify exception priority when multiple exceptions could fire:
#   - Misaligned load to valid addr       (MCAUSE=4, MTVAL=addr)
#   - Misaligned load to unmapped addr    (MCAUSE=4, not 5)
#   - Aligned load to unmapped addr       (MCAUSE=5, MTVAL=addr)
#   - Misaligned store to valid addr      (MCAUSE=6, MTVAL=addr)
#   - Misaligned store to unmapped addr   (MCAUSE=6, not 7)
#   - Aligned store to unmapped addr      (MCAUSE=7, MTVAL=addr)
#   - Illegal instruction                 (MCAUSE=2, MTVAL=0)
#
#   Key insight: misalignment is detected in EX stage and kills the
#   instruction before it reaches WB where access faults are detected.
#   So a misaligned access to unmapped space reports misaligned (4/6),
#   not access fault (5/7).
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
# Phase 2 (load misaligned, valid addr):
#   0x20: MCAUSE             (expect 4)
#   0x24: MTVAL              (expect 0x80000001)
#
# Phase 3 (load misaligned, unmapped addr -- priority test):
#   0x30: MCAUSE             (expect 4, NOT 5)
#   0x34: MTVAL              (expect 0x10000001)
#
# Phase 4 (load access fault, aligned unmapped):
#   0x40: MCAUSE             (expect 5)
#   0x44: MTVAL              (expect 0x10000000)
#
# Phase 5 (store misaligned, valid addr):
#   0x50: MCAUSE             (expect 6)
#   0x54: MTVAL              (expect 0x80000003)
#
# Phase 6 (store misaligned, unmapped addr -- priority test):
#   0x60: MCAUSE             (expect 6, NOT 7)
#   0x64: MTVAL              (expect 0x10000003)
#
# Phase 7 (store access fault, aligned unmapped):
#   0x70: MCAUSE             (expect 7)
#   0x74: MTVAL              (expect 0x00000000)
#
# Phase 8 (illegal instruction):
#   0x80: MCAUSE             (expect 2)
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
    # PHASE 2: Load misaligned to valid address (MCAUSE=4)
    #          Address 0x80000001 is in SRAM (valid) but misaligned
    #=================================================================

    li   t0, 0x80000001       # misaligned address in valid SRAM

load_misaligned_valid:
    lw   t1, 0(t0)            # word load from misaligned address

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x24(s1)         # MTVAL
    lw   t1, 0x24(s1)         # load-back

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Load misaligned to unmapped address (MCAUSE=4, NOT 5)
    #          Address 0x10000001 is unmapped AND misaligned.
    #          Misalignment detected in EX stage kills instruction
    #          before WB access fault can fire.
    #=================================================================

    li   t0, 0x10000001       # misaligned AND unmapped address

load_misaligned_unmapped:
    lw   t1, 0(t0)            # should get MCAUSE=4 (misaligned), not 5

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x34(s1)         # MTVAL
    lw   t1, 0x34(s1)         # load-back

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Load aligned to unmapped address (MCAUSE=5)
    #          Address 0x10000000 is unmapped but aligned.
    #          No misalignment, so access fault fires in WB.
    #=================================================================

    li   t0, 0x10000000       # aligned unmapped address

load_fault_aligned:
    lw   t1, 0(t0)            # load from unmapped address -> access fault

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x40(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x44(s1)         # MTVAL
    lw   t1, 0x44(s1)         # load-back

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Store misaligned to valid address (MCAUSE=6)
    #          Address 0x80000003 is in SRAM (valid) but misaligned
    #=================================================================

    li   t0, 0x80000003       # misaligned address in valid SRAM
    li   t2, 0x12345678       # data to store

store_misaligned_valid:
    sw   t2, 0(t0)            # word store to misaligned address

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x50(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x54(s1)         # MTVAL
    lw   t1, 0x54(s1)         # load-back

    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: Store misaligned to unmapped address (MCAUSE=6, NOT 7)
    #          Address 0x10000003 is unmapped AND misaligned.
    #          Misalignment detected in EX stage kills instruction
    #          before WB access fault can fire.
    #=================================================================

    li   t0, 0x10000003       # misaligned AND unmapped address
    li   t2, 0xDEADDEAD       # data to store

store_misaligned_unmapped:
    sw   t2, 0(t0)            # should get MCAUSE=6 (misaligned), not 7

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x60(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x64(s1)         # MTVAL
    lw   t1, 0x64(s1)         # load-back

    li   x31, 0x66666666


    #=================================================================
    # PHASE 7: Store aligned to unmapped address (MCAUSE=7)
    #          Address 0x00000000 is unmapped but aligned.
    #          No misalignment, so access fault fires in WB.
    #=================================================================

    li   t0, 0               # aligned unmapped address (address 0)
    li   t2, 0xCAFECAFE       # data to store

store_fault_aligned:
    sw   t2, 0(t0)            # store to unmapped address -> access fault

    # Handler advances MEPC by 4, returns here
    lw   t0, 0x04(s1)
    sw   t0, 0x70(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x74(s1)         # MTVAL
    lw   t1, 0x74(s1)         # load-back

    li   x31, 0x77777777


    #=================================================================
    # PHASE 8: Illegal instruction (MCAUSE=2, MTVAL=0)
    #=================================================================

illegal_inst:
    .word 0xFFFFFFFF           # illegal: bits[1:0]=11 (32-bit), invalid opcode

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
