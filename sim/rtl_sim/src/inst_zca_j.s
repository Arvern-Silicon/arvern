#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_j
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.J
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

    # Initialize test counter
    li  x8,  0x00000000  # Test counter
    li  x9,  0x00000000  # Forward jump counter
    li  x10, 0x00000000  # Backward jump counter
    li  x11, 0x00000000  # Sequential counter

    # Setup markers
    li  x1,  0x01000001
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.J (Compressed Jump)
    # Format: c.j offset
    # Function: PC = PC + sign_extend(offset)
    # Encoding: 101_offset[11|4|9:8|10|6|7|3:1|5]_01
    # Offset: 11-bit signed, scaled by 2 (range: -2048 to +2046)
    #
    # Key behavior:
    # - Unconditional jump to PC + offset
    # - No return address saved (unlike C.JAL)
    # - Offset is sign-extended and added to PC
    # - No registers modified
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Simple forward jump
    #-------------------------------------------------
test_1:
    addi x8, x8, 1       # Test counter = 1
    c.j  test_1_target
    addi x11, x11, 1     # Should be skipped
    addi x11, x11, 1     # Should be skipped

test_1_target:
    addi x9, x9, 1       # Forward jump counter = 1

    #-------------------------------------------------
    # Test Set 2: Jump over multiple instructions
    #-------------------------------------------------
test_2:
    addi x8, x8, 1       # Test counter = 2
    c.j  test_2_target
    addi x11, x11, 1     # Should be skipped
    addi x11, x11, 1     # Should be skipped
    addi x11, x11, 1     # Should be skipped
    addi x11, x11, 1     # Should be skipped
    addi x11, x11, 1     # Should be skipped

test_2_target:
    addi x9, x9, 1       # Forward jump counter = 2

    #-------------------------------------------------
    # Test Set 3: Backward jump (simple loop)
    #-------------------------------------------------
test_3:
    addi x8, x8, 1       # Test counter = 3
    li   x12, 3          # Loop counter
test_3_loop:
    addi x10, x10, 1     # Backward jump counter++
    addi x12, x12, -1    # Decrement loop counter
    beqz x12, test_3_end # Exit loop when counter reaches 0
    c.j  test_3_loop     # Backward jump using c.j
test_3_end:
    nop

    #-------------------------------------------------
    # Test Set 4: Jump to very next instruction (offset = 2)
    #-------------------------------------------------
test_4:
    addi x8, x8, 1       # Test counter = 4
    c.j  test_4_next
test_4_next:
    addi x9, x9, 1       # Forward jump counter = 3

    #-------------------------------------------------
    # Test Set 5: Nested forward jumps
    #-------------------------------------------------
test_5:
    addi x8, x8, 1       # Test counter = 5
    c.j  test_5_mid
    addi x11, x11, 1     # Should be skipped

test_5_mid:
    addi x13, x13, 1     # Nested counter = 1
    c.j  test_5_end
    addi x11, x11, 1     # Should be skipped

test_5_end:
    addi x9, x9, 1       # Forward jump counter = 4

    #-------------------------------------------------
    # Test Set 6: Jump chain
    #-------------------------------------------------
test_6:
    addi x8, x8, 1       # Test counter = 6
    c.j  test_6_a
    addi x11, x11, 1     # Should be skipped

test_6_a:
    addi x14, x14, 1     # Chain counter = 1
    c.j  test_6_b
    addi x11, x11, 1     # Should be skipped

test_6_b:
    addi x14, x14, 1     # Chain counter = 2
    c.j  test_6_c
    addi x11, x11, 1     # Should be skipped

test_6_c:
    addi x14, x14, 1     # Chain counter = 3
    c.j  test_6_end

test_6_end:
    addi x9, x9, 1       # Forward jump counter = 5

    #-------------------------------------------------
    # Test Set 7: Jump over compressed and standard mix
    #-------------------------------------------------
test_7:
    addi x8, x8, 1       # Test counter = 7
    c.j  test_7_target

.option norvc
    addi x11, x11, 1     # Should be skipped (standard)
    addi x11, x11, 1     # Should be skipped (standard)
.option rvc

test_7_target:
    addi x9, x9, 1       # Forward jump counter = 6

    #-------------------------------------------------
    # Test Set 8: Register preservation test
    #-------------------------------------------------
test_8:
    addi x8, x8, 1       # Test counter = 8
    li   x15, 0xDEADCAFE # Value before jump
    c.j  test_8_target
    addi x11, x11, 1     # Should be skipped

test_8_target:
    # x15 should still be 0xDEADCAFE
    addi x9, x9, 1       # Forward jump counter = 7

    #-------------------------------------------------
    # Test Set 9: Jump to section with different alignment
    #-------------------------------------------------
test_9:
    addi x8, x8, 1       # Test counter = 9
    c.j  test_9_target
    nop
    nop

test_9_target:
    addi x9, x9, 1       # Forward jump counter = 8

    #-------------------------------------------------
    # Test Set 10: Maximum positive offset (+2046 bytes)
    #-------------------------------------------------
test_10:
    addi x8, x8, 1       # Test counter = 10
    c.j  test_10_max_forward  # Jump +2046 bytes (maximum positive offset)
    addi x11, x11, 1     # Should be skipped

    # Fill space to create exactly +2046 byte offset
    # 2046 bytes = 1023 half-word slots
    # c.j instruction = 2 bytes, so we need 1021 more half-words
    .rept 1021
    c.nop                # 2-byte NOPs to fill space
    .endr

test_10_max_forward:
    addi x9, x9, 1       # Forward jump counter (max offset success)

    #-------------------------------------------------
    # Test Set 11: Maximum negative offset (-2048 bytes)
    #-------------------------------------------------
test_11_setup:
    addi x8, x8, 1       # Test counter = 11
    j    test_11_jump_point  # Jump to the actual test point

    # This label will be the target of the maximum negative jump
test_11_max_backward:
    addi x10, x10, 1     # Backward jump counter (max negative offset success)
    j    test_11_done    # Skip to end of test 11

    # Fill space to create exactly -2048 byte offset
    # Need 1022 half-words (2044 bytes) between target and jump instruction
.option norvc
    .rept 511
    nop                  # 4-byte NOPs to fill space (511 * 4 = 2044 bytes)
    .endr
.option rvc

test_11_jump_point:
    c.j  test_11_max_backward  # Jump -2048 bytes (maximum negative offset)
    addi x11, x11, 1     # Should be skipped

test_11_done:

    #-------------------------------------------------
    # Test Set 12: Final jump to end
    #-------------------------------------------------
test_12:
    addi x8, x8, 1       # Test counter = 12
    c.j  all_tests_done

.option norvc
    # Backup final results
all_tests_done:
    addi x16, x8,  0     # Backup test counter (should be 12)
    addi x17, x9,  0     # Backup forward jump counter (should be 9)
    addi x18, x10, 0     # Backup backward jump counter (should be 4)
    addi x19, x11, 0     # Backup sequential counter (should be 0 - all skipped)
    addi x20, x13, 0     # Backup nested counter (should be 1)
    addi x21, x14, 0     # Backup chain counter (should be 3)
    addi x22, x15, 0     # Backup preserved register (should be 0xDEADCAFE)

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
