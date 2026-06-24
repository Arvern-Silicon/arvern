#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zba_sh3add
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SH3ADD (Zba)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # SH3ADD operation: rd = rs2 + (rs1 << 3)
    # Useful for doubleword array indexing (base_address + index * 8)

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
    # TEST SH3ADD (Shift-Left-3 and Add) INSTRUCTION
    # Format: sh3add rd, rs1, rs2
    # Operation: rd = rs2 + (rs1 << 3)
    # Encoding: 0010000 rs2[4:0] rs1[4:0] 110 rd[4:0] 0110011
    # Use case: Array indexing for doublewords (8-byte elements)
    #-------------------------------------------------

    # Test 1: Zero base, zero index -> 0x00000000 + (0x00000000 << 3)
    # sh3add x11, x1, x1
    # Expected: 0x00000000
    sh3add x11, x1, x1

    # Test 2: Base address + index 1 -> 0x10000000 + (0x00000001 << 3)
    # sh3add x12, x3, x2
    # Expected: 0x10000008
    sh3add x12, x3, x2

    # Test 3: Base address + index 5 -> 0x10000000 + (0x00000005 << 3)
    # sh3add x13, x4, x2
    # Expected: 0x10000028
    sh3add x13, x4, x2

    # Test 4: Base address + index 10 -> 0x10000000 + (0x0000000A << 3)
    # sh3add x14, x5, x2
    # Expected: 0x10000050
    sh3add x14, x5, x2

    # Test 5: Zero base + index 256 -> 0x00000000 + (0x00000100 << 3)
    # sh3add x15, x10, x1
    # Expected: 0x00000800
    sh3add x15, x10, x1

    # Test 6: All ones + all ones -> 0xFFFFFFFF + (0xFFFFFFFF << 3)
    # sh3add x16, x6, x6
    # Expected: 0xFFFFFFF7 (overflow wraps)
    sh3add x16, x6, x6

    # Test 7: Random pattern base + index 1
    # sh3add x17, x3, x7 (0x12345678 + (0x00000001 << 3))
    # Expected: 0x12345680
    sh3add x17, x3, x7

    # Test 8: Max positive + index 1 -> 0x7FFFFFFF + (0x00000001 << 3)
    # sh3add x18, x3, x9
    # Expected: 0x80000007 (overflow to negative)
    sh3add x18, x3, x9

    # Test 9: Max negative + index 1 -> 0x80000000 + (0x00000001 << 3)
    # sh3add x19, x3, x8
    # Expected: 0x80000008
    sh3add x19, x3, x8

    # Test 10: Index pattern with zero base
    # sh3add x20, x7, x1 (0x00000000 + (0x12345678 << 3))
    # Expected: 0x91A2B3C0
    sh3add x20, x7, x1

    # Test 11: Larger index value
    li  x1, 0x00001000
    li  x2, 0x20000000
    # sh3add x21, x1, x2 (0x20000000 + (0x00001000 << 3))
    # Expected: 0x20008000
    sh3add x21, x1, x2

    # Test 12: Index that will overflow when shifted
    li  x1, 0x20000000
    li  x2, 0x00000100
    # sh3add x22, x1, x2 (0x00000100 + (0x20000000 << 3))
    # Expected: 0x00000100 (shift creates 0x00000000, overflow wraps)
    sh3add x22, x1, x2

    # Test 13: Negative base, positive index
    li  x1, 0x00000010
    li  x2, 0xFFFF0000
    # sh3add x23, x1, x2 (0xFFFF0000 + (0x00000010 << 3))
    # Expected: 0xFFFF0080
    sh3add x23, x1, x2

    # Test 14: Small values
    li  x1, 0x00000002
    li  x2, 0x00000008
    # sh3add x24, x1, x2 (0x00000008 + (0x00000002 << 3))
    # Expected: 0x00000018
    sh3add x24, x1, x2

    # Test 15: Pattern with alternating bits
    li  x1, 0xAAAAAAAA
    li  x2, 0x55555555
    # sh3add x25, x1, x2 (0x55555555 + (0xAAAAAAAA << 3))
    # Expected: 0xAAAAAAA5
    sh3add x25, x1, x2

    # Test 16: One operand zero
    li  x1, 0x00000000
    li  x2, 0x12345678
    # sh3add x26, x1, x2 (0x12345678 + (0x00000000 << 3))
    # Expected: 0x12345678
    sh3add x26, x1, x2

    # Test 17: Large index value
    li  x1, 0x0FFFFFFF
    li  x2, 0x00000008
    # sh3add x27, x1, x2 (0x00000008 + (0x0FFFFFFF << 3))
    # Expected: 0x80000000
    sh3add x27, x1, x2

    # Test 18: Index causing shift to highest bits
    li  x1, 0x10000000
    li  x2, 0x00000000
    # sh3add x28, x1, x2 (0x00000000 + (0x10000000 << 3))
    # Expected: 0x80000000
    sh3add x28, x1, x2

    # Test 19: Both operands with high bits set
    li  x1, 0xE0000000
    li  x2, 0x80000000
    # sh3add x29, x1, x2 (0x80000000 + (0xE0000000 << 3))
    # Expected: 0x80000000 (complete overflow)
    sh3add x29, x1, x2

    # Test 20: Sequential pattern
    li  x1, 0x01020304
    li  x2, 0x05060708
    # sh3add x30, x1, x2 (0x05060708 + (0x01020304 << 3))
    # Expected: 0x0D161F28
    sh3add x30, x1, x2

    # Test 21: Base with low bits set, index shifts to align
    li  x1, 0x00000007
    li  x2, 0x00000001
    # sh3add x1, x1, x2 (0x00000001 + (0x00000007 << 3))
    # Expected: 0x00000039
    sh3add x1, x1, x2

    # Test 22: Typical array access pattern
    li  x2, 0x20000000  # Base address
    li  x3, 0x0000000A  # Index 10
    # sh3add x2, x3, x2 (0x20000000 + (0x0000000A << 3))
    # Expected: 0x20000050
    sh3add x2, x3, x2

    # Test 23: Index = 1, base = 0xFFFFFFF8
    li  x3, 0x00000001
    li  x4, 0xFFFFFFF8
    # sh3add x3, x3, x4 (0xFFFFFFF8 + (0x00000001 << 3))
    # Expected: 0x00000000
    sh3add x3, x3, x4

    # Test 24: Power of 2 index
    li  x4, 0x00000200
    li  x5, 0x10000000
    # sh3add x4, x4, x5 (0x10000000 + (0x00000200 << 3))
    # Expected: 0x10001000
    sh3add x4, x4, x5

    # Test 25: Index with only LSB set
    li  x5, 0x00000001
    li  x6, 0xABCDEF00
    # sh3add x5, x5, x6 (0xABCDEF00 + (0x00000001 << 3))
    # Expected: 0xABCDEF08
    sh3add x5, x5, x6

    # Test 26: Negative index (two's complement)
    li  x6, 0xFFFFFFF0  # -16
    li  x7, 0x00000100
    # sh3add x6, x6, x7 (0x00000100 + (0xFFFFFFF0 << 3))
    # Expected: 0x00000080
    sh3add x6, x6, x7

    # Test 27: Index = max positive / 8, base = 8
    li  x7, 0x0FFFFFFF
    li  x8, 0x00000008
    # sh3add x7, x7, x8 (0x00000008 + (0x0FFFFFFF << 3))
    # Expected: 0x80000000
    sh3add x7, x7, x8

    # Test 28: Same register for both operands
    li  x8, 0x00000003
    # sh3add x8, x8, x8 (0x00000003 + (0x00000003 << 3))
    # Expected: 0x0000001B
    sh3add x8, x8, x8

    # Test 29: Index with alternating bits
    li  x9, 0x55555555
    li  x10, 0x00000000
    # sh3add x9, x9, x10 (0x00000000 + (0x55555555 << 3))
    # Expected: 0xAAAAAAA8
    sh3add x9, x9, x10

    # Test 30: Complex pattern
    li  x10, 0x12345678
    li  x1, 0xFEDCBA98
    # sh3add x10, x10, x1 (0xFEDCBA98 + (0x12345678 << 3))
    # Expected: 0x907F6E58
    sh3add x10, x10, x1

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
