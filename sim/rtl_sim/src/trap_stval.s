#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_stval
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP STVAL
#   Verify STVAL register content for exceptions delegated to S-mode:
#   - Load misaligned delegated to S-mode   (SCAUSE=4, STVAL=address)
#   - Store misaligned delegated to S-mode  (SCAUSE=6, STVAL=address)
#   - Illegal instruction delegated to S-mode (SCAUSE=2, STVAL=0)
#
#   Convention: a0 controls M-mode handler return behavior:
#   a0 = 0  ->  normal return (same privilege mode)
#   a0 = 1  ->  return to M-mode (set MPP = 11)
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
#   0x00C: last MSTATUS
#
# S-mode handler working area:
#   0x018: s_trap_count
#   0x01C: last SCAUSE
#   0x020: last STVAL
#   0x024: last SEPC
#   0x028: s_trap_handled flag
#
# Phase 2 (load misaligned, delegated to S-mode):
#   0x030: SCAUSE             (expect 4)
#   0x034: STVAL              (expect 0x80000001)
#
# Phase 3 (store misaligned, delegated to S-mode):
#   0x040: SCAUSE             (expect 6)
#   0x044: STVAL              (expect 0x80000003)
#
# Phase 4 (illegal instruction, delegated to S-mode):
#   0x050: SCAUSE             (expect 2)
#   0x054: STVAL              (expect 0)
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
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

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
    j    m_handler_done

m_ecall:
    addi t1, t1, 4
    csrw mepc, t1

    # If a0 == 1, return to M-mode (set MPP = 11)
    li   t4, 1
    bne  a0, t4, m_handler_done
    li   t4, 0x1800
    csrs mstatus, t4
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
    csrr t1, stval
    csrr t2, sepc

    # Increment S-mode trap count
    lw   t3, 0x18(s1)
    addi t3, t3, 1
    sw   t3, 0x18(s1)

    # Save to S-mode working area
    sw   t0, 0x1C(s1)
    sw   t1, 0x20(s1)
    sw   t2, 0x24(s1)

    # Set s_trap_handled flag
    li   t3, 1
    sw   t3, 0x28(s1)

    # Check if interrupt (MSB = 1)
    bltz t0, s_handler_done

    # Exception path: advance SEPC past faulting instruction
    lhu  t3, 0(t2)
    andi t3, t3, 0x3
    li   t1, 0x3
    beq  t3, t1, s_advance_4
    addi t2, t2, 2
    j    s_exc_done
s_advance_4:
    addi t2, t2, 4
s_exc_done:
    csrw sepc, t2

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

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Install S-mode trap handler
    la   t0, s_trap_handler
    csrw stvec, t0

    # Set MEDELEG to delegate to S-mode:
    #   bit 2 = illegal instruction
    #   bit 4 = load address misaligned
    #   bit 6 = store address misaligned
    li   t0, (1 << 2) | (1 << 4) | (1 << 6)
    csrs medeleg, t0

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Load misaligned, delegated to S-mode
    #          SCAUSE = 4, STVAL = 0x80000001
    #=================================================================

    # Transition M -> U mode
    la   t0, u_mode_p2
    csrw mepc, t0

    # Set MPP = 00 (U-mode), MPIE = 0
    li   t0, 0x1880
    csrc mstatus, t0

    mret                       # -> U-mode

u_mode_p2:
    # In U-mode: trigger load misaligned
    li   t0, 0x80000001       # misaligned address
    lw   t1, 0(t0)            # -> delegated to S-mode (SCAUSE=4)

    # S-mode handler returns here after advancing SEPC
    # Save Phase 2 results
    lw   t0, 0x1C(s1)          # SCAUSE
    sw   t0, 0x30(s1)
    lw   t0, 0x20(s1)          # STVAL
    sw   t0, 0x34(s1)
    lw   t1, 0x34(s1)          # load-back

    # Return to M-mode via ECALL
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Store misaligned, delegated to S-mode
    #          SCAUSE = 6, STVAL = 0x80000003
    #=================================================================

    # Transition M -> U mode
    la   t0, u_mode_p3
    csrw mepc, t0

    li   t0, 0x1880
    csrc mstatus, t0

    mret                       # -> U-mode

u_mode_p3:
    # In U-mode: trigger store misaligned
    li   t0, 0x80000003       # misaligned address
    li   t2, 0x12345678       # data to store
    sw   t2, 0(t0)            # -> delegated to S-mode (SCAUSE=6)

    # S-mode handler returns here
    lw   t0, 0x1C(s1)          # SCAUSE
    sw   t0, 0x40(s1)
    lw   t0, 0x20(s1)          # STVAL
    sw   t0, 0x44(s1)
    lw   t1, 0x44(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Illegal instruction, delegated to S-mode
    #          SCAUSE = 2, STVAL = 0
    #=================================================================

    # Transition M -> U mode
    la   t0, u_mode_p4
    csrw mepc, t0

    li   t0, 0x1880
    csrc mstatus, t0

    mret                       # -> U-mode

u_mode_p4:
    # In U-mode: trigger illegal instruction
    .word 0xFFFFFFFF           # illegal instruction (32-bit, bits[1:0]=11)

    # S-mode handler returns here
    lw   t0, 0x1C(s1)          # SCAUSE
    sw   t0, 0x50(s1)
    lw   t0, 0x20(s1)          # STVAL
    sw   t0, 0x54(s1)
    lw   t1, 0x54(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    # Clean up: clear MEDELEG
    li   t0, (1 << 2) | (1 << 4) | (1 << 6)
    csrc medeleg, t0

    li   x31, 0x44444444


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
