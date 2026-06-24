#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_timing
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP IRQ TIMING
#   Interrupt timing edge cases that stress the trap state machine:
#   - MRET re-entry: IRQ still asserted after MRET restores MIE=1
#   - CSR enable race: CSRS MIE enables already-pending interrupt
#   - WFI immediate wakeup: WFI with interrupt already pending
#   - IRQ during load/store sequence with SRAM accesses
#   - Rapid trap cycles: back-to-back ECALL-MRET with register pressure
#
#   Interrupt signals are driven by the testbench.
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
# Phase 2 (MRET re-entry):
#   0x20: trap_count after first IRQ
#   0x24: trap_count after re-entry (expect +1)
#   0x28: MCAUSE from re-entry handler
#
# Phase 3 (CSR enable race):
#   0x30: trap_count before CSRS
#   0x34: trap_count after IRQ taken
#   0x38: MCAUSE (expect timer 0x80000007)
#
# Phase 4 (WFI immediate wakeup):
#   0x40: marker before WFI
#   0x44: marker after WFI (proves WFI didn't stall)
#   0x48: trap_count after WFI+IRQ
#
# Phase 5 (IRQ during load/store):
#   0x50: loaded value 1 (should be correct despite IRQ)
#   0x54: loaded value 2
#   0x58: loaded value 3
#   0x5C: trap_count after load/store IRQ
#
# Phase 6 (rapid ECALL-MRET):
#   0x60: trap_count after 10 rapid ECALLs
#
# Data area for load/store phase:
#   0x80: test data word 0 = 0xDEADBEEF
#   0x84: test data word 1 = 0xCAFEBABE
#   0x88: test data word 2 = 0x12345678
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
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

    # Store to "last" working area
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    # Check if interrupt or exception
    bltz t0, handle_irq

    # ---- Exception path: advance MEPC past ECALL ----
    # ECALL from M-mode = 11
    li   t3, 11
    beq  t0, t3, advance_ecall
    # ECALL from U-mode = 8
    li   t3, 8
    beq  t0, t3, advance_ecall
    # Default: advance past instruction
    j    advance_generic

advance_ecall:
    addi t1, t1, 4
    csrw mepc, t1
    j    handler_done

advance_generic:
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, advance_4b
    addi t1, t1, 2
    j    mepc_done
advance_4b:
    addi t1, t1, 4
mepc_done:
    csrw mepc, t1
    j    handler_done

handle_irq:
    # Disable the specific MIE bit for the interrupt source
    andi t3, t0, 0x1F
    li   t4, 3
    beq  t3, t4, disable_msie
    li   t4, 7
    beq  t3, t4, disable_mtie
    li   t4, 11
    beq  t3, t4, disable_meie
    j    handler_done

disable_msie:
    li   t4, 0x8
    csrc mie, t4
    j    handler_done

disable_mtie:
    li   t4, 0x80
    csrc mie, t4
    j    handler_done

disable_meie:
    li   t4, 0x800
    csrc mie, t4

handler_done:
    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)
    lw   t4, 0x10(s1)

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

    # Initialize scratchpad base pointer
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
    sw   t0, 0x5C(s1)
    sw   t0, 0x60(s1)

    # Initialize test data for Phase 5
    li   t0, 0xDEADBEEF
    sw   t0, 0x80(s1)
    li   t0, 0xCAFEBABE
    sw   t0, 0x84(s1)
    li   t0, 0x12345678
    sw   t0, 0x88(s1)

    #=================================================================
    # PHASE 1: Install trap handler, initialize registers
    #=================================================================

    # Install trap handler (direct mode)
    la   t0, trap_handler
    csrw mtvec, t0

    # Enable MSTATUS.MIE
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
    # PHASE 2: MRET re-entry (IRQ still asserted after MRET)
    #   Testbench asserts timer IRQ and keeps it asserted.
    #   Handler disables MIE.MTIE, returns via MRET.
    #   MRET restores MIE=1. Since IRQ is still asserted but
    #   MIE.MTIE is now 0, no re-entry should occur.
    #   Testbench then re-enables MIE.MEIE and asserts external IRQ
    #   to test that a different source can still interrupt.
    #=================================================================

    # Enable MIE.MTIE + MIE.MEIE
    li   t0, 0x880
    csrs mie, t0

    # Clear trap_handled flag and trap_count
    sw   zero, 0x10(s1)
    sw   zero, 0x00(s1)

    # Signal: ready for timer IRQ
    li   x31, 0x21212121

    # Spin-wait for first trap
wait_trap2a:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap2a

    # Save trap_count after first IRQ
    lw   a0, 0x00(s1)
    sw   a0, 0x20(s1)

    # Clear trap_handled, re-enable MIE.MEIE (handler cleared it if external)
    sw   zero, 0x10(s1)
    li   t0, 0x800
    csrs mie, t0

    # Signal: ready for external IRQ (timer still asserted)
    li   x31, 0x22222222

    # Spin-wait for second trap
wait_trap2b:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap2b

    # Save trap_count and MCAUSE
    lw   a0, 0x00(s1)
    sw   a0, 0x24(s1)
    lw   a0, 0x04(s1)
    sw   a0, 0x28(s1)
    lw   a1, 0x28(s1)

    # Signal: Phase 2 complete
    li   x31, 0x23232323


    #=================================================================
    # PHASE 3: CSR enable race (CSRS MIE with IRQ already pending)
    #   Testbench asserts timer IRQ while MIE.MTIE=0.
    #   Firmware then enables MIE.MTIE via CSRS -- the interrupt
    #   should be taken on the very next instruction boundary.
    #=================================================================

    # Disable all MIE bits
    li   t0, 0xFFFFFFFF
    csrc mie, t0

    # Save trap_count before
    lw   a0, 0x00(s1)
    sw   a0, 0x30(s1)

    # Clear trap_handled
    sw   zero, 0x10(s1)

    # Signal: ready (testbench asserts timer IRQ now, MIE.MTIE=0 so no trap yet)
    li   x31, 0x31313131

    # Delay to let testbench assert IRQ
    nop
    nop
    nop
    nop
    nop

    # Now enable MIE.MTIE -- interrupt should be taken immediately after this
    li   t0, 0x80
    csrs mie, t0

    # These NOPs should NOT execute before the interrupt fires
    # (or at most 1-2 may execute due to pipeline latency)
    nop
    nop
    nop
    nop

    # If we get here, the interrupt was taken and handler returned
    # Spin-wait for trap_handled (should already be set)
wait_trap3:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap3

    # Save trap_count and MCAUSE
    lw   a0, 0x00(s1)
    sw   a0, 0x34(s1)
    lw   a0, 0x04(s1)
    sw   a0, 0x38(s1)
    lw   a1, 0x38(s1)

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: WFI immediate wakeup
    #   Testbench asserts timer IRQ while MIE.MTIE=1 but MSTATUS.MIE=0.
    #   Firmware executes WFI. Per spec, WFI should return immediately
    #   when an enabled interrupt is pending (regardless of MIE).
    #   Then re-enable MSTATUS.MIE to take the interrupt.
    #=================================================================

    # Disable MSTATUS.MIE (global interrupt disable)
    li   t0, 0x8
    csrc mstatus, t0

    # Enable MIE.MTIE
    li   t0, 0x80
    csrs mie, t0

    # Clear trap_handled
    sw   zero, 0x10(s1)

    # Write marker before WFI
    li   t0, 0xAAAA
    sw   t0, 0x40(s1)

    # Signal: ready (testbench asserts timer IRQ)
    li   x31, 0x41414141

    # Delay to let testbench assert IRQ
    nop
    nop
    nop
    nop
    nop

    # Execute WFI -- should return immediately since MTIP & MTIE are set
    wfi

    # Write marker after WFI (proves WFI didn't stall forever)
    li   t0, 0xBBBB
    sw   t0, 0x44(s1)

    # Now enable MSTATUS.MIE to actually take the interrupt
    li   t0, 0x8
    csrs mstatus, t0

    # Spin-wait for trap
wait_trap4:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap4

    # Save trap_count
    lw   a0, 0x00(s1)
    sw   a0, 0x48(s1)
    lw   a1, 0x48(s1)

    # Signal: Phase 4 complete
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: IRQ during load/store sequence
    #   Testbench asserts timer IRQ while firmware is doing a sequence
    #   of loads and stores to SRAM. Verifies that all memory
    #   operations complete correctly and loaded values are preserved.
    #=================================================================

    # Disable all MIE bits first (avoid race with Phase 4 timer deassert)
    li   t0, 0xFFFFFFFF
    csrc mie, t0

    # Clear trap_handled
    sw   zero, 0x10(s1)

    # Signal: ready (testbench deasserts old IRQs, then asserts timer)
    li   x31, 0x51515151

    # Delay to let testbench set up IRQ
    nop
    nop
    nop
    nop
    nop

    # Now enable MIE.MTIE (testbench has asserted timer by now)
    li   t0, 0x80
    csrs mie, t0

    # Load sequence from test data (IRQ should fire during this)
    lw   a2, 0x80(s1)       # expect 0xDEADBEEF
    lw   a3, 0x84(s1)       # expect 0xCAFEBABE
    lw   a4, 0x88(s1)       # expect 0x12345678

    # Store loaded values to verification area
    sw   a2, 0x50(s1)
    sw   a3, 0x54(s1)
    sw   a4, 0x58(s1)

    # Spin-wait for trap_handled (IRQ should have fired by now)
wait_trap5:
    lw   t0, 0x10(s1)
    beqz t0, wait_trap5

    # Save trap_count
    lw   a0, 0x00(s1)
    sw   a0, 0x5C(s1)
    lw   a1, 0x5C(s1)

    # Signal: Phase 5 complete
    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: Rapid ECALL-MRET cycles
    #   Execute 10 rapid ECALLs to stress the trap entry/exit path.
    #   Each ECALL traps to handler, handler advances MEPC, MRETs back.
    #   Verifies trap_count == 10 and no pipeline corruption.
    #=================================================================

    # Reset trap_count
    sw   zero, 0x00(s1)
    sw   zero, 0x10(s1)

    # Disable interrupts for this phase (sync exceptions only)
    li   t0, 0xFFFFFFFF
    csrc mie, t0

    # Signal: ready
    li   x31, 0x61616161

    # 5 rapid ECALLs
    ecall
    ecall
    ecall
    ecall
    ecall

    # Save trap_count (expect 5)
    lw   a0, 0x00(s1)
    sw   a0, 0x60(s1)
    lw   a1, 0x60(s1)

    # Signal: Phase 6 complete
    li   x31, 0x66666666


    # Check callee-saved registers preserved
    # (implicit -- testbench checks)


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
