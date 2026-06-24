#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_rol
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ROL (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # ROL operation: rd = (rs1 << rs2[4:0]) | (rs1 >> (32 - rs2[4:0]))
    # Rotates rs1 left by rs2[4:0] bit positions
    # Bits shifted out from the left are rotated into the right

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
    # TEST ROL (Rotate Left) INSTRUCTION
    # Format: rol rd, rs1, rs2
    # Operation: rd = (rs1 << rs2[4:0]) | (rs1 >> (32 - rs2[4:0]))
    # Encoding: 0110000 rs2[4:0] rs1[4:0] 001 rd[4:0] 0110011
    #-------------------------------------------------

    # Test 1: Rotate all zeros by any amount -> 0x00000000
    # rol x11, x1, x4 (0x00000000 << 1)
    # Expected: 0x00000000
    li  x4, 1
    rol x11, x1, x4

    # Test 2: Rotate all ones by any amount -> 0xFFFFFFFF
    # rol x12, x2, x4 (0xFFFFFFFF << 1)
    # Expected: 0xFFFFFFFF
    rol x12, x2, x4

    # Test 3: Rotate single bit at position 31 by 1 -> bit moves to position 0
    # rol x13, x3, x4 (0x80000000 << 1)
    # Expected: 0x00000001
    rol x13, x3, x4

    # Test 4: Rotate single bit at position 0 by 1 -> bit moves to position 1
    li  x4, 0x00000001
    # rol x14, x4, x4 (0x00000001 << 1)
    # Expected: 0x00000002
    rol x14, x4, x4

    # Test 5: Rotate 0xAAAAAAAA by 1 -> 0x55555555
    li  x4, 1
    # rol x15, x5, x4 (0xAAAAAAAA << 1)
    # Expected: 0x55555555
    rol x15, x5, x4

    # Test 6: Rotate 0x55555555 by 1 -> 0xAAAAAAAA
    # rol x16, x6, x4 (0x55555555 << 1)
    # Expected: 0xAAAAAAAA
    rol x16, x6, x4

    # Test 7: Rotate 0x12345678 by 0 -> unchanged
    li  x4, 0
    # rol x17, x7, x4 (0x12345678 << 0)
    # Expected: 0x12345678
    rol x17, x7, x4

    # Test 8: Rotate 0x12345678 by 4 -> 0x23456781
    li  x4, 4
    # rol x18, x7, x4 (0x12345678 << 4)
    # Expected: 0x23456781
    rol x18, x7, x4

    # Test 9: Rotate 0x12345678 by 8 -> 0x34567812
    li  x4, 8
    # rol x19, x7, x4 (0x12345678 << 8)
    # Expected: 0x34567812
    rol x19, x7, x4

    # Test 10: Rotate 0x12345678 by 16 -> 0x56781234 (swap halfwords)
    li  x4, 16
    # rol x20, x7, x4 (0x12345678 << 16)
    # Expected: 0x56781234
    rol x20, x7, x4

    # Test 11: Rotate 0x80000000 by 4 -> 0x00000008
    li  x4, 4
    # rol x21, x3, x4 (0x80000000 << 4)
    # Expected: 0x00000008
    rol x21, x3, x4

    # Test 12: Rotate 0x00000001 by 31 -> 0x80000000
    li  x3, 0x00000001
    li  x4, 31
    # rol x22, x3, x4 (0x00000001 << 31)
    # Expected: 0x80000000
    rol x22, x3, x4

    # Test 13: Rotate 0xDEADBEEF by 4 -> 0xEADBEEFD
    li  x4, 4
    # rol x23, x8, x4 (0xDEADBEEF << 4)
    # Expected: 0xEADBEEFD
    rol x23, x8, x4

    # Test 14: Rotate 0xDEADBEEF by 8 -> 0xADBEEFDE
    li  x4, 8
    # rol x24, x8, x4 (0xDEADBEEF << 8)
    # Expected: 0xADBEEFDE
    rol x24, x8, x4

    # Test 15: Rotate 0xDEADBEEF by 16 -> 0xBEEFDEAD
    li  x4, 16
    # rol x25, x8, x4 (0xDEADBEEF << 16)
    # Expected: 0xBEEFDEAD
    rol x25, x8, x4

    # Test 16: Rotate 0xF0F0F0F0 by 4 -> 0x0F0F0F0F
    li  x4, 4
    # rol x26, x9, x4 (0xF0F0F0F0 << 4)
    # Expected: 0x0F0F0F0F
    rol x26, x9, x4

    # Test 17: Rotate 0x0F0F0F0F by 4 -> 0xF0F0F0F0
    li  x4, 4
    # rol x27, x10, x4 (0x0F0F0F0F << 4)
    # Expected: 0xF0F0F0F0
    rol x27, x10, x4

    # Test 18: Rotate 0x12345678 by 32 -> same as by 0 (only lower 5 bits used)
    li  x4, 32
    # rol x28, x7, x4 (0x12345678 << 32, but 32 & 0x1F = 0)
    # Expected: 0x12345678
    rol x28, x7, x4

    # Test 19: Rotate 0x12345678 by 33 -> same as by 1 (33 & 0x1F = 1)
    li  x4, 33
    # rol x29, x7, x4 (0x12345678 << 33, but 33 & 0x1F = 1)
    # Expected: 0x2468ACF0
    rol x29, x7, x4

    # Test 20: Rotate 0xAAAAAAAA by 16 -> 0xAAAAAAAA (symmetric pattern)
    li  x4, 16
    # rol x30, x5, x4 (0xAAAAAAAA << 16)
    # Expected: 0xAAAAAAAA
    rol x30, x5, x4

    # Test 21: Rotate 0x00000001 by 16 -> 0x00010000
    li  x1, 0x00000001
    li  x4, 16
    # rol x1, x1, x4
    # Expected: 0x00010000
    rol x1, x1, x4

    # Test 22: Rotate 0x80000000 by 16 -> 0x00008000
    li  x2, 0x80000000
    li  x4, 16
    # rol x2, x2, x4
    # Expected: 0x00008000
    rol x2, x2, x4

    # Test 23: Rotate 0x12345678 by 12 -> 0x45678123
    li  x3, 0x12345678
    li  x4, 12
    # rol x3, x3, x4
    # Expected: 0x45678123
    rol x3, x3, x4

    # Test 24: Rotate 0xFFFF0000 by 8 -> 0xFF0000FF
    li  x4, 0xFFFF0000
    li  x5, 8
    # rol x4, x4, x5
    # Expected: 0xFF0000FF
    rol x4, x4, x5

    # Test 25: Rotate 0x0000FFFF by 8 -> 0x00FFFF00
    li  x5, 0x0000FFFF
    li  x6, 8
    # rol x5, x5, x6
    # Expected: 0x00FFFF00
    rol x5, x5, x6

    # Test 26: Rotate 0xF0000000 by 4 -> 0x0000000F
    li  x6, 0xF0000000
    li  x7, 4
    # rol x6, x6, x7
    # Expected: 0x0000000F
    rol x6, x6, x7

    # Test 27: Rotate 0x0000000F by 28 -> 0xF0000000
    li  x7, 0x0000000F
    li  x8, 28
    # rol x7, x7, x8
    # Expected: 0xF0000000
    rol x7, x7, x8

    # Test 28: Rotate 0xC0000003 by 1 -> 0x80000007
    li  x8, 0xC0000003
    li  x9, 1
    # rol x8, x8, x9
    # Expected: 0x80000007
    rol x8, x8, x9

    # Test 29: Rotate 0x00000003 by 30 -> 0xC0000000
    li  x9, 0x00000003
    li  x10, 30
    # rol x9, x9, x10
    # Expected: 0xC0000000
    rol x9, x9, x10

    # Test 30: Rotate 0x12345678 by 24 -> 0x78123456
    li  x10, 0x12345678
    li  x31, 24
    # rol x10, x10, x31
    # Expected: 0x78123456
    rol x10, x10, x31

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
