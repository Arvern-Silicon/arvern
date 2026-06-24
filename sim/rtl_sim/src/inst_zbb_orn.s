#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_orn
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ORN (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # ORN operation: rd = rs1 | ~rs2
    # This is useful for setting specific bits in rs1 based on inverted mask in rs2

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
    # TEST ORN (OR-NOT) INSTRUCTION
    # Format: orn rd, rs1, rs2
    # Operation: rd = rs1 | ~rs2
    # Encoding: 0100000 rs2[4:0] rs1[4:0] 110 rd[4:0] 0110011
    # Use case: Set bits in rs1 where rs2 has 0s (inverted mask setting)
    #-------------------------------------------------

    # Test 1: Basic functionality - all 1s result
    # orn x13, x1 (all 1s), x2 (all 0s)
    # Expected: 0xFFFFFFFF | ~0x00000000 = 0xFFFFFFFF | 0xFFFFFFFF = 0xFFFFFFFF
    orn x13, x1, x2

    # Test 2: All 1s due to inverted mask
    # orn x14, x2 (all 0s), x2 (all 0s)
    # Expected: 0x00000000 | ~0x00000000 = 0x00000000 | 0xFFFFFFFF = 0xFFFFFFFF
    orn x14, x2, x2

    # Test 3: Identity when rs2 is all 1s
    # orn x15, x1 (all 1s), x1 (all 1s)
    # Expected: 0xFFFFFFFF | ~0xFFFFFFFF = 0xFFFFFFFF | 0x00000000 = 0xFFFFFFFF
    orn x15, x1, x1

    # Test 4: Zero result only if rs1=0 and rs2=all 1s
    # orn x16, x2 (all 0s), x1 (all 1s)
    # Expected: 0x00000000 | ~0xFFFFFFFF = 0x00000000 | 0x00000000 = 0x00000000
    orn x16, x2, x1

    # Test 5: Alternating patterns
    # orn x17, x3 (0xAAAAAAAA), x4 (0x55555555)
    # Expected: 0xAAAAAAAA | ~0x55555555 = 0xAAAAAAAA | 0xAAAAAAAA = 0xAAAAAAAA
    orn x17, x3, x4

    # Test 6: Reverse alternating patterns
    # orn x18, x4 (0x55555555), x3 (0xAAAAAAAA)
    # Expected: 0x55555555 | ~0xAAAAAAAA = 0x55555555 | 0x55555555 = 0x55555555
    orn x18, x4, x3

    # Test 7: Nibble patterns
    # orn x19, x5 (0xF0F0F0F0), x6 (0x0F0F0F0F)
    # Expected: 0xF0F0F0F0 | ~0x0F0F0F0F = 0xF0F0F0F0 | 0xF0F0F0F0 = 0xF0F0F0F0
    orn x19, x5, x6

    # Test 8: Byte patterns
    # orn x20, x7 (0xFF00FF00), x8 (0x00FF00FF)
    # Expected: 0xFF00FF00 | ~0x00FF00FF = 0xFF00FF00 | 0xFF00FF00 = 0xFF00FF00
    orn x20, x7, x8

    # Test 9: Mixed data - set specific bits via inverted mask
    # orn x21, x9 (0x12345678), x11 (0x0000FFFF)
    # Expected: 0x12345678 | ~0x0000FFFF = 0x12345678 | 0xFFFF0000 = 0xFFFF5678
    orn x21, x9, x11

    # Test 10: Mixed data - set upper bits via inverted mask
    # orn x22, x10 (0xFEDCBA98), x12 (0xFFFF0000)
    # Expected: 0xFEDCBA98 | ~0xFFFF0000 = 0xFEDCBA98 | 0x0000FFFF = 0xFEDCFFFF
    orn x22, x10, x12

    # Test 11: Same register for rs1 and rd
    li   x23, 0x0FF000FF
    li   x24, 0xF00FF00F
    # orn x23, x23 (0x0FF000FF), x24 (0xF00FF00F)
    # Expected: 0x0FF000FF | ~0xF00FF00F = 0x0FF000FF | 0x0FF00FF0 = 0x0FF00FFF
    orn x23, x23, x24

    # Test 12: Verify ORN is different from OR
    # OR: 0xAAAAAAAA | 0x55555555 = 0xFFFFFFFF (all bits set)
    # ORN: 0xAAAAAAAA | ~0x55555555 = 0xAAAAAAAA | 0xAAAAAAAA = 0xAAAAAAAA
    or   x25, x3, x4    # OR result for comparison
    orn  x26, x3, x4    # ORN result

    # Test 13: Practical use - set bits via inverted mask
    li   x27, 0x00001000
    li   x28, 0xFF0F0FFF  # Mask where 0s indicate bits to set
    # orn x29, x27 (0x00001000), x28 (0xFF0F0FFF)
    # Expected: 0x00001000 | ~0xFF0F0FFF = 0x00001000 | 0x00F0F000 = 0x00F0F000
    orn x29, x27, x28

    # Test 14: Single bit operations
    li   x30, 0x7FFFFFFF  # All bits except bit 31
    li   x1,  0x7FFFFFFF  # Bit 31 clear
    # orn x2, x30 (0x7FFFFFFF), x1 (0x7FFFFFFF)
    # Expected: 0x7FFFFFFF | ~0x7FFFFFFF = 0x7FFFFFFF | 0x80000000 = 0xFFFFFFFF
    orn x2, x30, x1

    # Test 15: Edge case - alternating with zero
    li   x3, 0x00000000
    li   x4, 0xF0F0F0F0
    # orn x5, x3 (0x00000000), x4 (0xF0F0F0F0)
    # Expected: 0x00000000 | ~0xF0F0F0F0 = 0x00000000 | 0x0F0F0F0F = 0x0F0F0F0F
    orn x5, x3, x4

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
