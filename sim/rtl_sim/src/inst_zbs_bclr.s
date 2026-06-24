#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbs_bclr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BCLR (Zbs)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # BCLR/BCLRI operation: rd = rs1 & ~(1 << rs2[4:0])
    # Clears a single bit at the specified position

    # Test data with various patterns
    li  x1,  0xFFFFFFFF  # All ones
    li  x2,  0x00000000  # All zeros
    li  x3,  0x12345678  # Random pattern
    li  x4,  0xAAAAAAAA  # Alternating bits
    li  x5,  0x55555555  # Alternating bits (inverted)
    li  x6,  0x80000000  # Only MSB set
    li  x7,  0x00000001  # Only LSB set
    li  x8,  0xF0F0F0F0  # Pattern
    li  x9,  0x0F0F0F0F  # Pattern (inverted)
    li  x10, 0xDEADBEEF  # Mixed pattern

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST BCLR (Bit Clear) INSTRUCTION
    # Format: bclr rd, rs1, rs2
    # Operation: rd = rs1 & ~(1 << rs2[4:0])
    # Encoding: 0100100 rs2[4:0] rs1[4:0] 001 rd[4:0] 0110011
    # Also test BCLRI (immediate variant)
    #-------------------------------------------------

    # Test 1: Clear bit 0 from all ones -> 0xFFFFFFFE
    li  x2, 0
    bclr x11, x1, x2
    # Expected: 0xFFFFFFFE

    # Test 2: Clear bit 31 from all ones -> 0x7FFFFFFF
    li  x2, 31
    bclr x12, x1, x2
    # Expected: 0x7FFFFFFF

    # Test 3: Clear bit 15 from all ones -> 0xFFFF7FFF
    li  x2, 15
    bclr x13, x1, x2
    # Expected: 0xFFFF7FFF

    # Test 4: Clear bit 0 from all zeros -> 0x00000000 (no change)
    li  x1, 0x00000000
    li  x2, 0
    bclr x14, x1, x2
    # Expected: 0x00000000

    # Test 5: Clear bit 10 from pattern 0x12345678
    li  x1, 0x12345678
    li  x2, 10
    bclr x15, x1, x2
    # Expected: 0x12345278 (bit 10 was set, now cleared)

    # Test 6: Clear bit 5 from 0xAAAAAAAA
    li  x1, 0xAAAAAAAA
    li  x2, 5
    bclr x16, x1, x2
    # Expected: 0xAAAAAAA8A

    # Test 7: Clear bit 16 from 0x55555555
    li  x1, 0x55555555
    li  x2, 16
    bclr x17, x1, x2
    # Expected: 0x55545555

    # Test 8: Clear bit 7 from 0xF0F0F0F0
    li  x1, 0xF0F0F0F0
    li  x2, 7
    bclr x18, x1, x2
    # Expected: 0xF0F0F070

    # Test 9: Clear bit 24 from 0x0F0F0F0F
    li  x1, 0x0F0F0F0F
    li  x2, 24
    bclr x19, x1, x2
    # Expected: 0x0E0F0F0F

    # Test 10: Clear bit 20 from 0xDEADBEEF
    li  x1, 0xDEADBEEF
    li  x2, 20
    bclr x20, x1, x2
    # Expected: 0xDEADBEEF (bit 20 already 0)

    # Test 11-20: Test BCLRI (immediate variant)

    # Test 11: Clear bit 0 using immediate
    li  x1, 0xFFFFFFFF
    bclri x21, x1, 0
    # Expected: 0xFFFFFFFE

    # Test 12: Clear bit 31 using immediate
    li  x1, 0xFFFFFFFF
    bclri x22, x1, 31
    # Expected: 0x7FFFFFFF

    # Test 13: Clear bit 8 using immediate
    li  x1, 0x12345678
    bclri x23, x1, 8
    # Expected: 0x12345678 (bit 8 already 0)

    # Test 14: Clear bit 4 using immediate
    li  x1, 0xAAAAAAAA
    bclri x24, x1, 4
    # Expected: 0xAAAAAAA (bit 4 was already 0)

    # Test 15: Clear bit 12 using immediate
    li  x1, 0x55555555
    bclri x25, x1, 12
    # Expected: 0x55554555

    # Test 16: Clear bit 3 using immediate
    li  x1, 0xF0F0F0F0
    bclri x26, x1, 3
    # Expected: 0xF0F0F0F0 (bit 3 was already 0)

    # Test 17: Clear bit 20 using immediate
    li  x1, 0x0F0F0F0F
    bclri x27, x1, 20
    # Expected: 0x0F0F0F0F (bit 20 already 0)

    # Test 18: Clear bit 1 using immediate
    li  x1, 0xDEADBEEF
    bclri x28, x1, 1
    # Expected: 0xDEADBEED

    # Test 19: Clear bit 27 using immediate
    li  x1, 0x87654321
    bclri x29, x1, 27
    # Expected: 0x87654321 (bit 27 already 0)

    # Test 20: Clear bit 16 using immediate from pattern
    li  x1, 0xABCDEF01
    bclri x30, x1, 16
    # Expected: 0xABCDEF01 (bit 16 was already 0)

    # Test 21-30: Additional edge cases

    # Test 21: Clear bit using position > 31 (should use only lower 5 bits)
    li  x1, 0xFFFFFFFF
    li  x2, 32  # Same as position 0
    bclr x1, x1, x2
    # Expected: 0xFFFFFFFE

    # Test 22: Clear multiple consecutive bits (one at a time)
    li  x2, 0xFFFFFFFF
    bclri x2, x2, 4
    bclri x2, x2, 5
    bclri x2, x2, 6
    # Expected: 0xFFFFFF8F

    # Test 23: Clear bit from single bit value
    li  x3, 0x00000001
    li  x4, 0
    bclr x3, x3, x4
    # Expected: 0x00000000

    # Test 24: Clear bit from MSB only
    li  x4, 0x80000000
    li  x5, 31
    bclr x4, x4, x5
    # Expected: 0x00000000

    # Test 25: Clear alternating pattern bits
    li  x5, 0x12345678
    bclri x5, x5, 3
    bclri x5, x5, 6
    bclri x5, x5, 9
    # Expected: 0x12345438

    # Test 26: Same register for src and dest
    li  x6, 0xFFFF0000
    li  x7, 16
    bclr x6, x6, x7
    # Expected: 0xFFFE0000

    # Test 27: Clear bit from zero (no effect)
    li  x7, 0x00000000
    bclri x7, x7, 15
    # Expected: 0x00000000

    # Test 28: Clear high bit from max signed
    li  x8, 0x7FFFFFFF
    bclri x8, x8, 30
    # Expected: 0x3FFFFFFF

    # Test 29: Clear middle bits
    li  x9, 0xF0F0F0F0
    li  x10, 15
    bclr x9, x9, x10
    # Expected: 0xF0F07FF0

    # Test 30: Clear from pattern, verify bit was set
    li  x10, 0x55AA55AA
    bclri x10, x10, 17
    # Expected: 0x55A255AA

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
