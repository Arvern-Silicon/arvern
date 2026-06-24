#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_ebreak
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.EBREAK
#   Tests the C.EBREAK (compressed breakpoint) trap handling:
#   - C.EBREAK trap entry: MCAUSE (cause 3), MEPC, MSTATUS save
#   - MEPC points to the 2-byte C.EBREAK instruction
#   - MRET return: PC restore to MEPC+2 (compressed instruction)
#   - Multiple consecutive C.EBREAKs
#   - Back-to-back C.EBREAKs
#   - Pipeline stress around C.EBREAK
#   - Register preservation across trap entry/exit
#   - MTVEC configuration and readback
#   - MTVAL verification (should be 0 for EBREAK)
#   - Mixed C.EBREAK and standard EBREAK in same test
#   - MSTATUS.MIE toggle: trap with MIE=0 then MIE=1
#----------------------------------------------------------------------------

    .section .text
    .option norvc        # disable compressed instructions for setup code
    .global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
#   0x00: trap_count          (incremented by handler each time)
#   0x04: trap1_mcause        (MCAUSE from 1st C.EBREAK)
#   0x08: trap1_mepc          (MEPC from 1st C.EBREAK)
#   0x0C: trap1_mstatus       (MSTATUS inside 1st trap handler)
#   0x10: trap2_mcause        (MCAUSE from 2nd C.EBREAK)
#   0x14: trap2_mepc          (MEPC from 2nd C.EBREAK)
#   0x18: trap2_mstatus       (MSTATUS inside 2nd trap handler)
#   0x1C: mstatus_after_mret1 (MSTATUS read after 1st MRET)
#   0x20: expected_mepc1      (expected MEPC for 1st C.EBREAK)
#   0x24: expected_mepc2      (expected MEPC for 2nd C.EBREAK)
#   0x28: trap3_mcause        (MCAUSE from 3rd C.EBREAK - back-to-back)
#   0x2C: trap3_mepc          (MEPC from 3rd C.EBREAK)
#   0x30: trap4_mcause        (MCAUSE from 4th C.EBREAK - back-to-back)
#   0x34: trap4_mepc          (MEPC from 4th C.EBREAK)
#   0x38: mstatus_after_mret2 (MSTATUS read after last MRET)
#   0x3C: mtvec_readback      (MTVEC value read back after write)
#   0x40: pipeline_reg_save   (value of s0 after pipeline-stress C.EBREAK)
#   0x44: trap1_mtval         (MTVAL from 1st C.EBREAK - should be 0)
#   0x48: trap5_mcause        (MCAUSE from 5th trap - C.EBREAK with MIE=0)
#   0x4C: trap5_mstatus       (MSTATUS inside 5th trap handler)
#   0x50: trap6_mcause        (MCAUSE from 6th trap - standard EBREAK)
#   0x54: trap6_mepc          (MEPC from 6th trap - standard EBREAK)
#   0x58: trap7_mcause        (MCAUSE from 7th trap - C.EBREAK after std)
#   0x5C: trap7_mepc          (MEPC from 7th trap - C.EBREAK after std)
#   0x60: sp_before_traps     (SP value before trap sequence)
#   0x64: sp_after_traps      (SP value after trap sequence)
#   0x68: expected_mepc3      (expected MEPC for 3rd C.EBREAK)
#   0x6C: expected_mepc4      (expected MEPC for 4th C.EBREAK)
#   0x70: mstatus_after_mret3 (MSTATUS after MRET from MIE=0 test)
#   0x74: expected_mepc6      (expected MEPC for std EBREAK)
#   0x78: expected_mepc7      (expected MEPC for C.EBREAK after std)
#=========================================================================

main:
    j _start            # Reset Vector

    #=================================================================
    # INITIALIZATION
    #=================================================================
 _start:
    # Initialize stack pointer to top of executable SRAM
    li  sp, 0x80010000

    # Initialize scratchpad base pointer
    li  s1, 0x80000000     # s1 = scratchpad base (kept throughout test)

    # Zero out the scratchpad area (0x00..0x7C)
    li  t0, 0
    sw  t0, 0x00(s1)
    sw  t0, 0x04(s1)
    sw  t0, 0x08(s1)
    sw  t0, 0x0C(s1)
    sw  t0, 0x10(s1)
    sw  t0, 0x14(s1)
    sw  t0, 0x18(s1)
    sw  t0, 0x1C(s1)
    sw  t0, 0x20(s1)
    sw  t0, 0x24(s1)
    sw  t0, 0x28(s1)
    sw  t0, 0x2C(s1)
    sw  t0, 0x30(s1)
    sw  t0, 0x34(s1)
    sw  t0, 0x38(s1)
    sw  t0, 0x3C(s1)
    sw  t0, 0x40(s1)
    sw  t0, 0x44(s1)
    sw  t0, 0x48(s1)
    sw  t0, 0x4C(s1)
    sw  t0, 0x50(s1)
    sw  t0, 0x54(s1)
    sw  t0, 0x58(s1)
    sw  t0, 0x5C(s1)
    sw  t0, 0x60(s1)
    sw  t0, 0x64(s1)
    sw  t0, 0x68(s1)
    sw  t0, 0x6C(s1)
    sw  t0, 0x70(s1)
    sw  t0, 0x74(s1)
    sw  t0, 0x78(s1)

    #=================================================================
    # PHASE 1: Set up trap handler and verify MTVEC
    #=================================================================

    # Install trap handler (uses smart handler that detects instruction size)
    la   t0, trap_handler
    csrw mtvec, t0

    # Read back MTVEC and store to scratchpad for testbench verification
    csrr t1, mtvec
    sw   t1, 0x3C(s1)      # mtvec_readback

    # Enable machine interrupts globally: set MIE bit (bit 3) in MSTATUS
    li   t0, 0x8
    csrs mstatus, t0

    # Signal to testbench: phase 1 init complete
    li  x31, 0x11111111

    #=================================================================
    # PHASE 2: First C.EBREAK - basic trap entry/exit
    #=================================================================

    # Initialize callee-saved registers to known pattern
    li  s2,  0xAAAAAAAA
    li  s3,  0xBBBBBBBB
    li  s4,  0xCCCCCCCC
    li  s5,  0xDDDDDDDD
    li  s6,  0xEEEEEEEE

    # Store expected MEPC (= address of the upcoming c.ebreak instruction)
    la    t0, cebreak1_inst
    sw    t0, 0x20(s1)     # expected_mepc1

    .option rvc            # Enable compressed instructions
cebreak1_inst:
    c.ebreak               # C.EBREAK #1 → trap handler (2-byte instruction)
    .option norvc

    # After MRET, execution resumes here (MEPC+2)
    # Read MSTATUS after return and save
    csrr t0, mstatus
    sw   t0, 0x1C(s1)      # mstatus_after_mret1
    lw   t0, 0x1C(s1)      # Load-back to ensure store completes

    # Signal: phase 2 done (first C.EBREAK complete, MRET returned)
    li  x31, 0x22222222

    #=================================================================
    # PHASE 3: Second C.EBREAK - consecutive traps with ALU stress
    #=================================================================

    # Do some ALU work between C.EBREAKs to stress pipeline
    li   a0, 0x12345678
    li   a1, 0x9ABCDEF0
    add  a2, a0, a1        # a2 = 0xACF13568
    xor  a3, a0, a1        # a3 = 0x88888888
    and  a4, a0, a1        # a4 = 0x12345670
    or   a5, a0, a1        # a5 = 0x9ABCDEF8

    # Store expected MEPC for second c.ebreak
    la    t0, cebreak2_inst
    sw    t0, 0x24(s1)     # expected_mepc2

    .option rvc
cebreak2_inst:
    c.ebreak               # C.EBREAK #2 → trap handler
    .option norvc

    # Signal: phase 3 done (second C.EBREAK complete)
    li  x31, 0x33333333

    #=================================================================
    # PHASE 4: Back-to-back C.EBREAKs
    #=================================================================

    # Store expected MEPCs for both back-to-back c.ebreaks
    la    t0, cebreak3_inst
    sw    t0, 0x68(s1)     # expected_mepc3
    la    t0, cebreak4_inst
    sw    t0, 0x6C(s1)     # expected_mepc4

    .option rvc
cebreak3_inst:
    c.ebreak                # C.EBREAK #3 → immediate after previous return
    c.nop
cebreak4_inst:
    c.ebreak                # C.EBREAK #4 → immediate after C.EBREAK #3 return
    .option norvc

    # Signal: phase 4 done
    li  x31, 0x44444444

    #=================================================================
    # PHASE 5: C.EBREAK with load/store pipeline activity before it
    #=================================================================

    # Store some data to SRAM then immediately C.EBREAK
    li   s0, 0xDEADBEEF
    sw   s0, 0x40(s1)      # store to scratchpad
    lw   s0, 0x40(s1)      # load back
    add  s0, s0, s0        # ALU op on loaded value

    .option rvc
    c.ebreak               # C.EBREAK #5 → right after load+ALU
    .option norvc

    # Verify s0 wasn't corrupted (handler doesn't touch s-regs)
    sw   s0, 0x40(s1)      # pipeline_reg_save = s0 (should be 0xBD5B7DDE)
    lw   t0, 0x40(s1)      # Load-back to ensure store completes

    # Signal: phase 5 done
    li  x31, 0x55555555

    #=================================================================
    # PHASE 6: C.EBREAK with MIE=0
    #=================================================================

    # Clear MIE bit
    li   t0, 0x8
    csrc mstatus, t0

    .option rvc
    c.ebreak               # C.EBREAK #6 → should still trap with MIE=0
    .option norvc

    # Read MSTATUS after MRET from MIE=0 trap
    csrr t0, mstatus
    sw   t0, 0x70(s1)      # mstatus_after_mret3
    lw   t1, 0x70(s1)      # Load-back (use t1 to avoid clobbering t0)

    # Re-enable MIE for subsequent phases
    li   t0, 0x8
    csrs mstatus, t0

    # Signal: phase 6 done
    li  x31, 0x66666666

    #=================================================================
    # PHASE 7: Mixed C.EBREAK and standard EBREAK
    # Verify handler correctly distinguishes instruction size
    #=================================================================

    # Save SP before this sequence
    sw   sp, 0x60(s1)

    # Standard EBREAK first (4-byte instruction)
    la    t0, ebreak_std_inst
    sw    t0, 0x74(s1)     # expected_mepc6

ebreak_std_inst:
    ebreak                 # Trap #7 → standard EBREAK (cause 3, 4-byte)

    # Then C.EBREAK immediately after
    la    t0, cebreak7_inst
    sw    t0, 0x78(s1)     # expected_mepc7

    .option rvc
cebreak7_inst:
    c.ebreak               # Trap #8 → C.EBREAK (cause 3, 2-byte)
    .option norvc

    # Save SP after this sequence
    sw   sp, 0x64(s1)
    lw   t1, 0x64(s1)      # Load-back (use t1 to avoid clobbering t0)

    # Read final MSTATUS
    csrr t0, mstatus
    sw   t0, 0x38(s1)      # mstatus_after_mret2
    lw   t0, 0x38(s1)      # Load-back to ensure store completes before signal

    # Signal: all phases complete
    li  x31, 0x77777777

    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j end_of_test           # infinite loop


#=========================================================================
# TRAP HANDLER
# Smart handler that detects instruction size at MEPC to advance by
# the correct amount (2 bytes for compressed, 4 bytes for standard).
# Per RISC-V spec: bits [1:0] of a compressed instruction are != 2'b11.
#=========================================================================
    .align 2

trap_handler:
    # Save temporaries on stack (preserve caller state)
    addi sp, sp, -32
    sw   ra,  28(sp)
    sw   t0,  24(sp)
    sw   t1,  20(sp)
    sw   t2,  16(sp)
    sw   t3,  12(sp)
    sw   t4,   8(sp)

    # Read trap CSRs
    csrr t0, mcause         # t0 = cause
    csrr t1, mepc           # t1 = exception PC
    csrr t2, mstatus        # t2 = machine status

    # Load current trap count
    lw   t3, 0x00(s1)       # t3 = trap_count
    addi t3, t3, 1          # increment
    sw   t3, 0x00(s1)       # store back

    # Save CSR values based on trap count
    li   t4, 1
    beq  t3, t4, save_trap1
    li   t4, 2
    beq  t3, t4, save_trap2
    li   t4, 3
    beq  t3, t4, save_trap3
    li   t4, 4
    beq  t3, t4, save_trap4
    li   t4, 5
    beq  t3, t4, save_trap5
    li   t4, 6
    beq  t3, t4, save_trap6
    li   t4, 7
    beq  t3, t4, save_trap7
    li   t4, 8
    beq  t3, t4, save_trap8
    j    trap_advance

save_trap1:
    sw   t0, 0x04(s1)       # trap1_mcause
    sw   t1, 0x08(s1)       # trap1_mepc
    sw   t2, 0x0C(s1)       # trap1_mstatus
    # Also save MTVAL for verification
    csrr t4, mtval
    sw   t4, 0x44(s1)       # trap1_mtval
    j    trap_advance

save_trap2:
    sw   t0, 0x10(s1)       # trap2_mcause
    sw   t1, 0x14(s1)       # trap2_mepc
    sw   t2, 0x18(s1)       # trap2_mstatus
    j    trap_advance

save_trap3:
    sw   t0, 0x28(s1)       # trap3_mcause
    sw   t1, 0x2C(s1)       # trap3_mepc
    j    trap_advance

save_trap4:
    sw   t0, 0x30(s1)       # trap4_mcause
    sw   t1, 0x34(s1)       # trap4_mepc
    j    trap_advance

save_trap5:
    j    trap_advance        # pipeline stress - just advance

save_trap6:
    sw   t0, 0x48(s1)       # trap5_mcause (C.EBREAK with MIE=0)
    sw   t2, 0x4C(s1)       # trap5_mstatus
    j    trap_advance

save_trap7:
    sw   t0, 0x50(s1)       # trap6_mcause (standard EBREAK)
    sw   t1, 0x54(s1)       # trap6_mepc
    j    trap_advance

save_trap8:
    sw   t0, 0x58(s1)       # trap7_mcause (C.EBREAK after std)
    sw   t1, 0x5C(s1)       # trap7_mepc
    j    trap_advance

trap_advance:
    # Detect instruction size at MEPC to advance by correct amount
    # Load the halfword at MEPC
    lhu  t4, 0(t1)          # t4 = instruction halfword at MEPC
    andi t4, t4, 0x3        # Check bits [1:0]
    li   t3, 0x3
    beq  t4, t3, advance_4  # If bits[1:0] == 2'b11, it's a 4-byte instruction

    # Compressed instruction: advance by 2
    addi t1, t1, 2
    j    trap_done

advance_4:
    # Standard instruction: advance by 4
    addi t1, t1, 4

trap_done:
    csrw mepc, t1

    # Restore temporaries from stack
    lw   t4,   8(sp)
    lw   t3,  12(sp)
    lw   t2,  16(sp)
    lw   t1,  20(sp)
    lw   t0,  24(sp)
    lw   ra,  28(sp)
    addi sp, sp, 32

    mret
