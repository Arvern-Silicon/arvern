#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbs_bclri
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BCLRI (Zbs)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # BCLRI operation: rd = rs1 & ~(1 << imm[4:0])
    # Clears a single bit at the specified immediate position

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
    # TEST BCLRI (Bit Clear Immediate) INSTRUCTION
    # Format: bclri rd, rs1, imm
    # Operation: rd = rs1 & ~(1 << imm[4:0])
    # Encoding: 0100100 imm[4:0] rs1[4:0] 001 rd[4:0] 0010011
    # Use case: Clear specific bit positions using immediate
    #-------------------------------------------------

    # Test 1: Clear bit 0 from all ones -> 0xFFFFFFFE
    bclri x11, x1, 0
    # Expected: 0xFFFFFFFE

    # Test 2: Clear bit 31 from all ones -> 0x7FFFFFFF
    bclri x12, x1, 31
    # Expected: 0x7FFFFFFF

    # Test 3: Clear bit 15 from all ones -> 0xFFFF7FFF
    bclri x13, x1, 15
    # Expected: 0xFFFF7FFF

    # Test 4: Clear bit 0 from all zeros -> 0x00000000 (no change)
    bclri x14, x2, 0
    # Expected: 0x00000000

    # Test 5: Clear bit 8 from pattern 0x12345678
    bclri x15, x3, 8
    # Expected: 0x12345678 (bit 8 already 0)

    # Test 6: Clear bit 10 from pattern 0x12345678
    bclri x16, x3, 10
    # Expected: 0x12345278

    # Test 7: Clear bit 4 from 0xAAAAAAAA (already 0)
    bclri x17, x4, 4
    # Expected: 0xAAAAAAAA

    # Test 8: Clear bit 7 from 0xAAAAAAAA
    bclri x18, x4, 7
    # Expected: 0xAAAAAAA2A

    # Test 9: Clear bit 12 from 0x55555555
    bclri x19, x5, 12
    # Expected: 0x55554555

    # Test 10: Clear bit 16 from 0x55555555
    bclri x20, x5, 16
    # Expected: 0x55545555

    # Test 11: Clear bit 31 from 0x80000000 -> 0x00000000
    bclri x21, x6, 31
    # Expected: 0x00000000

    # Test 12: Clear bit 0 from 0x00000001 -> 0x00000000
    bclri x22, x7, 0
    # Expected: 0x00000000

    # Test 13: Clear bit 7 from 0xF0F0F0F0
    bclri x23, x8, 7
    # Expected: 0xF0F0F070

    # Test 14: Clear bit 3 from 0xF0F0F0F0 (already 0)
    bclri x24, x8, 3
    # Expected: 0xF0F0F0F0

    # Test 15: Clear bit 20 from 0x0F0F0F0F
    bclri x25, x9, 20
    # Expected: 0x0F0F0F0F (bit 20 already 0)

    # Test 16: Clear bit 24 from 0x0F0F0F0F
    bclri x26, x9, 24
    # Expected: 0x0E0F0F0F

    # Test 17: Clear bit 1 from 0xDEADBEEF
    bclri x27, x10, 1
    # Expected: 0xDEADBEED

    # Test 18: Clear bit 5 from 0xDEADBEEF
    bclri x28, x10, 5
    # Expected: 0xDEADBECF

    # Test 19: Clear bit 20 from 0xDEADBEEF (already 0)
    bclri x29, x10, 20
    # Expected: 0xDEADBEEF

    # Test 20: Clear bit 27 from 0xDEADBEEF
    bclri x30, x10, 27
    # Expected: 0xD6ADBEEF

    # Test 21-30: Sequential bit clearing and edge cases

    # Test 21: Clear bit 1 from 0xFFFFFFFF
    li  x1, 0xFFFFFFFF
    bclri x1, x1, 1
    # Expected: 0xFFFFFFFD

    # Test 22: Clear bits 2, 3, 4 sequentially
    li  x2, 0xFFFFFFFF
    bclri x2, x2, 2
    bclri x2, x2, 3
    bclri x2, x2, 4
    # Expected: 0xFFFFFFE3

    # Test 23: Clear bit 30 from 0x7FFFFFFF
    li  x3, 0x7FFFFFFF
    bclri x3, x3, 30
    # Expected: 0x3FFFFFFF

    # Test 24: Clear bit 16 from 0x12345678
    li  x4, 0x12345678
    bclri x4, x4, 16
    # Expected: 0x12345678 (bit 16 already 0)

    # Test 25: Clear bit 25 from 0xAAAAAAAA
    li  x5, 0xAAAAAAAA
    bclri x5, x5, 25
    # Expected: 0xA8AAAAAA

    # Test 26: Clear all even bits from LSB side
    li  x6, 0x55555555
    bclri x6, x6, 0
    bclri x6, x6, 2
    bclri x6, x6, 4
    bclri x6, x6, 6
    # Expected: 0x55555500

    # Test 27: Clear bit 29 from 0xF0F0F0F0
    li  x7, 0xF0F0F0F0
    bclri x7, x7, 29
    # Expected: 0xD0F0F0F0

    # Test 28: Clear bit 11 from 0x0F0F0F0F
    li  x8, 0x0F0F0F0F
    bclri x8, x8, 11
    # Expected: 0x0F0F070F

    # Test 29: Clear bit 17 from 0xABCDEF01
    li  x9, 0xABCDEF01
    bclri x9, x9, 17
    # Expected: 0xABCDEF01 (bit 17 already 0)

    # Test 30: Clear bit 22 from 0x87654321
    li  x10, 0x87654321
    bclri x10, x10, 22
    # Expected: 0x87254321

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
