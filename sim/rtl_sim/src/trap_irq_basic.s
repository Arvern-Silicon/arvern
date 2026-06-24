#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_basic
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ
#   Comprehensive asynchronous interrupt verification:
#   - Timer interrupt (MCAUSE = 0x80000007)
#   - Software interrupt (MCAUSE = 0x80000003)
#   - External interrupt (MCAUSE = 0x8000000B)
#   - Interrupt priority (simultaneous timer + external)
#   - MSTATUS.MIE gating (MIE=0 blocks all interrupts)
#   - MSTATUS save/restore across interrupt entry/exit
#   - Register preservation across interrupts
#   - MIE per-source enable/disable
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
#   0x0C: last MSTATUS      (in handler, after trap entry)
#   0x10: trap_handled flag  (set to 1 by handler)
#
# Configuration:
#   0x18: MTVEC readback
#
# Phase 2 copies (timer interrupt):
#   0x20: MCAUSE             (expect 0x80000007)
#   0x24: MEPC
#   0x28: MSTATUS in handler (MIE=0, MPIE=1, MPP=11)
#   0x2C: MSTATUS after MRET (MIE=1, MPIE=1, MPP=00)
#
# Phase 3 copies (software interrupt):
#   0x30: MCAUSE             (expect 0x80000003)
#   0x34: MEPC
#   0x38: MSTATUS in handler
#
# Phase 4 copies (external interrupt):
#   0x40: MCAUSE             (expect 0x8000000B)
#   0x44: MEPC
#   0x48: MSTATUS in handler
#
# Phase 5 data (priority test):
#   0x50: trap_count before phase 5
#   0x54: 1st MCAUSE from priority test
#   0x58: 2nd MCAUSE from priority test
#
# Phase 6 data (MIE=0 test):
#   0x60: trap_count before
#   0x64: trap_count after (should match 0x60)
#
# MCAUSE log (sequential, indexed by trap_count):
#   0xA0 + (n-1)*4: MCAUSE for trap #n (n starts at 1)
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
    csrr t2, mstatus

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Store MCAUSE to sequential log: s1 + 0xA0 + (count-1)*4
    addi t4, t3, -1
    slli t4, t4, 2
    add  t4, t4, s1
    sw   t0, 0xA0(t4)

    # Store to "last" working area
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    # Check if this is an interrupt (MCAUSE MSB = 1)
    bltz t0, handle_interrupt

    # ---- Exception path: advance MEPC ----
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
    sw   t0, 0x18(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
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
    sw   t0, 0xA0(s1)
    sw   t0, 0xA4(s1)
    sw   t0, 0xA8(s1)
    sw   t0, 0xAC(s1)
    sw   t0, 0xB0(s1)

    #=================================================================
    # PHASE 1: Install trap handler, initialize registers
    #=================================================================

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Read back MTVEC for verification
    csrr t0, mtvec
    sw   t0, 0x18(s1)
    lw   t1, 0x18(s1)         # load-back

    # Initialize callee-saved registers to known pattern
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Signal: Phase 1 init complete
    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Timer interrupt
    #=================================================================

    # Enable MIE.MTIE (bit 7)
    li   t0, 0x80
    csrs mie, t0

    # Enable MSTATUS.MIE (bit 3)
    li   t0, 0x8
    csrs mstatus, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Signal: ready for timer interrupt
    li   x31, 0x21212121

    # Spin-wait for trap_handled
wait_trap2:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap2

    # Copy saved CSRs to Phase 2 area
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x24(s1)         # MEPC
    lw   t0, 0x0C(s1)
    sw   t0, 0x28(s1)         # MSTATUS in handler

    # Read MSTATUS after MRET
    csrr t0, mstatus
    sw   t0, 0x2C(s1)
    lw   t1, 0x2C(s1)         # load-back

    # Signal: Phase 2 complete
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Software interrupt
    #=================================================================

    # Enable MIE.MSIE (bit 3)
    li   t0, 0x8
    csrs mie, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Signal: ready for software interrupt
    li   x31, 0x31313131

    # Spin-wait
wait_trap3:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap3

    # Copy to Phase 3 area
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x34(s1)         # MEPC
    lw   t0, 0x0C(s1)
    sw   t0, 0x38(s1)         # MSTATUS in handler
    lw   t1, 0x38(s1)         # load-back

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: External interrupt
    #=================================================================

    # Enable MIE.MEIE (bit 11)
    li   t0, 0x800
    csrs mie, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Signal: ready for external interrupt
    li   x31, 0x41414141

    # Spin-wait
wait_trap4:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap4

    # Copy to Phase 4 area
    lw   t0, 0x04(s1)
    sw   t0, 0x40(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x44(s1)         # MEPC
    lw   t0, 0x0C(s1)
    sw   t0, 0x48(s1)         # MSTATUS in handler
    lw   t1, 0x48(s1)         # load-back

    # Signal: Phase 4 complete
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Priority test (timer + external simultaneously)
    #=================================================================

    # Save trap_count before this phase
    lw   t0, 0x00(s1)
    sw   t0, 0x50(s1)

    # Re-enable both MTIE + MEIE
    li   t0, 0x880             # bits 7 + 11
    csrs mie, t0

    # Signal: ready for both interrupts
    li   x31, 0x51515151

    # Spin until trap_count == saved + 2 (both interrupts handled)
wait_phase5:
    lw   t0, 0x00(s1)         # current trap_count
    lw   t2, 0x50(s1)         # saved trap_count
    addi t2, t2, 2
    bne  t0, t2, wait_phase5

    # Copy MCAUSE values from log
    lw   t0, 0x50(s1)         # N = trap_count before phase 5
    slli t0, t0, 2            # N*4
    add  t0, t0, s1           # s1 + N*4
    lw   t1, 0xA0(t0)         # MCAUSE[N] = 1st interrupt
    sw   t1, 0x54(s1)
    lw   t1, 0xA4(t0)         # MCAUSE[N+1] = 2nd interrupt
    sw   t1, 0x58(s1)
    lw   t1, 0x58(s1)         # load-back

    # Signal: Phase 5 complete
    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: MIE=0 blocks interrupts
    #=================================================================

    # Disable MSTATUS.MIE
    li   t0, 0x8
    csrc mstatus, t0

    # Re-enable MIE.MTIE
    li   t0, 0x80
    csrs mie, t0

    # Save trap_count before
    lw   t0, 0x00(s1)
    sw   t0, 0x60(s1)
    lw   t1, 0x60(s1)         # load-back

    # Signal: ready (interrupt should be blocked by MIE=0)
    li   x31, 0x61616161

    # Delay loop: gives testbench time to assert and deassert irq
    li   t2, 50
nop_loop:
    addi t2, t2, -1
    bnez t2, nop_loop

    # Save trap_count after delay (should be unchanged)
    lw   t0, 0x00(s1)
    sw   t0, 0x64(s1)
    lw   t1, 0x64(s1)         # load-back

    # Disable MIE.MTIE before re-enabling global MIE
    li   t0, 0x80
    csrc mie, t0

    # Re-enable MSTATUS.MIE
    li   t0, 0x8
    csrs mstatus, t0

    # Signal: Phase 6 complete + final register check
    li   x31, 0x66666666


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
