#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbs_binv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BINV (Zbs)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # BINV operation: rd = rs1 ^ (1 << rs2[4:0])
    # Inverts (toggles) a single bit at the position specified by rs2

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
    # TEST BINV (Bit Invert) INSTRUCTION
    # Format: binv rd, rs1, rs2
    # Operation: rd = rs1 ^ (1 << rs2[4:0])
    # Encoding: 0110100 rs2[4:0] rs1[4:0] 001 rd[4:0] 0110011
    # Use case: Toggle specific bit positions using register
    #-------------------------------------------------

    # Test 1: Invert bit 0 from all ones -> bit 0 becomes 0
    li  x1, 0xFFFFFFFF
    li  x2, 0
    binv x11, x1, x2
    # Expected: 0xFFFFFFFE

    # Test 2: Invert bit 31 from all ones -> bit 31 becomes 0
    li  x1, 0xFFFFFFFF
    li  x2, 31
    binv x12, x1, x2
    # Expected: 0x7FFFFFFF

    # Test 3: Invert bit 15 from all ones -> bit 15 becomes 0
    li  x1, 0xFFFFFFFF
    li  x2, 15
    binv x13, x1, x2
    # Expected: 0xFFFF7FFF

    # Test 4: Invert bit 0 from all zeros -> bit 0 becomes 1
    li  x1, 0x00000000
    li  x2, 0
    binv x14, x1, x2
    # Expected: 0x00000001

    # Test 5: Invert bit 8 from pattern 0x12345678
    # Bit 8 of 0x12345678 is 0, so it becomes 1
    li  x1, 0x12345678
    li  x2, 8
    binv x15, x1, x2
    # Expected: 0x12345778

    # Test 6: Invert bit 10 from 0x12345678
    # Bit 10 of 0x12345678 is 1, so it becomes 0
    li  x1, 0x12345678
    li  x2, 10
    binv x16, x1, x2
    # Expected: 0x12345278

    # Test 7: Invert bit 4 from 0xAAAAAAAA
    # Bit 4 of 0xAAAAAAAA is 0 (pattern 10101010)
    li  x1, 0xAAAAAAAA
    li  x2, 4
    binv x17, x1, x2
    # Expected: 0xAAAAAABA

    # Test 8: Invert bit 7 from 0xAAAAAAAA
    # Bit 7 of 0xAAAAAAAA is 1
    li  x1, 0xAAAAAAAA
    li  x2, 7
    binv x18, x1, x2
    # Expected: 0xAAAAAA2A

    # Test 9: Invert bit 12 from 0x55555555
    # Bit 12 of 0x55555555 is 1 (pattern 01010101)
    li  x1, 0x55555555
    li  x2, 12
    binv x19, x1, x2
    # Expected: 0x55554555

    # Test 10: Invert bit 16 from 0x55555555
    # Bit 16 of 0x55555555 is 1
    li  x1, 0x55555555
    li  x2, 16
    binv x20, x1, x2
    # Expected: 0x55545555

    # Test 11: Invert bit 31 from 0x80000000 -> bit 31 becomes 0
    li  x1, 0x80000000
    li  x2, 31
    binv x21, x1, x2
    # Expected: 0x00000000

    # Test 12: Invert bit 0 from 0x00000001 -> bit 0 becomes 0
    li  x1, 0x00000001
    li  x2, 0
    binv x22, x1, x2
    # Expected: 0x00000000

    # Test 13: Invert bit 7 from 0xF0F0F0F0
    # Bit 7 of 0xF0F0F0F0 is 1 (pattern 11110000)
    li  x1, 0xF0F0F0F0
    li  x2, 7
    binv x23, x1, x2
    # Expected: 0xF0F0F070

    # Test 14: Invert bit 3 from 0xF0F0F0F0
    # Bit 3 of 0xF0F0F0F0 is 0
    li  x1, 0xF0F0F0F0
    li  x2, 3
    binv x24, x1, x2
    # Expected: 0xF0F0F0F8

    # Test 15: Invert bit 20 from 0x0F0F0F0F
    # Bit 20 of 0x0F0F0F0F is 0 (pattern 00001111)
    li  x1, 0x0F0F0F0F
    li  x2, 20
    binv x25, x1, x2
    # Expected: 0x0F1F0F0F

    # Test 16: Invert bit 24 from 0x0F0F0F0F
    # Bit 24 of 0x0F0F0F0F is 1
    li  x1, 0x0F0F0F0F
    li  x2, 24
    binv x26, x1, x2
    # Expected: 0x0E0F0F0F

    # Test 17: Invert bit 1 from 0xDEADBEEF
    # Bit 1 of 0xDEADBEEF is 1
    li  x1, 0xDEADBEEF
    li  x2, 1
    binv x27, x1, x2
    # Expected: 0xDEADBEED

    # Test 18: Invert bit 5 from 0xDEADBEEF
    # Bit 5 of 0xDEADBEEF is 1
    li  x1, 0xDEADBEEF
    li  x2, 5
    binv x28, x1, x2
    # Expected: 0xDEADBECF

    # Test 19: Invert bit 20 from 0xDEADBEEF
    # Bit 20 of 0xDEADBEEF is 0
    li  x1, 0xDEADBEEF
    li  x2, 20
    binv x29, x1, x2
    # Expected: 0xDEBDBEEF

    # Test 20: Invert bit 27 from 0xDEADBEEF
    # Bit 27 of 0xDEADBEEF is 1
    li  x1, 0xDEADBEEF
    li  x2, 27
    binv x30, x1, x2
    # Expected: 0xD6ADBEEF

    # Test 21-30: Additional edge cases and patterns

    # Test 21: Invert bit 1 from all ones
    li  x1, 0xFFFFFFFF
    li  x2, 1
    binv x1, x1, x2
    # Expected: 0xFFFFFFFD

    # Test 22: Invert bits 2, 3, 4 sequentially from all zeros
    li  x2, 0x00000000
    li  x3, 2
    binv x2, x2, x3
    li  x3, 3
    binv x2, x2, x3
    li  x3, 4
    binv x2, x2, x3
    # Expected: 0x0000001C (bits 2, 3, 4 set)

    # Test 23: Invert bit 30 from pattern
    li  x3, 0x7FFFFFFF
    li  x4, 30
    binv x3, x3, x4
    # Expected: 0x3FFFFFFF

    # Test 24: Invert bit 16 from pattern
    li  x4, 0x12345678
    li  x5, 16
    binv x4, x4, x5
    # Expected: 0x12355678

    # Test 25: Invert bit 25 from pattern
    li  x5, 0xAAAAAAAA
    li  x6, 25
    binv x5, x5, x6
    # Expected: 0xAAAAAAA  (bit 25 is 1, becomes 0)

    # Test 26: Invert bit 0 from pattern
    li  x6, 0x55555555
    li  x7, 0
    binv x6, x6, x7
    # Expected: 0x55555554

    # Test 27: Invert bit 29 from pattern
    li  x7, 0xF0F0F0F0
    li  x8, 29
    binv x7, x7, x8
    # Expected: 0xD0F0F0F0

    # Test 28: Same register for both operands
    # x8 = 0x00000003, so invert bit 3
    li  x8, 0x00000003
    binv x8, x8, x8
    # Expected: 0x0000000B (bit 3 inverted)

    # Test 29: Invert bit with position from alternating bits
    li  x9, 0x55555555
    li  x10, 17
    binv x9, x9, x10
    # Expected: 0x55575555 (bit 17 is 1, becomes 0)

    # Test 30: Complex pattern inversion
    li  x10, 0x12345678
    li  x1, 0xFEDCBA98
    li  x2, 22
    binv x10, x1, x2
    # Expected: 0xFEDCBA98 ^ (1 << 22) = 0xFE9CBA98

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
