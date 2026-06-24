#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_priv_modes
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ PRIVILEGE MODES
#   Interrupt behavior across privilege modes:
#   - Machine timer IRQ while in S-mode  (traps to M-mode, MPP=01)
#   - Machine timer IRQ while in U-mode  (traps to M-mode, MPP=00)
#   - Delegated supervisor timer IRQ from U-mode (traps to S-mode, SPP=0)
#   - Delegated supervisor timer IRQ from S-mode (traps to S-mode, SPP=1)
#   - SSTATUS.SIE=0 blocks delegated supervisor IRQ in S-mode
#   - Register preservation across all mode transitions
#
#   Machine interrupt signals are driven by the testbench.
#   Supervisor interrupts use software-set pending bits (MIP/SIP).
#
#   Convention: a0 controls M-mode handler return behavior:
#   a0 = 0  →  normal return (same privilege mode)
#   a0 = 1  →  return to M-mode (set MPP = 11)
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
#   0x010: m_trap_handled flag
#
# S-mode handler working area:
#   0x018: s_trap_count
#   0x01C: last SCAUSE
#   0x020: last SEPC
#   0x024: last SSTATUS
#   0x028: s_trap_handled flag
#
# Phase 2 (machine timer IRQ from S-mode → M-mode):
#   0x030: MCAUSE             (expect 0x80000007)
#   0x034: MSTATUS            (check MPP = 01)
#
# Phase 3 (machine timer IRQ from U-mode → M-mode):
#   0x040: MCAUSE             (expect 0x80000007)
#   0x044: MSTATUS            (check MPP = 00)
#
# Phase 4 (delegated S-timer IRQ from U-mode → S-mode):
#   0x050: SCAUSE             (expect 0x80000005)
#   0x054: SSTATUS            (check SPP = 0)
#
# Phase 5 (delegated S-timer IRQ from S-mode → S-mode):
#   0x060: SCAUSE             (expect 0x80000005)
#   0x064: SSTATUS            (check SPP = 1)
#
# Phase 6 (SIE=0 blocks delegated IRQ in S-mode):
#   0x070: s_trap_count_before
#   0x074: s_trap_count_after (should match 0x070)
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

    # Check if interrupt (MSB = 1)
    bltz t0, m_handle_interrupt

    # ---- Exception path ----
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
    # If a0 == 1, return to M-mode
    li   t4, 1
    bne  a0, t4, m_handler_done
    li   t4, 0x1800
    csrs mstatus, t4           # Set MPP = 11
    j    m_handler_done

m_handle_interrupt:
    # Disable the MIE bit for the interrupt that fired
    andi t3, t0, 0x1F
    li   t4, 3
    beq  t3, t4, m_disable_msie
    li   t4, 7
    beq  t3, t4, m_disable_mtie
    li   t4, 11
    beq  t3, t4, m_disable_meie
    j    m_irq_done

m_disable_msie:
    li   t4, 0x8               # MIE.MSIE = bit 3
    csrc mie, t4
    j    m_irq_done
m_disable_mtie:
    li   t4, 0x80              # MIE.MTIE = bit 7
    csrc mie, t4
    j    m_irq_done
m_disable_meie:
    li   t4, 0x800             # MIE.MEIE = bit 11
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

    # Check if interrupt (MSB = 1)
    bltz t0, s_handle_interrupt
    j    s_handler_done

s_handle_interrupt:
    # Clear the pending bit for the interrupt that fired
    andi t3, t0, 0x1F
    li   t1, 1
    beq  t3, t1, s_clear_ssip
    li   t1, 5
    beq  t3, t1, s_clear_stip
    li   t1, 9
    beq  t3, t1, s_clear_seip
    j    s_irq_done

s_clear_ssip:
    li   t1, 0x2               # SIP.SSIP = bit 1 (writable in SIP)
    csrc sip, t1
    j    s_irq_done
s_clear_stip:
    li   t1, 0x20              # SIE.STIE = bit 5 (STIP is read-only in SIP per spec)
    csrc sie, t1               # Disable STIE to prevent re-triggering
    j    s_irq_done
s_clear_seip:
    li   t1, 0x200             # SIE.SEIE = bit 9 (SEIP is read-only in SIP per spec)
    csrc sie, t1               # Disable SEIE to prevent re-triggering

s_irq_done:
    # Set s_trap_handled flag
    li   t1, 1
    sw   t1, 0x28(s1)

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
    sw   t0, 0x28(s1)
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

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Machine timer IRQ while in S-mode
    #          irq_m_timer driven by testbench → traps to M-mode
    #          MCAUSE = 0x80000007, MPP = 01 (was S-mode)
    #=================================================================

    # Enable MIE.MTIE (bit 7)
    li   t0, 0x80
    csrs mie, t0

    # Set MPIE = 1 (so MIE=1 after MRET) and MPP = 01 (S-mode)
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0880
    csrs mstatus, t0           # MPP=01, MPIE=1

    # Set MEPC to S-mode entry
    la   t0, s_mode_p2
    csrw mepc, t0

    # Clear m_trap_handled
    sw   zero, 0x10(s1)

    mret                       # → S-mode (MIE=1 from MPIE)

s_mode_p2:
    # Now in S-mode. Signal ready for timer interrupt.
    li   x31, 0x21212121

    # Spin-wait for M-mode trap handler
wait_p2:
    lw   t0, 0x10(s1)
    beqz t0, wait_p2

    # M-mode handler returned us to S-mode
    # Save Phase 2 results
    lw   t0, 0x04(s1)          # MCAUSE
    sw   t0, 0x30(s1)
    lw   t0, 0x0C(s1)          # MSTATUS
    sw   t0, 0x34(s1)
    lw   t1, 0x34(s1)          # load-back

    # Return to M-mode via ECALL
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Machine timer IRQ while in U-mode
    #          irq_m_timer driven by testbench → traps to M-mode
    #          MCAUSE = 0x80000007, MPP = 00 (was U-mode)
    #=================================================================

    # Disable MSTATUS.MIE first to prevent spurious interrupts
    # during setup (irq_m_timer may still be deasserted by testbench)
    li   t0, 0x8
    csrc mstatus, t0

    # Re-enable MIE.MTIE
    li   t0, 0x80
    csrs mie, t0

    # Set MPIE = 1 and MPP = 00 (U-mode)
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x80
    csrs mstatus, t0           # MPIE=1

    la   t0, u_mode_p3
    csrw mepc, t0

    # Clear m_trap_handled
    sw   zero, 0x10(s1)

    mret                       # → U-mode (MIE=1 from MPIE)

u_mode_p3:
    # Now in U-mode. Signal ready for timer interrupt.
    li   x31, 0x31313131

wait_p3:
    lw   t0, 0x10(s1)
    beqz t0, wait_p3

    # Save Phase 3 results
    lw   t0, 0x04(s1)
    sw   t0, 0x40(s1)          # MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x44(s1)          # MSTATUS
    lw   t1, 0x44(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Delegated supervisor timer IRQ from U-mode
    #          Set MIP.STIP from M-mode, delegate via MIDELEG[5]
    #          → traps to S-mode handler
    #          SCAUSE = 0x80000005, SPP = 0 (was U-mode)
    #=================================================================

    # Delegate supervisor timer interrupt (bit 5) to S-mode
    li   t0, (1 << 5)
    csrs mideleg, t0

    # Enable SIE.STIE (bit 5)
    li   t0, 0x20
    csrs sie, t0

    # Set SSTATUS.SIE (bit 1 of MSTATUS)
    li   t0, 0x2
    csrs mstatus, t0

    # Set supervisor timer pending: MIP.STIP (bit 5)
    li   t0, 0x20
    csrs mip, t0

    # Set MPIE = 1 and MPP = 00 (U-mode)
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x80
    csrs mstatus, t0           # MPIE=1

    la   t0, u_mode_p4
    csrw mepc, t0

    # Clear s_trap_handled
    sw   zero, 0x28(s1)

    mret                       # → U-mode (STIP pending, delegation on, SIE=1)

u_mode_p4:
    # Supervisor timer interrupt should fire immediately
wait_p4:
    lw   t0, 0x28(s1)
    beqz t0, wait_p4

    # S-mode handler returned us to U-mode
    lw   t0, 0x1C(s1)          # SCAUSE
    sw   t0, 0x50(s1)
    lw   t0, 0x24(s1)          # SSTATUS
    sw   t0, 0x54(s1)
    lw   t1, 0x54(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    # Clean up: clear MIDELEG[5] and any remaining pending
    li   t0, (1 << 5)
    csrc mideleg, t0
    li   t0, 0x20
    csrc mip, t0
    csrc sie, t0

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Delegated supervisor timer IRQ from S-mode
    #          Same as Phase 4 but transition to S-mode
    #          SCAUSE = 0x80000005, SPP = 1 (was S-mode)
    #=================================================================

    # Delegate supervisor timer interrupt
    li   t0, (1 << 5)
    csrs mideleg, t0

    # Enable SIE.STIE
    li   t0, 0x20
    csrs sie, t0

    # Set SSTATUS.SIE
    li   t0, 0x2
    csrs mstatus, t0

    # Set supervisor timer pending
    li   t0, 0x20
    csrs mip, t0

    # Set MPIE = 1 and MPP = 01 (S-mode)
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0880
    csrs mstatus, t0           # MPP=01, MPIE=1

    la   t0, s_mode_p5
    csrw mepc, t0

    # Clear s_trap_handled
    sw   zero, 0x28(s1)

    mret                       # → S-mode (STIP pending, delegation on, SIE=1)

s_mode_p5:
    # Supervisor timer interrupt should fire immediately
wait_p5:
    lw   t0, 0x28(s1)
    beqz t0, wait_p5

    # S-mode handler returned us to S-mode
    lw   t0, 0x1C(s1)          # SCAUSE
    sw   t0, 0x60(s1)
    lw   t0, 0x24(s1)          # SSTATUS
    sw   t0, 0x64(s1)
    lw   t1, 0x64(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    # Clean up
    li   t0, (1 << 5)
    csrc mideleg, t0
    li   t0, 0x20
    csrc mip, t0
    csrc sie, t0

    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: SSTATUS.SIE=0 blocks delegated supervisor IRQ
    #          Set up same as Phase 5 but leave SSTATUS.SIE=0
    #          Interrupt should NOT fire
    #=================================================================

    # Delegate supervisor timer interrupt
    li   t0, (1 << 5)
    csrs mideleg, t0

    # Enable SIE.STIE
    li   t0, 0x20
    csrs sie, t0

    # Clear SSTATUS.SIE (bit 1)
    li   t0, 0x2
    csrc mstatus, t0

    # Set supervisor timer pending
    li   t0, 0x20
    csrs mip, t0

    # Save s_trap_count before
    lw   t0, 0x18(s1)
    sw   t0, 0x70(s1)
    lw   t1, 0x70(s1)          # load-back

    # Set MPIE = 0 (so MIE=0 after MRET, preventing machine interrupts)
    # and MPP = 01 (S-mode)
    li   t0, 0x1880
    csrc mstatus, t0           # Clear MPP and MPIE
    li   t0, 0x0800
    csrs mstatus, t0           # MPP = 01

    la   t0, s_mode_p6
    csrw mepc, t0

    mret                       # → S-mode (STIP pending but SIE=0 → blocked)

s_mode_p6:
    # Delay loop — interrupt should NOT fire (SIE=0)
    li   t2, 50
nop_loop_p6:
    addi t2, t2, -1
    bnez t2, nop_loop_p6

    # Save s_trap_count after delay (should be unchanged)
    lw   t0, 0x18(s1)
    sw   t0, 0x74(s1)
    lw   t1, 0x74(s1)          # load-back

    # Return to M-mode via ECALL
    li   a0, 1
    ecall

    # Back in M-mode
    # Clean up: clear pending and delegation
    li   t0, (1 << 5)
    csrc mideleg, t0
    li   t0, 0x20
    csrc mip, t0
    csrc sie, t0

    li   x31, 0x66666666


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
