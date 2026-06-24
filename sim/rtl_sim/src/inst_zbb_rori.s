#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_rori
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: RORI (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # RORI operation: rd = (rs1 >> imm[4:0]) | (rs1 << (32 - imm[4:0]))
    # Rotates rs1 right by immediate value (0-31)
    # Bits shifted out from the right are rotated into the left

    # Test data with various patterns
    li  x1,  0x00000000  # All zeros
    li  x2,  0xFFFFFFFF  # All ones
    li  x3,  0x80000000  # Single bit at position 31
    li  x4,  0x00000001  # Single bit at position 0
    li  x5,  0xAAAAAAAA  # Alternating bits (10101010...)
    li  x6,  0x55555555  # Alternating bits (01010101...)
    li  x7,  0x12345678  # Mixed pattern
    li  x8,  0xDEADBEEF  # Mixed pattern
    li  x9,  0xF0F0F0F0  # Nibble pattern
    li  x10, 0x0F0F0F0F  # Nibble pattern

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST RORI (Rotate Right Immediate) INSTRUCTION
    # Format: rori rd, rs1, imm
    # Operation: rd = (rs1 >> imm[4:0]) | (rs1 << (32 - imm[4:0]))
    # Encoding: 0110000 imm[4:0] rs1[4:0] 101 rd[4:0] 0010011
    #-------------------------------------------------

    # Test 1: Rotate all zeros by any amount -> 0x00000000
    # rori x11, x1, 1 (0x00000000 >> 1)
    # Expected: 0x00000000
    rori x11, x1, 1

    # Test 2: Rotate all ones by any amount -> 0xFFFFFFFF
    # rori x12, x2, 8 (0xFFFFFFFF >> 8)
    # Expected: 0xFFFFFFFF
    rori x12, x2, 8

    # Test 3: Rotate single bit at position 0 by 1 -> bit moves to position 31
    # rori x13, x4, 1 (0x00000001 >> 1)
    # Expected: 0x80000000
    rori x13, x4, 1

    # Test 4: Rotate single bit at position 31 by 1 -> bit moves to position 30
    # rori x14, x3, 1 (0x80000000 >> 1)
    # Expected: 0x40000000
    rori x14, x3, 1

    # Test 5: Rotate 0xAAAAAAAA by 1 -> 0x55555555
    # rori x15, x5, 1 (0xAAAAAAAA >> 1)
    # Expected: 0x55555555
    rori x15, x5, 1

    # Test 6: Rotate 0x55555555 by 1 -> 0xAAAAAAAA
    # rori x16, x6, 1 (0x55555555 >> 1)
    # Expected: 0xAAAAAAAA
    rori x16, x6, 1

    # Test 7: Rotate 0x12345678 by 0 -> unchanged
    # rori x17, x7, 0 (0x12345678 >> 0)
    # Expected: 0x12345678
    rori x17, x7, 0

    # Test 8: Rotate 0x12345678 by 4 -> 0x81234567
    # rori x18, x7, 4 (0x12345678 >> 4)
    # Expected: 0x81234567
    rori x18, x7, 4

    # Test 9: Rotate 0x12345678 by 8 -> 0x78123456
    # rori x19, x7, 8 (0x12345678 >> 8)
    # Expected: 0x78123456
    rori x19, x7, 8

    # Test 10: Rotate 0x12345678 by 16 -> 0x56781234 (swap halfwords)
    # rori x20, x7, 16 (0x12345678 >> 16)
    # Expected: 0x56781234
    rori x20, x7, 16

    # Test 11: Rotate 0x00000001 by 4 -> 0x10000000
    # rori x21, x4, 4 (0x00000001 >> 4)
    # Expected: 0x10000000
    rori x21, x4, 4

    # Test 12: Rotate 0x80000000 by 31 -> 0x00000001
    # rori x22, x3, 31 (0x80000000 >> 31)
    # Expected: 0x00000001
    rori x22, x3, 31

    # Test 13: Rotate 0xDEADBEEF by 4 -> 0xFDEADBEE
    # rori x23, x8, 4 (0xDEADBEEF >> 4)
    # Expected: 0xFDEADBEE
    rori x23, x8, 4

    # Test 14: Rotate 0xDEADBEEF by 8 -> 0xEFDEADBE
    # rori x24, x8, 8 (0xDEADBEEF >> 8)
    # Expected: 0xEFDEADBE
    rori x24, x8, 8

    # Test 15: Rotate 0xDEADBEEF by 16 -> 0xBEEFDEAD
    # rori x25, x8, 16 (0xDEADBEEF >> 16)
    # Expected: 0xBEEFDEAD
    rori x25, x8, 16

    # Test 16: Rotate 0xF0F0F0F0 by 4 -> 0x0F0F0F0F
    # rori x26, x9, 4 (0xF0F0F0F0 >> 4)
    # Expected: 0x0F0F0F0F
    rori x26, x9, 4

    # Test 17: Rotate 0x0F0F0F0F by 4 -> 0xF0F0F0F0
    # rori x27, x10, 4 (0x0F0F0F0F >> 4)
    # Expected: 0xF0F0F0F0
    rori x27, x10, 4

    # Test 18: Rotate 0x12345678 by 12 -> 0x67812345
    # rori x28, x7, 12 (0x12345678 >> 12)
    # Expected: 0x67812345
    rori x28, x7, 12

    # Test 19: Rotate 0x12345678 by 24 -> 0x34567812
    # rori x29, x7, 24 (0x12345678 >> 24)
    # Expected: 0x34567812
    rori x29, x7, 24

    # Test 20: Rotate 0xAAAAAAAA by 16 -> 0xAAAAAAAA (symmetric pattern)
    # rori x30, x5, 16 (0xAAAAAAAA >> 16)
    # Expected: 0xAAAAAAAA
    rori x30, x5, 16

    # Test 21: Rotate 0x80000000 by 2 -> 0x20000000
    # rori x1, x3, 2
    # Expected: 0x20000000
    rori x1, x3, 2

    # Test 22: Rotate 0x00000001 by 3 -> 0x20000000
    # rori x2, x4, 3
    # Expected: 0x20000000
    rori x2, x4, 3

    # Test 23: Rotate 0x12345678 by 20 -> 0x45678123
    # rori x3, x7, 20
    # Expected: 0x45678123
    rori x3, x7, 20

    # Test 24: Rotate 0xFFFF0000 by 8 -> 0x00FFFF00
    li  x4, 0xFFFF0000
    # rori x4, x4, 8
    # Expected: 0x00FFFF00
    rori x4, x4, 8

    # Test 25: Rotate 0x0000FFFF by 8 -> 0xFF0000FF
    li  x5, 0x0000FFFF
    # rori x5, x5, 8
    # Expected: 0xFF0000FF
    rori x5, x5, 8

    # Test 26: Rotate 0x0000000F by 4 -> 0xF0000000
    li  x6, 0x0000000F
    # rori x6, x6, 4
    # Expected: 0xF0000000
    rori x6, x6, 4

    # Test 27: Rotate 0xF0000000 by 28 -> 0x0000000F
    li  x7, 0xF0000000
    # rori x7, x7, 28
    # Expected: 0x0000000F
    rori x7, x7, 28

    # Test 28: Rotate 0x80000007 by 2 -> 0xE0000001
    li  x8, 0x80000007
    # rori x8, x8, 2
    # Expected: 0xE0000001
    rori x8, x8, 2

    # Test 29: Rotate 0xC0000000 by 30 -> 0x00000003
    li  x9, 0xC0000000
    # rori x9, x9, 30
    # Expected: 0x00000003
    rori x9, x9, 30

    # Test 30: Rotate 0x00000003 by 2 -> 0xC0000000
    li  x10, 0x00000003
    # rori x10, x10, 2
    # Expected: 0xC0000000
    rori x10, x10, 2

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
