#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_zexth
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZEXT.H (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # ZEXT.H operation: rd = zero_extend(rs1[15:0])
    # Zero-extends the lower 16 bits (halfword) to 32 bits
    # Upper 16 bits are always cleared, regardless of bit 15

    # Test data with various halfword values
    li  x1,  0x00000000  # Zero
    li  x2,  0x00000001  # Small value: 1
    li  x3,  0x00007FFF  # 0x7FFF
    li  x4,  0x00008000  # 0x8000 (bit 15 set)
    li  x5,  0x0000FFFF  # All ones in halfword
    li  x6,  0x00005555  # 0x5555
    li  x7,  0x0000AAAA  # 0xAAAA (bit 15 set)
    li  x8,  0xFFFFFFFF  # All ones, halfword = 0xFFFF
    li  x9,  0x12345678  # Upper bits set, halfword = 0x5678
    li  x10, 0xABCDABCD  # Upper bits set, halfword = 0xABCD (bit 15 set)

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST ZEXT.H (Zero-Extend Halfword) INSTRUCTION
    # Format: zext.h rd, rs1
    # Operation: rd = {16'b0, rs1[15:0]}
    # Encoding: 0000100 00000 rs1[4:0] 100 rd[4:0] 0110011
    # Use case: Zero-extending 16-bit unsigned values
    #-------------------------------------------------

    # Test 1: Zero halfword -> 0x00000000
    # zext.h x11, x1 (0x00000000)
    # Expected: 0x00000000
    zext.h x11, x1

    # Test 2: Small value
    # zext.h x12, x2 (0x00000001)
    # Expected: 0x00000001
    zext.h x12, x2

    # Test 3: 0x7FFF (bit 15 = 0)
    # zext.h x13, x3 (0x00007FFF)
    # Expected: 0x00007FFF
    zext.h x13, x3

    # Test 4: 0x8000 (bit 15 = 1, but still zero-extended!)
    # zext.h x14, x4 (0x00008000)
    # Expected: 0x00008000 (NOT sign-extended)
    zext.h x14, x4

    # Test 5: All ones in halfword (0xFFFF)
    # zext.h x15, x5 (0x0000FFFF)
    # Expected: 0x0000FFFF (NOT 0xFFFFFFFF)
    zext.h x15, x5

    # Test 6: 0x5555
    # zext.h x16, x6 (0x00005555)
    # Expected: 0x00005555
    zext.h x16, x6

    # Test 7: 0xAAAA (bit 15 = 1)
    # zext.h x17, x7 (0x0000AAAA)
    # Expected: 0x0000AAAA (NOT sign-extended)
    zext.h x17, x7

    # Test 8: All ones, halfword = 0xFFFF
    # zext.h x18, x8 (0xFFFFFFFF)
    # Expected: 0x0000FFFF
    zext.h x18, x8

    # Test 9: Upper bits set, halfword = 0x5678
    # zext.h x19, x9 (0x12345678)
    # Expected: 0x00005678
    zext.h x19, x9

    # Test 10: Upper bits set, halfword = 0xABCD (bit 15 set)
    # zext.h x20, x10 (0xABCDABCD)
    # Expected: 0x0000ABCD
    zext.h x20, x10

    # Test 11: 0x7FFE
    li   x21, 0x00007FFE
    # zext.h x22, x21 (0x00007FFE)
    # Expected: 0x00007FFE
    zext.h x22, x21

    # Test 12: 0x8001 (bit 15 set)
    li   x23, 0x00008001
    # zext.h x24, x23 (0x00008001)
    # Expected: 0x00008001
    zext.h x24, x23

    # Test 13: Halfword = 0x0001 with upper bits set
    li   x25, 0xFFFF0001
    # zext.h x26, x25 (0xFFFF0001)
    # Expected: 0x00000001
    zext.h x26, x25

    # Test 14: Halfword = 0xFFFE with upper bits set
    li   x27, 0x1234FFFE
    # zext.h x28, x27 (0x1234FFFE)
    # Expected: 0x0000FFFE
    zext.h x28, x27

    # Test 15: 0x4000
    li   x29, 0x00004000
    # zext.h x30, x29 (0x00004000)
    # Expected: 0x00004000
    zext.h x30, x29

    # Test 16: 0xC000 (bit 15 set)
    li   x1, 0x0000C000
    # zext.h x2, x1 (0x0000C000)
    # Expected: 0x0000C000
    zext.h x2, x1

    # Test 17: Halfword = 0x0000 with upper bits set
    li   x3, 0xFFFF0000
    # zext.h x4, x3 (0xFFFF0000)
    # Expected: 0x00000000
    zext.h x4, x3

    # Test 18: Halfword = 0x7FFF with upper bits set
    li   x5, 0xABCD7FFF
    # zext.h x6, x5 (0xABCD7FFF)
    # Expected: 0x00007FFF
    zext.h x6, x5

    # Test 19: Halfword = 0x8000 with upper bits set
    li   x7, 0x12348000
    # zext.h x8, x7 (0x12348000)
    # Expected: 0x00008000
    zext.h x8, x7

    # Test 20: Halfword = 0xFFFF with different upper bits
    li   x9, 0x5678FFFF
    # zext.h x10, x9 (0x5678FFFF)
    # Expected: 0x0000FFFF
    zext.h x10, x9

    # Test 21: 0x0100
    li   x11, 0x00000100
    # zext.h x12, x11 (0x00000100)
    # Expected: 0x00000100
    zext.h x12, x11

    # Test 22: 0xFF00 (bit 15 set)
    li   x13, 0x0000FF00
    # zext.h x14, x13 (0x0000FF00)
    # Expected: 0x0000FF00
    zext.h x14, x13

    # Test 23: Halfword = 0x0002 with upper bits
    li   x15, 0xFEDC0002
    # zext.h x16, x15 (0xFEDC0002)
    # Expected: 0x00000002
    zext.h x16, x15

    # Test 24: Halfword = 0x8002 (bit 15 set)
    li   x17, 0x11118002
    # zext.h x18, x17 (0x11118002)
    # Expected: 0x00008002
    zext.h x18, x17

    # Test 25: 0x3FFF
    li   x19, 0x00003FFF
    # zext.h x20, x19 (0x00003FFF)
    # Expected: 0x00003FFF
    zext.h x20, x19

    # Test 26: 0xBFFF (bit 15 set)
    li   x21, 0x0000BFFF
    # zext.h x22, x21 (0x0000BFFF)
    # Expected: 0x0000BFFF
    zext.h x22, x21

    # Test 27: Halfword = 0x00FF with upper bits
    li   x23, 0xAAAA00FF
    # zext.h x24, x23 (0xAAAA00FF)
    # Expected: 0x000000FF
    zext.h x24, x23

    # Test 28: Halfword = 0x80FF (bit 15 set)
    li   x25, 0x555580FF
    # zext.h x26, x25 (0x555580FF)
    # Expected: 0x000080FF
    zext.h x26, x25

    # Test 29: 0x1234
    li   x27, 0x00001234
    # zext.h x28, x27 (0x00001234)
    # Expected: 0x00001234
    zext.h x28, x27

    # Test 30: Halfword = 0x9876 (bit 15 set)
    li   x29, 0xFFFF9876
    # zext.h x30, x29 (0xFFFF9876)
    # Expected: 0x00009876
    zext.h x30, x29

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
