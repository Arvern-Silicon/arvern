#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_seip
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP IRQ SEIP
#   Verifies that irq_s_external_i (SEIP hardware input) works correctly and
#   is independent from irq_m_external_i (MEIP):
#   - Phase 2: irq_s_external fires -> S-mode trap (delegated SEIP,
#   cause 9) via vectored STVEC
#   - Phase 3: irq_m_external fires -> M-mode trap (non-delegated MEIP,
#   cause 11) via vectored MTVEC; irq_s_external stays low
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
# Phase 2 results (delegated SEIP -> STVEC vectored):
#   0x030: SCAUSE             (expect 0x80000009)
#   0x034: s_vector_entry_id  (expect 9)
#
# Phase 3 results (non-delegated MEIP -> MTVEC vectored):
#   0x040: MCAUSE             (expect 0x8000000B)
#   0x044: m_vector_entry_id  (expect 11)
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

    # Disable the interrupt source to prevent re-fire
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
    # M-MODE SHARED HANDLER (for exceptions: ECALL from S-mode)
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

    # Increment s_trap_count
    lw   t3, 0x18(s1)
    addi t3, t3, 1
    sw   t3, 0x18(s1)

    sw   t0, 0x1C(s1)
    sw   t1, 0x20(s1)

    # Check if interrupt (MSB set)
    bltz t0, s_handle_interrupt

    # ---- Exception path ----
    # vector_entry_id = 0 (base entry for exceptions)
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

    # Disable SIE.SEIE to stop re-firing on SEI (cause 9)
    li   t4, 9
    bne  t3, t4, s_check_stie
    li   t4, 0x200
    csrc sie, t4
    j    s_handler_done

s_check_stie:
    # Disable SIE.STIE to stop re-firing on STI (cause 5)
    li   t4, 5
    bne  t3, t4, s_check_ssie
    li   t4, 0x20
    csrc sie, t4
    j    s_handler_done

s_check_ssie:
    # Disable SIE.SSIE to stop re-firing on SSI (cause 1)
    li   t4, 1
    bne  t3, t4, s_handler_done
    li   t4, 0x2
    csrc sie, t4

s_handler_done:
    li   t4, 1
    sw   t4, 0x24(s1)

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
    # Entry N is at STVEC_BASE + 4*N.
    # Entry 9 (SEI) is at offset 36 from base.
    # .align 4 ensures 16-byte alignment (required for vectored STVEC).
    # .option norvc ensures each jump is 4 bytes (not 2-byte compressed).
    #=================================================================
    .align 4
    .option push
    .option norvc

s_vector_table:
    j    s_shared_handler       # entry 0: exceptions / base
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

    #=================================================================
    # PHASE 1: Install handlers, set up delegation, sync
    #=================================================================

    # Install M-mode vector table (vectored mode)
    la   t0, m_vector_table
    ori  t0, t0, 0x1            # mode = 01 (vectored)
    csrw mtvec, t0

    # Install S-mode vector table (vectored mode)
    la   t0, s_vector_table
    ori  t0, t0, 0x1            # mode = 01 (vectored)
    csrw stvec, t0

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: irq_s_external fires -> S-mode trap (delegated SEIP)
    #
    # Delegate SEI to S-mode (MIDELEG bit 9).
    # Enable SIE.SEIE + SSTATUS.SIE.
    # Transition to S-mode via mret (MPP=01, MPIE=1).
    # In S-mode: signal testbench with x31=0x21212121, spin-wait
    # for s_handled. Testbench asserts irq_s_external after sync.
    # Handler fires, stores scause + vector_entry_id.
    # After sret returns to S-mode spin-wait completes, copy results,
    # ecall back to M-mode.
    #=================================================================

    # Delegate S-mode external interrupt to S-mode (MIDELEG bit 9)
    li   t0, 0x200
    csrs mideleg, t0

    # Enable SIE.SEIE (bit 9)
    li   t0, 0x200
    csrs sie, t0

    # Enable SSTATUS.SIE (bit 1)
    li   t0, 0x2
    csrs sstatus, t0

    # Clear s_handled
    sw   zero, 0x24(s1)

    # Disable MSTATUS.MIE to prevent premature M-mode interrupt
    li   t0, 0x8
    csrc mstatus, t0

    # Transition to S-mode: MPP=01, MPIE=1
    li   t0, 0x1800
    csrc mstatus, t0            # Clear MPP bits
    li   t0, 0x0800
    csrs mstatus, t0            # MPP = 01 (S-mode)
    li   t0, 0x80
    csrs mstatus, t0            # MPIE = 1

    la   t0, s_mode_p2
    csrw mepc, t0
    mret

    .align 2
s_mode_p2:
    # Now in S-mode with SIE=1. Signal testbench we are ready.
    li   x31, 0x21212121

    # Spin-wait for S-mode handler to complete
wait_s_p2:
    lw   t0, 0x24(s1)
    beqz t0, wait_s_p2

    # S-mode handler fired and returned here via sret.
    # Copy results to Phase 2 result area.
    lw   t0, 0x1C(s1)          # SCAUSE
    sw   t0, 0x30(s1)
    lw   t0, 0x28(s1)          # s_vector_entry_id
    sw   t0, 0x34(s1)
    lw   t1, 0x34(s1)          # load-back

    # ECALL to return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: irq_m_external fires -> M-mode trap, SEIP not involved
    #
    # Enable MIE.MEIE (bit 11).
    # Disable MSTATUS.MIE to prevent premature firing in M-mode.
    # Transition to S-mode via mret (MPP=01, MPIE=1).
    # In S-mode: signal testbench with x31=0x31313131, spin-wait
    # for m_handled. Testbench asserts irq_m_external after sync.
    # M-mode handler fires (preempts S-mode), disables MEIE, sets
    # m_handled=1, mret returns to S-mode.
    # After spin-wait, copy results, ecall back to M-mode.
    #=================================================================

    # Clear m_handled
    sw   zero, 0x0C(s1)

    # Disable MSTATUS.MIE first to prevent firing while in M-mode
    li   t0, 0x8
    csrc mstatus, t0

    # Enable MIE.MEIE (bit 11)
    li   t0, 0x800
    csrs mie, t0

    # Transition to S-mode: MPP=01, MPIE=1
    li   t0, 0x1800
    csrc mstatus, t0            # Clear MPP bits
    li   t0, 0x0800
    csrs mstatus, t0            # MPP = 01 (S-mode)
    li   t0, 0x80
    csrs mstatus, t0            # MPIE = 1

    la   t0, s_mode_p3
    csrw mepc, t0

    # Signal testbench: ready for external IRQ
    # MIE=0 here so the M-mode IRQ is held pending until MRET to S-mode
    # (M-mode interrupts are always taken from lower privilege modes
    #  regardless of MSTATUS.MIE)
    li   x31, 0x31313131

    mret

    .align 2
s_mode_p3:
    # In S-mode. Spin-wait for M-mode external IRQ handler.
wait_m_p3:
    lw   t0, 0x0C(s1)
    beqz t0, wait_m_p3

    # M-mode handler returned us to S-mode.
    # Copy results to Phase 3 result area.
    lw   t0, 0x04(s1)          # MCAUSE
    sw   t0, 0x40(s1)
    lw   t0, 0x10(s1)          # m_vector_entry_id
    sw   t0, 0x44(s1)
    lw   t1, 0x44(s1)          # load-back

    # ECALL to return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x33333333


    #=================================================================
    # END OF TEST
    #=================================================================
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
