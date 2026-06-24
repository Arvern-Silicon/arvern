#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_ctz
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CTZ (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # CTZ operation: rd = count_trailing_zeros(rs1)
    # Counts the number of consecutive zero bits starting from bit 0 (LSB)
    # Result range: 0-32

    # Test data with various trailing zero patterns
    li  x1,  0x00000001  # Bit 0 set -> 0 trailing zeros
    li  x2,  0x00000002  # Bit 1 set -> 1 trailing zero
    li  x3,  0x80000000  # Bit 31 set -> 31 trailing zeros
    li  x4,  0x00000000  # All zeros -> 32 trailing zeros
    li  x5,  0xFFFFFFFF  # All ones -> 0 trailing zeros
    li  x6,  0x00010000  # Bit 16 set -> 16 trailing zeros
    li  x7,  0x00000100  # Bit 8 set -> 8 trailing zeros
    li  x8,  0x00000004  # Bit 2 set -> 2 trailing zeros
    li  x9,  0x00000008  # Bit 3 set -> 3 trailing zeros
    li  x10, 0x00000010  # Bit 4 set -> 4 trailing zeros

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST CTZ (Count Trailing Zeros) INSTRUCTION
    # Format: ctz rd, rs1
    # Operation: rd = count_trailing_zeros(rs1)
    # Encoding: 0110000 00001 rs1[4:0] 001 rd[4:0] 0010011
    # Use case: Bit manipulation, finding LSB position
    #-------------------------------------------------

    # Test 1: LSB set (bit 0) -> 0 trailing zeros
    # ctz x11, x1 (0x00000001)
    # Expected: 0
    ctz x11, x1

    # Test 2: Bit 1 set -> 1 trailing zero
    # ctz x12, x2 (0x00000002)
    # Expected: 1
    ctz x12, x2

    # Test 3: MSB set (bit 31) -> 31 trailing zeros
    # ctz x13, x3 (0x80000000)
    # Expected: 31
    ctz x13, x3

    # Test 4: All zeros -> 32 trailing zeros
    # ctz x14, x4 (0x00000000)
    # Expected: 32
    ctz x14, x4

    # Test 5: All ones -> 0 trailing zeros (LSB is set)
    # ctz x15, x5 (0xFFFFFFFF)
    # Expected: 0
    ctz x15, x5

    # Test 6: Bit 16 set -> 16 trailing zeros
    # ctz x16, x6 (0x00010000)
    # Expected: 16
    ctz x16, x6

    # Test 7: Bit 8 set -> 8 trailing zeros
    # ctz x17, x7 (0x00000100)
    # Expected: 8
    ctz x17, x7

    # Test 8: Bit 2 set -> 2 trailing zeros
    # ctz x18, x8 (0x00000004)
    # Expected: 2
    ctz x18, x8

    # Test 9: Bit 3 set -> 3 trailing zeros
    # ctz x19, x9 (0x00000008)
    # Expected: 3
    ctz x19, x9

    # Test 10: Bit 4 set -> 4 trailing zeros
    # ctz x20, x10 (0x00000010)
    # Expected: 4
    ctz x20, x10

    # Test 11: Powers of 2 sequence (bit 5)
    li   x21, 0x00000020  # Bit 5 set
    # ctz x22, x21 (0x00000020)
    # Expected: 5
    ctz x22, x21

    # Test 12: Bit 6 set -> 6 trailing zeros
    li   x23, 0x00000040
    ctz x24, x23
    # Expected: 6

    # Test 13: Bit 7 set -> 7 trailing zeros
    li   x25, 0x00000080
    ctz x26, x25
    # Expected: 7

    # Test 14: Bit 11 set -> 11 trailing zeros
    li   x27, 0x00000800
    ctz x28, x27
    # Expected: 11

    # Test 15: Bit 19 set -> 19 trailing zeros
    li   x29, 0x00080000
    ctz x30, x29
    # Expected: 19

    # Test 16: Multiple bits set (only count to first 1 from LSB)
    li   x1, 0xAAAAAAAA   # Alternating bits, bit 1 is first set from LSB
    # ctz x2, x1 (0xAAAAAAAA)
    # Expected: 1 (bit 1 is the first set bit from LSB)
    ctz x2, x1

    # Test 17: Multiple bits set from bit 4
    li   x3, 0xFFFFFFF0   # Bits 4-31 set, bits 0-3 clear
    # ctz x4, x3 (0xFFFFFFF0)
    # Expected: 4
    ctz x4, x3

    # Test 18: Bit 27 set -> 27 trailing zeros
    li   x5, 0x08000000
    ctz x6, x5
    # Expected: 27

    # Test 19: Bit 30 set -> 30 trailing zeros
    li   x7, 0x40000000
    ctz x8, x7
    # Expected: 30

    # Test 20: Sequential test - bit 8
    li   x9, 0x00000100
    ctz x10, x9
    # Expected: 8

    # Test 21: Sequential test - bit 15
    li   x11, 0x00008000
    ctz x12, x11
    # Expected: 15

    # Test 22: Sequential test - bit 24
    li   x13, 0x01000000
    ctz x14, x13
    # Expected: 24

    # Test 23: Bit 28 set -> 28 trailing zeros
    li   x15, 0x10000000
    ctz x16, x15
    # Expected: 28

    # Test 24: Bit 29 set -> 29 trailing zeros
    li   x17, 0x20000000
    ctz x18, x17
    # Expected: 29

    # Test 25: Pattern with bit 9 set
    li   x19, 0x00000200
    ctz x20, x19
    # Expected: 9

    # Test 26: Pattern with bit 10 set
    li   x21, 0x00000400
    ctz x22, x21
    # Expected: 10

    # Test 27: Pattern with bit 12 set
    li   x23, 0x00001000
    ctz x24, x23
    # Expected: 12

    # Test 28: Pattern with bit 13 set
    li   x25, 0x00002000
    ctz x26, x25
    # Expected: 13

    # Test 29: Pattern with bit 14 set
    li   x27, 0x00004000
    ctz x28, x27
    # Expected: 14

    # Test 30: Verify with complex pattern (0x55555555)
    # Bit 0 is set, so result is 0
    li   x29, 0x55555555
    ctz x30, x29
    # Expected: 0

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
