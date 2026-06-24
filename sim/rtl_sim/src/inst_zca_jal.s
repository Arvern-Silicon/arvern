#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_jal
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.JAL
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

    li  x1,  0x00000000  # ra - will be overwritten by C.JAL
    li  x2,  0xDEADBEEF  # sp - should remain unchanged
    li  x3,  0xCAFEBABE
    li  x4,  0x12345678
    li  x5,  0xABCDEF01
    li  x10, 0x11111111  # Test counter
    li  x11, 0x22222222  # Test counter
    li  x12, 0x33333333  # Test counter
    li  x13, 0x44444444  # Test counter
    li  x14, 0x55555555  # Test counter
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.JAL (Compressed Jump and Link)
    # Format: c.jal offset
    # Function: x1 = PC + 2, PC = PC + sign_extend(offset)
    # Offset range: 11-bit signed (-2048 to +2046), multiple of 2
    # Always links to x1 (ra register)
    # RV32 only instruction
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test 1: Simple forward jump
    #-------------------------------------------------
test_1:
    c.jal  target_1          # Jump forward, save return address in x1
    c.li   x10, -1           # Should be skipped
    c.li   x10, -1           # Should be skipped
target_1:
    c.addi x10, 1            # x10 = 0x11111112

    #-------------------------------------------------
    # Test 2: Longer forward jump
    #-------------------------------------------------
test_2:
    c.jal  target_2          # Jump forward
    c.li   x11, -1           # Should be skipped
    c.li   x11, -1           # Should be skipped
    c.li   x11, -1           # Should be skipped
    c.li   x11, -1           # Should be skipped
    c.li   x11, -1           # Should be skipped
    c.li   x11, -1           # Should be skipped
    c.li   x11, -1           # Should be skipped
    c.li   x11, -1           # Should be skipped
target_2:
    c.addi x11, 2            # x11 = 0x22222224

    #-------------------------------------------------
    # Test 3: Jump over NOP instructions
    #-------------------------------------------------
test_3:
    c.jal  target_3          # Jump forward
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
target_3:
    c.addi x12, 3            # x12 = 0x33333336

    #-------------------------------------------------
    # Test 4: Backward jump
    #-------------------------------------------------
.option norvc
    j test_4_start
test_4_target:
    addi x13, x13, 4         # x13 = 0x44444448
    j test_4_end
test_4_start:
.option rvc
    c.jal test_4_target      # Jump backward
test_4_end:

    #-------------------------------------------------
    # Test 5: Jump to subroutine and verify return address
    #-------------------------------------------------
test_5:
.option norvc
    # Save x1 before the call
    addi x15, x1, 0          # Backup x1
.option rvc
    c.jal  subroutine_1      # Call subroutine
    c.addi x14, 5            # After return: x14 = 0x5555555A

.option norvc
    j test_6
.option rvc

subroutine_1:
    # The return address in x1 should point to "c.addi x14, 5"
    # Save return address for verification
.option norvc
    addi x16, x1, 0          # Save return address in x16
    addi x17, x15, 0         # Save previous x1 value in x17
.option rvc
    c.jr   x1                # Return using compressed jump register

    #-------------------------------------------------
    # Test 6: Multiple nested calls
    #-------------------------------------------------
test_6:
.option norvc
    addi x18, x0, 0          # Clear x18 counter
.option rvc
    c.jal  subroutine_2      # First call
    c.addi x18, 10           # x18 += 10

.option norvc
    j test_7
.option rvc

subroutine_2:
.option norvc
    addi x19, x1, 0          # Save return address
    addi x18, x18, 1         # x18 += 1
.option rvc
    c.jal  subroutine_3      # Nested call (x1 will be overwritten)
.option norvc
    addi x18, x18, 2         # x18 += 2
    jr   x19                 # Return using saved address
.option rvc

subroutine_3:
.option norvc
    addi x20, x1, 0          # Save return address
    addi x18, x18, 4         # x18 += 4
    jr   x20                 # Return
.option rvc

    #-------------------------------------------------
    # Test 7: Forward jump with maximum practical offset
    #-------------------------------------------------
test_7:
    c.jal  target_7          # Jump forward with larger offset
.option norvc
    # Add padding to increase jump distance
    .space 100, 0x00
.option rvc
target_7:
.option norvc
    addi x21, x0, 7          # x21 = 7
.option rvc

    #-------------------------------------------------
    # Test 8: Verify x1 changes but other registers don't
    #-------------------------------------------------
test_8:
    c.jal  target_8
target_8:
.option norvc
    addi x22, x1, 0          # Save final return address

    # Signal checkpoint 1 - verify intermediate state
    li   x31, 0xBBBBBBBB
.option rvc

    #-------------------------------------------------
    # Test 9: Jump to target with 16-bit alignment
    #-------------------------------------------------
test_9:
    c.jal  target_9
    c.nop
target_9:
.option norvc
    addi x23, x0, 9          # x23 = 9
.option rvc

    #-------------------------------------------------
    # Test 10: Final verification jump
    #-------------------------------------------------
test_10:
    c.jal  target_10
    c.nop
    c.nop
target_10:
.option norvc
    addi x24, x0, 10         # x24 = 10
.option rvc

    #-------------------------------------------------
    # Test Set 11: Maximum positive offset (+2046 bytes)
    #-------------------------------------------------
.option rvc
    c.jal test_11_max_forward  # Jump +2046 bytes (maximum positive offset)
    addi x26, x0, 11           # Should be skipped

    # Fill space to create exactly +2046 byte offset
    # 2046 bytes = 1023 half-word slots
    # c.jal instruction = 2 bytes, so we need 1021 more half-words
    .rept 1021
    c.nop                      # 2-byte NOPs to fill space
    .endr

test_11_max_forward:
.option norvc
    addi x25, x0, 11           # x25 = 11 (max positive offset success)
.option rvc

    #-------------------------------------------------
    # Test Set 12: Maximum negative offset (-2048 bytes)
    #-------------------------------------------------
    c.nop                      # Alignment
    j    test_12_jump_point    # Jump to the actual test point

    # This label will be the target of the maximum negative jump
test_12_max_backward:
.option norvc
    addi x26, x0, 12           # x26 = 12 (max negative offset success)
.option rvc
    j    test_12_done          # Skip to end of test 12

    # Fill space to create exactly -2048 byte offset
    # Need 1022 half-words (2044 bytes) between target and jump instruction
.option norvc
    .rept 511
    nop                        # 4-byte NOPs to fill space (511 * 4 = 2044 bytes)
    .endr
.option rvc

test_12_jump_point:
    c.jal test_12_max_backward # Jump -2048 bytes (maximum negative offset)
.option norvc
    addi x27, x0, 99           # Should be skipped
.option rvc

test_12_done:

.option norvc

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
