#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_and
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.AND
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
    li  x1,  0xADD4E550
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.AND (Compressed AND)
    # Format: c.and rd', rs2'
    # Function: rd' = rd' & rs2'
    # Registers: rd' and rs2' are x8-x15 (compressed register encoding)
    # Encoding: 100_0_11_rd'[2:0]_11_rs2'[2:0]_01
    #
    # AND truth table:
    # 0 & 0 = 0
    # 0 & 1 = 0
    # 1 & 0 = 0
    # 1 & 1 = 1
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Alternating patterns (should give zero)
    #-------------------------------------------------
    c.and x8,  x9        # 0xAAAAAAAA & 0x55555555 = 0x00000000
    c.and x12, x13       # 0xF0F0F0F0 & 0x0F0F0F0F = 0x00000000

.option norvc
    # Backup first set of results to x16-x17
    addi x16, x8,  0     # Backup x8:  0x00000000
    addi x17, x12, 0     # Backup x12: 0x00000000

    # Reload for second set
    li  x8,  0x12345678
    li  x9,  0x00000000  # Zero
    li  x10, 0xABCDEF01
    li  x11, 0x00000000  # Zero
.option rvc

    #-------------------------------------------------
    # Test Set 2: AND with zero (annihilation: n & 0 = 0)
    #-------------------------------------------------
    c.and x8,  x9        # 0x12345678 & 0x00000000 = 0x00000000
    c.and x10, x11       # 0xABCDEF01 & 0x00000000 = 0x00000000

.option norvc
    # Backup second set of results to x18-x19
    addi x18, x8,  0     # Backup x8:  0x00000000
    addi x19, x10, 0     # Backup x10: 0x00000000

    # Reload for third set
    li  x8,  0x12345678
    li  x9,  0xFFFFFFFF  # All 1s
    li  x10, 0xAAAAAAAA
    li  x11, 0xFFFFFFFF  # All 1s
.option rvc

    #-------------------------------------------------
    # Test Set 3: AND with all 1s (identity: n & 0xFFFFFFFF = n)
    #-------------------------------------------------
    c.and x8,  x9        # 0x12345678 & 0xFFFFFFFF = 0x12345678
    c.and x10, x11       # 0xAAAAAAAA & 0xFFFFFFFF = 0xAAAAAAAA

.option norvc
    # Backup third set of results to x20-x21
    addi x20, x8,  0     # Backup x8:  0x12345678
    addi x21, x10, 0     # Backup x10: 0xAAAAAAAA

    # Reload for fourth set
    li  x12, 0xDEADBEEF
    li  x13, 0xDEADBEEF
    li  x14, 0x7FFFFFFF
    li  x15, 0x7FFFFFFF
.option rvc

    #-------------------------------------------------
    # Test Set 4: Self-AND (idempotent: n & n = n)
    #-------------------------------------------------
    c.and x12, x13       # 0xDEADBEEF & 0xDEADBEEF = 0xDEADBEEF
    c.and x14, x15       # 0x7FFFFFFF & 0x7FFFFFFF = 0x7FFFFFFF

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
    # Test Set 5: Non-overlapping patterns (should give zero)
    #-------------------------------------------------
    c.and x8,  x9        # 0xFF00FF00 & 0x00FF00FF = 0x00000000
    c.and x10, x11       # 0xF0F0F0F0 & 0x0F0F0F0F = 0x00000000

.option norvc
    # Backup fifth set of results to x24-x25
    addi x24, x8,  0     # Backup x8:  0x00000000
    addi x25, x10, 0     # Backup x10: 0x00000000

    # Reload for sixth set (bit masking)
    li  x12, 0x12345678
    li  x13, 0xFFFF0000  # Upper half mask
    li  x14, 0xABCDEF01
    li  x15, 0x0000FFFF  # Lower half mask
.option rvc

    #-------------------------------------------------
    # Test Set 6: Bit masking (isolate bits)
    #-------------------------------------------------
    c.and x12, x13       # 0x12345678 & 0xFFFF0000 = 0x12340000 (upper half)
    c.and x14, x15       # 0xABCDEF01 & 0x0000FFFF = 0x0000EF01 (lower half)

.option norvc
    # Backup sixth set of results to x26-x27
    addi x26, x12, 0     # Backup x12: 0x12340000
    addi x27, x14, 0     # Backup x14: 0x0000EF01

    # Reload for seventh set (nibble masking)
    li  x8,  0x12345678
    li  x9,  0x0F0F0F0F  # Low nibble mask
    li  x10, 0xABCDEF01
    li  x11, 0xF0F0F0F0  # High nibble mask
.option rvc

    #-------------------------------------------------
    # Test Set 7: Nibble masking
    #-------------------------------------------------
    c.and x8,  x9        # 0x12345678 & 0x0F0F0F0F = 0x02040608
    c.and x10, x11       # 0xABCDEF01 & 0xF0F0F0F0 = 0xA0C0E000

.option norvc
    # Backup seventh set results
    addi x28, x8,  0     # Backup x8:  0x02040608
    addi x29, x10, 0     # Backup x10: 0xA0C0E000

    # Reload for eighth set (byte masking)
    li  x12, 0x12345678
    li  x13, 0xFF000000  # MSB mask
    li  x14, 0xABCDEF01
    li  x15, 0x000000FF  # LSB mask
.option rvc

    #-------------------------------------------------
    # Test Set 8: Byte masking
    #-------------------------------------------------
    c.and x12, x13       # 0x12345678 & 0xFF000000 = 0x12000000
    c.and x14, x15       # 0xABCDEF01 & 0x000000FF = 0x00000001

.option norvc
    # Backup eighth set results
    addi x30, x12, 0     # Backup x12: 0x12000000
    addi x2,  x14, 0     # Backup x14: 0x00000001

    # Reload for ninth set (consecutive ANDs)
    li  x8,  0xFFFFFFFF
    li  x9,  0xFFFFFFF0  # Clear low 4 bits
    li  x10, 0xFFFFFF00  # Clear low 8 bits
.option rvc

    #-------------------------------------------------
    # Test Set 9: Multiple consecutive ANDs (progressive masking)
    #-------------------------------------------------
    c.and x8,  x9        # 0xFFFFFFFF & 0xFFFFFFF0 = 0xFFFFFFF0
    c.and x8,  x10       # 0xFFFFFFF0 & 0xFFFFFF00 = 0xFFFFFF00

.option norvc
    # Backup ninth set result
    addi x3, x8, 0       # Backup x8: 0xFFFFFF00

    # Reload for tenth set (bit extraction)
    li  x11, 0x12345678
    li  x12, 0x000F0000  # Extract bits [19:16]
    li  x13, 0xAAAAAAAA
    li  x14, 0x55555555
.option rvc

    #-------------------------------------------------
    # Test Set 10: Bit extraction and overlap
    #-------------------------------------------------
    c.and x11, x12       # 0x12345678 & 0x000F0000 = 0x00040000
    c.and x13, x14       # 0xAAAAAAAA & 0x55555555 = 0x00000000

.option norvc
    # Backup tenth set results
    addi x4, x11, 0      # Backup x11: 0x00040000
    addi x5, x13, 0      # Backup x13: 0x00000000

    # Reload for eleventh set (single bit masking)
    li  x8,  0x80000000  # MSB set
    li  x9,  0x80000000  # MSB mask
    li  x10, 0x00000001  # LSB set
    li  x11, 0x00000001  # LSB mask
.option rvc

    #-------------------------------------------------
    # Test Set 11: Single bit extraction
    #-------------------------------------------------
    c.and x8,  x9        # 0x80000000 & 0x80000000 = 0x80000000
    c.and x10, x11       # 0x00000001 & 0x00000001 = 0x00000001

.option norvc
    # Backup eleventh set results
    addi x6, x8,  0      # Backup x8:  0x80000000
    addi x7, x10, 0      # Backup x10: 0x00000001

    # Reload for twelfth set (boundary values)
    li  x12, 0x7FFFFFFF  # Max positive
    li  x13, 0x80000000  # Min negative (MSB set)
    li  x14, 0xFFFFFFFF
    li  x15, 0x00000000
.option rvc

    #-------------------------------------------------
    # Test Set 12: Boundary values and edge cases
    #-------------------------------------------------
    c.and x12, x13       # 0x7FFFFFFF & 0x80000000 = 0x00000000 (no overlap)
    c.and x14, x15       # 0xFFFFFFFF & 0x00000000 = 0x00000000 (annihilation)

.option norvc
    # Note: Test Set 12 results are not backed up (both zero, already tested in other sets)
    # x12 = 0x00000000, x14 = 0x00000000

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
