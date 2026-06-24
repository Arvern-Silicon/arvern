#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_rev8
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: REV8 (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # REV8 operation: rd[31:24] = rs1[7:0], rd[23:16] = rs1[15:8],
    #                 rd[15:8] = rs1[23:16], rd[7:0] = rs1[31:24]
    # Reverses the byte order (endianness conversion)

    # Test data with various patterns
    li  x1,  0x00000000  # All zeros
    li  x2,  0xFFFFFFFF  # All ones
    li  x3,  0x12345678  # Sequential bytes
    li  x4,  0xDEADBEEF  # Mixed pattern
    li  x5,  0x000000FF  # Only byte 0 set
    li  x6,  0x0000FF00  # Only byte 1 set
    li  x7,  0x00FF0000  # Only byte 2 set
    li  x8,  0xFF000000  # Only byte 3 set
    li  x9,  0x01020304  # Sequential pattern
    li  x10, 0xAABBCCDD  # Distinct bytes

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST REV8 (Reverse Byte Order) INSTRUCTION
    # Format: rev8 rd, rs1
    # Operation: rd[31:24] = rs1[7:0], rd[23:16] = rs1[15:8],
    #            rd[15:8] = rs1[23:16], rd[7:0] = rs1[31:24]
    # Encoding: 0110101 11000 rs1[4:0] 101 rd[4:0] 0010011
    # Use case: Endianness conversion
    #-------------------------------------------------

    # Test 1: All zeros -> 0x00000000
    # rev8 x11, x1 (0x00000000)
    # Expected: 0x00000000
    rev8 x11, x1

    # Test 2: All ones -> 0xFFFFFFFF
    # rev8 x12, x2 (0xFFFFFFFF)
    # Expected: 0xFFFFFFFF
    rev8 x12, x2

    # Test 3: 0x12345678 -> 0x78563412
    # rev8 x13, x3 (0x12345678)
    # Expected: 0x78563412
    rev8 x13, x3

    # Test 4: 0xDEADBEEF -> 0xEFBEADDE
    # rev8 x14, x4 (0xDEADBEEF)
    # Expected: 0xEFBEADDE
    rev8 x14, x4

    # Test 5: Only byte 0 set -> byte becomes byte 3
    # rev8 x15, x5 (0x000000FF)
    # Expected: 0xFF000000
    rev8 x15, x5

    # Test 6: Only byte 1 set -> byte becomes byte 2
    # rev8 x16, x6 (0x0000FF00)
    # Expected: 0x00FF0000
    rev8 x16, x6

    # Test 7: Only byte 2 set -> byte becomes byte 1
    # rev8 x17, x7 (0x00FF0000)
    # Expected: 0x0000FF00
    rev8 x17, x7

    # Test 8: Only byte 3 set -> byte becomes byte 0
    # rev8 x18, x8 (0xFF000000)
    # Expected: 0x000000FF
    rev8 x18, x8

    # Test 9: Sequential pattern 0x01020304 -> 0x04030201
    # rev8 x19, x9 (0x01020304)
    # Expected: 0x04030201
    rev8 x19, x9

    # Test 10: Distinct bytes 0xAABBCCDD -> 0xDDCCBBAA
    # rev8 x20, x10 (0xAABBCCDD)
    # Expected: 0xDDCCBBAA
    rev8 x20, x10

    # Test 11: Palindrome pattern 0x12344321 -> 0x21433412
    li  x1, 0x12344321
    # rev8 x21, x1
    # Expected: 0x21433412
    rev8 x21, x1

    # Test 12: Pattern 0xA5A5A5A5 -> 0xA5A5A5A5 (symmetric)
    li  x2, 0xA5A5A5A5
    # rev8 x22, x2
    # Expected: 0xA5A5A5A5
    rev8 x22, x2

    # Test 13: Pattern 0x00FF00FF -> 0xFF00FF00
    li  x3, 0x00FF00FF
    # rev8 x23, x3
    # Expected: 0xFF00FF00
    rev8 x23, x3

    # Test 14: Pattern 0xFF00FF00 -> 0x00FF00FF
    li  x4, 0xFF00FF00
    # rev8 x24, x4
    # Expected: 0x00FF00FF
    rev8 x24, x4

    # Test 15: Pattern 0x80000000 -> 0x00000080
    li  x5, 0x80000000
    # rev8 x25, x5
    # Expected: 0x00000080
    rev8 x25, x5

    # Test 16: Pattern 0x00000001 -> 0x01000000
    li  x6, 0x00000001
    # rev8 x26, x6
    # Expected: 0x01000000
    rev8 x26, x6

    # Test 17: Pattern 0xF0F0F0F0 -> 0xF0F0F0F0 (symmetric)
    li  x7, 0xF0F0F0F0
    # rev8 x27, x7
    # Expected: 0xF0F0F0F0
    rev8 x27, x7

    # Test 18: Pattern 0x0F0F0F0F -> 0x0F0F0F0F (symmetric)
    li  x8, 0x0F0F0F0F
    # rev8 x28, x8
    # Expected: 0x0F0F0F0F
    rev8 x28, x8

    # Test 19: Pattern 0xFEDCBA98 -> 0x98BADCFE
    li  x9, 0xFEDCBA98
    # rev8 x29, x9
    # Expected: 0x98BADCFE
    rev8 x29, x9

    # Test 20: Pattern 0x11223344 -> 0x44332211
    li  x10, 0x11223344
    # rev8 x30, x10
    # Expected: 0x44332211
    rev8 x30, x10

    # Test 21: Double reverse should give original
    li  x1, 0x12345678
    rev8 x1, x1
    # x1 = 0x78563412
    # rev8 x1, x1 again
    # Expected: 0x12345678
    rev8 x1, x1

    # Test 22: Pattern 0x00112233 -> 0x33221100
    li  x2, 0x00112233
    # rev8 x2, x2
    # Expected: 0x33221100
    rev8 x2, x2

    # Test 23: Pattern 0x44556677 -> 0x77665544
    li  x3, 0x44556677
    # rev8 x3, x3
    # Expected: 0x77665544
    rev8 x3, x3

    # Test 24: Pattern 0x8899AABB -> 0xBBAA9988
    li  x4, 0x8899AABB
    # rev8 x4, x4
    # Expected: 0xBBAA9988
    rev8 x4, x4

    # Test 25: Pattern 0xCCDDEEFF -> 0xFFEEDDCC
    li  x5, 0xCCDDEEFF
    # rev8 x5, x5
    # Expected: 0xFFEEDDCC
    rev8 x5, x5

    # Test 26: Pattern 0x0000FFFF -> 0xFFFF0000
    li  x6, 0x0000FFFF
    # rev8 x6, x6
    # Expected: 0xFFFF0000
    rev8 x6, x6

    # Test 27: Pattern 0xFFFF0000 -> 0x0000FFFF
    li  x7, 0xFFFF0000
    # rev8 x7, x7
    # Expected: 0x0000FFFF
    rev8 x7, x7

    # Test 28: Pattern 0x7FFFFFFF -> 0xFFFFFF7F
    li  x8, 0x7FFFFFFF
    # rev8 x8, x8
    # Expected: 0xFFFFFF7F
    rev8 x8, x8

    # Test 29: Pattern 0x80808080 -> 0x80808080 (symmetric)
    li  x9, 0x80808080
    # rev8 x9, x9
    # Expected: 0x80808080
    rev8 x9, x9

    # Test 30: Pattern 0x01010101 -> 0x01010101 (symmetric)
    li  x10, 0x01010101
    # rev8 x10, x10
    # Expected: 0x01010101
    rev8 x10, x10

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    # Ensure all operations complete before marking test done
    fence

    # Mark test complete
    li  x31, 0x12345678

end_of_test:
    nop
    j end_of_test     # infinite loop
