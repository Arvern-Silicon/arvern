#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_vectored
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ VECTORED
#   MTVEC vectored interrupt mode (mode=01) verification:
#   - Timer interrupt vectored to BASE + 4*7  (MCAUSE = 0x80000007)
#   - Software interrupt vectored to BASE + 4*3 (MCAUSE = 0x80000003)
#   - External interrupt vectored to BASE + 4*11 (MCAUSE = 0x8000000B)
#   - Exception still goes to BASE (not vectored)
#   - Register preservation across interrupts
#
#   Interrupt signals are driven by the testbench (block-level verification).
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area (overwritten each trap):
#   0x00: trap_count        (incremented by handler)
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x0C: trap_handled flag  (set to 1 by handler)
#   0x10: vector_entry_id   (magic value identifying which vector was used)
#
# Phase 2 copies (timer interrupt):
#   0x20: MCAUSE             (expect 0x80000007)
#   0x24: vector_entry_id    (expect 7)
#
# Phase 3 copies (software interrupt):
#   0x30: MCAUSE             (expect 0x80000003)
#   0x34: vector_entry_id    (expect 3)
#
# Phase 4 copies (external interrupt):
#   0x40: MCAUSE             (expect 0x8000000B)
#   0x44: vector_entry_id    (expect 11)
#
# Phase 5 copies (exception / ECALL):
#   0x50: MCAUSE             (expect 11 = 0x0000000B)
#   0x54: vector_entry_id    (expect 0 = went to BASE, not vectored)
#=========================================================================

main:
    j _start

    #=================================================================
    # VECTOR TABLE (must be 4-byte aligned)
    #
    # Each entry is exactly one 32-bit J instruction (4 bytes).
    # MTVEC BASE points here, mode=01 (vectored).
    #
    # Entry  0: exceptions      -> BASE + 0    -> exception_entry
    # Entry  1: supervisor sw    -> BASE + 4    -> default_handler
    # Entry  2: reserved         -> BASE + 8    -> default_handler
    # Entry  3: machine sw       -> BASE + 12   -> software_vector_entry
    # Entry  4: reserved         -> BASE + 16   -> default_handler
    # Entry  5: supervisor timer -> BASE + 20   -> default_handler
    # Entry  6: reserved         -> BASE + 24   -> default_handler
    # Entry  7: machine timer    -> BASE + 28   -> timer_vector_entry
    # Entry  8: reserved         -> BASE + 32   -> default_handler
    # Entry  9: supervisor ext   -> BASE + 36   -> default_handler
    # Entry 10: reserved         -> BASE + 40   -> default_handler
    # Entry 11: machine ext      -> BASE + 44   -> external_vector_entry
    #=================================================================
    .align 2
    .option push                     # Save current arch state (rvc on/off)
    .option norvc                    # Force 4-byte instructions for vector table entries
vector_table:
    j    exception_entry          # entry  0: exceptions
    j    default_handler          # entry  1
    j    default_handler          # entry  2
    j    software_vector_entry    # entry  3: machine software interrupt
    j    default_handler          # entry  4
    j    default_handler          # entry  5
    j    default_handler          # entry  6
    j    timer_vector_entry       # entry  7: machine timer interrupt
    j    default_handler          # entry  8
    j    default_handler          # entry  9
    j    default_handler          # entry 10
    j    external_vector_entry    # entry 11: machine external interrupt
    .option pop                      # Restore surrounding arch state (don't force rvc into no-c builds)

    #=================================================================
    # VECTOR ENTRY STUBS
    #
    # Each sets vector_entry_id then jumps to shared handler
    #=================================================================

timer_vector_entry:
    li   t0, 7
    sw   t0, 0x10(s1)            # vector_entry_id = 7
    j    shared_handler

software_vector_entry:
    li   t0, 3
    sw   t0, 0x10(s1)            # vector_entry_id = 3
    j    shared_handler

external_vector_entry:
    li   t0, 11
    sw   t0, 0x10(s1)            # vector_entry_id = 11
    j    shared_handler

exception_entry:
    li   t0, 0
    sw   t0, 0x10(s1)            # vector_entry_id = 0 (went to BASE)
    j    shared_handler_exception

default_handler:
    li   t0, 0xFF
    sw   t0, 0x10(s1)            # vector_entry_id = 0xFF (unexpected)
    j    shared_handler

    #=================================================================
    # SHARED HANDLER (for interrupts)
    #=================================================================
shared_handler:
    # Save context on stack
    addi sp, sp, -20
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    # Read trap CSRs
    csrr t1, mcause
    csrr t2, mepc

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Store to "last" working area
    sw   t1, 0x04(s1)
    sw   t2, 0x08(s1)

    # Disable the MIE bit for the interrupt that fired
    andi t3, t1, 0x1F             # cause code (bits 4:0)

    li   t4, 3
    beq  t3, t4, vec_disable_msie
    li   t4, 7
    beq  t3, t4, vec_disable_mtie
    li   t4, 11
    beq  t3, t4, vec_disable_meie
    j    vec_handler_done         # unknown cause, just return

vec_disable_msie:
    li   t4, 0x8                  # MIE.MSIE = bit 3
    csrc mie, t4
    j    vec_handler_done

vec_disable_mtie:
    li   t4, 0x80                 # MIE.MTIE = bit 7
    csrc mie, t4
    j    vec_handler_done

vec_disable_meie:
    li   t4, 0x800                # MIE.MEIE = bit 11
    csrc mie, t4

vec_handler_done:
    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x0C(s1)
    lw   t4, 0x0C(s1)            # load-back fence

    # Restore context
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    addi sp, sp, 20

    mret


    #=================================================================
    # SHARED HANDLER (for exceptions - advances MEPC)
    #=================================================================
shared_handler_exception:
    # Save context on stack
    addi sp, sp, -20
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    # Read trap CSRs
    csrr t1, mcause
    csrr t2, mepc

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Store to "last" working area
    sw   t1, 0x04(s1)
    sw   t2, 0x08(s1)

    # Advance MEPC past the faulting instruction
    lhu  t4, 0(t2)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, exc_advance_4
    addi t2, t2, 2
    j    exc_advance_done
exc_advance_4:
    addi t2, t2, 4
exc_advance_done:
    csrw mepc, t2

    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x0C(s1)
    lw   t4, 0x0C(s1)            # load-back fence

    # Restore context
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    addi sp, sp, 20

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
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)

    #=================================================================
    # PHASE 1: Install vectored trap handler, initialize registers
    #=================================================================

    # Install trap handler with vectored mode (mode=01)
    la   t0, vector_table
    ori  t0, t0, 0x1             # Set mode=01 (vectored)
    csrw mtvec, t0

    # Read back MTVEC for verification
    csrr t0, mtvec
    sw   t0, 0x18(s1)
    lw   t1, 0x18(s1)            # load-back fence

    # Initialize callee-saved registers to known pattern
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Signal: Phase 1 init complete
    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Timer interrupt (vectored to BASE + 4*7)
    #=================================================================

    # Enable MIE.MTIE (bit 7)
    li   t0, 0x80
    csrs mie, t0

    # Enable MSTATUS.MIE (bit 3)
    li   t0, 0x8
    csrs mstatus, t0

    # Clear trap_handled flag
    sw   zero, 0x0C(s1)

    # Signal: ready for timer interrupt
    li   x31, 0x21212121

    # Spin-wait for trap_handled
wait_trap2:
    lw   t0, 0x0C(s1)
    beqz t0, wait_trap2

    # Copy saved data to Phase 2 area
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)            # MCAUSE
    lw   t0, 0x10(s1)
    sw   t0, 0x24(s1)            # vector_entry_id
    lw   t1, 0x24(s1)            # load-back

    # Signal: Phase 2 complete
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Software interrupt (vectored to BASE + 4*3)
    #=================================================================

    # Enable MIE.MSIE (bit 3)
    li   t0, 0x8
    csrs mie, t0

    # Clear trap_handled flag
    sw   zero, 0x0C(s1)

    # Signal: ready for software interrupt
    li   x31, 0x31313131

    # Spin-wait
wait_trap3:
    lw   t0, 0x0C(s1)
    beqz t0, wait_trap3

    # Copy to Phase 3 area
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)            # MCAUSE
    lw   t0, 0x10(s1)
    sw   t0, 0x34(s1)            # vector_entry_id
    lw   t1, 0x34(s1)            # load-back

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: External interrupt (vectored to BASE + 4*11)
    #=================================================================

    # Enable MIE.MEIE (bit 11)
    li   t0, 0x800
    csrs mie, t0

    # Clear trap_handled flag
    sw   zero, 0x0C(s1)

    # Signal: ready for external interrupt
    li   x31, 0x41414141

    # Spin-wait
wait_trap4:
    lw   t0, 0x0C(s1)
    beqz t0, wait_trap4

    # Copy to Phase 4 area
    lw   t0, 0x04(s1)
    sw   t0, 0x40(s1)            # MCAUSE
    lw   t0, 0x10(s1)
    sw   t0, 0x44(s1)            # vector_entry_id
    lw   t1, 0x44(s1)            # load-back

    # Signal: Phase 4 complete
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Exception (ECALL) still goes to BASE (not vectored)
    #=================================================================

    # Clear trap_handled flag
    sw   zero, 0x0C(s1)

    # Clear vector_entry_id (should be set to 0 by exception_entry)
    sw   zero, 0x10(s1)

    # Signal: ready for ECALL test
    li   x31, 0x51515151

    # Trigger synchronous exception
    ecall

    # Copy to Phase 5 area
    lw   t0, 0x04(s1)
    sw   t0, 0x50(s1)            # MCAUSE
    lw   t0, 0x10(s1)
    sw   t0, 0x54(s1)            # vector_entry_id (should be 0)
    lw   t1, 0x54(s1)            # load-back

    # Signal: Phase 5 complete
    li   x31, 0x55555555

    # Small delay to ensure testbench sees 0x55555555 before we move on
    nop
    nop
    nop
    nop
    nop

    #=================================================================
    # Register preservation check
    #=================================================================

    # Signal: final register check
    li   x31, 0x66666666


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
