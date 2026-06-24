#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_sexth
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SEXT.H (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # SEXT.H operation: rd = sign_extend(rs1[15:0])
    # Sign-extends the lower 16 bits (halfword) to 32 bits
    # Bit 15 determines the sign: 0 = positive, 1 = negative

    # Test data with various halfword values
    li  x1,  0x00000000  # Zero
    li  x2,  0x00000001  # Positive: 1
    li  x3,  0x00007FFF  # Max positive halfword: 32767
    li  x4,  0x00008000  # Min negative halfword: -32768
    li  x5,  0x0000FFFF  # -1 as halfword
    li  x6,  0x00005555  # Positive: 0x5555
    li  x7,  0x0000AAAA  # Negative: 0xAAAA
    li  x8,  0xFFFFFFFF  # All ones, halfword = 0xFFFF
    li  x9,  0x12345678  # Upper bits set, halfword = 0x5678
    li  x10, 0xABCDABCD  # Upper bits set, halfword = 0xABCD

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST SEXT.H (Sign-Extend Halfword) INSTRUCTION
    # Format: sext.h rd, rs1
    # Operation: rd = {{16{rs1[15]}}, rs1[15:0]}
    # Encoding: 0110000 00101 rs1[4:0] 001 rd[4:0] 0010011
    # Use case: Sign-extending 16-bit signed values
    #-------------------------------------------------

    # Test 1: Zero halfword -> 0x00000000
    # sext.h x11, x1 (0x00000000)
    # Expected: 0x00000000
    sext.h x11, x1

    # Test 2: Positive halfword (bit 15 = 0) -> zero-extended
    # sext.h x12, x2 (0x00000001)
    # Expected: 0x00000001
    sext.h x12, x2

    # Test 3: Max positive halfword (0x7FFF = 32767)
    # sext.h x13, x3 (0x00007FFF)
    # Expected: 0x00007FFF
    sext.h x13, x3

    # Test 4: Min negative halfword (0x8000 = -32768)
    # sext.h x14, x4 (0x00008000)
    # Expected: 0xFFFF8000
    sext.h x14, x4

    # Test 5: -1 as halfword (0xFFFF)
    # sext.h x15, x5 (0x0000FFFF)
    # Expected: 0xFFFFFFFF
    sext.h x15, x5

    # Test 6: Positive halfword 0x5555
    # sext.h x16, x6 (0x00005555)
    # Expected: 0x00005555
    sext.h x16, x6

    # Test 7: Negative halfword 0xAAAA
    # sext.h x17, x7 (0x0000AAAA)
    # Expected: 0xFFFFAAAA
    sext.h x17, x7

    # Test 8: All ones, halfword = 0xFFFF
    # sext.h x18, x8 (0xFFFFFFFF)
    # Expected: 0xFFFFFFFF
    sext.h x18, x8

    # Test 9: Upper bits set, halfword = 0x5678 (positive)
    # sext.h x19, x9 (0x12345678)
    # Expected: 0x00005678
    sext.h x19, x9

    # Test 10: Upper bits set, halfword = 0xABCD (negative)
    # sext.h x20, x10 (0xABCDABCD)
    # Expected: 0xFFFFABCD
    sext.h x20, x10

    # Test 11: Boundary - 0x7FFE (positive)
    li   x21, 0x00007FFE
    # sext.h x22, x21 (0x00007FFE)
    # Expected: 0x00007FFE
    sext.h x22, x21

    # Test 12: Boundary - 0x8001 (negative)
    li   x23, 0x00008001
    # sext.h x24, x23 (0x00008001)
    # Expected: 0xFFFF8001
    sext.h x24, x23

    # Test 13: Halfword = 0x0001 with upper bits set
    li   x25, 0xFFFF0001
    # sext.h x26, x25 (0xFFFF0001)
    # Expected: 0x00000001
    sext.h x26, x25

    # Test 14: Halfword = 0xFFFE with various upper bits
    li   x27, 0x1234FFFE
    # sext.h x28, x27 (0x1234FFFE)
    # Expected: 0xFFFFFFFE
    sext.h x28, x27

    # Test 15: Halfword = 0x4000 (middle positive)
    li   x29, 0x00004000
    # sext.h x30, x29 (0x00004000)
    # Expected: 0x00004000
    sext.h x30, x29

    # Test 16: Halfword = 0xC000 (middle negative)
    li   x1, 0x0000C000
    # sext.h x2, x1 (0x0000C000)
    # Expected: 0xFFFFC000
    sext.h x2, x1

    # Test 17: Halfword = 0x0000 with upper bits set
    li   x3, 0xFFFF0000
    # sext.h x4, x3 (0xFFFF0000)
    # Expected: 0x00000000
    sext.h x4, x3

    # Test 18: Halfword = 0x7FFF with upper bits set
    li   x5, 0xABCD7FFF
    # sext.h x6, x5 (0xABCD7FFF)
    # Expected: 0x00007FFF
    sext.h x6, x5

    # Test 19: Halfword = 0x8000 with upper bits set
    li   x7, 0x12348000
    # sext.h x8, x7 (0x12348000)
    # Expected: 0xFFFF8000
    sext.h x8, x7

    # Test 20: Halfword = 0xFFFF with different upper bits
    li   x9, 0x5678FFFF
    # sext.h x10, x9 (0x5678FFFF)
    # Expected: 0xFFFFFFFF
    sext.h x10, x9

    # Test 21: Small positive values (0x0100)
    li   x11, 0x00000100
    # sext.h x12, x11 (0x00000100)
    # Expected: 0x00000100
    sext.h x12, x11

    # Test 22: Small negative values (0xFF00 = -256)
    li   x13, 0x0000FF00
    # sext.h x14, x13 (0x0000FF00)
    # Expected: 0xFFFFFF00
    sext.h x14, x13

    # Test 23: Halfword = 0x0002
    li   x15, 0xFEDC0002
    # sext.h x16, x15 (0xFEDC0002)
    # Expected: 0x00000002
    sext.h x16, x15

    # Test 24: Halfword = 0x8002 (negative)
    li   x17, 0x11118002
    # sext.h x18, x17 (0x11118002)
    # Expected: 0xFFFF8002
    sext.h x18, x17

    # Test 25: Halfword = 0x3FFF
    li   x19, 0x00003FFF
    # sext.h x20, x19 (0x00003FFF)
    # Expected: 0x00003FFF
    sext.h x20, x19

    # Test 26: Halfword = 0xBFFF (negative)
    li   x21, 0x0000BFFF
    # sext.h x22, x21 (0x0000BFFF)
    # Expected: 0xFFFFBFFF
    sext.h x22, x21

    # Test 27: Halfword = 0x00FF
    li   x23, 0xAAAA00FF
    # sext.h x24, x23 (0xAAAA00FF)
    # Expected: 0x000000FF
    sext.h x24, x23

    # Test 28: Halfword = 0x80FF (negative)
    li   x25, 0x555580FF
    # sext.h x26, x25 (0x555580FF)
    # Expected: 0xFFFF80FF
    sext.h x26, x25

    # Test 29: Halfword = 0x1234
    li   x27, 0x00001234
    # sext.h x28, x27 (0x00001234)
    # Expected: 0x00001234
    sext.h x28, x27

    # Test 30: Halfword = 0x9876 (negative)
    li   x29, 0xFFFF9876
    # sext.h x30, x29 (0xFFFF9876)
    # Expected: 0xFFFF9876
    sext.h x30, x29

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
