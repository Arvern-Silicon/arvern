#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_drain
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP DRAIN
#   Pipeline drain correctness when a trap occurs during multi-cycle ops:
#   - Timer IRQ during long divide  (pipeline must drain before trap)
#   - Timer IRQ during back-to-back divides
#   - Timer IRQ during multiply
#   - Synchronous exception after divide (load misaligned)
#
#   The pipeline must wait for EX/WB stages to complete before taking the
#   trap.  Each phase verifies that the multi-cycle result is correct AND
#   the trap is properly recorded.
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
# Phase 2 (timer IRQ during DIV):
#   0x20: MCAUSE             (expect 0x80000007)
#   0x24: div_result (s7)    (expect 0x000003E8 = 1000)
#
# Phase 3 (timer IRQ during back-to-back DIVs):
#   0x30: MCAUSE             (expect 0x80000007)
#   0x34: div1_result (s7)   (expect 0x000003E8 = 1000)
#   0x38: div2_result (s8)   (expect 0x000003E8 = 1000)
#
# Phase 4 (timer IRQ during MUL):
#   0x40: MCAUSE             (expect 0x80000007)
#   0x44: mul_result (s7)    (expect 0x3B9ACA00 = 1000000000)
#
# Phase 5 (exception after DIV -- load misaligned):
#   0x50: MCAUSE             (expect 0x00000004)
#   0x54: div_result (s7)    (expect 0x000003E8 = 1000)
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

    # Check if interrupt (MCAUSE MSB = 1)
    bltz t0, handle_interrupt

    # ---- Exception path: advance MEPC past faulting instruction ----
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
    j    handler_done

handle_interrupt:
    # Disable the MIE bit for the interrupt that fired
    andi t3, t0, 0x1F         # cause code (bits 4:0)

    li   t4, 3
    beq  t3, t4, disable_msie
    li   t4, 7
    beq  t3, t4, disable_mtie
    li   t4, 11
    beq  t3, t4, disable_meie
    j    handler_done          # unknown cause, just return

disable_msie:
    li   t4, 0x8               # MIE.MSIE = bit 3
    csrc mie, t4
    j    handler_done

disable_mtie:
    li   t4, 0x80              # MIE.MTIE = bit 7
    csrc mie, t4
    j    handler_done

disable_meie:
    li   t4, 0x800             # MIE.MEIE = bit 11
    csrc mie, t4

handler_done:
    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)
    lw   t4, 0x10(s1)         # load-back fence

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
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)

    #=================================================================
    # PHASE 1: Install trap handler, initialize registers
    #=================================================================

    # Install trap handler (direct mode)
    la   t0, trap_handler
    csrw mtvec, t0

    # Initialize callee-saved registers to known pattern
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Signal: Phase 1 init complete
    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Timer IRQ during long divide
    #=================================================================
    # Setup: disable MSTATUS.MIE, prepare operands, then re-enable
    # via a carefully placed sequence so the testbench can assert
    # irq_m_timer while the divide is in-flight.

    # Disable MSTATUS.MIE
    li   t0, 0x8
    csrc mstatus, t0

    # Enable MIE.MTIE (bit 7)
    li   t0, 0x80
    csrs mie, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Load divide operands into t2/t3
    li   t2, 0x000F4240        # 1000000
    li   t3, 0x000003E8        # 1000

    # Signal: ready for timer IRQ (testbench will assert irq_m_timer)
    li   x31, 0x21212121

    # Re-enable MSTATUS.MIE and immediately start divide
    li   t0, 0x8
    csrs mstatus, t0
    div  s7, t2, t3            # s7 = 1000000 / 1000 = 1000

    # If IRQ fires during divide, pipeline drains first, then traps.
    # After MRET we land here. Either way s7 must be correct.

    # Spin-wait for trap_handled (in case IRQ hasn't fired yet)
wait_trap2:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap2

    # Save results to scratchpad
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)         # MCAUSE
    sw   s7, 0x24(s1)         # div result
    lw   t1, 0x24(s1)         # load-back

    # Signal: Phase 2 complete
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Timer IRQ during back-to-back DIVs
    #=================================================================

    # Disable MSTATUS.MIE
    li   t0, 0x8
    csrc mstatus, t0

    # Re-enable MIE.MTIE
    li   t0, 0x80
    csrs mie, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Load divide operands
    li   t2, 0x000F4240        # 1000000
    li   t3, 0x000003E8        # 1000
    li   t4, 0x00002710        # 10000
    li   t5, 0x0000000A        # 10

    # Signal: ready for timer IRQ
    li   x31, 0x31313131

    # Re-enable MSTATUS.MIE and immediately start back-to-back divides
    li   t0, 0x8
    csrs mstatus, t0
    div  s7, t2, t3            # s7 = 1000000 / 1000 = 1000
    div  s8, t4, t5            # s8 = 10000 / 10 = 1000

    # Spin-wait for trap_handled
wait_trap3:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap3

    # Save results to scratchpad
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)         # MCAUSE
    sw   s7, 0x34(s1)         # div1 result
    sw   s8, 0x38(s1)         # div2 result
    lw   t1, 0x38(s1)         # load-back

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Timer IRQ during multiply
    #=================================================================

    # Disable MSTATUS.MIE
    li   t0, 0x8
    csrc mstatus, t0

    # Re-enable MIE.MTIE
    li   t0, 0x80
    csrs mie, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Load multiply operands
    li   t2, 0x000F4240        # 1000000
    li   t3, 0x000003E8        # 1000

    # Signal: ready for timer IRQ
    li   x31, 0x41414141

    # Re-enable MSTATUS.MIE and immediately start multiply
    li   t0, 0x8
    csrs mstatus, t0
    mul  s7, t2, t3            # s7 = (1000000 * 1000) low 32 bits = 0x3B9ACA00

    # Spin-wait for trap_handled
wait_trap4:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap4

    # Save results to scratchpad
    lw   t0, 0x04(s1)
    sw   t0, 0x40(s1)         # MCAUSE
    sw   s7, 0x44(s1)         # mul result
    lw   t1, 0x44(s1)         # load-back

    # Signal: Phase 4 complete
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Synchronous exception after DIV (load misaligned)
    #=================================================================

    # Disable interrupts for this phase (purely synchronous)
    li   t0, 0x8
    csrc mstatus, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Load divide operands
    li   t2, 0x000F4240        # 1000000
    li   t3, 0x000003E8        # 1000

    # Re-enable MSTATUS.MIE (needed for handler to work, but no IRQ sources)
    li   t0, 0x8
    csrs mstatus, t0

    # Execute divide followed immediately by misaligned load
    div  s7, t2, t3            # s7 = 1000 (must complete before exception)
    li   t0, 0x80000001        # misaligned address
    lw   t1, 0(t0)             # load misaligned exception (MCAUSE=4)

    # Handler advances MEPC, returns here

    # Save results to scratchpad
    lw   t0, 0x04(s1)
    sw   t0, 0x50(s1)         # MCAUSE
    sw   s7, 0x54(s1)         # div result
    lw   t1, 0x54(s1)         # load-back

    # Signal: Phase 5 complete
    li   x31, 0x55555555


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
