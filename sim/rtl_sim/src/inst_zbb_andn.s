#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_andn
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ANDN (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # ANDN operation: rd = rs1 & ~rs2
    # This is useful for clearing specific bits in rs1 based on mask in rs2

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
    # TEST ANDN (AND-NOT) INSTRUCTION
    # Format: andn rd, rs1, rs2
    # Operation: rd = rs1 & ~rs2
    # Encoding: 0100000 rs2[4:0] rs1[4:0] 111 rd[4:0] 0110011
    # Use case: Clear bits in rs1 where rs2 has 1s (mask clearing)
    #-------------------------------------------------

    # Test 1: Basic functionality - clear all bits
    # andn x13, x1 (all 1s), x1 (all 1s)
    # Expected: 0xFFFFFFFF & ~0xFFFFFFFF = 0xFFFFFFFF & 0x00000000 = 0x00000000
    andn x13, x1, x1

    # Test 2: Identity - clear no bits
    # andn x14, x1 (all 1s), x2 (all 0s)
    # Expected: 0xFFFFFFFF & ~0x00000000 = 0xFFFFFFFF & 0xFFFFFFFF = 0xFFFFFFFF
    andn x14, x1, x2

    # Test 3: Zero operand
    # andn x15, x2 (all 0s), x1 (all 1s)
    # Expected: 0x00000000 & ~0xFFFFFFFF = 0x00000000 & 0x00000000 = 0x00000000
    andn x15, x2, x1

    # Test 4: Alternating patterns
    # andn x16, x3 (0xAAAAAAAA), x4 (0x55555555)
    # Expected: 0xAAAAAAAA & ~0x55555555 = 0xAAAAAAAA & 0xAAAAAAAA = 0xAAAAAAAA
    andn x16, x3, x4

    # Test 5: Reverse alternating patterns
    # andn x17, x4 (0x55555555), x3 (0xAAAAAAAA)
    # Expected: 0x55555555 & ~0xAAAAAAAA = 0x55555555 & 0x55555555 = 0x55555555
    andn x17, x4, x3

    # Test 6: Nibble patterns
    # andn x18, x5 (0xF0F0F0F0), x6 (0x0F0F0F0F)
    # Expected: 0xF0F0F0F0 & ~0x0F0F0F0F = 0xF0F0F0F0 & 0xF0F0F0F0 = 0xF0F0F0F0
    andn x18, x5, x6

    # Test 7: Byte patterns
    # andn x19, x7 (0xFF00FF00), x8 (0x00FF00FF)
    # Expected: 0xFF00FF00 & ~0x00FF00FF = 0xFF00FF00 & 0xFF00FF00 = 0xFF00FF00
    andn x19, x7, x8

    # Test 8: Mixed data - clear specific bits
    # andn x20, x9 (0x12345678), x11 (0x0000FFFF)
    # Expected: 0x12345678 & ~0x0000FFFF = 0x12345678 & 0xFFFF0000 = 0x12340000
    andn x20, x9, x11

    # Test 9: Mixed data - clear upper bits
    # andn x21, x10 (0xFEDCBA98), x12 (0xFFFF0000)
    # Expected: 0xFEDCBA98 & ~0xFFFF0000 = 0xFEDCBA98 & 0x0000FFFF = 0x0000BA98
    andn x21, x10, x12

    # Test 10: Same register for rs1 and rd
    li   x22, 0xF00F0FF0
    li   x23, 0x0FF00F0F
    # andn x22, x22 (0xF00F0FF0), x23 (0x0FF00F0F)
    # Expected: 0xF00F0FF0 & ~0x0FF00F0F = 0xF00F0FF0 & 0xF00FF0F0 = 0xF00F00F0
    andn x22, x22, x23

    # Test 11: Verify ANDN is different from AND
    # AND: 0xAAAAAAAA & 0x55555555 = 0x00000000 (no common bits)
    # ANDN: 0xAAAAAAAA & ~0x55555555 = 0xAAAAAAAA & 0xAAAAAAAA = 0xAAAAAAAA
    and  x24, x3, x4    # AND result for comparison
    andn x25, x3, x4    # ANDN result

    # Test 12: Practical use - clear bit mask
    li   x26, 0xDEADBEEF
    li   x27, 0x00F0F000  # Mask to clear certain bits
    # andn x28, x26 (0xDEADBEEF), x27 (0x00F0F000)
    # Expected: 0xDEADBEEF & ~0x00F0F000 = 0xDEADBEEF & 0xFF0F0FFF = 0xDE0D0EEF
    andn x28, x26, x27

    # Test 13: Single bit operations
    li   x29, 0x80000000  # Bit 31 set
    li   x30, 0x00000001  # Bit 0 set
    # andn x1, x1 (0xFFFFFFFF), x29 (0x80000000)
    # Expected: 0xFFFFFFFF & ~0x80000000 = 0xFFFFFFFF & 0x7FFFFFFF = 0x7FFFFFFF
    andn x1, x1, x29

    # andn x2, x1 (0x7FFFFFFF), x30 (0x00000001)
    # Expected: 0x7FFFFFFF & ~0x00000001 = 0x7FFFFFFF & 0xFFFFFFFE = 0x7FFFFFFE
    andn x2, x1, x30

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
