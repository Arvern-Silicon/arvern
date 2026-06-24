#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_inst_addr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: INST ADDR MISALIGNED
#   Synchronous exception verification:
#   - Instruction address misaligned (MCAUSE = 0)
#   - STD mode only (without C extension, 2-byte aligned addresses fault)
#   - MEPC, MCAUSE save/restore
#   - Register preservation across exceptions
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x0C: last MSTATUS
#   0x10: last MTVAL
#   0x14: recovery address (set before triggering IF exception)
#
# Phase 2 (inst addr misaligned via JALR to 2-byte aligned addr):
#   0x20: MCAUSE             (expect 0)
#   0x24: MEPC               (expect = PC of the JALR per RISC-V spec)
#   0x28: expected MEPC      (PC of phase2_jalr label, captured via `la`)
#   0x2C: MTVAL              (captured; expect 0x20000002 = misaligned target)
#
# Phase 3 (inst addr misaligned via JALR to different 2-byte aligned addr):
#   0x30: MCAUSE             (expect 0)
#   0x34: MEPC               (expect = PC of the JALR per RISC-V spec)
#   0x38: expected MEPC      (PC of phase3_jalr label, captured via `la`)
#   0x3C: MTVAL              (captured; expect 0x20000006 = misaligned target)
#
# RISC-V spec (Unprivileged Vol I §1.5, Privileged §3.1.14 mepc):
#   inst-addr-misaligned is reported on the branch/jump instruction, not
#   on the target ⇒ mepc = PC of the JAL/JALR; mtval = misaligned target.
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mstatus
    csrr t3, mtval

    # Increment trap_count
    lw   t4, 0x00(s1)
    addi t4, t4, 1
    sw   t4, 0x00(s1)

    # Save to working area
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)
    sw   t3, 0x10(s1)

    # Check if interrupt
    bltz t0, handle_interrupt

    # Check for instruction fetch exceptions (cause 0 or 1)
    # For these, MEPC points to an invalid/misaligned address,
    # so we can't read the instruction. Use recovery address.
    beqz t0, use_recovery_addr     # cause 0: inst addr misaligned
    li   t3, 1
    beq  t0, t3, use_recovery_addr # cause 1: inst access fault

    # For other exceptions: advance MEPC past faulting instruction
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, advance_4
    addi t1, t1, 2
    j    exc_done
advance_4:
    addi t1, t1, 4
    j    exc_done

use_recovery_addr:
    lw   t1, 0x14(s1)             # load recovery address from scratchpad

exc_done:
    csrw mepc, t1
    j    handler_done

handle_interrupt:
    andi t3, t0, 0x1F
    li   t4, 7
    beq  t3, t4, disable_mtie
    j    handler_done
disable_mtie:
    li   t4, 0x80
    csrc mie, t4

handler_done:
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
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)

    #=================================================================
    # PHASE 1: Install trap handler
    #=================================================================

    la   t0, trap_handler
    csrw mtvec, t0

    # Enable MSTATUS.MIE
    li   t0, 0x8
    csrs mstatus, t0

    # Initialize callee-saved registers for preservation check
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Instruction address misaligned (MCAUSE = 0)
    #          JALR to 2-byte aligned address 0x20000002
    #          (without C extension, this is misaligned)
    #=================================================================

    # Store recovery address
    la   t0, recovery_2
    sw   t0, 0x14(s1)

    # Store expected MEPC = PC of the JALR instruction below (spec-correct;
    # inst-addr-misaligned is reported ON the branch/jump, not on the target).
    la   t0, phase2_jalr
    sw   t0, 0x28(s1)

    # JALR to 2-byte aligned address -> instruction address misaligned
    li   t0, 0x20000002
phase2_jalr:
    jalr x0, t0, 0

recovery_2:
    # Handler should redirect here
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x24(s1)         # MEPC
    lw   t0, 0x10(s1)
    sw   t0, 0x2C(s1)         # MTVAL (expect 0x20000002)

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Instruction address misaligned (MCAUSE = 0)
    #          JALR to different 2-byte aligned address 0x20000006
    #=================================================================

    # Store recovery address
    la   t0, recovery_3
    sw   t0, 0x14(s1)

    # Store expected MEPC = PC of the JALR instruction below (see Phase 2).
    la   t0, phase3_jalr
    sw   t0, 0x38(s1)

    # JALR to 2-byte aligned address -> instruction address misaligned
    li   t0, 0x20000006
phase3_jalr:
    jalr x0, t0, 0

recovery_3:
    # Handler should redirect here
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x34(s1)         # MEPC
    lw   t0, 0x10(s1)
    sw   t0, 0x3C(s1)         # MTVAL (expect 0x20000006)

    li   x31, 0x33333333


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
