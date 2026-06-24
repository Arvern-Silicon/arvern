#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_tsr_tw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP TSR / TW
#   MSTATUS.TSR and MSTATUS.TW bit verification:
#   - TSR=1: SRET in S-mode raises illegal instruction (MCAUSE=2)
#   - TSR=0: SRET in S-mode works normally
#   - TW=1:  WFI in S-mode raises illegal instruction (MCAUSE=2)
#   - TW=0:  WFI in S-mode stalls until interrupt (no trap)
#   - Register preservation across all mode transitions
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
#   0x008: last MSTATUS
#   0x00C: last MEPC
#   0x010: m_trap_handled flag
#
# Phase 2 (TSR=1, SRET in S-mode -> illegal instruction):
#   0x020: MCAUSE             (expect 2)
#   0x024: MSTATUS            (check MPP = 01)
#
# Phase 3 (TSR=0, SRET in S-mode -> works normally):
#   0x030: m_trap_count_before
#   0x034: m_trap_count_after (should match 0x030)
#
# Phase 4 (TW=1, WFI in S-mode -> illegal instruction):
#   0x040: MCAUSE             (expect 2)
#   0x044: MSTATUS            (check MPP = 01)
#
# Phase 5 (TW=0, WFI in S-mode -> stalls until timer interrupt):
#   0x050: m_trap_count_before
#   0x054: m_trap_count_after (should match 0x050 + 1 for timer only)
#   0x058: wfi_completed flag
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
    sw   t1, 0x0C(s1)
    sw   t2, 0x08(s1)

    # Check if interrupt (MSB = 1)
    bltz t0, m_handle_interrupt

    # ---- Exception path ----
    andi t3, t0, 0x1F

    # Illegal instruction (cause 2): advance MEPC by 4
    li   t4, 2
    beq  t3, t4, m_illegal_inst

    # ECALL causes (8, 9, 11): advance MEPC by 4
    li   t4, 8
    beq  t3, t4, m_ecall
    li   t4, 9
    beq  t3, t4, m_ecall
    li   t4, 11
    beq  t3, t4, m_ecall
    j    m_handler_done

m_illegal_inst:
    # Advance MEPC past the faulting instruction
    addi t1, t1, 4
    csrw mepc, t1
    # Keep MPP as-is (return to same mode that faulted)
    j    m_handler_done

m_ecall:
    addi t1, t1, 4
    csrw mepc, t1
    # If a0 == 1, return to M-mode
    li   t4, 1
    bne  a0, t4, m_handler_done
    li   t4, 0x1800
    csrs mstatus, t4           # Set MPP = 11
    j    m_handler_done

m_handle_interrupt:
    # Disable the MIE bit for the interrupt that fired
    andi t3, t0, 0x1F
    li   t4, 7
    beq  t3, t4, m_disable_mtie
    j    m_irq_done

m_disable_mtie:
    li   t4, 0x80              # MIE.MTIE = bit 7
    csrc mie, t4

m_irq_done:
    # Set m_trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)

m_handler_done:
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
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)
    sw   t0, 0x58(s1)

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: TSR=1, SRET in S-mode -> illegal instruction
    #          MCAUSE = 2, MPP = 01 (from S-mode)
    #=================================================================

    # Set MSTATUS.TSR = 1 (bit 22)
    li   t0, (1 << 22)
    csrs mstatus, t0

    # Set MPP = 01 (S-mode), MPIE = 1
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0880
    csrs mstatus, t0           # MPP=01, MPIE=1

    # Set MEPC to S-mode entry for phase 2
    la   t0, s_mode_p2
    csrw mepc, t0

    # Set up SEPC to point to after_sret_p2 and SPP=0
    la   t0, after_sret_p2
    csrw sepc, t0
    li   t0, (1 << 8)
    csrc mstatus, t0           # Clear SPP (bit 8)

    mret                       # -> S-mode

s_mode_p2:
    # Now in S-mode with TSR=1. Execute SRET -> should trap
    sret                       # Should cause illegal instruction

    # Should not reach here (handler advances MEPC past sret)
after_sret_p2:
    nop

    # Save Phase 2 results
    lw   t0, 0x04(s1)          # MCAUSE
    sw   t0, 0x20(s1)
    lw   t0, 0x08(s1)          # MSTATUS
    sw   t0, 0x24(s1)
    lw   t1, 0x24(s1)          # load-back

    # Return to M-mode via ECALL
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: TSR=0, SRET in S-mode -> works normally
    #          Should NOT trap, SRET returns to where SEPC points
    #=================================================================

    # Clear MSTATUS.TSR = 0 (bit 22)
    li   t0, (1 << 22)
    csrc mstatus, t0

    # Save m_trap_count before
    lw   t0, 0x00(s1)
    sw   t0, 0x30(s1)
    lw   t1, 0x30(s1)          # load-back

    # Set MPP = 01 (S-mode), MPIE = 1
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0880
    csrs mstatus, t0           # MPP=01, MPIE=1

    # Set MEPC to S-mode entry for phase 3
    la   t0, s_mode_p3
    csrw mepc, t0

    # Set up SEPC to point to after_sret_p3 and SPP=0
    la   t0, after_sret_p3
    csrw sepc, t0
    li   t0, (1 << 8)
    csrc mstatus, t0           # Clear SPP (bit 8)

    mret                       # -> S-mode

s_mode_p3:
    # Now in S-mode with TSR=0. Execute SRET -> should work normally
    sret                       # Should return to after_sret_p3 (U-mode since SPP=0)

after_sret_p3:
    # Now in U-mode (SPP was 0). SRET worked without trapping.
    # Return to M-mode via ECALL
    li   a0, 1
    ecall

    # Back in M-mode
    # Save m_trap_count after (should be same as before, only ecall incremented it)
    lw   t0, 0x00(s1)
    # Subtract 1 for the ecall we just did
    addi t0, t0, -1
    sw   t0, 0x34(s1)
    lw   t1, 0x34(s1)          # load-back

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: TW=1, WFI in S-mode -> illegal instruction
    #          MCAUSE = 2, MPP = 01 (from S-mode)
    #=================================================================

    # Clear TSR, set TW = 1 (bit 21)
    li   t0, (1 << 22)
    csrc mstatus, t0           # Clear TSR
    li   t0, (1 << 21)
    csrs mstatus, t0           # Set TW

    # Set MPP = 01 (S-mode), MPIE = 1
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0880
    csrs mstatus, t0           # MPP=01, MPIE=1

    # Set MEPC to S-mode entry for phase 4
    la   t0, s_mode_p4
    csrw mepc, t0

    mret                       # -> S-mode

s_mode_p4:
    # Now in S-mode with TW=1. Execute WFI -> should trap
    wfi                        # Should cause illegal instruction

    # Handler advances MEPC past WFI, returns to here
    # Save Phase 4 results
    lw   t0, 0x04(s1)          # MCAUSE
    sw   t0, 0x40(s1)
    lw   t0, 0x08(s1)          # MSTATUS
    sw   t0, 0x44(s1)
    lw   t1, 0x44(s1)          # load-back

    # Return to M-mode via ECALL
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: TW=0, WFI in S-mode -> stalls until timer interrupt
    #          WFI should NOT trap, stalls until irq_m_timer
    #=================================================================

    # Clear TW
    li   t0, (1 << 21)
    csrc mstatus, t0           # Clear TW

    # Save m_trap_count before
    lw   t0, 0x00(s1)
    sw   t0, 0x50(s1)
    lw   t1, 0x50(s1)          # load-back

    # Enable MIE.MTIE (bit 7) for timer interrupt
    li   t0, 0x80
    csrs mie, t0

    # Set MPP = 01 (S-mode), MPIE = 1 (so MIE=1 after MRET)
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0880
    csrs mstatus, t0           # MPP=01, MPIE=1

    # Set MEPC to S-mode entry for phase 5
    la   t0, s_mode_p5
    csrw mepc, t0

    # Clear m_trap_handled and wfi_completed
    sw   zero, 0x10(s1)
    sw   zero, 0x58(s1)

    # Signal testbench to prepare timer interrupt
    li   x31, 0x51515151

    mret                       # -> S-mode (MIE=1 from MPIE)

s_mode_p5:
    # Now in S-mode with TW=0. Execute WFI -> should stall until interrupt
    wfi                        # Stalls until irq_m_timer fires

    # Timer IRQ fired, M-mode handler ran, returned here
    # Mark WFI completed
    li   t0, 1
    sw   t0, 0x58(s1)

    # Save m_trap_count after (should be m_trap_count_before + 1 for timer only)
    lw   t0, 0x00(s1)
    sw   t0, 0x54(s1)
    lw   t1, 0x54(s1)          # load-back

    # Return to M-mode via ECALL
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x55555555


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
