#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zba_sh2add
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SH2ADD (Zba)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # SH2ADD operation: rd = rs2 + (rs1 << 2)
    # Useful for word array indexing (base_address + index * 4)

    # Test data with various patterns
    li  x1,  0x00000000  # Zero
    li  x2,  0x10000000  # Base address example
    li  x3,  0x00000001  # Index 1
    li  x4,  0x00000005  # Index 5
    li  x5,  0x0000000A  # Index 10
    li  x6,  0xFFFFFFFF  # All ones (-1)
    li  x7,  0x12345678  # Random pattern
    li  x8,  0x80000000  # Maximum negative
    li  x9,  0x7FFFFFFF  # Maximum positive
    li  x10, 0x00000100  # Index 256

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST SH2ADD (Shift-Left-2 and Add) INSTRUCTION
    # Format: sh2add rd, rs1, rs2
    # Operation: rd = rs2 + (rs1 << 2)
    # Encoding: 0010000 rs2[4:0] rs1[4:0] 100 rd[4:0] 0110011
    # Use case: Array indexing for words (4-byte elements)
    #-------------------------------------------------

    # Test 1: Zero base, zero index -> 0x00000000 + (0x00000000 << 2)
    # sh2add x11, x1, x1
    # Expected: 0x00000000
    sh2add x11, x1, x1

    # Test 2: Base address + index 1 -> 0x10000000 + (0x00000001 << 2)
    # sh2add x12, x3, x2
    # Expected: 0x10000004
    sh2add x12, x3, x2

    # Test 3: Base address + index 5 -> 0x10000000 + (0x00000005 << 2)
    # sh2add x13, x4, x2
    # Expected: 0x10000014
    sh2add x13, x4, x2

    # Test 4: Base address + index 10 -> 0x10000000 + (0x0000000A << 2)
    # sh2add x14, x5, x2
    # Expected: 0x10000028
    sh2add x14, x5, x2

    # Test 5: Zero base + index 256 -> 0x00000000 + (0x00000100 << 2)
    # sh2add x15, x10, x1
    # Expected: 0x00000400
    sh2add x15, x10, x1

    # Test 6: All ones + all ones -> 0xFFFFFFFF + (0xFFFFFFFF << 2)
    # sh2add x16, x6, x6
    # Expected: 0xFFFFFFFB (overflow wraps)
    sh2add x16, x6, x6

    # Test 7: Random pattern base + index 1
    # sh2add x17, x3, x7 (0x12345678 + (0x00000001 << 2))
    # Expected: 0x1234567C
    sh2add x17, x3, x7

    # Test 8: Max positive + index 1 -> 0x7FFFFFFF + (0x00000001 << 2)
    # sh2add x18, x3, x9
    # Expected: 0x80000003 (overflow to negative)
    sh2add x18, x3, x9

    # Test 9: Max negative + index 1 -> 0x80000000 + (0x00000001 << 2)
    # sh2add x19, x3, x8
    # Expected: 0x80000004
    sh2add x19, x3, x8

    # Test 10: Index pattern with zero base
    # sh2add x20, x7, x1 (0x00000000 + (0x12345678 << 2))
    # Expected: 0x48D159E0
    sh2add x20, x7, x1

    # Test 11: Larger index value
    li  x1, 0x00001000
    li  x2, 0x20000000
    # sh2add x21, x1, x2 (0x20000000 + (0x00001000 << 2))
    # Expected: 0x20004000
    sh2add x21, x1, x2

    # Test 12: Index that will overflow when shifted
    li  x1, 0x40000000
    li  x2, 0x00000100
    # sh2add x22, x1, x2 (0x00000100 + (0x40000000 << 2))
    # Expected: 0x00000100 (shift creates 0x00000000, overflow wraps)
    sh2add x22, x1, x2

    # Test 13: Negative base, positive index
    li  x1, 0x00000010
    li  x2, 0xFFFF0000
    # sh2add x23, x1, x2 (0xFFFF0000 + (0x00000010 << 2))
    # Expected: 0xFFFF0040
    sh2add x23, x1, x2

    # Test 14: Small values
    li  x1, 0x00000002
    li  x2, 0x00000008
    # sh2add x24, x1, x2 (0x00000008 + (0x00000002 << 2))
    # Expected: 0x00000010
    sh2add x24, x1, x2

    # Test 15: Pattern with alternating bits
    li  x1, 0xAAAAAAAA
    li  x2, 0x55555555
    # sh2add x25, x1, x2 (0x55555555 + (0xAAAAAAAA << 2))
    # Expected: 0xAAAAAAAA + 1 = 0xAAAAAA9D
    sh2add x25, x1, x2

    # Test 16: One operand zero
    li  x1, 0x00000000
    li  x2, 0x12345678
    # sh2add x26, x1, x2 (0x12345678 + (0x00000000 << 2))
    # Expected: 0x12345678
    sh2add x26, x1, x2

    # Test 17: Large index value
    li  x1, 0x1FFFFFFF
    li  x2, 0x00000004
    # sh2add x27, x1, x2 (0x00000004 + (0x1FFFFFFF << 2))
    # Expected: 0x80000000
    sh2add x27, x1, x2

    # Test 18: Index causing shift to highest bits
    li  x1, 0x20000000
    li  x2, 0x00000000
    # sh2add x28, x1, x2 (0x00000000 + (0x20000000 << 2))
    # Expected: 0x80000000
    sh2add x28, x1, x2

    # Test 19: Both operands with high bits set
    li  x1, 0xC0000000
    li  x2, 0x80000000
    # sh2add x29, x1, x2 (0x80000000 + (0xC0000000 << 2))
    # Expected: 0x80000000 (complete overflow)
    sh2add x29, x1, x2

    # Test 20: Sequential pattern
    li  x1, 0x01020304
    li  x2, 0x05060708
    # sh2add x30, x1, x2 (0x05060708 + (0x01020304 << 2))
    # Expected: 0x09141B18
    sh2add x30, x1, x2

    # Test 21: Base with low bits set, index shifts to align
    li  x1, 0x00000007
    li  x2, 0x00000001
    # sh2add x1, x1, x2 (0x00000001 + (0x00000007 << 2))
    # Expected: 0x0000001D
    sh2add x1, x1, x2

    # Test 22: Typical array access pattern
    li  x2, 0x20000000  # Base address
    li  x3, 0x0000000A  # Index 10
    # sh2add x2, x3, x2 (0x20000000 + (0x0000000A << 2))
    # Expected: 0x20000028
    sh2add x2, x3, x2

    # Test 23: Index = 1, base = 0xFFFFFFFC
    li  x3, 0x00000001
    li  x4, 0xFFFFFFFC
    # sh2add x3, x3, x4 (0xFFFFFFFC + (0x00000001 << 2))
    # Expected: 0x00000000
    sh2add x3, x3, x4

    # Test 24: Power of 2 index
    li  x4, 0x00000200
    li  x5, 0x10000000
    # sh2add x4, x4, x5 (0x10000000 + (0x00000200 << 2))
    # Expected: 0x10000800
    sh2add x4, x4, x5

    # Test 25: Index with only LSB set
    li  x5, 0x00000001
    li  x6, 0xABCDEF00
    # sh2add x5, x5, x6 (0xABCDEF00 + (0x00000001 << 2))
    # Expected: 0xABCDEF04
    sh2add x5, x5, x6

    # Test 26: Negative index (two's complement)
    li  x6, 0xFFFFFFF0  # -16
    li  x7, 0x00000100
    # sh2add x6, x6, x7 (0x00000100 + (0xFFFFFFF0 << 2))
    # Expected: 0x000000C0
    sh2add x6, x6, x7

    # Test 27: Index = max positive / 4, base = 4
    li  x7, 0x1FFFFFFF
    li  x8, 0x00000004
    # sh2add x7, x7, x8 (0x00000004 + (0x1FFFFFFF << 2))
    # Expected: 0x80000000
    sh2add x7, x7, x8

    # Test 28: Same register for both operands
    li  x8, 0x00000003
    # sh2add x8, x8, x8 (0x00000003 + (0x00000003 << 2))
    # Expected: 0x0000000F
    sh2add x8, x8, x8

    # Test 29: Index with alternating bits
    li  x9, 0x55555555
    li  x10, 0x00000000
    # sh2add x9, x9, x10 (0x00000000 + (0x55555555 << 2))
    # Expected: 0x55555554
    sh2add x9, x9, x10

    # Test 30: Complex pattern
    li  x10, 0x12345678
    li  x1, 0xFEDCBA98
    # sh2add x10, x10, x1 (0xFEDCBA98 + (0x12345678 << 2))
    # Expected: 0x47AE1478
    sh2add x10, x10, x1

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
