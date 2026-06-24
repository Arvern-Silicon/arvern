#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_jalr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.JALR
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
    li  x16, 0x00000000  # Call counter
    li  x17, 0x00000000  # Test counter
    li  x19, 0x00000000  # Function body counter
    li  x22, 0x00000000  # Sequential call counter
    li  x25, 0x00000000  # Function pointer counter

    # Setup markers
    li  x2,  0x1A120002
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.JALR (Compressed Jump and Link Register)
    # Format: c.jalr rs1
    # Function: x1 = PC + 2, PC = rs1
    # Registers: rs1 can be any x1-x31 (not x0)
    # Encoding: 100_1_rs1[4:0]_00000_10 (rs1 != 0, bit[12]=1)
    #
    # Key behavior:
    # - Jumps to address in rs1
    # - Saves return address (PC+2) in x1
    # - Source register remains unchanged
    # - Commonly used for function calls
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Simple call using compressed register (x8)
    #-------------------------------------------------
test_1:
    addi x17, x17, 1     # Test counter = 1
    la   x8, test_1_func
    c.jalr x8            # Call function, save return address in x1
    # Return here
    addi x16, x16, 1     # Call counter = 1
    addi x18, x1, 0      # Backup return address (should be address of this instruction)
    j    test_2

test_1_func:
    addi x19, x19, 1     # Function body counter = 1
    c.jr x1              # Return using saved address

    #-------------------------------------------------
    # Test Set 2: Call using non-compressed register (x25)
    #-------------------------------------------------
test_2:
    addi x17, x17, 1     # Test counter = 2
    la   x25, test_2_func
    c.jalr x25           # Call function
    # Return here
    addi x16, x16, 1     # Call counter = 2
    j    test_3

test_2_func:
    addi x19, x19, 1     # Function body counter = 2
    c.jr x1              # Return

    #-------------------------------------------------
    # Test Set 3: Source register preservation
    #-------------------------------------------------
test_3:
    addi x17, x17, 1     # Test counter = 3
    la   x9, test_3_func
    addi x20, x9, 0      # Backup x9 before call
    c.jalr x9            # Call function
    # Return here
    addi x16, x16, 1     # Call counter = 3
    addi x21, x9, 0      # Backup x9 after call (should be unchanged)
    j    test_4

test_3_func:
    addi x19, x19, 1     # Function body counter = 3
    c.jr x1              # Return

    #-------------------------------------------------
    # Test Set 4: Nested function calls
    #-------------------------------------------------
test_4:
    addi x17, x17, 1     # Test counter = 4
    la   x10, test_4_func1
    c.jalr x10           # Call outer function
    # Return here
    addi x16, x16, 1     # Call counter = 6
    j    test_5

test_4_func1:
    addi x19, x19, 1     # Function body counter = 4
    addi x16, x16, 1     # Call counter = 4
    addi x3, x1, 0       # Save outer return address
    la   x11, test_4_func2
    c.jalr x11           # Call inner function
    # Return here from inner
    addi x16, x16, 1     # Call counter = 5
    addi x1, x3, 0       # Restore outer return address
    c.jr x1              # Return to test_4

test_4_func2:
    addi x19, x19, 1     # Function body counter = 5
    c.jr x1              # Return to test_4_func1

    #-------------------------------------------------
    # Test Set 5: Multiple sequential calls
    #-------------------------------------------------
test_5:
    addi x17, x17, 1     # Test counter = 5

    la   x12, test_5_func1
    c.jalr x12
    addi x16, x16, 1     # Call counter = 7

    la   x13, test_5_func2
    c.jalr x13
    addi x16, x16, 1     # Call counter = 8

    la   x14, test_5_func3
    c.jalr x14
    addi x16, x16, 1     # Call counter = 9

    j    test_6

test_5_func1:
    addi x19, x19, 1     # Function body counter
    addi x22, x22, 1     # Sequential call counter = 1
    c.jr x1

test_5_func2:
    addi x19, x19, 1     # Function body counter
    addi x22, x22, 1     # Sequential call counter = 2
    c.jr x1

test_5_func3:
    addi x19, x19, 1     # Function body counter
    addi x22, x22, 1     # Sequential call counter = 3
    c.jr x1

    #-------------------------------------------------
    # Test Set 6: Call with x1 as source (edge case)
    #-------------------------------------------------
test_6:
    addi x17, x17, 1     # Test counter = 6
    la   x1, test_6_func # Load function address into x1
    addi x4, x1, 0       # Backup original x1 value
    c.jalr x1            # Call with x1 as source (x1 will be overwritten with return address)
    # Return here
    addi x16, x16, 1     # Call counter = 10
    addi x5, x1, 0       # Backup new x1 (return address)
    j    test_7

test_6_func:
    addi x19, x19, 1     # Function body counter = 6
    # x1 now contains return address, not function address
    c.jr x1              # Return using x1

    #-------------------------------------------------
    # Test Set 7: Function with parameters and return value
    #-------------------------------------------------
test_7:
    addi x17, x17, 1     # Test counter = 7
    li   x8, 5           # Parameter 1
    li   x9, 3           # Parameter 2
    la   x15, test_7_add_func
    c.jalr x15           # Call add function
    # Return here, result in x10
    addi x16, x16, 1     # Call counter = 11
    addi x23, x10, 0     # Backup result (should be 8)
    j    test_8

test_7_add_func:
    addi x19, x19, 1     # Function body counter = 7
    add  x10, x8, x9     # Result = 5 + 3 = 8
    c.jr x1              # Return

    #-------------------------------------------------
    # Test Set 8: Recursive function (factorial of 3)
    #-------------------------------------------------
test_8:
    addi x17, x17, 1     # Test counter = 8
    li   x2, 0x80000800  # Initialize stack pointer to SRAM for recursion
    li   x8, 3           # Calculate factorial(3)
    la   x11, test_8_factorial
    c.jalr x11           # Call factorial
    # Return here, result in x10
    addi x16, x16, 1     # Call counter = 15 (1 + 3 + 2 + 1 = 7 calls, starting from 11)
    addi x24, x10, 0     # Backup result (should be 6)
    li   x2, 0x1A120002  # Restore x2 to marker value
    j    test_9

test_8_factorial:
    addi x19, x19, 1     # Function body counter increments with each call
    addi x16, x16, 1     # Call counter
    # Base case: if x8 <= 1, return 1
    li   x10, 1
    addi x12, x0, 1      # x12 = 1 for comparison
    ble  x8, x12, test_8_factorial_return

    # Recursive case: factorial(n) = n * factorial(n-1)
    # Save return address and n on stack
    addi x2, x2, -8      # Allocate 8 bytes on stack
    sw   x1, 4(x2)       # Save return address at [sp+4]
    sw   x8, 0(x2)       # Save n at [sp+0]

    addi x8, x8, -1      # x8 = n - 1
    la   x11, test_8_factorial
    c.jalr x11           # Call factorial(n-1)

    # x10 has factorial(n-1)
    lw   x7, 0(x2)       # Load n into x7

    # Inline shift-add: x10 = x10 * x7 (no M-ext required so the C.JALR
    # recursion is exercised across all M_EXTENSION configs, not just M==2)
    addi x12, x10, 0         # x12 = multiplicand (orig x10)
    li   x10, 0              # accumulator
test_8_mul_loop:
    beqz x7,  test_8_mul_done
    andi x13, x7, 1
    beqz x13, test_8_mul_skip
    add  x10, x10, x12
test_8_mul_skip:
    slli x12, x12, 1
    srli x7,  x7, 1
    j    test_8_mul_loop
test_8_mul_done:                # x10 = n * factorial(n-1); x7,x12,x13 clobbered

    lw   x1, 4(x2)       # Restore return address
    addi x2, x2, 8       # Deallocate stack space

test_8_factorial_return:
    c.jr x1              # Return

    #-------------------------------------------------
    # Test Set 9: Function pointer table
    #-------------------------------------------------
test_9:
    addi x17, x17, 1     # Test counter = 9
    li   x25, 0          # Clear x25 (was used as function addr in Test 2)
    li   x8, 1           # Select function 1
    la   x3, test_9_table # Use x3 for table base address
    slli x8, x8, 2       # Multiply by 4 (word size)
    add  x8, x8, x3      # Get address of entry
    lw   x8, 0(x8)       # Load function address
    c.jalr x8            # Call selected function
    # Return here
    addi x16, x16, 1     # Call counter = 16
    j    test_10

.align 2
test_9_table:
    .word test_9_func0
    .word test_9_func1
    .word test_9_func2

test_9_func0:
    addi x25, x25, 1     # Should not execute
    c.jr x1

test_9_func1:
    addi x25, x25, 1     # Function pointer counter = 1
    addi x19, x19, 1     # Function body counter
    c.jr x1

test_9_func2:
    addi x25, x25, 1     # Should not execute
    c.jr x1

    #-------------------------------------------------
    # Test Set 10: Return address verification
    #-------------------------------------------------
test_10:
    addi x17, x17, 1     # Test counter = 10
    la   x12, test_10_func
    c.jalr x12           # Call function
test_10_return:
    addi x16, x16, 1     # Call counter = 17
    # x26 should contain address of test_10_return
    j    test_11

test_10_func:
    addi x19, x19, 1     # Function body counter
    addi x26, x1, 0      # Save return address for verification
    c.jr x1              # Return

    #-------------------------------------------------
    # Test Set 11: Shadow write tracking via ALU
    # C.JALR x8, modify x8 with ALU, C.JALR x8 again
    # Shadow must track the ALU write to x8
    #-------------------------------------------------
test_11:
    addi x17, x17, 1     # Test counter = 11
    la   x8, test_11_func1
    c.jalr x8            # Shadow starts tracking x8
    addi x16, x16, 1     # Call counter = 18
    la   x8, test_11_func2   # ALU write to x8 → shadow must track
    c.jalr x8            # Shadow hit: must use updated x8
    addi x16, x16, 1     # Call counter = 19
    j    test_12

test_11_func1:
    addi x19, x19, 1
    c.jr x1

test_11_func2:
    addi x19, x19, 1
    c.jr x1

    #-------------------------------------------------
    # Test Set 12: Shadow miss then hit
    # C.JALR x8, C.JALR x9 (miss), C.JALR x9 (hit)
    #-------------------------------------------------
test_12:
    addi x17, x17, 1     # Test counter = 12
    la   x8, test_12_func1
    c.jalr x8            # Shadow tracks x8
    addi x16, x16, 1     # Call counter = 20
    la   x9, test_12_func2
    c.jalr x9            # Shadow miss → switch to x9
    addi x16, x16, 1     # Call counter = 21
    la   x9, test_12_func3
    c.jalr x9            # Shadow hit (x9 updated via ALU, tracked)
    addi x16, x16, 1     # Call counter = 22
    j    test_13

test_12_func1:
    addi x19, x19, 1
    c.jr x1

test_12_func2:
    addi x19, x19, 1
    c.jr x1

test_12_func3:
    addi x19, x19, 1
    c.jr x1

    #-------------------------------------------------
    # Test Set 13: Rapid shadow switching (4 registers)
    # C.JALR x8, C.JALR x9, C.JALR x10, C.JALR x11
    # Each forces a shadow miss
    #-------------------------------------------------
test_13:
    addi x17, x17, 1     # Test counter = 13
    la   x8,  test_13_func1
    c.jalr x8
    addi x16, x16, 1     # Call counter = 23
    la   x9,  test_13_func2
    c.jalr x9
    addi x16, x16, 1     # Call counter = 24
    la   x10, test_13_func3
    c.jalr x10
    addi x16, x16, 1     # Call counter = 25
    la   x11, test_13_func4
    c.jalr x11
    addi x16, x16, 1     # Call counter = 26
    j    test_14

test_13_func1:
    addi x19, x19, 1
    c.jr x1

test_13_func2:
    addi x19, x19, 1
    c.jr x1

test_13_func3:
    addi x19, x19, 1
    c.jr x1

test_13_func4:
    addi x19, x19, 1
    c.jr x1

    #-------------------------------------------------
    # Test Set 14: Back-to-back shadow hits with write tracking
    # 3 consecutive C.JALR x8, with x8 modified between each
    #-------------------------------------------------
test_14:
    addi x17, x17, 1     # Test counter = 14
    la   x8,  test_14_func1
    c.jalr x8
    addi x16, x16, 1     # Call counter = 27
    la   x8,  test_14_func2     # ALU write → shadow tracks
    c.jalr x8            # Shadow hit
    addi x16, x16, 1     # Call counter = 28
    la   x8,  test_14_func3     # ALU write → shadow tracks
    c.jalr x8            # Shadow hit
    addi x16, x16, 1     # Call counter = 29
    j    test_end

test_14_func1:
    addi x19, x19, 1
    c.jr x1

test_14_func2:
    addi x19, x19, 1
    c.jr x1

test_14_func3:
    addi x19, x19, 1
    c.jr x1

.option norvc
test_end:
    # Backup final results
    addi x27, x16, 0     # Backup call counter
    addi x28, x17, 0     # Backup test counter
    addi x29, x19, 0     # Backup function body counter
    addi x30, x22, 0     # Backup sequential call counter

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
