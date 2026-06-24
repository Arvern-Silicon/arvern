#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbs_bext
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BEXT (Zbs)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # BEXT operation: rd = {31'b0, rs1[rs2[4:0]]}
    # Extracts a single bit at the specified position and zero-extends

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
    # TEST BEXT (Bit Extract) INSTRUCTION
    # Format: bext rd, rs1, rs2
    # Operation: rd = {31'b0, rs1[rs2[4:0]]}
    # Encoding: 0100100 rs2[4:0] rs1[4:0] 101 rd[4:0] 0110011
    # Use case: Extract specific bit positions using register
    #-------------------------------------------------

    # Test 1: Extract bit 0 from all ones -> 1
    li  x2, 0
    bext x11, x1, x2
    # Expected: 0x00000001

    # Test 2: Extract bit 31 from all ones -> 1
    li  x2, 31
    bext x12, x1, x2
    # Expected: 0x00000001

    # Test 3: Extract bit 15 from all ones -> 1
    li  x2, 15
    bext x13, x1, x2
    # Expected: 0x00000001

    # Test 4: Extract bit 0 from all zeros -> 0
    li  x1, 0x00000000
    li  x2, 0
    bext x14, x1, x2
    # Expected: 0x00000000

    # Test 5: Extract bit 10 from pattern 0x12345678
    # Bit 10 of 0x12345678 is 1
    li  x1, 0x12345678
    li  x2, 10
    bext x15, x1, x2
    # Expected: 0x00000001

    # Test 6: Extract bit 5 from 0xAAAAAAAA
    # Bit 5 of 0xAAAAAAAA is 1 (pattern 10101010)
    li  x1, 0xAAAAAAAA
    li  x2, 5
    bext x16, x1, x2
    # Expected: 0x00000001

    # Test 7: Extract bit 16 from 0x55555555
    # Bit 16 of 0x55555555 is 1 (pattern 01010101)
    li  x1, 0x55555555
    li  x2, 16
    bext x17, x1, x2
    # Expected: 0x00000001

    # Test 8: Extract bit 7 from 0xF0F0F0F0
    # Bit 7 of 0xF0F0F0F0 is 1 (pattern 11110000)
    li  x1, 0xF0F0F0F0
    li  x2, 7
    bext x18, x1, x2
    # Expected: 0x00000001

    # Test 9: Extract bit 24 from 0x0F0F0F0F
    # Bit 24 of 0x0F0F0F0F is 1 (pattern 00001111)
    li  x1, 0x0F0F0F0F
    li  x2, 24
    bext x19, x1, x2
    # Expected: 0x00000001

    # Test 10: Extract bit 20 from 0xDEADBEEF
    # Bit 20 of 0xDEADBEEF is 0
    li  x1, 0xDEADBEEF
    li  x2, 20
    bext x20, x1, x2
    # Expected: 0x00000000

    # Test 11: Extract bit 0 from all ones
    li  x1, 0xFFFFFFFF
    li  x2, 0
    bext x21, x1, x2
    # Expected: 0x00000001

    # Test 12: Extract bit 31 from MSB only pattern
    li  x1, 0x80000000
    li  x2, 31
    bext x22, x1, x2
    # Expected: 0x00000001

    # Test 13: Extract bit 8 from 0x12345678
    # Bit 8 of 0x12345678 is 0
    li  x1, 0x12345678
    li  x2, 8
    bext x23, x1, x2
    # Expected: 0x00000000

    # Test 14: Extract bit 4 from 0xAAAAAAAA
    # Bit 4 of 0xAAAAAAAA is 0
    li  x1, 0xAAAAAAAA
    li  x2, 4
    bext x24, x1, x2
    # Expected: 0x00000000

    # Test 15: Extract bit 12 from 0x55555555
    # Bit 12 of 0x55555555 is 1
    li  x1, 0x55555555
    li  x2, 12
    bext x25, x1, x2
    # Expected: 0x00000001

    # Test 16: Extract bit 3 from 0xF0F0F0F0
    # Bit 3 of 0xF0F0F0F0 is 0
    li  x1, 0xF0F0F0F0
    li  x2, 3
    bext x26, x1, x2
    # Expected: 0x00000000

    # Test 17: Extract bit 20 from 0x0F0F0F0F
    # Bit 20 of 0x0F0F0F0F is 0
    li  x1, 0x0F0F0F0F
    li  x2, 20
    bext x27, x1, x2
    # Expected: 0x00000000

    # Test 18: Extract bit 1 from 0xDEADBEEF
    # Bit 1 of 0xDEADBEEF is 1
    li  x1, 0xDEADBEEF
    li  x2, 1
    bext x28, x1, x2
    # Expected: 0x00000001

    # Test 19: Extract bit 27 from 0x87654321
    # Bit 27 of 0x87654321 is 0
    li  x1, 0x87654321
    li  x2, 27
    bext x29, x1, x2
    # Expected: 0x00000000

    # Test 20: Extract bit 16 from 0xABCDEF01
    # Bit 16 of 0xABCDEF01 is 1
    li  x1, 0xABCDEF01
    li  x2, 16
    bext x30, x1, x2
    # Expected: 0x00000001

    # Test 21-30: Additional edge cases

    # Test 21: Extract bit using position > 31 (should use only lower 5 bits)
    li  x1, 0xFFFFFFFF
    li  x2, 32  # Same as position 0
    bext x1, x1, x2
    # Expected: 0x00000001

    # Test 22: Extract bit 4 from pattern
    li  x2, 0x12345678
    li  x3, 4
    bext x2, x2, x3
    # Expected: 0x00000001

    # Test 23: Extract from single bit value at bit 0
    li  x3, 0x00000001
    li  x4, 0
    bext x3, x3, x4
    # Expected: 0x00000001

    # Test 24: Extract from MSB only at bit 30
    li  x4, 0x80000000
    li  x5, 30
    bext x4, x4, x5
    # Expected: 0x00000000

    # Test 25: Extract bit 3 from pattern
    li  x5, 0x12345678
    li  x6, 3
    bext x5, x5, x6
    # Expected: 0x00000001

    # Test 26: Same register for src and dest
    li  x6, 0xFFFF0000
    li  x7, 16
    bext x6, x6, x7
    # Expected: 0x00000001

    # Test 27: Extract from zero (always returns 0)
    li  x7, 0x00000000
    li  x8, 15
    bext x7, x7, x8
    # Expected: 0x00000000

    # Test 28: Extract bit 30 from max signed positive
    li  x8, 0x7FFFFFFF
    li  x9, 30
    bext x8, x8, x9
    # Expected: 0x00000001

    # Test 29: Extract bit 15 from pattern
    li  x9, 0xF0F0F0F0
    li  x10, 15
    bext x9, x9, x10
    # Expected: 0x00000001

    # Test 30: Extract bit 17 from pattern
    li  x10, 0x55AA55AA
    li  x31, 17
    bext x10, x10, x31
    # Expected: 0x00000001

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
