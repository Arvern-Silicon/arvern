#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_orcb
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ORC.B (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # ORC.B operation: rd[i*8+7:i*8] = {8{|rs1[i*8+7:i*8]}} for i=0,1,2,3
    # OR-combines all bits within each byte:
    #   - If any bit in a byte is 1, the entire byte becomes 0xFF
    #   - If all bits in a byte are 0, the entire byte remains 0x00

    # Test data with various byte patterns
    li  x1,  0x00000000  # All bytes zero
    li  x2,  0xFFFFFFFF  # All bytes 0xFF
    li  x3,  0x00000001  # Only LSB of byte 0 set
    li  x4,  0x01000000  # Only LSB of byte 3 set
    li  x5,  0x00010000  # Only LSB of byte 2 set
    li  x6,  0x00000100  # Only LSB of byte 1 set
    li  x7,  0x80000000  # Only MSB of byte 3 set
    li  x8,  0x00800000  # Only MSB of byte 2 set
    li  x9,  0x00008000  # Only MSB of byte 1 set
    li  x10, 0x00000080  # Only MSB of byte 0 set

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST ORC.B (OR-Combine Byte) INSTRUCTION
    # Format: orc.b rd, rs1
    # Operation: rd[i*8+7:i*8] = {8{|rs1[i*8+7:i*8]}} for i=0,1,2,3
    # Encoding: 0010100 00111 rs1[4:0] 101 rd[4:0] 0010011
    # Use case: Fast byte-level mask generation
    #-------------------------------------------------

    # Test 1: All bytes zero -> 0x00000000
    # orc.b x11, x1 (0x00000000)
    # Expected: 0x00000000
    orc.b x11, x1

    # Test 2: All bytes 0xFF -> 0xFFFFFFFF
    # orc.b x12, x2 (0xFFFFFFFF)
    # Expected: 0xFFFFFFFF
    orc.b x12, x2

    # Test 3: Only LSB of byte 0 set -> byte 0 becomes 0xFF
    # orc.b x13, x3 (0x00000001)
    # Expected: 0x000000FF
    orc.b x13, x3

    # Test 4: Only LSB of byte 3 set -> byte 3 becomes 0xFF
    # orc.b x14, x4 (0x01000000)
    # Expected: 0xFF000000
    orc.b x14, x4

    # Test 5: Only LSB of byte 2 set -> byte 2 becomes 0xFF
    # orc.b x15, x5 (0x00010000)
    # Expected: 0x00FF0000
    orc.b x15, x5

    # Test 6: Only LSB of byte 1 set -> byte 1 becomes 0xFF
    # orc.b x16, x6 (0x00000100)
    # Expected: 0x0000FF00
    orc.b x16, x6

    # Test 7: Only MSB of byte 3 set -> byte 3 becomes 0xFF
    # orc.b x17, x7 (0x80000000)
    # Expected: 0xFF000000
    orc.b x17, x7

    # Test 8: Only MSB of byte 2 set -> byte 2 becomes 0xFF
    # orc.b x18, x8 (0x00800000)
    # Expected: 0x00FF0000
    orc.b x18, x8

    # Test 9: Only MSB of byte 1 set -> byte 1 becomes 0xFF
    # orc.b x19, x9 (0x00008000)
    # Expected: 0x0000FF00
    orc.b x19, x9

    # Test 10: Only MSB of byte 0 set -> byte 0 becomes 0xFF
    # orc.b x20, x10 (0x00000080)
    # Expected: 0x000000FF
    orc.b x20, x10

    # Test 11: Mixed pattern 0x12345678
    li  x1, 0x12345678
    # Byte 3: 0x12 (has bits) -> 0xFF
    # Byte 2: 0x34 (has bits) -> 0xFF
    # Byte 1: 0x56 (has bits) -> 0xFF
    # Byte 0: 0x78 (has bits) -> 0xFF
    # orc.b x21, x1
    # Expected: 0xFFFFFFFF
    orc.b x21, x1

    # Test 12: Pattern with zero bytes 0x00FF0000
    li  x2, 0x00FF0000
    # Byte 3: 0x00 (no bits) -> 0x00
    # Byte 2: 0xFF (has bits) -> 0xFF
    # Byte 1: 0x00 (no bits) -> 0x00
    # Byte 0: 0x00 (no bits) -> 0x00
    # orc.b x22, x2
    # Expected: 0x00FF0000
    orc.b x22, x2

    # Test 13: Pattern with zero bytes 0xFF00FF00
    li  x3, 0xFF00FF00
    # Byte 3: 0xFF (has bits) -> 0xFF
    # Byte 2: 0x00 (no bits) -> 0x00
    # Byte 1: 0xFF (has bits) -> 0xFF
    # Byte 0: 0x00 (no bits) -> 0x00
    # orc.b x23, x3
    # Expected: 0xFF00FF00
    orc.b x23, x3

    # Test 14: Pattern with zero bytes 0x00FF00FF
    li  x4, 0x00FF00FF
    # Byte 3: 0x00 (no bits) -> 0x00
    # Byte 2: 0xFF (has bits) -> 0xFF
    # Byte 1: 0x00 (no bits) -> 0x00
    # Byte 0: 0xFF (has bits) -> 0xFF
    # orc.b x24, x4
    # Expected: 0x00FF00FF
    orc.b x24, x4

    # Test 15: Single bit per byte 0x01010101
    li  x5, 0x01010101
    # All bytes have at least one bit set
    # orc.b x25, x5
    # Expected: 0xFFFFFFFF
    orc.b x25, x5

    # Test 16: Single bit per byte 0x80808080
    li  x6, 0x80808080
    # All bytes have at least one bit set
    # orc.b x26, x6
    # Expected: 0xFFFFFFFF
    orc.b x26, x6

    # Test 17: Alternating bytes 0xAA00AA00
    li  x7, 0xAA00AA00
    # Byte 3: 0xAA (has bits) -> 0xFF
    # Byte 2: 0x00 (no bits) -> 0x00
    # Byte 1: 0xAA (has bits) -> 0xFF
    # Byte 0: 0x00 (no bits) -> 0x00
    # orc.b x27, x7
    # Expected: 0xFF00FF00
    orc.b x27, x7

    # Test 18: Alternating bytes 0x0055005
    li  x8, 0x00550055
    # Byte 3: 0x00 (no bits) -> 0x00
    # Byte 2: 0x55 (has bits) -> 0xFF
    # Byte 1: 0x00 (no bits) -> 0x00
    # Byte 0: 0x55 (has bits) -> 0xFF
    # orc.b x28, x8
    # Expected: 0x00FF00FF
    orc.b x28, x8

    # Test 19: Pattern 0xDEADBEEF
    li  x9, 0xDEADBEEF
    # All bytes have bits set
    # orc.b x29, x9
    # Expected: 0xFFFFFFFF
    orc.b x29, x9

    # Test 20: Pattern 0x10203040
    li  x10, 0x10203040
    # All bytes have at least one bit set
    # orc.b x30, x10
    # Expected: 0xFFFFFFFF
    orc.b x30, x10

    # Test 21: Pattern 0x00000000 (verify again)
    li  x1, 0x00000000
    # orc.b x1, x1
    # Expected: 0x00000000
    orc.b x1, x1

    # Test 22: Pattern 0x000000FF
    li  x2, 0x000000FF
    # orc.b x2, x2
    # Expected: 0x000000FF
    orc.b x2, x2

    # Test 23: Pattern 0x0000FF00
    li  x3, 0x0000FF00
    # orc.b x3, x3
    # Expected: 0x0000FF00
    orc.b x3, x3

    # Test 24: Pattern 0x00FF0000
    li  x4, 0x00FF0000
    # orc.b x4, x4
    # Expected: 0x00FF0000
    orc.b x4, x4

    # Test 25: Pattern 0xFF000000
    li  x5, 0xFF000000
    # orc.b x5, x5
    # Expected: 0xFF000000
    orc.b x5, x5

    # Test 26: Pattern 0xF0F0F0F0
    li  x6, 0xF0F0F0F0
    # All bytes have bits set
    # orc.b x6, x6
    # Expected: 0xFFFFFFFF
    orc.b x6, x6

    # Test 27: Pattern 0x0F0F0F0F
    li  x7, 0x0F0F0F0F
    # All bytes have bits set
    # orc.b x7, x7
    # Expected: 0xFFFFFFFF
    orc.b x7, x7

    # Test 28: Pattern 0x00000001
    li  x8, 0x00000001
    # orc.b x8, x8
    # Expected: 0x000000FF
    orc.b x8, x8

    # Test 29: Pattern 0x00010000
    li  x9, 0x00010000
    # orc.b x9, x9
    # Expected: 0x00FF0000
    orc.b x9, x9

    # Test 30: Pattern 0x01000000
    li  x10, 0x01000000
    # orc.b x10, x10
    # Expected: 0xFF000000
    orc.b x10, x10

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
