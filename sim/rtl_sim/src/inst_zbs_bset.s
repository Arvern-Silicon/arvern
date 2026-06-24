#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbs_bset
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BSET (Zbs)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # BSET operation: rd = rs1 | (1 << rs2[4:0])
    # Sets a single bit at the position specified by rs2

    # Test data with various patterns
    li  x1,  0xFFFFFFFF  # All ones
    li  x2,  0x00000000  # All zeros
    li  x3,  0x12345678  # Random pattern
    li  x4,  0xAAAAAAAA  # Alternating bits (10101010...)
    li  x5,  0x55555555  # Alternating bits (01010101...)
    li  x6,  0x80000000  # Only MSB set
    li  x7,  0x00000001  # Only LSB set
    li  x8,  0xF0F0F0F0  # Pattern
    li  x9,  0x0F0F0F0F  # Pattern (inverted)
    li  x10, 0xDEADBEEF  # Mixed pattern

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST BSET (Bit Set) INSTRUCTION
    # Format: bset rd, rs1, rs2
    # Operation: rd = rs1 | (1 << rs2[4:0])
    # Encoding: 0010100 rs2[4:0] rs1[4:0] 001 rd[4:0] 0110011
    # Use case: Set specific bit positions using register
    #-------------------------------------------------

    # Test 1: Set bit 0 from all ones -> bit 0 stays 1
    li  x1, 0xFFFFFFFF
    li  x2, 0
    bset x11, x1, x2
    # Expected: 0xFFFFFFFF

    # Test 2: Set bit 31 from all ones -> bit 31 stays 1
    li  x1, 0xFFFFFFFF
    li  x2, 31
    bset x12, x1, x2
    # Expected: 0xFFFFFFFF

    # Test 3: Set bit 15 from all ones -> bit 15 stays 1
    li  x1, 0xFFFFFFFF
    li  x2, 15
    bset x13, x1, x2
    # Expected: 0xFFFFFFFF

    # Test 4: Set bit 0 from all zeros -> bit 0 becomes 1
    li  x1, 0x00000000
    li  x2, 0
    bset x14, x1, x2
    # Expected: 0x00000001

    # Test 5: Set bit 8 from pattern 0x12345678
    # Bit 8 of 0x12345678 is 0, so it becomes 1
    li  x1, 0x12345678
    li  x2, 8
    bset x15, x1, x2
    # Expected: 0x12345778

    # Test 6: Set bit 10 from 0x12345678
    # Bit 10 of 0x12345678 is 1, so it stays 1
    li  x1, 0x12345678
    li  x2, 10
    bset x16, x1, x2
    # Expected: 0x12345678

    # Test 7: Set bit 4 from 0xAAAAAAAA
    # Bit 4 of 0xAAAAAAAA is 0 (pattern 10101010)
    li  x1, 0xAAAAAAAA
    li  x2, 4
    bset x17, x1, x2
    # Expected: 0xAAAAAABA

    # Test 8: Set bit 7 from 0xAAAAAAAA
    # Bit 7 of 0xAAAAAAAA is 1, stays 1
    li  x1, 0xAAAAAAAA
    li  x2, 7
    bset x18, x1, x2
    # Expected: 0xAAAAAAAA

    # Test 9: Set bit 12 from 0x55555555
    # Bit 12 of 0x55555555 is 1 (pattern 01010101), stays 1
    li  x1, 0x55555555
    li  x2, 12
    bset x19, x1, x2
    # Expected: 0x55555555

    # Test 10: Set bit 16 from 0x55555555
    # Bit 16 of 0x55555555 is 1, stays 1
    li  x1, 0x55555555
    li  x2, 16
    bset x20, x1, x2
    # Expected: 0x55555555

    # Test 11: Set bit 31 from 0x00000000 -> bit 31 becomes 1
    li  x1, 0x00000000
    li  x2, 31
    bset x21, x1, x2
    # Expected: 0x80000000

    # Test 12: Set bit 0 from 0x00000000 -> bit 0 becomes 1
    li  x1, 0x00000000
    li  x2, 0
    bset x22, x1, x2
    # Expected: 0x00000001

    # Test 13: Set bit 7 from 0xF0F0F0F0
    # Bit 7 of 0xF0F0F0F0 is 1 (pattern 11110000), stays 1
    li  x1, 0xF0F0F0F0
    li  x2, 7
    bset x23, x1, x2
    # Expected: 0xF0F0F0F0

    # Test 14: Set bit 3 from 0xF0F0F0F0
    # Bit 3 of 0xF0F0F0F0 is 0, becomes 1
    li  x1, 0xF0F0F0F0
    li  x2, 3
    bset x24, x1, x2
    # Expected: 0xF0F0F0F8

    # Test 15: Set bit 20 from 0x0F0F0F0F
    # Bit 20 of 0x0F0F0F0F is 0 (pattern 00001111), becomes 1
    li  x1, 0x0F0F0F0F
    li  x2, 20
    bset x25, x1, x2
    # Expected: 0x0F1F0F0F

    # Test 16: Set bit 24 from 0x0F0F0F0F
    # Bit 24 of 0x0F0F0F0F is 1, stays 1
    li  x1, 0x0F0F0F0F
    li  x2, 24
    bset x26, x1, x2
    # Expected: 0x0F0F0F0F

    # Test 17: Set bit 1 from 0xDEADBEEF
    # Bit 1 of 0xDEADBEEF is 1, stays 1
    li  x1, 0xDEADBEEF
    li  x2, 1
    bset x27, x1, x2
    # Expected: 0xDEADBEEF

    # Test 18: Set bit 5 from 0xDEADBEEF
    # Bit 5 of 0xDEADBEEF is 1, stays 1
    li  x1, 0xDEADBEEF
    li  x2, 5
    bset x28, x1, x2
    # Expected: 0xDEADBEEF

    # Test 19: Set bit 20 from 0xDEADBEEF
    # Bit 20 of 0xDEADBEEF is 0, becomes 1
    li  x1, 0xDEADBEEF
    li  x2, 20
    bset x29, x1, x2
    # Expected: 0xDEBDBEEF

    # Test 20: Set bit 27 from 0xDEADBEEF
    # Bit 27 of 0xDEADBEEF is 1, stays 1
    li  x1, 0xDEADBEEF
    li  x2, 27
    bset x30, x1, x2
    # Expected: 0xDEADBEEF

    # Test 21-30: Additional edge cases and patterns

    # Test 21: Set bit 1 from all zeros
    li  x1, 0x00000000
    li  x2, 1
    bset x1, x1, x2
    # Expected: 0x00000002

    # Test 22: Set bits 2, 3, 4 sequentially from all zeros
    li  x2, 0x00000000
    li  x3, 2
    bset x2, x2, x3
    li  x3, 3
    bset x2, x2, x3
    li  x3, 4
    bset x2, x2, x3
    # Expected: 0x0000001C (bits 2, 3, 4 set)

    # Test 23: Set bit 30 from pattern
    li  x3, 0x3FFFFFFF
    li  x4, 30
    bset x3, x3, x4
    # Expected: 0x7FFFFFFF

    # Test 24: Set bit 16 from pattern (already set)
    li  x4, 0x12345678
    li  x5, 16
    bset x4, x4, x5
    # Expected: 0x12355678

    # Test 25: Set bit 25 from pattern
    li  x5, 0xA0AAAAAA
    li  x6, 25
    bset x5, x5, x6
    # Expected: 0xA2AAAAAA

    # Test 26: Set bit 0 from pattern (already clear)
    li  x6, 0x55555554
    li  x7, 0
    bset x6, x6, x7
    # Expected: 0x55555555

    # Test 27: Set bit 29 from pattern
    li  x7, 0xD0F0F0F0
    li  x8, 29
    bset x7, x7, x8
    # Expected: 0xF0F0F0F0 (bit 29 is 0, becomes 1)

    # Test 28: Same register for both operands
    # x8 = 0x00000003, so set bit 3
    li  x8, 0x00000003
    bset x8, x8, x8
    # Expected: 0x0000000B (bit 3 set)

    # Test 29: Set bit 17 from pattern
    li  x9, 0x55555555
    li  x10, 17
    bset x9, x9, x10
    # Expected: 0x55575555

    # Test 30: Complex pattern bit set
    li  x10, 0x12345678
    li  x1, 0xFE9CBA98
    li  x2, 22
    bset x10, x1, x2
    # Expected: 0xFEDCBA98 (bit 22 set)

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
