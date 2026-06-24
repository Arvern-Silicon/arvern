#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_platform
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PLATFORM INTERRUPTS
#   Platform-designated interrupts (MIP/MIE bits 31:16):
#   - Platform interrupt 0 in M-mode via software (MCAUSE = 0x80000010)
#   - Platform interrupt 0 delegated to S-mode via software
#   - Platform interrupt 0 in M-mode via external irq_platform_i[0]
#   - Platform interrupt 5 delegated to S-mode via irq_platform_i[5]
#
#   Platform interrupts ip_pip[15:0] map to MIP bits [31:16].
#   ip_pip[N] -> cause (16+N), so ip_pip[0] -> cause 16 (0x10).
#   MIE bits [31:16] are the corresponding enable bits.
#   MIDELEG bits [31:16] control delegation to S-mode.
#
#   MIP bits 31:16 are the OR of software-written bits and irq_platform_i.
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
#   0x010: m_trap_handled flag
#
# S-mode handler working area:
#   0x018: s_trap_count
#   0x01C: last SCAUSE
#   0x020: last SEPC
#   0x024: last SSTATUS
#   0x028: s_trap_handled flag
#
# Phase 2 (platform IRQ 0 in M-mode, software-set):
#   0x030: MCAUSE             (expect 0x80000010)
#
# Phase 3 (platform IRQ 0 delegated to S-mode, software-set):
#   0x040: SCAUSE             (expect 0x80000010)
#
# Phase 4 (platform IRQ 0 in M-mode, external hw-driven):
#   0x050: MCAUSE             (expect 0x80000010)
#
# Phase 5 (platform IRQ 5 delegated to S-mode, external hw-driven):
#   0x060: SCAUSE             (expect 0x80000015 = cause 21)
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
    # For platform interrupts (cause >= 16): clear the pending bit in MIP
    andi t3, t0, 0x1F         # cause code (bits 4:0)

    # Standard interrupts: disable in MIE
    li   t4, 3
    beq  t3, t4, m_disable_msie
    li   t4, 7
    beq  t3, t4, m_disable_mtie
    li   t4, 11
    beq  t3, t4, m_disable_meie

    # Platform interrupts (cause 16-31): disable MIE and clear MIP
    # MIE disable prevents re-fire when external hw input is still asserted
    # MIP clear removes the software-written pending bit
    li   t4, 1
    sll  t4, t4, t3           # t4 = (1 << cause)
    csrc mie, t4              # disable interrupt enable
    csrc mip, t4              # clear software pending bit
    j    m_irq_done

m_disable_msie:
    li   t4, 0x8
    csrc mie, t4
    j    m_irq_done
m_disable_mtie:
    li   t4, 0x80
    csrc mie, t4
    j    m_irq_done
m_disable_meie:
    li   t4, 0x800
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
    # Clear pending bit in SIP for the interrupt that fired
    andi t3, t0, 0x1F

    # Standard S-mode interrupts
    li   t1, 1
    beq  t3, t1, s_clear_ssip
    li   t1, 5
    beq  t3, t1, s_clear_stip
    li   t1, 9
    beq  t3, t1, s_clear_seip

    # Platform interrupts (cause 16-31): disable SIE and clear SIP
    li   t1, 1
    sll  t1, t1, t3           # t1 = (1 << cause)
    csrc sie, t1              # disable interrupt enable
    csrc sip, t1              # clear software pending bit
    j    s_irq_done

s_clear_ssip:
    j    s_irq_done
s_clear_stip:
    j    s_irq_done
s_clear_seip:

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
    sw   t0, 0x40(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x60(s1)

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
    # PHASE 2: Platform interrupt 0 in M-mode
    #          ip_pip[0] -> MIP bit 16 -> cause 16
    #          MCAUSE = 0x80000010
    #=================================================================

    # Enable platform interrupt 0 in MIE (bit 16)
    li   t0, (1 << 16)
    csrs mie, t0

    # Enable MSTATUS.MIE (bit 3)
    li   t0, 0x8
    csrs mstatus, t0

    # Clear m_trap_handled flag
    sw   zero, 0x10(s1)

    # Set platform interrupt 0 pending: MIP bit 16
    li   t0, (1 << 16)
    csrs mip, t0

    # Interrupt should fire immediately
    # Spin-wait for handler
wait_p2:
    lw   t0, 0x10(s1)
    beqz t0, wait_p2

    # Copy MCAUSE to Phase 2 area
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)
    lw   t1, 0x30(s1)          # load-back

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Platform interrupt 0 delegated to S-mode
    #          Set MIDELEG bit 16 to delegate to S-mode
    #          SCAUSE = 0x80000010
    #=================================================================

    # Disable MSTATUS.MIE to prevent spurious interrupts during setup
    li   t0, 0x8
    csrc mstatus, t0

    # Delegate platform interrupt 0 (bit 16) to S-mode
    li   t0, (1 << 16)
    csrs mideleg, t0

    # Enable platform interrupt 0 in SIE (bit 16)
    # (SIE accesses bits delegated via MIDELEG)
    li   t0, (1 << 16)
    csrs sie, t0

    # Set SSTATUS.SIE (bit 1 of MSTATUS)
    li   t0, 0x2
    csrs mstatus, t0

    # Set platform interrupt 0 pending: MIP bit 16
    li   t0, (1 << 16)
    csrs mip, t0

    # Transition to S-mode
    # Set MPIE = 1 and MPP = 01 (S-mode)
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0880
    csrs mstatus, t0           # MPP=01, MPIE=1

    la   t0, s_mode_p3
    csrw mepc, t0

    # Clear s_trap_handled
    sw   zero, 0x28(s1)

    mret                       # -> S-mode (platform IRQ pending + delegated)

s_mode_p3:
    # Supervisor interrupt should fire immediately
wait_p3:
    lw   t0, 0x28(s1)
    beqz t0, wait_p3

    # S-mode handler returned us to S-mode
    lw   t0, 0x1C(s1)          # SCAUSE
    sw   t0, 0x40(s1)
    lw   t1, 0x40(s1)          # load-back

    # Return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    # Clean up
    li   t0, (1 << 16)
    csrc mideleg, t0
    csrc mip, t0
    csrc sie, t0
    csrc mie, t0

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Hardware-driven platform interrupt 0 in M-mode
    #          Testbench asserts irq_platform[0] -> cause 16
    #          MCAUSE = 0x80000010
    #=================================================================

    # Re-enable platform interrupt 0 in MIE (bit 16)
    li   t0, (1 << 16)
    csrs mie, t0

    # Enable MSTATUS.MIE (bit 3)
    li   t0, 0x8
    csrs mstatus, t0

    # Clear m_trap_handled flag
    sw   zero, 0x10(s1)

    # Signal testbench: assert irq_platform[0]
    li   x31, 0x41414141

    # Spin-wait for handler
wait_p4:
    lw   t0, 0x10(s1)
    beqz t0, wait_p4

    # Copy MCAUSE
    lw   t0, 0x04(s1)
    sw   t0, 0x50(s1)
    lw   t1, 0x50(s1)

    # Signal testbench: Phase 4 complete (deassert irq_platform)
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Hardware-driven platform interrupt 5 delegated to S-mode
    #          Testbench asserts irq_platform[5] -> cause 21
    #          SCAUSE = 0x80000015
    #=================================================================

    # Disable MSTATUS.MIE during setup
    li   t0, 0x8
    csrc mstatus, t0

    # Delegate platform interrupt 5 (bit 21) to S-mode
    li   t0, (1 << 21)
    csrs mideleg, t0

    # Enable platform interrupt 5 in SIE (bit 21)
    li   t0, (1 << 21)
    csrs sie, t0

    # Set SSTATUS.SIE (bit 1)
    li   t0, 0x2
    csrs mstatus, t0

    # Transition to S-mode: MPP=01, MPIE=1
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0880
    csrs mstatus, t0

    la   t0, s_mode_p5
    csrw mepc, t0

    # Clear s_trap_handled
    sw   zero, 0x28(s1)

    # Signal testbench: assert irq_platform[5]
    li   x31, 0x51515151

    mret

s_mode_p5:
wait_p5:
    lw   t0, 0x28(s1)
    beqz t0, wait_p5

    # Copy SCAUSE
    lw   t0, 0x1C(s1)
    sw   t0, 0x60(s1)
    lw   t1, 0x60(s1)

    # Return to M-mode
    li   a0, 1
    ecall

    # Back in M-mode
    # Clean up
    li   t0, (1 << 21)
    csrc mideleg, t0
    csrc sie, t0
    csrc sip, t0              # Clear pending bit

    # Signal testbench: Phase 5 complete (deassert irq_platform)
    li   x31, 0x55555555


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
