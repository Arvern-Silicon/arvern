#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_priv_modes
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PRIVILEGE MODES
#   Privilege mode transition verification:
#   - M-mode to S-mode via MRET (MCAUSE = 9 on ECALL back)
#   - M-mode to U-mode via MRET (MCAUSE = 8 on ECALL back)
#   - S-mode to U-mode via SRET (MCAUSE = 8 on ECALL back)
#   - Trap delegation: U-mode ECALL delegated to S-mode via MEDELEG
#   - CSR access violation from U-mode (illegal instruction)
#   - CSR access violation from S-mode (illegal instruction)
#   - MSTATUS.MPP / SSTATUS.SPP verification across transitions
#   - Register preservation across all mode changes
#
#   Convention: a0 controls trap handler return behavior:
#   a0 = 0  →  normal return (same privilege mode)
#   a0 = 1  →  return to M-mode (M handler) or S-mode (S handler)
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
#   0x010: s_trap_count
#   0x014: last SCAUSE
#   0x018: last SEPC
#   0x01C: last SSTATUS
#
# Phase 2 (M→S→M, ECALL from S-mode):
#   0x020: MCAUSE             (expect 9)
#   0x024: MSTATUS            (check MPP = 01)
#
# Phase 3 (M→U→M, ECALL from U-mode):
#   0x030: MCAUSE             (expect 8)
#   0x034: MSTATUS            (check MPP = 00)
#
# Phase 4 (M→S→U→M, ECALL from U-mode via SRET):
#   0x040: MCAUSE             (expect 8)
#   0x044: MSTATUS            (check MPP = 00)
#
# Phase 5 (delegation: U-mode ECALL → S-mode):
#   0x050: SCAUSE             (expect 8)
#   0x054: SSTATUS            (check SPP = 0)
#
# Phase 6 (CSR violation from U-mode):
#   0x060: MCAUSE             (expect 2)
#   0x064: MSTATUS            (check MPP = 00)
#
# Phase 7 (CSR violation from S-mode):
#   0x070: MCAUSE             (expect 2)
#   0x074: MSTATUS            (check MPP = 01)
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
    csrr t1, sepc
    csrr t2, sstatus

    # Increment S-mode trap count
    lw   t3, 0x10(s1)
    addi t3, t3, 1
    sw   t3, 0x10(s1)

    # Save to S-mode working area
    sw   t0, 0x14(s1)
    sw   t1, 0x18(s1)
    sw   t2, 0x1C(s1)

    # Advance SEPC past ECALL (always 4 bytes)
    addi t1, t1, 4
    csrw sepc, t1

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
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x64(s1)
    sw   t0, 0x70(s1)
    sw   t0, 0x74(s1)

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

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: M-mode → S-mode → M-mode
    #          ECALL from S-mode generates MCAUSE = 9
    #          MSTATUS.MPP should be 01 (was S-mode)
    #=================================================================

    # Set MEPC to S-mode entry point
    la   t0, s_mode_p2
    csrw mepc, t0

    # Set MPP = 01 (S-mode)
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = 01 (S-mode)

    # Clear MPIE so MIE stays 0 after MRET
    li   t0, 0x80
    csrc mstatus, t0

    mret                       # → S-mode

s_mode_p2:
    # Now in S-mode
    li   a0, 0
    ecall                      # → M-mode (cause 9: ECALL from S-mode)

    # Back in S-mode after handler returns
    # Save Phase 2 results
    lw   t0, 0x04(s1)          # MCAUSE from M-mode working area
    sw   t0, 0x20(s1)          # Phase 2 MCAUSE
    lw   t0, 0x0C(s1)          # MSTATUS from M-mode working area
    sw   t0, 0x24(s1)          # Phase 2 MSTATUS
    lw   t1, 0x24(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    ecall                      # → M-mode, handler sets MPP=11, MRET → M-mode

    # Back in M-mode
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: M-mode → U-mode → M-mode
    #          ECALL from U-mode generates MCAUSE = 8
    #          MSTATUS.MPP should be 00 (was U-mode)
    #=================================================================

    la   t0, u_mode_p3
    csrw mepc, t0

    # Set MPP = 00 (U-mode)
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP

    # Clear MPIE
    li   t0, 0x80
    csrc mstatus, t0

    mret                       # → U-mode

u_mode_p3:
    # Now in U-mode
    li   a0, 0
    ecall                      # → M-mode (cause 8: ECALL from U-mode)

    # Back in U-mode
    lw   t0, 0x04(s1)          # MCAUSE
    sw   t0, 0x30(s1)
    lw   t0, 0x0C(s1)          # MSTATUS
    sw   t0, 0x34(s1)
    lw   t1, 0x34(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: M-mode → S-mode → U-mode → M-mode
    #          SRET from S-mode to U-mode, then ECALL back
    #          MCAUSE = 8, MPP = 00
    #=================================================================

    la   t0, s_mode_p4
    csrw mepc, t0

    # Set MPP = 01 (S-mode)
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0

    # Clear MPIE
    li   t0, 0x80
    csrc mstatus, t0

    mret                       # → S-mode

s_mode_p4:
    # In S-mode, set up SRET to U-mode
    la   t0, u_mode_p4
    csrw sepc, t0

    # Clear SPP = 0 (U-mode) and SPIE = 0
    li   t0, 0x120
    csrc sstatus, t0

    sret                       # → U-mode

u_mode_p4:
    # Now in U-mode (came from S-mode via SRET)
    li   a0, 0
    ecall                      # → M-mode (cause 8: ECALL from U-mode)

    # Back in U-mode
    lw   t0, 0x04(s1)
    sw   t0, 0x40(s1)          # Phase 4 MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x44(s1)          # Phase 4 MSTATUS
    lw   t1, 0x44(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Trap delegation
    #          Set MEDELEG[8] → U-mode ECALL delegated to S-mode
    #          S-mode handler sees SCAUSE = 8, SPP = 0
    #=================================================================

    # Enable delegation for ECALL from U-mode (bit 8)
    li   t0, (1 << 8)
    csrs medeleg, t0

    # Transition: M → S → U
    la   t0, s_mode_p5
    csrw mepc, t0

    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = 01

    li   t0, 0x80
    csrc mstatus, t0           # MPIE = 0

    mret                       # → S-mode

s_mode_p5:
    # In S-mode, SRET to U-mode
    la   t0, u_mode_p5
    csrw sepc, t0

    li   t0, 0x120
    csrc sstatus, t0           # SPP = 0, SPIE = 0

    sret                       # → U-mode

u_mode_p5:
    # In U-mode with delegation active
    li   a0, 0
    ecall                      # → S-mode (delegated! SCAUSE = 8)

    # Back in U-mode after S-mode handler returns
    # Save Phase 5 results from S-mode working area
    lw   t0, 0x14(s1)          # SCAUSE
    sw   t0, 0x50(s1)
    lw   t0, 0x1C(s1)          # SSTATUS
    sw   t0, 0x54(s1)
    lw   t1, 0x54(s1)          # load-back

    # Return: U → S (delegated, a0=1, SPP=1) → S → M (a0=1, MPP=11)
    li   a0, 1
    ecall                      # → S-mode (delegated, handler sets SPP=1, SRET → S-mode)

    # Now in S-mode
    li   a0, 1
    ecall                      # → M-mode (cause 9, handler sets MPP=11, MRET → M-mode)

    # Back in M-mode
    # Clear delegation
    li   t0, (1 << 8)
    csrc medeleg, t0

    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: CSR access violation from U-mode
    #          Attempt to read M-mode CSR → illegal instruction
    #          MCAUSE = 2, MPP = 00
    #=================================================================

    la   t0, u_mode_p6
    csrw mepc, t0

    li   t0, 0x1800
    csrc mstatus, t0           # MPP = 00 (U-mode)

    li   t0, 0x80
    csrc mstatus, t0           # MPIE = 0

    mret                       # → U-mode

u_mode_p6:
    # In U-mode, try to read M-mode CSR → illegal instruction
    li   a0, 1                 # Set a0=1 so handler returns to M-mode
    csrr t0, mstatus           # ILLEGAL! M-mode CSR from U-mode

    # Back in M-mode (handler set MPP=11, MRET → M-mode)
    lw   t0, 0x04(s1)          # MCAUSE
    sw   t0, 0x60(s1)
    lw   t0, 0x0C(s1)          # MSTATUS (MPP = 00, saved on trap entry)
    sw   t0, 0x64(s1)
    lw   t1, 0x64(s1)          # load-back

    li   x31, 0x66666666


    #=================================================================
    # PHASE 7: CSR access violation from S-mode
    #          Attempt to read M-mode CSR → illegal instruction
    #          MCAUSE = 2, MPP = 01
    #=================================================================

    la   t0, s_mode_p7
    csrw mepc, t0

    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = 01 (S-mode)

    li   t0, 0x80
    csrc mstatus, t0           # MPIE = 0

    mret                       # → S-mode

s_mode_p7:
    # In S-mode, try to read M-mode CSR → illegal instruction
    li   a0, 1                 # Return to M-mode
    csrr t0, mtvec             # ILLEGAL! M-mode CSR (0x305) from S-mode

    # Back in M-mode
    lw   t0, 0x04(s1)
    sw   t0, 0x70(s1)          # Phase 7 MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x74(s1)          # Phase 7 MSTATUS
    lw   t1, 0x74(s1)          # load-back

    li   x31, 0x77777777


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
