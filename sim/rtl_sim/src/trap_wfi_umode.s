#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_wfi_umode
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP WFI U-MODE
#   WFI behavior in U-mode:
#   - TW=1: WFI in U-mode raises illegal instruction (MCAUSE=2, MPP=00)
#   - TW=0: WFI in U-mode STILL raises illegal instruction -- the U-mode rule
#           is independent of TW (Priv 3.1.6.6: "When S-mode is implemented,
#           then executing WFI in U-mode causes an illegal-instruction
#           exception, unless it completes within an implementation-specific,
#           bounded time limit"). aRVern's bound is 0.
#   - TW=0: WFI in S-mode DOES stall until a timer interrupt (no trap) --
#           only TW=1 may bound an S-mode WFI, so this must not change.
#   - Register preservation across all mode transitions
#
#   Convention: a0 controls M-mode handler return behavior:
#   a0 = 0  ->  normal return (same privilege mode)
#   a0 = 1  ->  return to M-mode (set MPP = 11)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

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
# Phase 2 (TW=1, WFI in U-mode -> illegal instruction):
#   0x020: MCAUSE             (expect 2)
#   0x024: MSTATUS            (check MPP = 00)
#
# Phase 3 (TW=0, WFI in U-mode -> illegal instruction anyway):
#   0x030: MCAUSE             (expect 2)
#   0x034: MSTATUS            (check MPP = 00)
#
# Phase 4 (TW=0, WFI in S-mode -> stalls until timer interrupt):
#   0x040: m_trap_count_before
#   0x044: m_trap_count_after (expect before + 1 for timer only)
#   0x048: wfi_completed flag
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

    # ECALL causes (8 = from U, 9 = from S, 11 = from M): advance MEPC by 4
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
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
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
    sw   t0, 0x48(s1)

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Smrnmi (ratified): "When NMIE=0, all interrupts are disabled" and NMIE
    # resets to 0, so boot code must set mnstatus.NMIE=1 before any
    # ordinary interrupt can be delivered. Smrnmi is unconditional.
    csrsi 0x744, 8              # mnstatus.NMIE = 1

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: TW=1, WFI in U-mode -> illegal instruction
    #          MCAUSE = 2, MPP = 00 (from U-mode)
    #=================================================================

    # Set MSTATUS.TW = 1 (bit 21)
    li   t0, (1 << 21)
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0

    # Set MPP = 00 (U-mode), MPIE = 1
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0080
    csrs mstatus, t0           # MPIE=1

    # Set MEPC to U-mode entry for phase 2
    la   t0, u_mode_p2
    csrw mepc, t0

    mret                       # -> U-mode

u_mode_p2:
    # Now in U-mode with TW=1. Execute WFI -> should trap
    wfi                        # Should cause illegal instruction

    # Handler advances MEPC past WFI, returns to here
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
    # PHASE 3: TW=0, WFI in U-mode -> STILL illegal instruction
    #          MCAUSE = 2, MPP = 00 (from U-mode)
    #
    # The U-mode rule is independent of TW (Priv 3.1.6.6): "When S-mode is
    # implemented, then executing WFI in U-mode causes an illegal-instruction
    # exception, unless it completes within an implementation-specific,
    # bounded time limit." aRVern's bound is 0, so clearing TW must NOT make
    # a U-mode WFI legal -- the outcome is identical to phase 2.
    #=================================================================

    # Clear TW -- this is exactly what used to make the WFI below legal
    li   t0, (1 << 21)
    csrc mstatus, t0           # Clear TW

    # Set MPP = 00 (U-mode), MPIE = 1
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0080
    csrs mstatus, t0           # MPIE=1

    # Set MEPC to U-mode entry for phase 3
    la   t0, u_mode_p3
    csrw mepc, t0

    mret                       # -> U-mode

u_mode_p3:
    # Now in U-mode with TW=0. Execute WFI -> must STILL trap
    wfi                        # Should cause illegal instruction

    # Handler advances MEPC past WFI, returns to here
    lw   t0, 0x04(s1)          # MCAUSE
    sw   t0, 0x30(s1)
    lw   t0, 0x08(s1)          # MSTATUS
    sw   t0, 0x34(s1)
    lw   t1, 0x34(s1)          # load-back

    # Return to M-mode via ECALL
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: TW=0, WFI in S-mode -> stalls until timer interrupt
    #          WFI must NOT trap. This is the case that must stay
    #          UNCHANGED: only TW=1 may bound an S-mode WFI, so with
    #          TW=0 S-mode is entitled to stall indefinitely. It also
    #          keeps the clock-gating / wake coverage that used to live
    #          in the U-mode phase.
    #=================================================================

    # TW is already 0 from phase 3.

    # Save m_trap_count before
    lw   t0, 0x00(s1)
    sw   t0, 0x40(s1)
    lw   t1, 0x40(s1)          # load-back

    # Enable MIE.MTIE (bit 7) for timer interrupt
    li   t0, 0x80
    csrs mie, t0

    # Set MPP = 01 (S-mode), MPIE = 1 (so MIE=1 after MRET)
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = S-mode
    li   t0, 0x0080
    csrs mstatus, t0           # MPIE=1

    # Set MEPC to S-mode entry for phase 4
    la   t0, s_mode_p4
    csrw mepc, t0

    # Clear m_trap_handled and wfi_completed
    sw   zero, 0x10(s1)
    sw   zero, 0x48(s1)

    # Signal testbench to prepare timer interrupt
    li   x31, 0x41414141

    mret                       # -> S-mode (MIE=1 from MPIE)

s_mode_p4:
    # Now in S-mode with TW=0. Execute WFI -> should stall until interrupt
    wfi                        # Stalls until irq_m_timer fires

    # Timer IRQ fired, M-mode handler ran, returned here
    # Mark WFI completed
    li   t0, 1
    sw   t0, 0x48(s1)

    # Return to M-mode via ECALL
    li   a0, 1
    ecall

    # Back in M-mode
    # Save m_trap_count after
    lw   t0, 0x00(s1)
    # Subtract 1 for the ecall we just did
    addi t0, t0, -1
    sw   t0, 0x44(s1)
    lw   t1, 0x44(s1)          # load-back

    li   x31, 0x44444444


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
