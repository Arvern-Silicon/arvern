#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_jr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.JR
#----------------------------------------------------------------------------

    .section .text
	.option norvc        # disable all compressed instructions in this section
    .global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP
    #-------------------------------------------------

    # Initialize counters
    li  x16, 0x00000000  # Jump counter
    li  x17, 0x00000000  # Test counter

    # Setup markers
    li  x1,  0x1600D001
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.JR (Compressed Jump Register)
    # Format: c.jr rs1
    # Function: PC = rs1
    # Registers: rs1 can be any x1-x31 (not x0)
    # Encoding: 100_0_rs1[4:0]_00000_10 (rs1 != 0, bit[12]=0)
    #
    # Key behavior:
    # - Jumps to address in rs1
    # - No return address saved (unlike C.JALR)
    # - Source register remains unchanged
    # - Commonly used for function returns
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Simple jump using x1 (ra)
    #-------------------------------------------------
test_1:
    addi x17, x17, 1     # Test counter = 1
    la   x1, test_1_target
    c.jr x1
    addi x18, x18, 1     # Should be skipped
    addi x18, x18, 1     # Should be skipped

test_1_target:
    addi x16, x16, 1     # Jump counter = 1

    #-------------------------------------------------
    # Test Set 2: Jump using compressed register (x8)
    #-------------------------------------------------
test_2:
    addi x17, x17, 1     # Test counter = 2
    la   x8, test_2_target
    c.jr x8
    addi x18, x18, 1     # Should be skipped

test_2_target:
    addi x16, x16, 1     # Jump counter = 2

    #-------------------------------------------------
    # Test Set 3: Jump using non-compressed register (x25)
    #-------------------------------------------------
test_3:
    addi x17, x17, 1     # Test counter = 3
    la   x25, test_3_target
    c.jr x25
    addi x18, x18, 1     # Should be skipped

test_3_target:
    addi x16, x16, 1     # Jump counter = 3

    #-------------------------------------------------
    # Test Set 4: Sequential jumps (chain)
    #-------------------------------------------------
test_4:
    addi x17, x17, 1     # Test counter = 4
    la   x9, test_4_a
    c.jr x9
    addi x18, x18, 1     # Should be skipped

test_4_a:
    addi x19, x19, 1     # Chain counter = 1
    la   x10, test_4_b
    c.jr x10
    addi x18, x18, 1     # Should be skipped

test_4_b:
    addi x19, x19, 1     # Chain counter = 2
    la   x11, test_4_c
    c.jr x11
    addi x18, x18, 1     # Should be skipped

test_4_c:
    addi x19, x19, 1     # Chain counter = 3
    addi x16, x16, 1     # Jump counter = 4

    #-------------------------------------------------
    # Test Set 5: Register preservation test
    #-------------------------------------------------
test_5:
    addi x17, x17, 1     # Test counter = 5
    la   x12, test_5_target
    addi x20, x12, 0     # Backup x12 before jump
    c.jr x12
    addi x18, x18, 1     # Should be skipped

test_5_target:
    addi x16, x16, 1     # Jump counter = 5
    addi x21, x12, 0     # Backup x12 after jump (should be unchanged)

    #-------------------------------------------------
    # Test Set 6: Jump table pattern
    #-------------------------------------------------
test_6:
    addi x17, x17, 1     # Test counter = 6
    li   x13, 0          # Select case 0
    la   x2, test_6_table
    slli x13, x13, 2     # Multiply by 4 (word size)
    add  x13, x13, x2    # Get address of entry
    lw   x13, 0(x13)     # Load target address
    c.jr x13
    addi x18, x18, 1     # Should be skipped

.align 2
test_6_table:
    .word test_6_case0
    .word test_6_case1

test_6_case0:
    addi x22, x22, 1     # Case 0 executed
    addi x16, x16, 1     # Jump counter = 6
    j    test_6_end

test_6_case1:
    addi x18, x18, 1     # Should not be executed

test_6_end:

    #-------------------------------------------------
    # Test Set 7: Function call/return pattern
    #-------------------------------------------------
test_7:
    addi x17, x17, 1     # Test counter = 7
    la   x1, test_7_return
    la   x14, test_7_func
    c.jr x14             # "Call" function

test_7_return:
    addi x16, x16, 1     # Jump counter = 8 (after return)
    j    test_7_end

test_7_func:
    addi x23, x23, 1     # Function body counter = 1
    addi x16, x16, 1     # Jump counter = 7
    c.jr x1              # "Return" from function

test_7_end:

    #-------------------------------------------------
    # Test Set 8: Multiple jumps with different registers
    #-------------------------------------------------
test_8:
    addi x17, x17, 1     # Test counter = 8

    # Using x8
    la   x8, test_8_a
    c.jr x8

test_8_a:
    addi x16, x16, 1     # Jump counter = 9

    # Using x9
    la   x9, test_8_b
    c.jr x9

test_8_b:
    addi x16, x16, 1     # Jump counter = 10

    # Using x10
    la   x10, test_8_c
    c.jr x10

test_8_c:
    addi x16, x16, 1     # Jump counter = 11

    #-------------------------------------------------
    # Test Set 9: Jump with x1 (return address register)
    #-------------------------------------------------
test_9:
    addi x17, x17, 1     # Test counter = 9
    la   x1, test_9_target
    addi x24, x1, 0      # Backup x1 before jump
    c.jr x1
    addi x18, x18, 1     # Should be skipped

test_9_target:
    addi x16, x16, 1     # Jump counter = 12
    addi x25, x1, 0      # Backup x1 after jump (should be unchanged)

    #-------------------------------------------------
    # Test Set 10: Jump to nearby address
    #-------------------------------------------------
test_10:
    addi x17, x17, 1     # Test counter = 10
    la   x15, test_10_target
    c.jr x15

test_10_target:
    addi x16, x16, 1     # Jump counter = 13

.option norvc
    # Backup final results
    addi x26, x16, 0     # Backup jump counter (should be 13)
    addi x27, x17, 0     # Backup test counter (should be 10)
    addi x28, x18, 0     # Backup skipped counter (should be 0)
    addi x29, x19, 0     # Backup chain counter (should be 3)
    addi x30, x23, 0     # Backup function body counter (should be 1)

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
