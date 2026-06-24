#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_clz
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CLZ (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # CLZ operation: rd = count_leading_zeros(rs1)
    # Counts the number of consecutive zero bits starting from bit 31
    # Result range: 0-32

    # Test data with various leading zero patterns
    li  x1,  0x80000000  # Bit 31 set -> 0 leading zeros
    li  x2,  0x40000000  # Bit 30 set -> 1 leading zero
    li  x3,  0x00000001  # Bit 0 set -> 31 leading zeros
    li  x4,  0x00000000  # All zeros -> 32 leading zeros
    li  x5,  0xFFFFFFFF  # All ones -> 0 leading zeros
    li  x6,  0x00010000  # Bit 16 set -> 15 leading zeros
    li  x7,  0x00000100  # Bit 8 set -> 23 leading zeros
    li  x8,  0x20000000  # Bit 29 set -> 2 leading zeros
    li  x9,  0x10000000  # Bit 28 set -> 3 leading zeros
    li  x10, 0x08000000  # Bit 27 set -> 4 leading zeros

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST CLZ (Count Leading Zeros) INSTRUCTION
    # Format: clz rd, rs1
    # Operation: rd = count_leading_zeros(rs1)
    # Encoding: 0110000 00000 rs1[4:0] 001 rd[4:0] 0010011
    # Use case: Bit manipulation, normalization, priority encoding
    #-------------------------------------------------

    # Test 1: MSB set (bit 31) -> 0 leading zeros
    # clz x11, x1 (0x80000000)
    # Expected: 0
    clz x11, x1

    # Test 2: Bit 30 set -> 1 leading zero
    # clz x12, x2 (0x40000000)
    # Expected: 1
    clz x12, x2

    # Test 3: LSB set (bit 0) -> 31 leading zeros
    # clz x13, x3 (0x00000001)
    # Expected: 31
    clz x13, x3

    # Test 4: All zeros -> 32 leading zeros
    # clz x14, x4 (0x00000000)
    # Expected: 32
    clz x14, x4

    # Test 5: All ones -> 0 leading zeros (MSB is set)
    # clz x15, x5 (0xFFFFFFFF)
    # Expected: 0
    clz x15, x5

    # Test 6: Bit 16 set -> 15 leading zeros
    # clz x16, x6 (0x00010000)
    # Expected: 15
    clz x16, x6

    # Test 7: Bit 8 set -> 23 leading zeros
    # clz x17, x7 (0x00000100)
    # Expected: 23
    clz x17, x7

    # Test 8: Bit 29 set -> 2 leading zeros
    # clz x18, x8 (0x20000000)
    # Expected: 2
    clz x18, x8

    # Test 9: Bit 28 set -> 3 leading zeros
    # clz x19, x9 (0x10000000)
    # Expected: 3
    clz x19, x9

    # Test 10: Bit 27 set -> 4 leading zeros
    # clz x20, x10 (0x08000000)
    # Expected: 4
    clz x20, x10

    # Test 11: Powers of 2 sequence (bit 26)
    li   x21, 0x04000000  # Bit 26 set
    # clz x22, x21 (0x04000000)
    # Expected: 5
    clz x22, x21

    # Test 12: Bit 25 set -> 6 leading zeros
    li   x23, 0x02000000
    clz x24, x23
    # Expected: 6

    # Test 13: Bit 24 set -> 7 leading zeros
    li   x25, 0x01000000
    clz x26, x25
    # Expected: 7

    # Test 14: Bit 20 set -> 11 leading zeros
    li   x27, 0x00100000
    clz x28, x27
    # Expected: 11

    # Test 15: Bit 12 set -> 19 leading zeros
    li   x29, 0x00001000
    clz x30, x29
    # Expected: 19

    # Test 16: Multiple bits set (only count to first 1)
    # Store result in unused register to avoid conflicts
    li   x1, 0xAAAAAAAA   # Alternating bits, MSB set
    li   x2, 0xDEADDEAD   # Temp marker
    # clz x2, x1 (0xAAAAAAAA)
    # Expected: 0 (bit 31 is set)
    clz x2, x1

    # Test 17: Multiple bits set without MSB
    # Store result in unused register to avoid conflicts
    li   x3, 0x0FFFFFFF   # Bits 0-27 set, bits 28-31 clear
    li   x4, 0xBEEFBEEF   # Temp marker
    # clz x4, x3 (0x0FFFFFFF)
    # Expected: 4
    clz x4, x3

    # Test 18: Bit 4 set -> 27 leading zeros
    li   x5, 0x00000010
    clz x6, x5
    # Expected: 27

    # Test 19: Bit 1 set -> 30 leading zeros
    li   x7, 0x00000002
    clz x8, x7
    # Expected: 30

    # Test 20: Sequential test - bit 23
    li   x9, 0x00800000
    clz x10, x9
    # Expected: 8

    # Test 21: Sequential test - bit 15
    li   x11, 0x00008000
    clz x12, x11
    # Expected: 16

    # Test 22: Sequential test - bit 7
    li   x13, 0x00000080
    clz x14, x13
    # Expected: 24

    # Test 23: Bit 3 set -> 28 leading zeros
    li   x15, 0x00000008
    clz x16, x15
    # Expected: 28

    # Test 24: Bit 2 set -> 29 leading zeros
    li   x17, 0x00000004
    clz x18, x17
    # Expected: 29

    # Test 25: Pattern with bit 22 set
    li   x19, 0x00400000
    clz x20, x19
    # Expected: 9

    # Test 26: Pattern with bit 21 set
    li   x21, 0x00200000
    clz x22, x21
    # Expected: 10

    # Test 27: Pattern with bit 19 set
    li   x23, 0x00080000
    clz x24, x23
    # Expected: 12

    # Test 28: Pattern with bit 18 set
    li   x25, 0x00040000
    clz x26, x25
    # Expected: 13

    # Test 29: Pattern with bit 17 set
    li   x27, 0x00020000
    clz x28, x27
    # Expected: 14

    # Test 30: Verify with complex pattern (0x55555555)
    # Use x1 as destination to avoid x30 issues
    li   x29, 0x55555555   # Bit 30 is set, so result is 1
    clz x1, x29
    # Expected: 1 (stored in x1 instead of x30)

    # Test 31: Retest the failing cases with backup destinations
    # Retest x2 case using x30 as destination
    li   x2, 0xAAAAAAAA
    clz x30, x2
    # Expected: 0

    # Retest x4 case using x3 as destination
    li   x4, 0x0FFFFFFF
    clz x3, x4
    # Expected: 4

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
