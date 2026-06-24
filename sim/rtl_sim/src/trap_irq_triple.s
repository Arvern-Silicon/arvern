#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_triple
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ TRIPLE
#   Verify 3 simultaneous interrupts (software+timer+external) are handled
#   in RISC-V priority order: External(11) > Timer(7) > Software(3).
#
#   The trap handler disables its own MIE bit and re-enables MSTATUS.MIE so
#   the next pending interrupt fires upon MRET.
#
#   IRQ signals are driven simultaneously by the testbench stimulus.
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
# Phase 2 data:
#   0x50: trap_count_before
#   0x54: 1st MCAUSE        (expect 0x8000000B - external)
#   0x58: 2nd MCAUSE        (expect 0x80000007 - timer)
#   0x5C: 3rd MCAUSE        (expect 0x80000003 - software)
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
    # NOTE: Do NOT re-enable MSTATUS.MIE here. MRET naturally restores
    # MIE from MPIE (which was 1 since MIE was enabled at trap entry).
    # Re-enabling MIE inside the handler would cause nested traps that
    # corrupt MEPC (only one copy), creating an infinite MRET loop.

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
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)
    sw   t0, 0x58(s1)
    sw   t0, 0x5C(s1)
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

    # Initialize callee-saved registers to known pattern
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Signal: Phase 1 init complete
    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: 3 simultaneous IRQs (software+timer+external)
    #=================================================================

    # Enable all 3 MIE bits: MSIE(3) + MTIE(7) + MEIE(11)
    li   t0, 0x888             # bits 3 + 7 + 11
    csrs mie, t0

    # Enable MSTATUS.MIE (bit 3)
    li   t0, 0x8
    csrs mstatus, t0

    # Save trap_count before
    lw   t0, 0x00(s1)
    sw   t0, 0x50(s1)

    # Signal: ready for all 3 interrupts
    li   x31, 0x21212121

    # Spin until trap_count == saved + 3 (all 3 interrupts handled)
wait_phase2:
    lw   t0, 0x00(s1)         # current trap_count
    lw   t2, 0x50(s1)         # saved trap_count
    addi t2, t2, 3
    bne  t0, t2, wait_phase2

    # Copy MCAUSE values from log to phase area
    lw   t0, 0x50(s1)         # N = trap_count before phase 2
    slli t0, t0, 2            # N*4
    add  t0, t0, s1           # s1 + N*4
    lw   t1, 0xA0(t0)         # MCAUSE[N]   = 1st interrupt
    sw   t1, 0x54(s1)
    lw   t1, 0xA4(t0)         # MCAUSE[N+1] = 2nd interrupt
    sw   t1, 0x58(s1)
    lw   t1, 0xA8(t0)         # MCAUSE[N+2] = 3rd interrupt
    sw   t1, 0x5C(s1)
    lw   t1, 0x5C(s1)         # load-back

    # Signal: Phase 2 complete, IRQs handled
    li   x31, 0x22222222

    # Delay so testbench sees the 0x22222222 -> 0x33333333 transition
    nop
    nop
    nop
    nop
    nop

    #=================================================================
    # PHASE 3: Verify priority order
    #=================================================================

    # Read back the MCAUSE values and signal for testbench check
    # (Already stored at 0x54, 0x58, 0x5C)

    # Signal: Phase 3 - verification
    li   x31, 0x33333333


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
