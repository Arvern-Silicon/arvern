#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_max
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MAX (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # MAX operation: rd = max(rs1, rs2) - signed comparison
    # Returns the maximum of two signed integer values

    # Test data with various signed values
    li  x1,  10          # Positive value
    li  x2,  20          # Larger positive value
    li  x3,  -10         # Negative value
    li  x4,  -20         # More negative value
    li  x5,  0           # Zero
    li  x6,  0x7FFFFFFF  # INT_MAX (2147483647)
    li  x7,  0x80000000  # INT_MIN (-2147483648)
    li  x8,  1           # Small positive
    li  x9,  -1          # Small negative
    li  x10, 100         # Medium positive

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST MAX (Maximum - Signed) INSTRUCTION
    # Format: max rd, rs1, rs2
    # Operation: rd = (rs1 >s rs2) ? rs1 : rs2
    # Encoding: 0000101 rs2[4:0] rs1[4:0] 110 rd[4:0] 0110011
    # Use case: Finding maximum of signed values
    #-------------------------------------------------

    # Test 1: Positive vs larger positive -> larger
    # max x11, x1, x2 (10 vs 20)
    # Expected: 20
    max x11, x1, x2

    # Test 2: Larger positive vs smaller positive -> larger
    # max x12, x2, x1 (20 vs 10)
    # Expected: 20 (commutative check)
    max x12, x2, x1

    # Test 3: Negative vs more negative -> less negative
    # max x13, x3, x4 (-10 vs -20)
    # Expected: -10
    max x13, x3, x4

    # Test 4: More negative vs less negative -> less negative
    # max x14, x4, x3 (-20 vs -10)
    # Expected: -10 (commutative check)
    max x14, x4, x3

    # Test 5: Positive vs negative -> positive
    # max x15, x1, x3 (10 vs -10)
    # Expected: 10
    max x15, x1, x3

    # Test 6: Negative vs positive -> positive
    # max x16, x3, x1 (-10 vs 10)
    # Expected: 10 (commutative check)
    max x16, x3, x1

    # Test 7: Zero vs positive -> positive
    # max x17, x5, x1 (0 vs 10)
    # Expected: 10
    max x17, x5, x1

    # Test 8: Positive vs zero -> positive
    # max x18, x1, x5 (10 vs 0)
    # Expected: 10 (commutative check)
    max x18, x1, x5

    # Test 9: Zero vs negative -> zero
    # max x19, x5, x3 (0 vs -10)
    # Expected: 0
    max x19, x5, x3

    # Test 10: Negative vs zero -> zero
    # max x20, x3, x5 (-10 vs 0)
    # Expected: 0 (commutative check)
    max x20, x3, x5

    # Test 11: Equal positive values -> same value
    # max x21, x1, x1 (10 vs 10)
    # Expected: 10
    max x21, x1, x1

    # Test 12: Equal negative values -> same value
    # max x22, x3, x3 (-10 vs -10)
    # Expected: -10
    max x22, x3, x3

    # Test 13: Zero vs zero -> zero
    # max x23, x5, x5 (0 vs 0)
    # Expected: 0
    max x23, x5, x5

    # Test 14: INT_MAX vs positive -> INT_MAX
    # max x24, x6, x1 (0x7FFFFFFF vs 10)
    # Expected: 0x7FFFFFFF
    max x24, x6, x1

    # Test 15: Positive vs INT_MAX -> INT_MAX
    # max x25, x1, x6 (10 vs 0x7FFFFFFF)
    # Expected: 0x7FFFFFFF (commutative check)
    max x25, x1, x6

    # Test 16: INT_MIN vs negative -> negative
    # max x26, x7, x3 (0x80000000 vs -10)
    # Expected: -10
    max x26, x7, x3

    # Test 17: Negative vs INT_MIN -> negative
    # max x27, x3, x7 (-10 vs 0x80000000)
    # Expected: -10 (commutative check)
    max x27, x3, x7

    # Test 18: INT_MAX vs INT_MIN -> INT_MAX
    # max x28, x6, x7 (0x7FFFFFFF vs 0x80000000)
    # Expected: 0x7FFFFFFF
    max x28, x6, x7

    # Test 19: INT_MIN vs INT_MAX -> INT_MAX
    # max x29, x7, x6 (0x80000000 vs 0x7FFFFFFF)
    # Expected: 0x7FFFFFFF (commutative check)
    max x29, x7, x6

    # Test 20: Small positive vs small negative -> positive
    # max x30, x8, x9 (1 vs -1)
    # Expected: 1
    max x30, x8, x9

    # Test 21: Small negative vs small positive -> positive
    li   x1, -1
    li   x2, 1
    # max x3, x1, x2 (-1 vs 1)
    # Expected: 1 (commutative check)
    max x3, x1, x2

    # Test 22: Large positive values
    li   x4, 1000000
    li   x5, 2000000
    # max x6, x4, x5 (1000000 vs 2000000)
    # Expected: 2000000
    max x6, x4, x5

    # Test 23: Large negative values
    li   x7, -1000000
    li   x8, -2000000
    # max x9, x7, x8 (-1000000 vs -2000000)
    # Expected: -1000000
    max x9, x7, x8

    # Test 24: Adjacent values (positive)
    li   x10, 99
    li   x11, 100
    # max x12, x10, x11 (99 vs 100)
    # Expected: 100
    max x12, x10, x11

    # Test 25: Adjacent values (negative)
    li   x13, -100
    li   x14, -99
    # max x15, x13, x14 (-100 vs -99)
    # Expected: -99
    max x15, x13, x14

    # Test 26: Power of 2 values
    li   x16, 0x00000080  # 128
    li   x17, 0x00000100  # 256
    # max x18, x16, x17 (128 vs 256)
    # Expected: 256
    max x18, x16, x17

    # Test 27: Negative power of 2 values
    li   x19, 0xFFFFFF80  # -128
    li   x20, 0xFFFFFF00  # -256
    # max x21, x19, x20 (-128 vs -256)
    # Expected: -128
    max x21, x19, x20

    # Test 28: Mixed magnitude
    li   x22, 50
    li   x23, -100
    # max x24, x22, x23 (50 vs -100)
    # Expected: 50
    max x24, x22, x23

    # Test 29: INT_MAX vs INT_MAX -> INT_MAX
    li   x25, 0x7FFFFFFF
    li   x26, 0x7FFFFFFF
    # max x27, x25, x26
    # Expected: 0x7FFFFFFF
    max x27, x25, x26

    # Test 30: INT_MIN vs INT_MIN -> INT_MIN
    li   x28, 0x80000000
    li   x29, 0x80000000
    # max x30, x28, x29
    # Expected: 0x80000000
    max x30, x28, x29

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
