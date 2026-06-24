#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_vectored_deleg
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP VECTORED DELEG
#   Combined MTVEC + STVEC vectored mode with delegation:
#   - MTVEC in vectored mode for non-delegated M-mode interrupts
#   - STVEC in vectored mode for delegated S-mode interrupts
#   - Both vectored modes active simultaneously
#   - Delegated S-timer from U-mode -> STVEC vectored (cause 5)
#   - Non-delegated M-external from S-mode -> MTVEC vectored (cause 11)
#   - Exception in S-mode -> STVEC BASE (not vectored)
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# M-mode handler working area:
#   0x000: m_trap_count
#   0x004: last MCAUSE
#   0x008: last MEPC
#   0x00C: m_handled flag
#   0x010: m_vector_entry_id
#
# S-mode handler working area:
#   0x018: s_trap_count
#   0x01C: last SCAUSE
#   0x020: last SEPC
#   0x024: s_handled flag
#   0x028: s_vector_entry_id
#
# Phase 2 (delegated S-timer -> STVEC vectored):
#   0x030: SCAUSE             (expect 0x80000005)
#   0x034: s_vector_entry_id  (expect 5)
#
# Phase 3 (non-delegated M-external -> MTVEC vectored):
#   0x040: MCAUSE             (expect 0x8000000B)
#   0x044: m_vector_entry_id  (expect 11)
#
# Phase 4 (exception in S-mode -> STVEC BASE):
#   0x050: SCAUSE             (expect 2 - illegal instruction)
#   0x054: s_vector_entry_id  (expect 0 - base entry)
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE VECTOR TABLE (vectored mode: MTVEC base, mode=01)
    #
    # Entry N is at MTVEC_BASE + 4*N.
    #=================================================================
    .align 2
    .option push
    .option norvc

m_vector_table:
    j    m_exception_entry      # entry  0: exceptions
    j    m_default_handler      # entry  1
    j    m_default_handler      # entry  2
    j    m_sw_vector_entry      # entry  3: machine software
    j    m_default_handler      # entry  4
    j    m_default_handler      # entry  5
    j    m_default_handler      # entry  6
    j    m_timer_vector_entry   # entry  7: machine timer
    j    m_default_handler      # entry  8
    j    m_default_handler      # entry  9
    j    m_default_handler      # entry 10
    j    m_ext_vector_entry     # entry 11: machine external

    .option pop

    #=================================================================
    # M-MODE VECTOR ENTRY STUBS
    #=================================================================

m_timer_vector_entry:
    li   t0, 7
    sw   t0, 0x10(s1)
    j    m_shared_handler

m_sw_vector_entry:
    li   t0, 3
    sw   t0, 0x10(s1)
    j    m_shared_handler

m_ext_vector_entry:
    li   t0, 11
    sw   t0, 0x10(s1)
    j    m_shared_handler

m_exception_entry:
    li   t0, 0
    sw   t0, 0x10(s1)
    j    m_shared_handler_exception

m_default_handler:
    li   t0, 0xFF
    sw   t0, 0x10(s1)
    j    m_shared_handler


    #=================================================================
    # M-MODE SHARED HANDLER (for interrupts)
    #=================================================================
m_shared_handler:
    addi sp, sp, -24
    sw   t1, 20(sp)
    sw   t2, 16(sp)
    sw   t3, 12(sp)
    sw   t4,  8(sp)
    sw   a0,  4(sp)

    csrr t1, mcause
    csrr t2, mepc

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    sw   t1, 0x04(s1)
    sw   t2, 0x08(s1)

    # Disable the interrupt source
    andi t3, t1, 0x1F
    li   t4, 7
    beq  t3, t4, m_vec_disable_mtie
    li   t4, 11
    beq  t3, t4, m_vec_disable_meie
    li   t4, 3
    beq  t3, t4, m_vec_disable_msie
    j    m_vec_irq_done

m_vec_disable_mtie:
    li   t4, 0x80
    csrc mie, t4
    j    m_vec_irq_done

m_vec_disable_meie:
    li   t4, 0x800
    csrc mie, t4
    j    m_vec_irq_done

m_vec_disable_msie:
    li   t4, 0x8
    csrc mie, t4

m_vec_irq_done:
    li   t4, 1
    sw   t4, 0x0C(s1)

    lw   a0,  4(sp)
    lw   t4,  8(sp)
    lw   t3, 12(sp)
    lw   t2, 16(sp)
    lw   t1, 20(sp)
    addi sp, sp, 24
    mret


    #=================================================================
    # M-MODE SHARED HANDLER (for exceptions: ECALL)
    #=================================================================
m_shared_handler_exception:
    addi sp, sp, -24
    sw   t1, 20(sp)
    sw   t2, 16(sp)
    sw   t3, 12(sp)
    sw   t4,  8(sp)
    sw   a0,  4(sp)

    csrr t1, mcause
    csrr t2, mepc

    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    sw   t1, 0x04(s1)
    sw   t2, 0x08(s1)

    # Advance MEPC past ECALL (4 bytes)
    addi t2, t2, 4
    csrw mepc, t2

    # If a0 == 1, return to M-mode: set MPP=11
    li   t4, 1
    bne  a0, t4, m_exc_done
    li   t4, 0x1800
    csrs mstatus, t4

m_exc_done:
    li   t4, 1
    sw   t4, 0x0C(s1)

    lw   a0,  4(sp)
    lw   t4,  8(sp)
    lw   t3, 12(sp)
    lw   t2, 16(sp)
    lw   t1, 20(sp)
    addi sp, sp, 24
    mret


    #=================================================================
    # S-MODE SHARED HANDLER (jumped to from S-mode vector table)
    #=================================================================
    .align 2

s_shared_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, scause
    csrr t1, sepc
    csrr t2, sstatus

    lw   t3, 0x18(s1)
    addi t3, t3, 1
    sw   t3, 0x18(s1)

    sw   t0, 0x1C(s1)
    sw   t1, 0x20(s1)

    # Check if interrupt
    bltz t0, s_handle_interrupt

    # ---- Exception path ----
    # vector_entry_id = 0 (went to base)
    sw   zero, 0x28(s1)

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
    andi t3, t0, 0x1F
    sw   t3, 0x28(s1)          # vector_entry_id = cause code

    # Disable SIE.STIE to stop re-firing
    li   t4, 5
    bne  t3, t4, s_handler_done
    li   t4, 0x20
    csrc sie, t4

s_handler_done:
    li   t4, 1
    sw   t4, 0x24(s1)
    lw   t4, 0x24(s1)

    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
    sret


    #=================================================================
    # S-MODE VECTOR TABLE (vectored mode: STVEC base, mode=01)
    #=================================================================
    .align 4
    .option push
    .option norvc

s_vector_table:
    j    s_shared_handler       # entry 0: exceptions
    j    s_shared_handler       # entry 1: S-mode software (SSI)
    j    s_shared_handler       # entry 2: reserved
    j    s_shared_handler       # entry 3: reserved
    j    s_shared_handler       # entry 4: reserved
    j    s_shared_handler       # entry 5: S-mode timer (STI)
    j    s_shared_handler       # entry 6: reserved
    j    s_shared_handler       # entry 7: reserved
    j    s_shared_handler       # entry 8: reserved
    j    s_shared_handler       # entry 9: S-mode external (SEI)

    .option pop


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
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
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)

    #=================================================================
    # PHASE 1: Install handlers, set up delegation
    #=================================================================

    # Install M-mode vector table (vectored mode)
    la   t0, m_vector_table
    ori  t0, t0, 0x1            # mode = 01 (vectored)
    csrw mtvec, t0

    # Install S-mode vector table (vectored mode)
    la   t0, s_vector_table
    ori  t0, t0, 0x1            # mode = 01 (vectored)
    csrw stvec, t0

    # Delegate S-mode timer interrupt to S-mode (MIDELEG bit 5)
    li   t0, 0x20
    csrs mideleg, t0

    # Delegate illegal instruction exception to S-mode (MEDELEG bit 2)
    li   t0, 0x4
    csrs medeleg, t0

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Delegated S-timer from U-mode -> STVEC vectored
    #
    # Set MIP.STIP from M-mode. Enable SIE.STIE + SSTATUS.SIE.
    # Transition to U-mode. S-timer fires, delegated to S-mode
    # via vectored STVEC: target = STVEC_BASE + 4*5.
    #=================================================================

    # Set MIP.STIP (bit 5)
    li   t0, 0x20
    csrs mip, t0

    # Enable SIE.STIE (bit 5)
    li   t0, 0x20
    csrs sie, t0

    # Enable SSTATUS.SIE (bit 1)
    li   t0, 0x2
    csrs sstatus, t0

    # Clear s_handled
    sw   zero, 0x24(s1)

    # Transition to U-mode: MPP=00, MPIE=1
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x80
    csrs mstatus, t0

    la   t0, u_mode_p2
    csrw mepc, t0
    mret

    .align 2
u_mode_p2:
    # S-mode handler ran and returned here
wait_s_p2:
    lw   t0, 0x24(s1)
    beqz t0, wait_s_p2

    # Copy results
    lw   t0, 0x1C(s1)          # SCAUSE
    sw   t0, 0x30(s1)
    lw   t0, 0x28(s1)          # s_vector_entry_id
    sw   t0, 0x34(s1)
    lw   t1, 0x34(s1)

    # ECALL to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Non-delegated M-external from S-mode -> MTVEC vectored
    #
    # Testbench drives irq_m_external. M-mode external interrupt is
    # NOT delegated, so it traps to M-mode via MTVEC vectored:
    # target = MTVEC_BASE + 4*11.
    #=================================================================

    # Disable MSTATUS.MIE first -- prevents the external IRQ from firing
    # in M-mode (which would overwrite MEPC/MPP set up for MRET to S-mode)
    li   t0, 0x8
    csrc mstatus, t0

    # Enable MIE.MEIE (bit 11)
    li   t0, 0x800
    csrs mie, t0

    # Clear m_handled
    sw   zero, 0x0C(s1)

    # Transition to S-mode: MPP=01, MPIE=1
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0
    li   t0, 0x80
    csrs mstatus, t0

    la   t0, s_mode_p3
    csrw mepc, t0

    # Signal testbench: ready for external IRQ
    # MIE=0 here so the IRQ is held pending until MRET to S-mode
    # (M-mode interrupts are always taken from S-mode regardless of MIE)
    li   x31, 0x31313131

    mret

    .align 2
s_mode_p3:
    # In S-mode. Spin-wait for m_handled (M-mode external IRQ handler)
wait_m_p3:
    lw   t0, 0x0C(s1)
    beqz t0, wait_m_p3

    # Copy results
    lw   t0, 0x04(s1)          # MCAUSE
    sw   t0, 0x40(s1)
    lw   t0, 0x10(s1)          # m_vector_entry_id
    sw   t0, 0x44(s1)
    lw   t1, 0x44(s1)

    # ECALL to M-mode (from S-mode)
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Exception in S-mode -> STVEC BASE (not vectored)
    #
    # Trigger illegal instruction in S-mode with delegation active.
    # Exception goes to STVEC BASE (entry 0, not vectored).
    # This verifies exceptions use BASE even when STVEC is vectored.
    #=================================================================

    # Clear s_handled and set sentinel for vector_entry_id
    sw   zero, 0x24(s1)
    li   t0, 0xFF
    sw   t0, 0x28(s1)

    # Re-enable SSTATUS.SIE
    li   t0, 0x2
    csrs sstatus, t0

    # Transition to S-mode: MPP=01, MPIE=1
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0
    li   t0, 0x80
    csrs mstatus, t0

    la   t0, s_mode_p4
    csrw mepc, t0
    mret

    .align 2
s_mode_p4:
    # Trigger illegal instruction
    .word 0xFFFFFFFF

    # Handler advances SEPC, returns here
wait_s_p4:
    lw   t0, 0x24(s1)
    beqz t0, wait_s_p4

    # Copy results
    lw   t0, 0x1C(s1)          # SCAUSE
    sw   t0, 0x50(s1)
    lw   t0, 0x28(s1)          # s_vector_entry_id
    sw   t0, 0x54(s1)
    lw   t1, 0x54(s1)

    # ECALL to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x44444444


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
