#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_mret_edge
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP MRET EDGE
#   Verify MRET/SRET behavior with unusual MPIE/SPIE pre-states:
#   - MRET with MPIE=0: MIE restored to 0, MPIE set to 1
#   - MRET to U-mode with MPIE=0: privilege transition + MIE=0
#   - SRET with SPIE=0: SIE restored to 0, SPIE set to 1
#   - Double MRET: MRET -> trap -> MRET chain
#
#   All tests are synchronous -- no testbench-driven IRQ needed.
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
# Phase 2 (MRET with MPIE=0):
#   0x20: MSTATUS after MRET (check MIE=0, MPIE=1)
#
# Phase 3 (MRET to U-mode with MPIE=0):
#   0x30: MSTATUS in ECALL handler (check MPP=00 from U-mode)
#
# Phase 4 (SRET with SPIE=0):
#   0x40: MSTATUS after SRET+ECALL (check SIE=0, SPIE=1)
#
# Phase 5 (Double MRET):
#   0x50: success flag (1 if both MRETs completed)
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

    # Check cause type
    # ECALL from U-mode = 8
    # ECALL from S-mode = 9
    # ECALL from M-mode = 11
    li   t3, 8
    beq  t0, t3, handle_ecall_u
    li   t3, 9
    beq  t0, t3, handle_ecall_s
    li   t3, 11
    beq  t0, t3, handle_ecall_m
    li   t3, 2
    beq  t0, t3, handle_illegal

    # Default: advance MEPC past the faulting instruction
    j    advance_mepc

handle_ecall_u:
    # Save MSTATUS for Phase 3 verification
    sw   t2, 0x30(s1)

    # Advance MEPC past ECALL (always 4 bytes)
    addi t1, t1, 4
    csrw mepc, t1

    # Return to M-mode: set MPP=11
    li   t3, 0x1800
    csrs mstatus, t3

    j    handler_done

handle_ecall_s:
    # Advance MEPC past ECALL
    addi t1, t1, 4
    csrw mepc, t1

    # Return to M-mode: set MPP=11
    li   t3, 0x1800
    csrs mstatus, t3

    j    handler_done

handle_ecall_m:
    # Advance MEPC past ECALL
    addi t1, t1, 4
    csrw mepc, t1
    j    handler_done

handle_illegal:
    # For Phase 5 double MRET: illegal SRET in U-mode triggers this
    # Advance MEPC past the illegal instruction
    j    advance_mepc

advance_mepc:
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
    sw   t0, 0x30(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x50(s1)

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
    # PHASE 2: MRET with MPIE=0
    #   Set MPP=11 (M-mode), MPIE=0, MEPC=after_mret2
    #   After MRET: MIE should be 0 (from MPIE), MPIE should be 1
    #=================================================================

    # Clear MSTATUS.MIE and MSTATUS.MPIE
    li   t0, 0x88              # MIE(3) + MPIE(7)
    csrc mstatus, t0

    # Set MPP=11 (M-mode)
    li   t0, 0x1800
    csrs mstatus, t0

    # Set MEPC to target after MRET
    la   t0, after_mret2
    csrw mepc, t0

    # Execute MRET
    mret

    .align 2
after_mret2:
    # Read MSTATUS after MRET
    csrr t0, mstatus
    sw   t0, 0x20(s1)
    lw   t1, 0x20(s1)         # load-back

    # Signal: Phase 2 complete
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: MRET to U-mode with MPIE=0
    #   Set MPP=00 (U-mode), MPIE=0, MEPC=u_mode_code_p3
    #   In U-mode, ECALL back to M-mode
    #   Verify MPP was 00 in handler
    #=================================================================

    # Clear MSTATUS.MIE, MPIE, and MPP
    li   t0, 0x1888            # MIE(3) + MPIE(7) + MPP(12:11)
    csrc mstatus, t0

    # MPP=00 is already set (cleared above)
    # MPIE=0 already cleared

    # Set MEPC to U-mode target
    la   t0, u_mode_code_p3
    csrw mepc, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # MRET to U-mode
    mret

    .align 2
u_mode_code_p3:
    # Now in U-mode
    # ECALL to return to M-mode
    ecall

    # Back in M-mode after handler returns here
    # (handler set MPP=11, so MRET returns to M-mode)

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: SRET with SPIE=0
    #   Set SPP=0 (U-mode), SPIE=0, SEPC=target
    #   Execute SRET from S-mode (via MRET to S-mode first)
    #   After SRET: SIE=0 (from SPIE), SPIE=1
    #   ECALL back to M-mode, check MSTATUS
    #=================================================================

    # First, set up S-mode: MRET to S-mode
    # Set MPP=01 (S-mode)
    li   t0, 0x1800            # clear MPP
    csrc mstatus, t0
    li   t0, 0x0800            # set MPP=01
    csrs mstatus, t0

    # Set MPIE=1 so MIE=1 after MRET (we want interrupts manageable)
    li   t0, 0x80
    csrs mstatus, t0

    # Set MEPC to S-mode code
    la   t0, s_mode_code_p4
    csrw mepc, t0

    # Set up SSTATUS: clear SIE and SPIE
    li   t0, 0x22              # SIE(1) + SPIE(5)
    csrc sstatus, t0

    # Set SPP=0 (U-mode target)
    li   t0, 0x100             # SPP bit 8
    csrc sstatus, t0

    # Set SEPC to U-mode target after SRET
    la   t0, u_mode_after_sret_p4
    csrw sepc, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # MRET to S-mode
    mret

    .align 2
s_mode_code_p4:
    # Now in S-mode
    # Execute SRET to U-mode with SPIE=0
    sret

    .align 2
u_mode_after_sret_p4:
    # Now in U-mode after SRET
    # Read SSTATUS is not accessible from U-mode, so ECALL to M-mode
    ecall

    # Back in M-mode after handler
    # Read MSTATUS to check SIE and SPIE fields
    csrr t0, mstatus
    sw   t0, 0x40(s1)
    lw   t1, 0x40(s1)         # load-back

    # Signal: Phase 4 complete
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Double MRET
    #   Set up MRET to code that triggers an ECALL, handler returns
    #   via MRET. Tests MRET -> trap -> MRET chain.
    #=================================================================

    # Clear success flag
    sw   zero, 0x50(s1)

    # Set MPP=00 (U-mode)
    li   t0, 0x1800
    csrc mstatus, t0

    # Set MPIE=1
    li   t0, 0x80
    csrs mstatus, t0

    # Set MEPC to U-mode code that does ECALL
    la   t0, u_mode_ecall_p5
    csrw mepc, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # First MRET: M-mode -> U-mode
    mret

    .align 2
u_mode_ecall_p5:
    # In U-mode: trigger ECALL (trap to M-mode, handler does 2nd MRET)
    ecall

    # After handler's MRET, we return here
    # Back in M-mode (handler set MPP=11)

    # Mark success
    li   t0, 1
    sw   t0, 0x50(s1)
    lw   t1, 0x50(s1)         # load-back

    # Signal: Phase 5 complete
    li   x31, 0x55555555


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
