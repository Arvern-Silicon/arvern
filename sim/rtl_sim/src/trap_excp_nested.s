#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_nested
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NESTED EXCEPTIONS
#   Nested exception verification:
#   - Exception during S-mode exception handler must trap to M-mode
#   (in_s_excp_trap blocks re-delegation while sepc/scause are still live
#   for an in-progress S-mode exception handler)
#   - Normal delegation still works after nested trap clears
#
#   Note: nested exception during an S-mode IRQ handler IS delegated to S
#   (the spec allows nesting; SIE blocks further S-IRQs, but not exceptions).
#   That case is covered by trap_s_nested_excp.{s,v}.
#
#   Convention: a0 controls trap handler return behavior:
#   a0 = 0  ->  normal return (same privilege mode)
#   a0 = 1  ->  return to M-mode (M handler) or S-mode (S handler)
#
#   a1 controls S-mode exception handler nested exception behavior:
#   a1 = 0  ->  normal S-mode handler (advance SEPC, SRET)
#   a1 = 1  ->  trigger illegal instruction inside S-mode exception handler
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# M-mode handler working area:
#   0x000: m_trap_count
#   0x004: last MCAUSE
#   0x008: last MSTATUS
#   0x00C: last MEPC
#   0x010: m_trap_handled flag
#
# S-mode handler working area:
#   0x018: s_trap_count
#   0x01C: last SCAUSE
#   0x020: last SEPC
#   0x024: last SSTATUS
#   0x028: s_trap_handled flag
#
# Phase 2 (normal delegation: U-mode ECALL -> S-mode):
#   0x030: SCAUSE             (expect 8)
#   0x034: s_trap_count       (expect 1)
#
# Phase 3 (nested: exception in S-mode handler -> M-mode):
#   0x040: MCAUSE_nested      (expect 2, illegal instruction)
#   0x044: MSTATUS_nested     (check MPP = 01, from S-mode)
#   0x048: s_trap_count       (expect 1, only the original ECALL)
#
# Phase 4 (verify delegation still works after nested trap):
#   0x050: SCAUSE             (expect 8)
#   0x054: s_trap_count       (expect 1)
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mstatus

    # Increment M-mode trap count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Save to working area
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    sw   t1, 0x0C(s1)

    # Check if interrupt
    bltz t0, m_handler_done

    # Get exception cause
    andi t3, t0, 0x1F

    # ECALL causes (8, 9, 11): advance MEPC by 4
    li   t4, 8
    beq  t3, t4, m_ecall
    li   t4, 9
    beq  t3, t4, m_ecall
    li   t4, 11
    beq  t3, t4, m_ecall

    # Illegal instruction (cause 2): advance past faulting instruction
    li   t4, 2
    beq  t3, t4, m_advance_mepc

    j    m_handler_done

m_ecall:
    addi t1, t1, 4
    csrw mepc, t1

    # If a0 == 1, return to M-mode (set MPP = 11)
    li   t4, 1
    bne  a0, t4, m_handler_done
    li   t4, 0x1800
    csrs mstatus, t4           # Set MPP = 11
    j    m_handler_done

m_advance_mepc:
    # Determine instruction size (compressed vs standard)
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, m_advance_4
    addi t1, t1, 2
    j    m_advance_done
m_advance_4:
    addi t1, t1, 4
m_advance_done:
    csrw mepc, t1

    # For illegal instruction, keep MPP as-is (return to wherever it came from)
    j    m_handler_done

m_handler_done:
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
    mret


    #=================================================================
    # S-MODE TRAP HANDLER
    #=================================================================
    .align 2

s_trap_handler:
    addi sp, sp, -20
    sw   t0, 16(sp)
    sw   t1, 12(sp)
    sw   t2,  8(sp)
    sw   t3,  4(sp)

    csrr t0, scause
    csrr t1, sepc
    csrr t2, sstatus

    # Increment S-mode trap count
    lw   t3, 0x18(s1)
    addi t3, t3, 1
    sw   t3, 0x18(s1)

    # Save to S-mode working area
    sw   t0, 0x1C(s1)
    sw   t1, 0x20(s1)
    sw   t2, 0x24(s1)

    # ---- Exception path (ECALLs) ----
    # Advance SEPC past ECALL (always 4 bytes)
    addi t1, t1, 4
    csrw sepc, t1

    # Check if we should trigger a nested exception (a1 == 1)
    li   t3, 1
    bne  a1, t3, s_no_nested

    # Clear the flag so we don't loop on the nested exception
    li   a1, 0

    # Deliberately trigger an illegal instruction inside S-mode exception handler.
    # Must trap to M-mode (NOT re-delegated to S-mode) because in_s_excp_trap=1.
    .word 0xFFFFFFFF           # Illegal instruction (32-bit, bits[1:0]=11)

    # Execution continues here after M-mode handles it and MRETs back

s_no_nested:
    # If a0 == 1, return to S-mode (set SPP = 1)
    li   t3, 1
    bne  a0, t3, s_handler_done
    li   t3, 0x100             # SPP bit (bit 8)
    csrs sstatus, t3

s_handler_done:
    lw   t3,  4(sp)
    lw   t2,  8(sp)
    lw   t1, 12(sp)
    lw   t0, 16(sp)
    addi sp, sp, 20
    sret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

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
    sw   t0, 0x28(s1)          # s_trap_handled flag (used as spin-wait signal in Phases 5/6)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x48(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Install S-mode trap handler
    la   t0, s_trap_handler
    csrw stvec, t0

    # Initialize callee-saved registers for preservation check
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Clear control flags
    li   a0, 0
    li   a1, 0

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Normal delegation works (baseline)
    #          Set MEDELEG[8] -> U-mode ECALL delegated to S-mode
    #          S-mode handler: SCAUSE=8, advance SEPC, SRET
    #          Then return to M-mode via ECALL with a0=1
    #=================================================================

    # Enable delegation for ECALL from U-mode (bit 8)
    li   t0, (1 << 8)
    csrs medeleg, t0

    # Zero trap counts for this phase
    li   t0, 0
    sw   t0, 0x00(s1)          # m_trap_count
    sw   t0, 0x18(s1)          # s_trap_count

    # Transition M -> S -> U
    la   t0, s_mode_p2
    csrw mepc, t0

    # Set MPP = 01 (S-mode)
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0

    # Clear MPIE
    li   t0, 0x80
    csrc mstatus, t0

    mret                       # -> S-mode

s_mode_p2:
    # In S-mode, SRET to U-mode
    la   t0, u_mode_p2
    csrw sepc, t0

    # Clear SPP = 0 (U-mode) and SPIE = 0
    li   t0, 0x120
    csrc sstatus, t0

    sret                       # -> U-mode

u_mode_p2:
    # In U-mode with delegation active
    li   a0, 0                 # Normal return
    li   a1, 0                 # No nested exception
    ecall                      # -> S-mode (delegated! SCAUSE = 8)

    # Back in U-mode after S-mode handler returns
    # Save Phase 2 results
    lw   t0, 0x1C(s1)          # SCAUSE from S-mode working area
    sw   t0, 0x30(s1)          # Phase 2 SCAUSE
    lw   t0, 0x18(s1)          # s_trap_count
    sw   t0, 0x34(s1)          # Phase 2 s_trap_count
    lw   t1, 0x34(s1)          # load-back

    # Return to M-mode: U -> S (delegated, a0=1, SPP=1) -> S -> M (a0=1, MPP=11)
    li   a0, 1
    li   a1, 0
    ecall                      # -> S-mode (delegated, handler sets SPP=1, SRET -> S-mode)

    # Now in S-mode
    li   a0, 1
    ecall                      # -> M-mode (cause 9, handler sets MPP=11, MRET -> M-mode)

    # Back in M-mode
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Exception during S-mode handler -> M-mode
    #          Set MEDELEG to delegate both ECALL-from-U (bit 8)
    #          AND illegal instruction (bit 2) to S-mode.
    #          U-mode ECALL -> delegated to S-mode handler.
    #          S-mode handler triggers illegal instruction (.word 0).
    #          Illegal inst in S-mode handler -> M-mode (NOT re-delegated)
    #          because in_excp_trap=1 blocks delegation.
    #          M-mode handles it: MCAUSE=2, MPP=01 (S-mode).
    #          M-mode returns to S-mode handler, which finishes with SRET.
    #=================================================================

    # Set MEDELEG: delegate ECALL-from-U (bit 8) AND illegal inst (bit 2)
    li   t0, (1 << 8) | (1 << 2)
    csrw medeleg, t0

    # Zero trap counts for this phase
    li   t0, 0
    sw   t0, 0x00(s1)          # m_trap_count
    sw   t0, 0x18(s1)          # s_trap_count

    # Transition M -> S -> U
    la   t0, s_mode_p3
    csrw mepc, t0

    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = 01

    li   t0, 0x80
    csrc mstatus, t0           # MPIE = 0

    mret                       # -> S-mode

s_mode_p3:
    la   t0, u_mode_p3
    csrw sepc, t0

    li   t0, 0x120
    csrc sstatus, t0           # SPP = 0, SPIE = 0

    sret                       # -> U-mode

u_mode_p3:
    # In U-mode with delegation active for both ECALL-from-U and illegal inst
    li   a0, 0                 # Normal return from S-mode handler
    li   a1, 1                 # Tell S-mode handler to trigger nested exception
    ecall                      # -> S-mode (delegated, SCAUSE=8)
                               # S-mode handler triggers .word 0 (illegal inst)
                               # -> M-mode (NOT re-delegated, MCAUSE=2, MPP=01)
                               # M-mode handles it, returns to S-mode handler
                               # S-mode handler finishes, SRETs back to U-mode

    # Back in U-mode
    # Save Phase 3 results
    lw   t0, 0x04(s1)          # MCAUSE from M-mode working area (nested exception)
    sw   t0, 0x40(s1)          # Phase 3 MCAUSE_nested
    lw   t0, 0x08(s1)          # MSTATUS from M-mode working area
    sw   t0, 0x44(s1)          # Phase 3 MSTATUS_nested
    lw   t0, 0x18(s1)          # s_trap_count
    sw   t0, 0x48(s1)          # Phase 3 s_trap_count
    lw   t1, 0x48(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    li   a1, 0
    ecall                      # -> S-mode (delegated, SPP=1, SRET -> S-mode)

    # Now in S-mode
    li   a0, 1
    ecall                      # -> M-mode (cause 9, MPP=11, MRET -> M-mode)

    # Back in M-mode
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Verify delegation still works after nested trap clears
    #          Repeat Phase 2 scenario to confirm delegation works
    #          normally after the nested exception is resolved.
    #=================================================================

    # Keep MEDELEG with both bits set (delegation should still work)
    # But only ECALL-from-U matters for this phase

    # Zero trap counts for this phase
    li   t0, 0
    sw   t0, 0x00(s1)          # m_trap_count
    sw   t0, 0x18(s1)          # s_trap_count

    # Transition M -> S -> U
    la   t0, s_mode_p4
    csrw mepc, t0

    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = 01

    li   t0, 0x80
    csrc mstatus, t0           # MPIE = 0

    mret                       # -> S-mode

s_mode_p4:
    la   t0, u_mode_p4
    csrw sepc, t0

    li   t0, 0x120
    csrc sstatus, t0           # SPP = 0, SPIE = 0

    sret                       # -> U-mode

u_mode_p4:
    # In U-mode with delegation active
    li   a0, 0                 # Normal return
    li   a1, 0                 # No nested exception
    ecall                      # -> S-mode (delegated, SCAUSE = 8)

    # Back in U-mode
    # Save Phase 4 results
    lw   t0, 0x1C(s1)          # SCAUSE from S-mode working area
    sw   t0, 0x50(s1)          # Phase 4 SCAUSE
    lw   t0, 0x18(s1)          # s_trap_count
    sw   t0, 0x54(s1)          # Phase 4 s_trap_count
    lw   t1, 0x54(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    li   a1, 0
    ecall                      # -> S-mode (delegated, SPP=1, SRET -> S-mode)

    # Now in S-mode
    li   a0, 1
    ecall                      # -> M-mode (cause 9, MPP=11, MRET -> M-mode)

    # Back in M-mode
    # Clear delegation
    li   t0, (1 << 8) | (1 << 2)
    csrc medeleg, t0

    li   x31, 0x44444444

    # End-of-test sentinel (testbench waits on this)
    li   x31, 0xdeadbeef


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
