#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_inst_edge
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP IRQ INST EDGE
#   IRQ edge cases with specific instruction types:
#   - IRQ during compressed instruction stream: verify MEPC alignment and
#   correct resume after MRET
#   - IRQ during CSR read-modify-write: verify atomicity (CSR value is
#   consistent with MEPC, i.e. CSR op fully done or not started)
#   - IRQ immediately after branch: verify MEPC points to branch target
#
#   Interrupt signals are driven by the testbench (block-level verification).
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x000: trap_count
#   0x004: last MCAUSE
#   0x008: last MSTATUS
#   0x00C: last MEPC
#   0x010: trap_handled flag
#
# Phase 2 (IRQ during instruction stream):
#   0x020: MEPC captured during IRQ
#   0x024: MCAUSE (expect timer 0x80000007)
#   0x028: marker_after_sled (expect 0xAAAA1111 if resumed correctly)
#   0x02C: sled_start_addr
#   0x030: sled_end_addr
#
# Phase 3 (IRQ during CSR sequence):
#   0x040: MEPC captured during IRQ
#   0x044: MCAUSE (expect timer 0x80000007)
#   0x048: MSCRATCH final value
#   0x04C: csr_seq_start_addr
#   0x050: csr_seq_end_addr
#
# Phase 4 (IRQ after branch instruction):
#   0x060: MEPC captured during IRQ
#   0x064: MCAUSE (expect timer 0x80000007)
#   0x068: marker_after_branch (expect 0xBBBB2222 if resumed correctly)
#   0x06C: branch_target_addr
#   0x070: branch_end_addr
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

    # Increment trap count
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

    # ECALL from M-mode (cause 11): advance MEPC by 4
    li   t4, 11
    beq  t3, t4, m_ecall
    j    m_handler_done

m_ecall:
    addi t1, t1, 4
    csrw mepc, t1
    j    m_handler_done

m_handle_interrupt:
    # Disable the MIE bit for the interrupt that fired
    andi t3, t0, 0x1F
    li   t4, 7
    beq  t3, t4, m_disable_mtie
    li   t4, 11
    beq  t3, t4, m_disable_meie
    j    m_irq_done

m_disable_mtie:
    li   t4, 0x80              # MIE.MTIE = bit 7
    csrc mie, t4
    j    m_irq_done

m_disable_meie:
    li   t4, 0x800             # MIE.MEIE = bit 11
    csrc mie, t4

m_irq_done:
    # Set trap_handled flag
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
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x48(s1)
    sw   t0, 0x4C(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x64(s1)
    sw   t0, 0x68(s1)
    sw   t0, 0x6C(s1)
    sw   t0, 0x70(s1)

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
    # PHASE 2: IRQ during instruction stream
    #
    # Execute a long NOP sled. The testbench fires a timer IRQ
    # during the sled. After the handler returns, verify:
    #   - MEPC is within the sled address range
    #   - MEPC[0] == 0 (properly aligned)
    #   - Execution resumes correctly (marker written after sled)
    #=================================================================

    # Record sled address range
    la   t0, irq_sled_start
    sw   t0, 0x2C(s1)
    la   t0, irq_sled_end
    sw   t0, 0x30(s1)

    # Enable MIE.MTIE (bit 7) and MSTATUS.MIE (bit 3)
    li   t0, 0x80
    csrs mie, t0
    li   t0, 0x8
    csrs mstatus, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Signal: ready for timer IRQ during sled
    li   x31, 0x21212121

    # ---- NOP sled (long enough for IRQ to hit somewhere in the middle) ----
    # Use a mix of instructions that may be compressed in COMP mode
irq_sled_start:
    nop
    nop
    addi t0, zero, 1
    addi t0, zero, 2
    nop
    addi t0, zero, 3
    addi t0, zero, 4
    nop
    nop
    addi t0, zero, 5
    addi t0, zero, 6
    nop
    addi t0, zero, 7
    addi t0, zero, 8
    nop
    nop
    addi t0, zero, 9
    addi t0, zero, 10
    nop
    addi t0, zero, 11
    addi t0, zero, 12
    nop
    nop
    addi t0, zero, 13
    addi t0, zero, 14
    nop
    addi t0, zero, 15
    addi t0, zero, 16
    nop
    nop
irq_sled_end:

    # Copy MEPC and MCAUSE to Phase 2 area
    lw   t0, 0x0C(s1)          # last MEPC
    sw   t0, 0x20(s1)
    lw   t0, 0x04(s1)          # last MCAUSE
    sw   t0, 0x24(s1)

    # Write marker proving execution resumed correctly
    li   t0, 0xAAAA1111
    sw   t0, 0x28(s1)
    lw   t1, 0x28(s1)          # load-back

    # Signal: Phase 2 complete
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: IRQ during CSR read-modify-write sequence
    #
    # Write a sequence of known values to MSCRATCH using CSRRW.
    # The testbench fires a timer IRQ during the sequence.
    # After the handler returns, verify:
    #   - MEPC is within the CSR sequence range
    #   - MSCRATCH has a valid value from the sequence
    #   - Execution resumes correctly
    #=================================================================

    # Record CSR sequence address range
    la   t0, csr_seq_start
    sw   t0, 0x4C(s1)
    la   t0, csr_seq_end
    sw   t0, 0x50(s1)

    # Re-enable MIE.MTIE
    li   t0, 0x80
    csrs mie, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Initialize MSCRATCH to 0
    csrw mscratch, zero

    # Signal: ready for timer IRQ during CSR sequence
    li   x31, 0x31313131

    # ---- CSR sequence: write incrementing values to MSCRATCH ----
csr_seq_start:
    li   t0, 0x11111111
    csrrw zero, mscratch, t0
    li   t0, 0x22222222
    csrrw zero, mscratch, t0
    li   t0, 0x33333333
    csrrw zero, mscratch, t0
    li   t0, 0x44444444
    csrrw zero, mscratch, t0
    li   t0, 0x55555555
    csrrw zero, mscratch, t0
    li   t0, 0x66666666
    csrrw zero, mscratch, t0
    li   t0, 0x77777777
    csrrw zero, mscratch, t0
    li   t0, 0x88888888
    csrrw zero, mscratch, t0
    li   t0, 0x99999999
    csrrw zero, mscratch, t0
    li   t0, 0xAAAAAAAA
    csrrw zero, mscratch, t0
    li   t0, 0xBBBBBBBB
    csrrw zero, mscratch, t0
    li   t0, 0xCCCCCCCC
    csrrw zero, mscratch, t0
    li   t0, 0xDDDDDDDD
    csrrw zero, mscratch, t0
    li   t0, 0xEEEEEEEE
    csrrw zero, mscratch, t0
    li   t0, 0xFFFFFFFF
    csrrw zero, mscratch, t0
csr_seq_end:

    # Copy MEPC and MCAUSE to Phase 3 area
    lw   t0, 0x0C(s1)          # last MEPC
    sw   t0, 0x40(s1)
    lw   t0, 0x04(s1)          # last MCAUSE
    sw   t0, 0x44(s1)

    # Read final MSCRATCH value
    csrr t0, mscratch
    sw   t0, 0x48(s1)
    lw   t1, 0x48(s1)          # load-back

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: IRQ after branch instruction
    #
    # Execute a branch followed by instructions at the target.
    # The testbench fires an external IRQ timed to hit around the
    # branch. After the handler returns, verify:
    #   - MEPC is within expected range (target area)
    #   - Execution resumes correctly (marker written)
    #=================================================================

    # Record branch target range
    la   t0, branch_target
    sw   t0, 0x6C(s1)
    la   t0, branch_end
    sw   t0, 0x70(s1)

    # Re-enable MIE.MEIE (bit 11) and MSTATUS.MIE (bit 3)
    li   t0, 0x800
    csrs mie, t0
    li   t0, 0x8
    csrs mstatus, t0

    # Clear trap_handled flag
    sw   zero, 0x10(s1)

    # Signal: ready for external IRQ around branch
    li   x31, 0x41414141

    # ---- Branch sequence ----
    li   t0, 1
    li   t1, 1
    beq  t0, t1, branch_target   # Always taken
    nop                            # Should be skipped

branch_target:
    nop
    nop
    nop
    addi t0, zero, 42
    nop
    nop
    nop
    nop
    addi t0, zero, 43
    nop
    nop
    nop
branch_end:

    # Copy MEPC and MCAUSE to Phase 4 area
    lw   t0, 0x0C(s1)          # last MEPC
    sw   t0, 0x60(s1)
    lw   t0, 0x04(s1)          # last MCAUSE
    sw   t0, 0x64(s1)

    # Write marker proving execution resumed correctly
    li   t0, 0xBBBB2222
    sw   t0, 0x68(s1)
    lw   t1, 0x68(s1)          # load-back

    # Signal: Phase 4 complete
    li   x31, 0x44444444


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
