#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_vectored_stvec
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ VECTORED STVEC
#   Verify vectored interrupt mode on STVEC for delegated S-mode interrupts:
#   - S-mode vectored timer IRQ from U-mode
#   - S-mode exception still goes to STVEC BASE (not vectored)
#
#   STIP is set from firmware (no testbench-driven IRQ needed).
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# M-mode handler working area:
#   0x00: m_trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x0C: last MSTATUS
#   0x10: m_handled flag
#
# S-mode handler working area:
#   0x18: s_trap_count
#   0x1C: last SCAUSE
#   0x20: last SEPC
#   0x24: last SSTATUS
#   0x28: s_handled flag
#   0x2C: vector_entry_id (which vector table entry was used)
#
# Phase 2 copies (S-mode vectored timer IRQ):
#   0x30: SCAUSE             (expect 0x80000005 - S-timer)
#   0x34: vector_entry_id    (expect 5)
#
# Phase 3 copies (S-mode exception, not vectored):
#   0x40: SCAUSE             (expect 2 - illegal instruction)
#   0x44: vector_entry_id    (expect 0 - base entry)
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER (direct mode)
    #=================================================================
    .align 2

m_trap_handler:
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

    # Increment m_trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Store to working area
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    # Check cause
    # ECALL from U-mode = 8
    # ECALL from S-mode = 9
    li   t3, 8
    beq  t0, t3, m_handle_ecall
    li   t3, 9
    beq  t0, t3, m_handle_ecall

    # Default: advance MEPC
    j    m_advance_mepc

m_handle_ecall:
    # Advance MEPC past ECALL (4 bytes)
    addi t1, t1, 4
    csrw mepc, t1

    # Return to M-mode: set MPP=11
    li   t3, 0x1800
    csrs mstatus, t3

    j    m_handler_done

m_advance_mepc:
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, m_advance_4b
    addi t1, t1, 2
    j    m_mepc_done
m_advance_4b:
    addi t1, t1, 4
m_mepc_done:
    csrw mepc, t1

m_handler_done:
    # Set m_handled flag
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
    # S-MODE SHARED HANDLER (jumped to from vector table entries)
    #=================================================================
    .align 2

s_shared_handler:
    # Save context on stack
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    # Read S-mode trap CSRs
    csrr t0, scause
    csrr t1, sepc
    csrr t2, sstatus

    # Increment s_trap_count
    lw   t3, 0x18(s1)
    addi t3, t3, 1
    sw   t3, 0x18(s1)

    # Store to working area
    sw   t0, 0x1C(s1)
    sw   t1, 0x20(s1)
    sw   t2, 0x24(s1)

    # Check if interrupt (MSB=1)
    bltz t0, s_handle_interrupt

    # ---- Exception path ----
    # Store vector_entry_id = 0 (base, not vectored)
    sw   zero, 0x2C(s1)

    # Advance SEPC past faulting instruction
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, s_advance_4b
    addi t1, t1, 2
    j    s_sepc_done
s_advance_4b:
    addi t1, t1, 4
s_sepc_done:
    csrw sepc, t1
    j    s_handler_done

s_handle_interrupt:
    # Extract cause code
    andi t3, t0, 0x1F

    # Store vector_entry_id = cause code
    sw   t3, 0x2C(s1)

    # Check for S-mode timer interrupt (cause 5)
    li   t4, 5
    bne  t3, t4, s_handler_done

    # Clear MIP.STIP (bit 5) - need to use M-mode CSR via ECALL
    # Actually, we can clear SIP.STIP from S-mode if writable
    # Per spec, STIP in MIP is writable from M-mode only
    # From S-mode, clear SIE.STIE to stop re-firing
    li   t4, 0x20              # SIE.STIE = bit 5
    csrc sie, t4

s_handler_done:
    # Set s_handled flag
    li   t4, 1
    sw   t4, 0x28(s1)
    lw   t4, 0x28(s1)

    # Restore context
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24

    sret


    #=================================================================
    # S-MODE VECTOR TABLE (vectored mode: STVEC base, mode=01)
    #
    # Each entry is exactly 4 bytes (one JAL/J instruction).
    # Entry N is at STVEC_BASE + 4*N.
    #   Entry 0: exceptions (not vectored, but base handler)
    #   Entry 1: S-mode software interrupt (SSI, cause 1)
    #   Entry 2: reserved
    #   Entry 3: reserved (M-mode software, not delegated normally)
    #   Entry 4: reserved
    #   Entry 5: S-mode timer interrupt (STI, cause 5)
    #   Entry 6-8: reserved
    #   Entry 9: S-mode external interrupt (SEI, cause 9)
    #=================================================================
    .align 4                   # 16-byte alignment minimum for vector table
    .option push               # Save current arch state (rvc on/off)
    .option norvc              # Force 4-byte instructions for vector table entries

s_vector_table:
    j    s_shared_handler      # Entry 0: exception handler (base)
    j    s_shared_handler      # Entry 1: SSI
    j    s_shared_handler      # Entry 2: reserved
    j    s_shared_handler      # Entry 3: reserved
    j    s_shared_handler      # Entry 4: reserved
    j    s_shared_handler      # Entry 5: STI (S-mode timer)
    j    s_shared_handler      # Entry 6: reserved
    j    s_shared_handler      # Entry 7: reserved
    j    s_shared_handler      # Entry 8: reserved
    j    s_shared_handler      # Entry 9: SEI (S-mode external)

    .option pop                # Restore surrounding arch state -- under -march
                               # without 'c' this keeps rvc OFF (no compressed
                               # instructions emitted into the rest of the .s),
                               # so the binary runs under C_EXTENSION=0 too.
                               # Under -march with 'c' this restores rvc so
                               # main test code auto-compresses as before.


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
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)

    #=================================================================
    # PHASE 1: Install handlers, set up delegation
    #=================================================================

    # Install M-mode trap handler (direct mode)
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Install S-mode vector table (vectored mode: base | 0x1)
    la   t0, s_vector_table
    ori  t0, t0, 1             # mode = 01 (vectored)
    csrw stvec, t0

    # Delegate S-mode timer interrupt to S-mode (MIDELEG bit 5)
    li   t0, 0x20              # bit 5 = STI
    csrs mideleg, t0

    # Delegate illegal instruction exception to S-mode (MEDELEG bit 2)
    li   t0, 0x4               # bit 2 = illegal instruction
    csrs medeleg, t0

    # Initialize callee-saved registers to known pattern
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Signal: Phase 1 init complete
    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: S-mode vectored timer IRQ from U-mode
    #
    # Set MIP.STIP from M-mode, enable SIE.STIE, enable SSTATUS.SIE.
    # Transition M->U mode. S-timer interrupt fires, delegated to
    # S-mode via vectored STVEC: target = STVEC_BASE + 4*5.
    #=================================================================

    # Set MIP.STIP (bit 5) to create pending S-timer interrupt
    li   t0, 0x20
    csrs mip, t0

    # Enable SIE.STIE (bit 5)
    li   t0, 0x20
    csrs sie, t0

    # Enable SSTATUS.SIE (bit 1)
    li   t0, 0x2
    csrs sstatus, t0

    # Clear s_handled flag
    sw   zero, 0x28(s1)

    # Transition to U-mode: set MPP=00, MPIE=1
    li   t0, 0x1800            # clear MPP
    csrc mstatus, t0
    li   t0, 0x80              # set MPIE=1
    csrs mstatus, t0

    # Set MEPC to U-mode target
    la   t0, u_mode_p2
    csrw mepc, t0

    # MRET to U-mode (interrupt will fire since SIE=1 in S/U mode)
    mret

    .align 2
u_mode_p2:
    # After S-mode handler's SRET, we return here in U-mode
    # Wait for s_handled (should already be set)
wait_s_handled_p2:
    lw   t0, 0x28(s1)
    beqz t0, wait_s_handled_p2

    # Copy results to Phase 2 area
    lw   t0, 0x1C(s1)         # SCAUSE
    sw   t0, 0x30(s1)
    lw   t0, 0x2C(s1)         # vector_entry_id
    sw   t0, 0x34(s1)
    lw   t1, 0x34(s1)         # load-back

    # ECALL back to M-mode
    ecall

    # Back in M-mode

    # Clear MIP.STIP for next phase
    li   t0, 0x20
    csrc mip, t0

    # Signal: Phase 2 complete
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: S-mode exception goes to STVEC BASE (not vectored)
    #
    # In S-mode, trigger illegal instruction. S-mode handler catches
    # it at STVEC BASE (entry 0, not vectored for exceptions).
    #=================================================================

    # Clear s_handled and vector_entry_id
    sw   zero, 0x28(s1)
    li   t0, 0xFF
    sw   t0, 0x2C(s1)         # sentinel to detect if it gets cleared to 0

    # Re-enable SIE in SSTATUS
    li   t0, 0x2
    csrs sstatus, t0

    # Transition to S-mode: set MPP=01
    li   t0, 0x1800            # clear MPP
    csrc mstatus, t0
    li   t0, 0x0800            # set MPP=01 (S-mode)
    csrs mstatus, t0
    li   t0, 0x80              # set MPIE=1
    csrs mstatus, t0

    # Set MEPC to S-mode target
    la   t0, s_mode_p3
    csrw mepc, t0

    # MRET to S-mode
    mret

    .align 2
s_mode_p3:
    # In S-mode: trigger illegal instruction
    # Use an invalid instruction encoding
    .word 0xFFFFFFFF           # illegal instruction (32-bit, bits[1:0]=11)

    # After S-mode handler advances SEPC, we return here
    # Wait for s_handled
wait_s_handled_p3:
    lw   t0, 0x28(s1)
    beqz t0, wait_s_handled_p3

    # Copy results to Phase 3 area
    lw   t0, 0x1C(s1)         # SCAUSE
    sw   t0, 0x40(s1)
    lw   t0, 0x2C(s1)         # vector_entry_id
    sw   t0, 0x44(s1)
    lw   t1, 0x44(s1)         # load-back

    # ECALL back to M-mode (from S-mode)
    ecall

    # Back in M-mode

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
