#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_ecall
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ECALL
#   Tests the trap handling hardware comprehensively:
#   - ECALL trap entry: MCAUSE, MEPC, MSTATUS save
#   - MRET return: PC restore, MSTATUS restore
#   - Multiple consecutive ECALLs
#   - Pipeline stress around ECALL (ALU, load/store before/after)
#   - Register preservation across trap entry/exit
#   - MTVEC configuration
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
#   0x00: trap_count        (incremented by handler each time)
#   0x04: trap1_mcause      (MCAUSE from 1st ECALL)
#   0x08: trap1_mepc        (MEPC from 1st ECALL)
#   0x0C: trap1_mstatus     (MSTATUS inside 1st trap handler)
#   0x10: trap2_mcause      (MCAUSE from 2nd ECALL)
#   0x14: trap2_mepc        (MEPC from 2nd ECALL)
#   0x18: trap2_mstatus     (MSTATUS inside 2nd trap handler)
#   0x1C: mstatus_after_mret1 (MSTATUS read after 1st MRET)
#   0x20: expected_mepc1    (expected MEPC for 1st ECALL, stored before ecall)
#   0x24: expected_mepc2    (expected MEPC for 2nd ECALL, stored before ecall)
#   0x28: trap3_mcause      (MCAUSE from 3rd ECALL - back-to-back test)
#   0x2C: trap3_mepc        (MEPC from 3rd ECALL)
#   0x30: trap4_mcause      (MCAUSE from 4th ECALL - after load/store)
#   0x34: trap4_mepc        (MEPC from 4th ECALL)
#   0x38: mstatus_after_mret2 (MSTATUS read after last MRET)
#   0x3C: mtvec_readback    (MTVEC value read back after write)
#   0x40: pipeline_reg_save (value of s0 after pipeline-stress ECALL)
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

    # Zero out the scratchpad area (0x00..0x44)
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

    #=================================================================
    # PHASE 1: Set up trap handler and verify MTVEC
    #=================================================================

    # Install trap handler
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
    # PHASE 2: First ECALL - basic trap entry/exit
    #=================================================================

    # Initialize callee-saved registers to known pattern
    li  s2,  0xAAAAAAAA
    li  s3,  0xBBBBBBBB
    li  s4,  0xCCCCCCCC
    li  s5,  0xDDDDDDDD
    li  s6,  0xEEEEEEEE

    # Store expected MEPC (= address of the upcoming ecall instruction)
    la    t0, ecall1_inst
    sw    t0, 0x20(s1)     # expected_mepc1

ecall1_inst:
    ecall                   # ECALL #1 → trap handler

    # After MRET, execution resumes here
    # Read MSTATUS after return and save
    csrr t0, mstatus
    sw   t0, 0x1C(s1)      # mstatus_after_mret1
    lw   t0, 0x1C(s1)      # Load-back to ensure store completes

    # Signal: phase 2 done (first ECALL complete, MRET returned)
    li  x31, 0x22222222

    #=================================================================
    # PHASE 3: Second ECALL - verify consecutive traps work
    #=================================================================

    # Do some ALU work between ECALLs to stress pipeline
    li   a0, 0x12345678
    li   a1, 0x9ABCDEF0
    add  a2, a0, a1        # a2 = 0xACF13568
    xor  a3, a0, a1        # a3 = 0x88888888
    and  a4, a0, a1        # a4 = 0x12345670
    or   a5, a0, a1        # a5 = 0x9ABCDEF8

    # Store expected MEPC for second ecall
    la    t0, ecall2_inst
    sw    t0, 0x24(s1)     # expected_mepc2

ecall2_inst:
    ecall                   # ECALL #2 → trap handler

    # Signal: phase 3 done (second ECALL complete)
    li  x31, 0x33333333

    #=================================================================
    # PHASE 4: Back-to-back ECALL (ECALL right after MRET return)
    #=================================================================

    ecall                   # ECALL #3 → immediate after previous return

    ecall                   # ECALL #4 → immediate after ECALL #3 return

    # Signal: phase 4 done
    li  x31, 0x44444444

    #=================================================================
    # PHASE 5: ECALL with load/store pipeline activity before it
    #=================================================================

    # Store some data to SRAM then immediately ECALL
    li   s0, 0xDEADBEEF
    sw   s0, 0x40(s1)      # store to scratchpad
    lw   s0, 0x40(s1)      # load back
    add  s0, s0, s0        # ALU op on loaded value

    ecall                   # ECALL #5 → right after load+ALU

    # Verify s0 wasn't corrupted (handler doesn't touch s-regs)
    sw   s0, 0x40(s1)      # pipeline_reg_save = s0 (should be 0xBD5B7DDE)
    lw   t0, 0x40(s1)      # Load-back to ensure store completes

    # Read final MSTATUS
    csrr t0, mstatus
    sw   t0, 0x38(s1)      # mstatus_after_mret2
    lw   t0, 0x38(s1)      # Load-back to ensure store completes before signal

    # Signal: all phases complete
    li  x31, 0x55555555

    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j end_of_test           # infinite loop


#=========================================================================
# TRAP HANDLER
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
    j    trap_advance        # trap 5+ just advance PC

save_trap1:
    sw   t0, 0x04(s1)       # trap1_mcause
    sw   t1, 0x08(s1)       # trap1_mepc
    sw   t2, 0x0C(s1)       # trap1_mstatus
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

trap_advance:
    # Advance MEPC past the ECALL instruction (+4 bytes)
    addi t1, t1, 4
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
