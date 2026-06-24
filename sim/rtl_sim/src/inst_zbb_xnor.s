#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_xnor
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: XNOR (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # XNOR operation: rd = ~(rs1 ^ rs2) = rs1 XNOR rs2
    # This is useful for bitwise equality checking and inverted XOR operations

    li  x1,  0xFFFFFFFF  # All 1s
    li  x2,  0x00000000  # All 0s
    li  x3,  0xAAAAAAAA  # Alternating pattern 10101010...
    li  x4,  0x55555555  # Alternating pattern 01010101...
    li  x5,  0xF0F0F0F0  # Nibble pattern
    li  x6,  0x0F0F0F0F  # Inverted nibble pattern
    li  x7,  0xFF00FF00  # Byte pattern
    li  x8,  0x00FF00FF  # Inverted byte pattern
    li  x9,  0x12345678  # Test data 1
    li  x10, 0xFEDCBA98  # Test data 2
    li  x11, 0x0000FFFF  # Lower halfword all 1s
    li  x12, 0xFFFF0000  # Upper halfword all 1s

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST XNOR (Exclusive-NOR) INSTRUCTION
    # Format: xnor rd, rs1, rs2
    # Operation: rd = ~(rs1 ^ rs2)
    # Encoding: 0100000 rs2[4:0] rs1[4:0] 100 rd[4:0] 0110011
    # Use case: Bitwise equality checking, inverted XOR
    #-------------------------------------------------

    # Test 1: XNOR with same value (equality) - all bits match
    # xnor x13, x1 (all 1s), x1 (all 1s)
    # Expected: ~(0xFFFFFFFF ^ 0xFFFFFFFF) = ~0x00000000 = 0xFFFFFFFF
    xnor x13, x1, x1

    # Test 2: XNOR with all 0s vs all 1s (complete difference)
    # xnor x14, x1 (all 1s), x2 (all 0s)
    # Expected: ~(0xFFFFFFFF ^ 0x00000000) = ~0xFFFFFFFF = 0x00000000
    xnor x14, x1, x2

    # Test 3: XNOR with zero and itself
    # xnor x15, x2 (all 0s), x2 (all 0s)
    # Expected: ~(0x00000000 ^ 0x00000000) = ~0x00000000 = 0xFFFFFFFF
    xnor x15, x2, x2

    # Test 4: Alternating patterns (complementary)
    # xnor x16, x3 (0xAAAAAAAA), x4 (0x55555555)
    # Expected: ~(0xAAAAAAAA ^ 0x55555555) = ~0xFFFFFFFF = 0x00000000
    xnor x16, x3, x4

    # Test 5: Same alternating pattern
    # xnor x17, x3 (0xAAAAAAAA), x3 (0xAAAAAAAA)
    # Expected: ~(0xAAAAAAAA ^ 0xAAAAAAAA) = ~0x00000000 = 0xFFFFFFFF
    xnor x17, x3, x3

    # Test 6: Reverse pattern
    # xnor x18, x4 (0x55555555), x4 (0x55555555)
    # Expected: ~(0x55555555 ^ 0x55555555) = ~0x00000000 = 0xFFFFFFFF
    xnor x18, x4, x4

    # Test 7: Nibble patterns (complementary)
    # xnor x19, x5 (0xF0F0F0F0), x6 (0x0F0F0F0F)
    # Expected: ~(0xF0F0F0F0 ^ 0x0F0F0F0F) = ~0xFFFFFFFF = 0x00000000
    xnor x19, x5, x6

    # Test 8: Byte patterns (complementary)
    # xnor x20, x7 (0xFF00FF00), x8 (0x00FF00FF)
    # Expected: ~(0xFF00FF00 ^ 0x00FF00FF) = ~0xFFFFFFFF = 0x00000000
    xnor x20, x7, x8

    # Test 9: Mixed data XOR
    # xnor x21, x9 (0x12345678), x10 (0xFEDCBA98)
    # Expected: ~(0x12345678 ^ 0xFEDCBA98) = ~0xECE8ECE0 = 0x1317131F
    xnor x21, x9, x10

    # Test 10: XNOR with zero (inverts the value)
    # xnor x22, x9 (0x12345678), x2 (0x00000000)
    # Expected: ~(0x12345678 ^ 0x00000000) = ~0x12345678 = 0xEDCBA987
    xnor x22, x9, x2

    # Test 11: XNOR with all 1s (inverts the value)
    # xnor x23, x9 (0x12345678), x1 (0xFFFFFFFF)
    # Expected: ~(0x12345678 ^ 0xFFFFFFFF) = ~0xEDCBA987 = 0x12345678
    xnor x23, x9, x1

    # Test 12: Same register for rs1 and rd
    li   x24, 0xF00F0FF0
    li   x25, 0x0FF0F00F
    # xnor x24, x24 (0xF00F0FF0), x25 (0x0FF0F00F)
    # Expected: ~(0xF00F0FF0 ^ 0x0FF0F00F) = ~0xFFFFFFFF = 0x00000000
    xnor x24, x24, x25

    # Test 13: Verify XNOR is different from XOR
    # XOR:  0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF (all different bits)
    # XNOR: ~(0xAAAAAAAA ^ 0x55555555) = 0x00000000 (inverted XOR)
    xor  x26, x3, x4    # XOR result for comparison
    xnor x27, x3, x4    # XNOR result

    # Test 14: Practical use - partial equality check
    li   x28, 0xDEADBEEF
    li   x29, 0xDEADBEEF
    # xnor x30, x28 (0xDEADBEEF), x29 (0xDEADBEEF)
    # Expected: ~(0xDEADBEEF ^ 0xDEADBEEF) = ~0x00000000 = 0xFFFFFFFF (equal)
    xnor x30, x28, x29

    # Test 15: Partial difference
    li   x1, 0xDEADBEEF
    li   x2, 0xDEADBEE0  # Last nibble different
    # xnor x3, x1 (0xDEADBEEF), x2 (0xDEADBEE0)
    # Expected: ~(0xDEADBEEF ^ 0xDEADBEE0) = ~0x0000000F = 0xFFFFFFF0
    xnor x3, x1, x2

    # Test 16: Commutative property verification
    li   x4, 0xABCD1234
    li   x5, 0x56789ABC
    # xnor x6, x4, x5
    # Expected: ~(0xABCD1234 ^ 0x56789ABC) = ~0xFDB58E88 = 0x024A7177
    xnor x6, x4, x5
    # xnor x7, x5, x4 (reversed operands, should give same result)
    xnor x7, x5, x4

    # Test 17: Single bit difference detection
    li   x8, 0x80000000  # Bit 31 set
    li   x9, 0x00000000  # All clear
    # xnor x10, x8 (0x80000000), x9 (0x00000000)
    # Expected: ~(0x80000000 ^ 0x00000000) = ~0x80000000 = 0x7FFFFFFF
    xnor x10, x8, x9

    # Test 18: Multi-bit pattern
    li   x11, 0x5A5A5A5A  # 01011010 pattern
    li   x12, 0xA5A5A5A5  # 10100101 pattern (complement)
    # xnor x13, x11 (0x5A5A5A5A), x12 (0xA5A5A5A5)
    # Expected: ~(0x5A5A5A5A ^ 0xA5A5A5A5) = ~0xFFFFFFFF = 0x00000000
    xnor x13, x11, x12

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
