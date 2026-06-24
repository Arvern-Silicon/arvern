#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbs_bexti
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BEXTI (Zbs)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # BEXTI operation: rd = {31'b0, rs1[imm[4:0]]}
    # Extracts a single bit at the specified immediate position and zero-extends

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
    # TEST BEXTI (Bit Extract Immediate) INSTRUCTION
    # Format: bexti rd, rs1, imm
    # Operation: rd = {31'b0, rs1[imm[4:0]]}
    # Encoding: 0100100 imm[4:0] rs1[4:0] 101 rd[4:0] 0010011
    # Use case: Extract specific bit positions using immediate
    #-------------------------------------------------

    # Test 1: Extract bit 0 from all ones -> 1
    bexti x11, x1, 0
    # Expected: 0x00000001

    # Test 2: Extract bit 31 from all ones -> 1
    bexti x12, x1, 31
    # Expected: 0x00000001

    # Test 3: Extract bit 15 from all ones -> 1
    bexti x13, x1, 15
    # Expected: 0x00000001

    # Test 4: Extract bit 0 from all zeros -> 0
    bexti x14, x2, 0
    # Expected: 0x00000000

    # Test 5: Extract bit 8 from pattern 0x12345678
    # Bit 8 of 0x12345678 is 0
    bexti x15, x3, 8
    # Expected: 0x00000000

    # Test 6: Extract bit 10 from 0x12345678
    # Bit 10 of 0x12345678 is 1
    bexti x16, x3, 10
    # Expected: 0x00000001

    # Test 7: Extract bit 4 from 0xAAAAAAAA
    # Bit 4 of 0xAAAAAAAA is 0 (pattern 10101010)
    bexti x17, x4, 4
    # Expected: 0x00000000

    # Test 8: Extract bit 7 from 0xAAAAAAAA
    # Bit 7 of 0xAAAAAAAA is 1
    bexti x18, x4, 7
    # Expected: 0x00000001

    # Test 9: Extract bit 12 from 0x55555555
    # Bit 12 of 0x55555555 is 1 (pattern 01010101)
    bexti x19, x5, 12
    # Expected: 0x00000001

    # Test 10: Extract bit 16 from 0x55555555
    # Bit 16 of 0x55555555 is 1
    bexti x20, x5, 16
    # Expected: 0x00000001

    # Test 11: Extract bit 31 from 0x80000000 -> 1
    bexti x21, x6, 31
    # Expected: 0x00000001

    # Test 12: Extract bit 0 from 0x00000001 -> 1
    bexti x22, x7, 0
    # Expected: 0x00000001

    # Test 13: Extract bit 7 from 0xF0F0F0F0
    # Bit 7 of 0xF0F0F0F0 is 1 (pattern 11110000)
    bexti x23, x8, 7
    # Expected: 0x00000001

    # Test 14: Extract bit 3 from 0xF0F0F0F0
    # Bit 3 of 0xF0F0F0F0 is 0
    bexti x24, x8, 3
    # Expected: 0x00000000

    # Test 15: Extract bit 20 from 0x0F0F0F0F
    # Bit 20 of 0x0F0F0F0F is 0 (pattern 00001111)
    bexti x25, x9, 20
    # Expected: 0x00000000

    # Test 16: Extract bit 24 from 0x0F0F0F0F
    # Bit 24 of 0x0F0F0F0F is 1
    bexti x26, x9, 24
    # Expected: 0x00000001

    # Test 17: Extract bit 1 from 0xDEADBEEF
    # Bit 1 of 0xDEADBEEF is 1
    bexti x27, x10, 1
    # Expected: 0x00000001

    # Test 18: Extract bit 5 from 0xDEADBEEF
    # Bit 5 of 0xDEADBEEF is 1
    bexti x28, x10, 5
    # Expected: 0x00000001

    # Test 19: Extract bit 20 from 0xDEADBEEF
    # Bit 20 of 0xDEADBEEF is 0
    bexti x29, x10, 20
    # Expected: 0x00000000

    # Test 20: Extract bit 27 from 0xDEADBEEF
    # Bit 27 of 0xDEADBEEF is 1
    bexti x30, x10, 27
    # Expected: 0x00000001

    # Test 21-30: Additional edge cases and patterns

    # Test 21: Extract bit 1 from all ones
    li  x1, 0xFFFFFFFF
    bexti x1, x1, 1
    # Expected: 0x00000001

    # Test 22: Extract bits 2, 3, 4 sequentially
    li  x2, 0xFFFFFFFF
    bexti x2, x2, 2
    bexti x2, x2, 3
    bexti x2, x2, 4
    # Expected: 0x00000000 (final extraction of bit 4 from 0x00000000)

    # Test 23: Extract bit 30 from pattern
    li  x3, 0x7FFFFFFF
    bexti x3, x3, 30
    # Expected: 0x00000001

    # Test 24: Extract bit 16 from pattern
    li  x4, 0x12345678
    bexti x4, x4, 16
    # Expected: 0x00000000 (bit 16 is 0)

    # Test 25: Extract bit 25 from pattern
    li  x5, 0xAAAAAAAA
    bexti x5, x5, 25
    # Expected: 0x00000001

    # Test 26: Extract sequential bits (bit 0)
    li  x6, 0x55555555
    bexti x6, x6, 0
    # Expected: 0x00000001

    # Test 27: Extract bit 29 from pattern
    li  x7, 0xF0F0F0F0
    bexti x7, x7, 29
    # Expected: 0x00000001

    # Test 28: Extract bit 11 from pattern
    li  x8, 0x0F0F0F0F
    bexti x8, x8, 11
    # Expected: 0x00000001

    # Test 29: Extract bit 17 from pattern
    li  x9, 0xABCDEF01
    bexti x9, x9, 17
    # Expected: 0x00000000 (bit 17 is 0)

    # Test 30: Extract bit 22 from pattern
    li  x10, 0x87654321
    bexti x10, x10, 22
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
