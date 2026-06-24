#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_or
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.OR
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

    # Load compressed registers (x8-x15) with test patterns
    li  x8,  0xAAAAAAAA  # Alternating pattern 1010...
    li  x9,  0x55555555  # Alternating pattern 0101...
    li  x10, 0xFFFFFFFF  # All 1s
    li  x11, 0x00000000  # All 0s
    li  x12, 0xF0F0F0F0  # Nibble pattern
    li  x13, 0x0F0F0F0F  # Inverse nibble
    li  x14, 0x12345678  # Test pattern
    li  x15, 0xABCDEF01  # Test pattern

    # Setup markers
    li  x1,  0x04DE4ED0
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.OR (Compressed OR)
    # Format: c.or rd', rs2'
    # Function: rd' = rd' | rs2'
    # Registers: rd' and rs2' are x8-x15 (compressed register encoding)
    # Encoding: 100_0_11_rd'[2:0]_10_rs2'[2:0]_01
    #
    # OR truth table:
    # 0 | 0 = 0
    # 0 | 1 = 1
    # 1 | 0 = 1
    # 1 | 1 = 1
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Alternating patterns (should give all 1s)
    #-------------------------------------------------
    c.or x8,  x9         # 0xAAAAAAAA | 0x55555555 = 0xFFFFFFFF
    c.or x12, x13        # 0xF0F0F0F0 | 0x0F0F0F0F = 0xFFFFFFFF

.option norvc
    # Backup first set of results to x16-x17
    addi x16, x8,  0     # Backup x8:  0xFFFFFFFF
    addi x17, x12, 0     # Backup x12: 0xFFFFFFFF

    # Reload for second set
    li  x8,  0x12345678
    li  x9,  0x00000000  # Zero
    li  x10, 0xABCDEF01
    li  x11, 0x00000000  # Zero
.option rvc

    #-------------------------------------------------
    # Test Set 2: OR with zero (identity: n | 0 = n)
    #-------------------------------------------------
    c.or x8,  x9         # 0x12345678 | 0x00000000 = 0x12345678
    c.or x10, x11        # 0xABCDEF01 | 0x00000000 = 0xABCDEF01

.option norvc
    # Backup second set of results to x18-x19
    addi x18, x8,  0     # Backup x8:  0x12345678
    addi x19, x10, 0     # Backup x10: 0xABCDEF01

    # Reload for third set
    li  x8,  0x12345678
    li  x9,  0xFFFFFFFF  # All 1s
    li  x10, 0xAAAAAAAA
    li  x11, 0xFFFFFFFF  # All 1s
.option rvc

    #-------------------------------------------------
    # Test Set 3: OR with all 1s (saturation: n | 0xFFFFFFFF = 0xFFFFFFFF)
    #-------------------------------------------------
    c.or x8,  x9         # 0x12345678 | 0xFFFFFFFF = 0xFFFFFFFF
    c.or x10, x11        # 0xAAAAAAAA | 0xFFFFFFFF = 0xFFFFFFFF

.option norvc
    # Backup third set of results to x20-x21
    addi x20, x8,  0     # Backup x8:  0xFFFFFFFF
    addi x21, x10, 0     # Backup x10: 0xFFFFFFFF

    # Reload for fourth set
    li  x12, 0xDEADBEEF
    li  x13, 0xDEADBEEF
    li  x14, 0x7FFFFFFF
    li  x15, 0x7FFFFFFF
.option rvc

    #-------------------------------------------------
    # Test Set 4: Self-OR (idempotent: n | n = n)
    #-------------------------------------------------
    c.or x12, x13        # 0xDEADBEEF | 0xDEADBEEF = 0xDEADBEEF
    c.or x14, x15        # 0x7FFFFFFF | 0x7FFFFFFF = 0x7FFFFFFF

.option norvc
    # Backup fourth set of results to x22-x23
    addi x22, x12, 0     # Backup x12: 0xDEADBEEF
    addi x23, x14, 0     # Backup x14: 0x7FFFFFFF

    # Reload for fifth set
    li  x8,  0xFF00FF00
    li  x9,  0x00FF00FF
    li  x10, 0xF0F0F0F0
    li  x11, 0x0F0F0F0F
.option rvc

    #-------------------------------------------------
    # Test Set 5: Complementary patterns
    #-------------------------------------------------
    c.or x8,  x9         # 0xFF00FF00 | 0x00FF00FF = 0xFFFFFFFF
    c.or x10, x11        # 0xF0F0F0F0 | 0x0F0F0F0F = 0xFFFFFFFF

.option norvc
    # Backup fifth set of results to x24-x25
    addi x24, x8,  0     # Backup x8:  0xFFFFFFFF
    addi x25, x10, 0     # Backup x10: 0xFFFFFFFF

    # Reload for sixth set
    li  x12, 0x12345678
    li  x13, 0xABCDEF01
    li  x14, 0x80000000  # MSB set
    li  x15, 0x00000001  # LSB set
.option rvc

    #-------------------------------------------------
    # Test Set 6: Specific bit patterns
    #-------------------------------------------------
    c.or x12, x13        # 0x12345678 | 0xABCDEF01 = 0xBBFDFF79
    c.or x14, x15        # 0x80000000 | 0x00000001 = 0x80000001

.option norvc
    # Backup sixth set of results to x26-x27
    addi x26, x12, 0     # Backup x12: 0xBBFDFF79
    addi x27, x14, 0     # Backup x14: 0x80000001

    # Reload for seventh set (bit setting)
    li  x8,  0x00000000
    li  x9,  0x80000000  # Set MSB
    li  x10, 0x12340000  # Upper bits
    li  x11, 0x00005678  # Lower bits
.option rvc

    #-------------------------------------------------
    # Test Set 7: Bit setting
    #-------------------------------------------------
    c.or x8,  x9         # 0x00000000 | 0x80000000 = 0x80000000
    c.or x10, x11        # 0x12340000 | 0x00005678 = 0x12345678

.option norvc
    # Backup seventh set results
    addi x28, x8,  0     # Backup x8:  0x80000000
    addi x29, x10, 0     # Backup x10: 0x12345678

    # Reload for eighth set (multiple consecutive ORs)
    li  x12, 0x11111111
    li  x13, 0x22222222
    li  x14, 0x44444444
.option rvc

    #-------------------------------------------------
    # Test Set 8: Multiple consecutive ORs
    #-------------------------------------------------
    c.or x12, x13        # 0x11111111 | 0x22222222 = 0x33333333
    c.or x12, x14        # 0x33333333 | 0x44444444 = 0x77777777

.option norvc
    # Backup eighth set result
    addi x30, x12, 0     # Backup x12: 0x77777777

    # Reload for ninth set (partial overlap)
    li  x8,  0xF000000F
    li  x9,  0x0FFFFFF0
    li  x10, 0xAAAA0000
    li  x11, 0x00005555
.option rvc

    #-------------------------------------------------
    # Test Set 9: Partial overlap patterns
    #-------------------------------------------------
    c.or x8,  x9         # 0xF000000F | 0x0FFFFFF0 = 0xFFFFFFFF
    c.or x10, x11        # 0xAAAA0000 | 0x00005555 = 0xAAAA5555

.option norvc
    # Backup ninth set results
    addi x2, x8,  0      # Backup x8:  0xFFFFFFFF
    addi x3, x10, 0      # Backup x10: 0xAAAA5555

    # Reload for tenth set (all zeros)
    li  x12, 0x00000000
    li  x13, 0x00000000
.option rvc

    #-------------------------------------------------
    # Test Set 10: Zero OR zero
    #-------------------------------------------------
    c.or x12, x13        # 0x00000000 | 0x00000000 = 0x00000000

.option norvc
    # Backup tenth set result
    addi x4, x12, 0      # Backup x12: 0x00000000

    # Reload for eleventh set (boundary values)
    li  x14, 0x7FFFFFFF  # Max positive
    li  x15, 0x80000000  # Min negative
.option rvc

    #-------------------------------------------------
    # Test Set 11: Boundary values
    #-------------------------------------------------
    c.or x14, x15        # 0x7FFFFFFF | 0x80000000 = 0xFFFFFFFF

.option norvc
    # Backup eleventh set result
    addi x5, x14, 0      # Backup x14: 0xFFFFFFFF

    # Reload for twelfth set (byte masking)
    li  x8,  0x12000000
    li  x9,  0x00340000
    li  x10, 0x00005600
    li  x11, 0x00000078
.option rvc

    #-------------------------------------------------
    # Test Set 12: Building value with byte ORs
    #-------------------------------------------------
    c.or x8,  x9         # 0x12000000 | 0x00340000 = 0x12340000
    c.or x8,  x10        # 0x12340000 | 0x00005600 = 0x12345600
    c.or x8,  x11        # 0x12345600 | 0x00000078 = 0x12345678

.option norvc
    # Backup twelfth set result
    addi x6, x8, 0       # Backup x8: 0x12345678

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
