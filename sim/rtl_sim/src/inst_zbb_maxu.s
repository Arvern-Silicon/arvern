#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_maxu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MAXU (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # MAXU operation: rd = maxu(rs1, rs2) - unsigned comparison
    # Returns the maximum of two unsigned integer values

    # Test data with various unsigned values
    li  x1,  10          # Small value
    li  x2,  20          # Larger value
    li  x3,  0xFFFFFFFF  # Max unsigned (4294967295)
    li  x4,  0x80000000  # 2147483648 (unsigned), INT_MIN (signed)
    li  x5,  0           # Zero
    li  x6,  0x7FFFFFFF  # 2147483647 (unsigned), INT_MAX (signed)
    li  x7,  1           # Minimum non-zero
    li  x8,  100         # Medium value
    li  x9,  0xFFFFFFFE  # Max - 1
    li  x10, 0x00000001  # One

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST MAXU (Maximum - Unsigned) INSTRUCTION
    # Format: maxu rd, rs1, rs2
    # Operation: rd = (rs1 >u rs2) ? rs1 : rs2
    # Encoding: 0000101 rs2[4:0] rs1[4:0] 111 rd[4:0] 0110011
    # Use case: Finding maximum of unsigned values
    #-------------------------------------------------

    # Test 1: Small vs larger -> larger
    # maxu x11, x1, x2 (10 vs 20)
    # Expected: 20
    maxu x11, x1, x2

    # Test 2: Larger vs small -> larger
    # maxu x12, x2, x1 (20 vs 10)
    # Expected: 20 (commutative check)
    maxu x12, x2, x1

    # Test 3: Max unsigned vs any positive -> max unsigned
    # maxu x13, x3, x1 (0xFFFFFFFF vs 10)
    # Expected: 0xFFFFFFFF
    maxu x13, x3, x1

    # Test 4: Any positive vs max unsigned -> max unsigned
    # maxu x14, x1, x3 (10 vs 0xFFFFFFFF)
    # Expected: 0xFFFFFFFF (commutative check)
    maxu x14, x1, x3

    # Test 5: Zero vs positive -> positive
    # maxu x15, x5, x1 (0 vs 10)
    # Expected: 10
    maxu x15, x5, x1

    # Test 6: Positive vs zero -> positive
    # maxu x16, x1, x5 (10 vs 0)
    # Expected: 10 (commutative check)
    maxu x16, x1, x5

    # Test 7: Zero vs zero -> zero
    # maxu x17, x5, x5 (0 vs 0)
    # Expected: 0
    maxu x17, x5, x5

    # Test 8: Equal positive values -> same value
    # maxu x18, x1, x1 (10 vs 10)
    # Expected: 10
    maxu x18, x1, x1

    # Test 9: 0x80000000 vs 0x7FFFFFFF -> 0x80000000 (unsigned comparison!)
    # maxu x19, x4, x6 (0x80000000 vs 0x7FFFFFFF)
    # Expected: 0x80000000 (2147483648 > 2147483647 in unsigned)
    maxu x19, x4, x6

    # Test 10: 0x7FFFFFFF vs 0x80000000 -> 0x80000000
    # maxu x20, x6, x4 (0x7FFFFFFF vs 0x80000000)
    # Expected: 0x80000000 (commutative check)
    maxu x20, x6, x4

    # Test 11: Max unsigned vs max-1 -> max unsigned
    # maxu x21, x3, x9 (0xFFFFFFFF vs 0xFFFFFFFE)
    # Expected: 0xFFFFFFFF
    maxu x21, x3, x9

    # Test 12: Max-1 vs max unsigned -> max unsigned
    # maxu x22, x9, x3 (0xFFFFFFFE vs 0xFFFFFFFF)
    # Expected: 0xFFFFFFFF (commutative check)
    maxu x22, x9, x3

    # Test 13: 0x80000000 vs small positive -> 0x80000000
    # maxu x23, x4, x1 (0x80000000 vs 10)
    # Expected: 0x80000000
    maxu x23, x4, x1

    # Test 14: Small positive vs 0x80000000 -> 0x80000000
    # maxu x24, x1, x4 (10 vs 0x80000000)
    # Expected: 0x80000000 (commutative check)
    maxu x24, x1, x4

    # Test 15: Max unsigned vs 0x80000000 -> max unsigned
    # maxu x25, x3, x4 (0xFFFFFFFF vs 0x80000000)
    # Expected: 0xFFFFFFFF
    maxu x25, x3, x4

    # Test 16: 0x80000000 vs max unsigned -> max unsigned
    # maxu x26, x4, x3 (0x80000000 vs 0xFFFFFFFF)
    # Expected: 0xFFFFFFFF (commutative check)
    maxu x26, x4, x3

    # Test 17: Max unsigned vs zero -> max unsigned
    # maxu x27, x3, x5 (0xFFFFFFFF vs 0)
    # Expected: 0xFFFFFFFF
    maxu x27, x3, x5

    # Test 18: Zero vs max unsigned -> max unsigned
    # maxu x28, x5, x3 (0 vs 0xFFFFFFFF)
    # Expected: 0xFFFFFFFF (commutative check)
    maxu x28, x5, x3

    # Test 19: One vs max-1 -> max-1
    # maxu x29, x10, x9 (1 vs 0xFFFFFFFE)
    # Expected: 0xFFFFFFFE
    maxu x29, x10, x9

    # Test 20: Max-1 vs one -> max-1
    # maxu x30, x9, x10 (0xFFFFFFFE vs 1)
    # Expected: 0xFFFFFFFE (commutative check)
    maxu x30, x9, x10

    # Test 21: Large unsigned values
    li   x1, 0x80000000
    li   x2, 0x80000001
    # maxu x3, x1, x2 (0x80000000 vs 0x80000001)
    # Expected: 0x80000001
    maxu x3, x1, x2

    # Test 22: Upper half range
    li   x4, 0xF0000000
    li   x5, 0xE0000000
    # maxu x6, x4, x5 (0xF0000000 vs 0xE0000000)
    # Expected: 0xF0000000
    maxu x6, x4, x5

    # Test 23: Lower half range
    li   x7, 0x10000000
    li   x8, 0x20000000
    # maxu x9, x7, x8 (0x10000000 vs 0x20000000)
    # Expected: 0x20000000
    maxu x9, x7, x8

    # Test 24: Powers of 2 - adjacent
    li   x10, 0x00000080  # 128
    li   x11, 0x00000100  # 256
    # maxu x12, x10, x11 (128 vs 256)
    # Expected: 256
    maxu x12, x10, x11

    # Test 25: High bit patterns
    li   x13, 0xFF000000
    li   x14, 0x00FFFFFF
    # maxu x15, x13, x14 (0xFF000000 vs 0x00FFFFFF)
    # Expected: 0xFF000000
    maxu x15, x13, x14

    # Test 26: Adjacent values (low)
    li   x16, 99
    li   x17, 100
    # maxu x18, x16, x17 (99 vs 100)
    # Expected: 100
    maxu x18, x16, x17

    # Test 27: Adjacent values (high)
    li   x19, 0xFFFFFFFD
    li   x20, 0xFFFFFFFE
    # maxu x21, x19, x20
    # Expected: 0xFFFFFFFE
    maxu x21, x19, x20

    # Test 28: Mid-range values
    li   x22, 0x40000000
    li   x23, 0x3FFFFFFF
    # maxu x24, x22, x23 (0x40000000 vs 0x3FFFFFFF)
    # Expected: 0x40000000
    maxu x24, x22, x23

    # Test 29: Small difference
    li   x25, 1000
    li   x26, 1001
    # maxu x27, x25, x26 (1000 vs 1001)
    # Expected: 1001
    maxu x27, x25, x26

    # Test 30: Max unsigned vs max unsigned -> max unsigned
    li   x28, 0xFFFFFFFF
    li   x29, 0xFFFFFFFF
    # maxu x30, x28, x29
    # Expected: 0xFFFFFFFF
    maxu x30, x28, x29

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
