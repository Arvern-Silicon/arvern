#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_sextb
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SEXT.B (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # SEXT.B operation: rd = sign_extend(rs1[7:0])
    # Sign-extends the lower 8 bits (byte) to 32 bits
    # Bit 7 determines the sign: 0 = positive, 1 = negative

    # Test data with various byte values
    li  x1,  0x00000000  # Zero
    li  x2,  0x00000001  # Positive: 1
    li  x3,  0x0000007F  # Max positive byte: 127
    li  x4,  0x00000080  # Min negative byte: -128
    li  x5,  0x000000FF  # -1 as byte
    li  x6,  0x00000055  # Positive: 0x55
    li  x7,  0x000000AA  # Negative: 0xAA
    li  x8,  0xFFFFFFFF  # All ones, byte = 0xFF
    li  x9,  0x12345678  # Upper bits set, byte = 0x78
    li  x10, 0xABCDEFAB  # Upper bits set, byte = 0xAB

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST SEXT.B (Sign-Extend Byte) INSTRUCTION
    # Format: sext.b rd, rs1
    # Operation: rd = {{24{rs1[7]}}, rs1[7:0]}
    # Encoding: 0110000 00100 rs1[4:0] 001 rd[4:0] 0010011
    # Use case: Sign-extending 8-bit signed values
    #-------------------------------------------------

    # Test 1: Zero byte -> 0x00000000
    # sext.b x11, x1 (0x00000000)
    # Expected: 0x00000000
    sext.b x11, x1

    # Test 2: Positive byte (bit 7 = 0) -> zero-extended
    # sext.b x12, x2 (0x00000001)
    # Expected: 0x00000001
    sext.b x12, x2

    # Test 3: Max positive byte (0x7F = 127)
    # sext.b x13, x3 (0x0000007F)
    # Expected: 0x0000007F
    sext.b x13, x3

    # Test 4: Min negative byte (0x80 = -128)
    # sext.b x14, x4 (0x00000080)
    # Expected: 0xFFFFFF80
    sext.b x14, x4

    # Test 5: -1 as byte (0xFF)
    # sext.b x15, x5 (0x000000FF)
    # Expected: 0xFFFFFFFF
    sext.b x15, x5

    # Test 6: Positive byte 0x55
    # sext.b x16, x6 (0x00000055)
    # Expected: 0x00000055
    sext.b x16, x6

    # Test 7: Negative byte 0xAA
    # sext.b x17, x7 (0x000000AA)
    # Expected: 0xFFFFFFAA
    sext.b x17, x7

    # Test 8: All ones, byte = 0xFF
    # sext.b x18, x8 (0xFFFFFFFF)
    # Expected: 0xFFFFFFFF
    sext.b x18, x8

    # Test 9: Upper bits set, byte = 0x78 (positive)
    # sext.b x19, x9 (0x12345678)
    # Expected: 0x00000078
    sext.b x19, x9

    # Test 10: Upper bits set, byte = 0xAB (negative)
    # sext.b x20, x10 (0xABCDEFAB)
    # Expected: 0xFFFFFFAB
    sext.b x20, x10

    # Test 11: Boundary - 0x7E (positive)
    li   x21, 0x0000007E
    # sext.b x22, x21 (0x0000007E)
    # Expected: 0x0000007E
    sext.b x22, x21

    # Test 12: Boundary - 0x81 (negative)
    li   x23, 0x00000081
    # sext.b x24, x23 (0x00000081)
    # Expected: 0xFFFFFF81
    sext.b x24, x23

    # Test 13: Byte = 0x01 with upper bits set
    li   x25, 0xFFFFFF01
    # sext.b x26, x25 (0xFFFFFF01)
    # Expected: 0x00000001
    sext.b x26, x25

    # Test 14: Byte = 0xFE with various upper bits
    li   x27, 0x123456FE
    # sext.b x28, x27 (0x123456FE)
    # Expected: 0xFFFFFFFE
    sext.b x28, x27

    # Test 15: Byte = 0x40 (middle positive)
    li   x29, 0x00000040
    # sext.b x30, x29 (0x00000040)
    # Expected: 0x00000040
    sext.b x30, x29

    # Test 16: Byte = 0xC0 (middle negative)
    li   x1, 0x000000C0
    # sext.b x2, x1 (0x000000C0)
    # Expected: 0xFFFFFFC0
    sext.b x2, x1

    # Test 17: Byte = 0x00 with upper bits set
    li   x3, 0xFFFFFF00
    # sext.b x4, x3 (0xFFFFFF00)
    # Expected: 0x00000000
    sext.b x4, x3

    # Test 18: Byte = 0x7F with upper bits set
    li   x5, 0xABCD007F
    # sext.b x6, x5 (0xABCD007F)
    # Expected: 0x0000007F
    sext.b x6, x5

    # Test 19: Byte = 0x80 with upper bits set
    li   x7, 0x12340080
    # sext.b x8, x7 (0x12340080)
    # Expected: 0xFFFFFF80
    sext.b x8, x7

    # Test 20: Byte = 0xFF with different upper bits
    li   x9, 0x567890FF
    # sext.b x10, x9 (0x567890FF)
    # Expected: 0xFFFFFFFF
    sext.b x10, x9

    # Test 21: Small positive values
    li   x11, 0x00000010
    # sext.b x12, x11 (0x00000010)
    # Expected: 0x00000010
    sext.b x12, x11

    # Test 22: Small negative values (0xF0 = -16)
    li   x13, 0x000000F0
    # sext.b x14, x13 (0x000000F0)
    # Expected: 0xFFFFFFF0
    sext.b x14, x13

    # Test 23: Byte = 0x02
    li   x15, 0xFEDCBA02
    # sext.b x16, x15 (0xFEDCBA02)
    # Expected: 0x00000002
    sext.b x16, x15

    # Test 24: Byte = 0x82 (negative)
    li   x17, 0x11111182
    # sext.b x18, x17 (0x11111182)
    # Expected: 0xFFFFFF82
    sext.b x18, x17

    # Test 25: Byte = 0x3F
    li   x19, 0x0000003F
    # sext.b x20, x19 (0x0000003F)
    # Expected: 0x0000003F
    sext.b x20, x19

    # Test 26: Byte = 0xBF (negative)
    li   x21, 0x000000BF
    # sext.b x22, x21 (0x000000BF)
    # Expected: 0xFFFFFFBF
    sext.b x22, x21

    # Test 27: Byte = 0x0F
    li   x23, 0xAAAA000F
    # sext.b x24, x23 (0xAAAA000F)
    # Expected: 0x0000000F
    sext.b x24, x23

    # Test 28: Byte = 0x8F (negative)
    li   x25, 0x5555558F
    # sext.b x26, x25 (0x5555558F)
    # Expected: 0xFFFFFF8F
    sext.b x26, x25

    # Test 29: Byte = 0x7D
    li   x27, 0x0000007D
    # sext.b x28, x27 (0x0000007D)
    # Expected: 0x0000007D
    sext.b x28, x27

    # Test 30: Byte = 0x83 (negative)
    li   x29, 0xFFFF0083
    # sext.b x30, x29 (0xFFFF0083)
    # Expected: 0xFFFFFF83
    sext.b x30, x29

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
