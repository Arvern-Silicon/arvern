#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_irq_hazard
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSR WRITE / IRQ DETECTION PIPELINE HAZARD
#   Tests that an IRQ cannot slip through on the same cycle that a CSR write
#   clears MIE (mstatus bit 3).
#
#   The hazard: irq_detect is combinational using the OLD (registered) value
#   of mstatus_mie, while CSRRCI writes the NEW value on the same clock edge.
#   If irq_detect is not suppressed during the CSR write, a spurious IRQ is
#   taken after MIE has been cleared.
#
#   Strategy:
#   1. Set up trap handler that clears MTIE on entry (prevents re-entry)
#   2. Testbench asserts irq_m_timer and holds it high
#   3. Firmware disables MTIE (no IRQ despite irq_m_timer=1 and MIE=1)
#   4. Firmware executes: csrs mie, 0x80  (enable MTIE)
#   csrc mstatus, 0x8  (disable MIE)
#   These two back-to-back CSR instructions create a 1-cycle window
#   where MTIE becomes 1 on the same edge that CSRRCI enters execute.
#   5. With the bug: irq_detect fires → spurious IRQ → IRQ count += 1
#   Without bug: irq_detect suppressed → no IRQ → count unchanged
#----------------------------------------------------------------------------

.section .text
.global main

    #=================================================================
    # ENTRY POINT — jump to main (trap handler follows)
    #=================================================================
    j    main

    #=================================================================
    # TRAP HANDLER (before main, at fixed address)
    #=================================================================
    # Custom handler that:
    #   - Increments trap counter at 0x80001FF0
    #   - Clears MTIE to prevent infinite re-entry from sustained irq_m_timer
    #   - For exceptions: advances MEPC past faulting instruction

    .align 2
_test_trap_handler:

    # Swap SP with MSCRATCH (handler stack)
    csrrw  sp, mscratch, sp

    # Save context
    addi sp, sp, -16
    sw   t0,  12(sp)
    sw   t1,   8(sp)

    # Increment trap counter
    li   t0, 0x80001FF0
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)

    # Check trap type
    csrr t0, mcause
    bltz t0, _test_handler_is_irq

    # Exception: advance MEPC past faulting instruction
    csrr t0, mepc
    lhu  t1, 0(t0)
    andi t1, t1, 0x3
    li   t0, 0x3
    csrr t0, mepc
    beq  t1, t0, _test_advance_4
    addi t0, t0, 2
    j    _test_exc_done
_test_advance_4:
    addi t0, t0, 4
_test_exc_done:
    csrw mepc, t0
    j    _test_handler_done

_test_handler_is_irq:
    # Clear MTIE (bit 7) to prevent re-entry from sustained irq_m_timer
    li   t0, 0x80
    csrc mie, t0

_test_handler_done:
    # Restore context
    lw   t1,   8(sp)
    lw   t0,  12(sp)
    addi sp, sp, 16
    csrrw  sp, mscratch, sp
    mret


    #=================================================================
    # MAIN TEST
    #=================================================================

    .align 2
main:

    #-------------------------------------------------
    # INITIALIZE TRAP HANDLER
    #-------------------------------------------------

    # Set MTVEC to our custom handler
    la   t0, _test_trap_handler
    csrw mtvec, t0

    # Zero the trap counter
    li   t0, 0x80001FF0
    sw   zero, 0(t0)

    # Set MSCRATCH to handler stack
    li   t0, 0x80001F00
    csrw mscratch, t0

    # Enable timer interrupt in MIE (bit 7 = MTIE)
    li   t0, 0x80
    csrw mie, t0

    # Keep 0x80 (MTIE mask) in s0 for back-to-back CSR hazard sequences
    li   s0, 0x80

    # Enable global interrupts: MIE (mstatus bit 3)
    csrs mstatus, 0x8

    # Store sync word to SRAM[0] — testbench starts irq_m_timer
    li   x29, 0x80000000
    li   x1,  0xDEAD0001
    sw   x1,  0(x29)

    # Small delay: let the IRQ fire and be serviced
    # (handler will clear MTIE, preventing re-entry)
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    #-------------------------------------------------
    # READ IRQ COUNT BEFORE HAZARD TEST
    #-------------------------------------------------

    li   t0, 0x80001FF0
    lw   x10, 0(t0)        # x10 = irq count before hazard test
    sw   x10, 4(x29)       # store to SRAM[1]

    #-------------------------------------------------
    # HAZARD TEST
    #-------------------------------------------------
    # At this point: MIE=1, MTIE=0, irq_m_timer=1 (from testbench)
    #
    # Execute csrs mie, 0x80 (enable MTIE) immediately followed by
    # csrc mstatus, 0x8 (clear MIE).
    #
    # Pipeline timing:
    #   Edge N  : csrs mie in execute → MTIE becomes 1 at edge N+1
    #   Edge N+1: csrc mstatus in execute, MTIE just became 1
    #             irq_detect sees: MIE=1(old), MTIE=1(new), irq_m_timer=1
    #             → BUG: spurious IRQ taken
    #             → FIX: irq_detect suppressed by csr_irq_config_wr

    .align 2
    csrs mie, s0          # enable MTIE
    csrc mstatus, 0x8       # immediately disable MIE — hazard window!

    # If bug: spurious IRQ was taken, handler ran, MTIE cleared, MRET.
    #         MIE = MPIE = 0 (permanently disabled).
    # If fix: no IRQ, MIE = 0 (from csrc).

    nop
    nop
    nop
    nop

    #-------------------------------------------------
    # READ IRQ COUNT AFTER HAZARD TEST
    #-------------------------------------------------

    li   t0, 0x80001FF0
    lw   x11, 0(t0)        # x11 = irq count after hazard test
    sw   x11, 8(x29)       # store to SRAM[2]

    #-------------------------------------------------
    # REPEAT HAZARD TEST (csrs mie + csrc mstatus)
    # to verify it's consistent
    #-------------------------------------------------

    # Re-enable MIE for a second hazard test
    .align 2
    csrs mstatus, 0x8       # MIE = 1 again (MTIE still 0 from handler)
    csrs mie, s0          # enable MTIE
    csrc mstatus, 0x8       # disable MIE — hazard window again!

    nop
    nop
    nop
    nop

    li   t0, 0x80001FF0
    lw   x12, 0(t0)        # x12 = irq count after second hazard test
    sw   x12, 12(x29)      # store to SRAM[3]

    #-------------------------------------------------
    # THIRD HAZARD TEST: csrs mie + csrci mstatus
    # (using CSRRCI immediate form)
    #-------------------------------------------------

    .align 2
    csrs mstatus, 0x8
    csrs mie, s0
    csrci mstatus, 0x8      # immediate form

    nop
    nop
    nop
    nop

    li   t0, 0x80001FF0
    lw   x13, 0(t0)        # x13 = irq count after third hazard test
    sw   x13, 16(x29)      # store to SRAM[4]

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    csrc mstatus, 0x8
end_of_test:
    nop
    j end_of_test
