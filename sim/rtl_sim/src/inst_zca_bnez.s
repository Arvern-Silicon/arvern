#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_bnez
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.BNEZ
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
    li  x16, 0x00000000  # Taken counter
    li  x17, 0x00000000  # Not-taken counter
    li  x18, 0x00000000  # Test counter
    li  x19, 0x00000000  # Loop body counter

    # Setup markers
    li  x1,  0xB0E70001
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.BNEZ (Compressed Branch if Not Equal to Zero)
    # Format: c.bnez rs1', offset
    # Function: if (rs1' != 0) PC = PC + sign_extend(offset)
    # Registers: rs1' can only be x8-x15 (compressed registers)
    # Offset: 8-bit signed, scaled by 2 (range: -256 to +254)
    # Encoding: 111_offset[8|4:3]_rs1'[2:0]_offset[7:6|2:1|5]_01
    #
    # Key behavior:
    # - Branch taken if rs1' != 0
    # - Branch not taken if rs1' == 0
    # - No registers modified
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Branch taken (rs1' = 1)
    #-------------------------------------------------
test_1:
    addi x18, x18, 1     # Test counter = 1
    li   x8, 1           # Set x8 = 1 (non-zero)
    c.bnez x8, test_1_taken
    addi x17, x17, 1     # Should be skipped
    addi x17, x17, 1     # Should be skipped

test_1_taken:
    addi x16, x16, 1     # Taken counter = 1

    #-------------------------------------------------
    # Test Set 2: Branch not taken (rs1' = 0)
    #-------------------------------------------------
test_2:
    addi x18, x18, 1     # Test counter = 2
    li   x8, 0           # Set x8 = 0 (zero)
    c.bnez x8, test_2_taken
    addi x17, x17, 1     # Not-taken counter = 1
    j    test_2_end

test_2_taken:
    addi x16, x16, 1     # Should not be executed

test_2_end:

    #-------------------------------------------------
    # Test Set 3: Branch taken (rs1' = positive)
    #-------------------------------------------------
test_3:
    addi x18, x18, 1     # Test counter = 3
    li   x9, 0x12345678  # Set x9 = positive value
    c.bnez x9, test_3_taken
    addi x17, x17, 1     # Should be skipped

test_3_taken:
    addi x16, x16, 1     # Taken counter = 2

    #-------------------------------------------------
    # Test Set 4: Branch taken (rs1' = negative)
    #-------------------------------------------------
test_4:
    addi x18, x18, 1     # Test counter = 4
    li   x10, 0xFFFFFFFF # Set x10 = -1 (negative, non-zero)
    c.bnez x10, test_4_taken
    addi x17, x17, 1     # Should be skipped

test_4_taken:
    addi x16, x16, 1     # Taken counter = 3

    #-------------------------------------------------
    # Test Set 5: Multiple branches with non-zero
    #-------------------------------------------------
test_5:
    addi x18, x18, 1     # Test counter = 5
    li   x11, 0x00000005 # Set x11 = 5
    c.bnez x11, test_5_a
    addi x17, x17, 1     # Should be skipped

test_5_a:
    addi x16, x16, 1     # Taken counter = 4
    c.bnez x11, test_5_b
    addi x17, x17, 1     # Should be skipped

test_5_b:
    addi x16, x16, 1     # Taken counter = 5

    #-------------------------------------------------
    # Test Set 6: Backward branch (countdown loop)
    #-------------------------------------------------
test_6:
    addi x18, x18, 1     # Test counter = 6
    li   x12, 3          # Loop counter

.option norvc
test_6_loop:
    addi x19, x19, 1     # Loop body counter
    addi x12, x12, -1    # Decrement counter
    bnez x12, test_6_loop # Loop while not zero (standard instruction for scaffolding)
.option rvc
    # When x12 = 0, test c.bnez (should not branch since x12 = 0)
    c.bnez x12, test_6_skip
    addi x17, x17, 1     # Not-taken counter = 2 (should execute since x12=0)
    j    test_7
test_6_skip:
    addi x17, x17, 1     # Should NOT execute

    #-------------------------------------------------
    # Test Set 7: Test all compressed registers (x8-x15)
    #-------------------------------------------------
test_7:
    addi x18, x18, 1     # Test counter = 7

    # Test x8
    li   x8, 1
    c.bnez x8, test_7_a
    addi x17, x17, 1

test_7_a:
    addi x16, x16, 1     # Taken counter = 6

    # Test x9
    li   x9, 1
    c.bnez x9, test_7_b
    addi x17, x17, 1

test_7_b:
    addi x16, x16, 1     # Taken counter = 7

    # Test x10
    li   x10, 1
    c.bnez x10, test_7_c
    addi x17, x17, 1

test_7_c:
    addi x16, x16, 1     # Taken counter = 8

    # Test x11
    li   x11, 1
    c.bnez x11, test_7_d
    addi x17, x17, 1

test_7_d:
    addi x16, x16, 1     # Taken counter = 9

    # Test x12
    li   x12, 1
    c.bnez x12, test_7_e
    addi x17, x17, 1

test_7_e:
    addi x16, x16, 1     # Taken counter = 10

    # Test x13
    li   x13, 1
    c.bnez x13, test_7_f
    addi x17, x17, 1

test_7_f:
    addi x16, x16, 1     # Taken counter = 11

    # Test x14
    li   x14, 1
    c.bnez x14, test_7_g
    addi x17, x17, 1

test_7_g:
    addi x16, x16, 1     # Taken counter = 12

    # Test x15
    li   x15, 1
    c.bnez x15, test_7_h
    addi x17, x17, 1

test_7_h:
    addi x16, x16, 1     # Taken counter = 13

    #-------------------------------------------------
    # Test Set 8: Alternate taken/not-taken pattern
    #-------------------------------------------------
test_8:
    addi x18, x18, 1     # Test counter = 8
    li   x8, 1           # Non-zero
    c.bnez x8, test_8_a
    addi x17, x17, 1     # Should be skipped

test_8_a:
    addi x16, x16, 1     # Taken counter = 14
    li   x8, 0           # Zero
    c.bnez x8, test_8_b
    addi x17, x17, 1     # Not-taken counter = 3
    j    test_8_c

test_8_b:
    addi x16, x16, 1     # Should not be executed

test_8_c:
    li   x8, 0xFFFFFFFF  # Non-zero (negative)
    c.bnez x8, test_8_d
    addi x17, x17, 1     # Should be skipped

test_8_d:
    addi x16, x16, 1     # Taken counter = 15

    #-------------------------------------------------
    # Test Set 9: Branch over longer code section
    #-------------------------------------------------
test_9:
    addi x18, x18, 1     # Test counter = 9
    li   x9, 0x00000042  # Non-zero value
    c.bnez x9, test_9_end
    addi x17, x17, 1     # Should be skipped
    addi x17, x17, 1     # Should be skipped
    addi x17, x17, 1     # Should be skipped
    addi x17, x17, 1     # Should be skipped
    addi x17, x17, 1     # Should be skipped
    addi x17, x17, 1     # Should be skipped

test_9_end:
    addi x16, x16, 1     # Taken counter = 16

    #-------------------------------------------------
    # Test Set 10: Register preservation (branch doesn't modify register)
    #-------------------------------------------------
test_10:
    addi x18, x18, 1     # Test counter = 10
    li   x10, 0xDEADCAFE # Set x10 = non-zero
    addi x20, x10, 0     # Backup x10 before branch
    c.bnez x10, test_10_end
    addi x17, x17, 1     # Should be skipped

test_10_end:
    addi x16, x16, 1     # Taken counter = 17
    addi x21, x10, 0     # Backup x10 after branch (should still be 0xDEADCAFE)

    #-------------------------------------------------
    # Test Set 11: Maximum positive offset (+254 bytes)
    #-------------------------------------------------
test_11:
    addi x18, x18, 1     # Test counter = 11
.option norvc
    li   x6, 1           # Set x6 = 1 (non-zero, will take branch) - use x6 to avoid overwriting x8
    addi x8, x6, 0       # Move to x8 for compressed register encoding
.option rvc
    c.bnez x8, test_11_max_forward  # Branch +254 bytes (maximum positive offset)
    addi x17, x17, 1     # Should be skipped

    # Fill space to create exactly +254 byte offset
    # 254 bytes = 127 half-word slots
    # c.bnez instruction = 2 bytes, so we need 125 more half-words
    .rept 125
    c.nop                # 2-byte NOPs to fill space
    .endr

test_11_max_forward:
    addi x16, x16, 1     # Taken counter = 18 (max positive offset success)
.option norvc
    li   x8, 0xFFFFFFFF  # Restore x8 to expected value from Test Set 8
.option rvc

    #-------------------------------------------------
    # Test Set 12: Maximum negative offset (-256 bytes)
    #-------------------------------------------------
test_12_setup:
    addi x18, x18, 1     # Test counter = 12
    j    test_12_jump_point  # Jump to the actual test point

    # This label will be the target of the maximum negative branch
test_12_max_backward:
    addi x16, x16, 1     # Taken counter = 19 (max negative offset success)
    j    test_12_done    # Skip to end of test 12

    # Fill space to create exactly -256 byte offset
    # Need 126 half-words (252 bytes) between target and branch instruction
.option norvc
    .rept 63
    nop                  # 4-byte NOPs to fill space (63 * 4 = 252 bytes)
    .endr
.option rvc

test_12_jump_point:
.option norvc
    li   x7, 0xABCD      # Set x7 = non-zero (will take branch) - use x7 to avoid overwriting x9
    addi x9, x7, 0       # Move to x9 for compressed register encoding
.option rvc
    c.bnez x9, test_12_max_backward  # Branch -256 bytes (maximum negative offset)
    addi x17, x17, 1     # Should be skipped

test_12_done:
.option norvc
    li   x9, 0x42        # Restore x9 to expected value from Test Set 9
.option rvc

.option norvc
    # Backup final results
    addi x22, x16, 0     # Backup taken counter (should be 19)
    addi x23, x17, 0     # Backup not-taken counter (should be 3)
    addi x24, x18, 0     # Backup test counter (should be 12)
    addi x25, x19, 0     # Backup loop body counter (should be 3)
    addi x26, x20, 0     # Backup x10 before branch (should be 0xDEADCAFE)
    addi x27, x21, 0     # Backup x10 after branch (should be 0xDEADCAFE)

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
