#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbb_cpop
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CPOP (Zbb)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # CPOP operation: rd = count_population(rs1)
    # Counts the number of set bits (1s) in the source operand
    # Result range: 0-32

    # Test data with various bit patterns
    li  x1,  0x00000000  # All zeros -> 0 ones
    li  x2,  0xFFFFFFFF  # All ones -> 32 ones
    li  x3,  0x00000001  # Single bit (bit 0) -> 1 one
    li  x4,  0x80000000  # Single bit (bit 31) -> 1 one
    li  x5,  0x0000000F  # Lower nibble set -> 4 ones
    li  x6,  0xF0000000  # Upper nibble set -> 4 ones
    li  x7,  0x000000FF  # Lower byte set -> 8 ones
    li  x8,  0xFF000000  # Upper byte set -> 8 ones
    li  x9,  0x0000FFFF  # Lower half set -> 16 ones
    li  x10, 0xFFFF0000  # Upper half set -> 16 ones

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST CPOP (Count Population) INSTRUCTION
    # Format: cpop rd, rs1
    # Operation: rd = count_population(rs1)
    # Encoding: 0110000 00010 rs1[4:0] 001 rd[4:0] 0010011
    # Use case: Bit manipulation, counting set bits
    #-------------------------------------------------

    # Test 1: All zeros -> 0 ones
    # cpop x11, x1 (0x00000000)
    # Expected: 0
    cpop x11, x1

    # Test 2: All ones -> 32 ones
    # cpop x12, x2 (0xFFFFFFFF)
    # Expected: 32
    cpop x12, x2

    # Test 3: Single bit at position 0 -> 1 one
    # cpop x13, x3 (0x00000001)
    # Expected: 1
    cpop x13, x3

    # Test 4: Single bit at position 31 -> 1 one
    # cpop x14, x4 (0x80000000)
    # Expected: 1
    cpop x14, x4

    # Test 5: Lower nibble (4 bits) -> 4 ones
    # cpop x15, x5 (0x0000000F)
    # Expected: 4
    cpop x15, x5

    # Test 6: Upper nibble (4 bits) -> 4 ones
    # cpop x16, x6 (0xF0000000)
    # Expected: 4
    cpop x16, x6

    # Test 7: Lower byte (8 bits) -> 8 ones
    # cpop x17, x7 (0x000000FF)
    # Expected: 8
    cpop x17, x7

    # Test 8: Upper byte (8 bits) -> 8 ones
    # cpop x18, x8 (0xFF000000)
    # Expected: 8
    cpop x18, x8

    # Test 9: Lower half (16 bits) -> 16 ones
    # cpop x19, x9 (0x0000FFFF)
    # Expected: 16
    cpop x19, x9

    # Test 10: Upper half (16 bits) -> 16 ones
    # cpop x20, x10 (0xFFFF0000)
    # Expected: 16
    cpop x20, x10

    # Test 11: Alternating bits pattern 1 (0xAAAAAAAA)
    li   x21, 0xAAAAAAAA
    # cpop x22, x21 (0xAAAAAAAA)
    # Expected: 16
    cpop x22, x21

    # Test 12: Alternating bits pattern 2 (0x55555555)
    li   x23, 0x55555555
    # cpop x24, x23 (0x55555555)
    # Expected: 16
    cpop x24, x23

    # Test 13: Sparse bits (0x80008001) -> 3 ones
    li   x25, 0x80008001
    cpop x26, x25
    # Expected: 3

    # Test 14: Two adjacent bytes (0x00FFFF00) -> 16 ones
    li   x27, 0x00FFFF00
    cpop x28, x27
    # Expected: 16

    # Test 15: Diagonal pattern (0x01010101) -> 4 ones
    li   x29, 0x01010101
    cpop x30, x29
    # Expected: 4

    # Test 16: Checkerboard upper bits (0x88888888) -> 8 ones
    li   x1, 0x88888888
    cpop x2, x1
    # Expected: 8

    # Test 17: Powers of 2 sum (0x00000007) -> 3 ones
    li   x3, 0x00000007
    cpop x4, x3
    # Expected: 3

    # Test 18: Three bytes (0x00FFFFFF) -> 24 ones
    li   x5, 0x00FFFFFF
    cpop x6, x5
    # Expected: 24

    # Test 19: High and low nibbles (0xF000000F) -> 8 ones
    li   x7, 0xF000000F
    cpop x8, x7
    # Expected: 8

    # Test 20: Sequential bits low (0x0000001F) -> 5 ones
    li   x9, 0x0000001F
    cpop x10, x9
    # Expected: 5

    # Test 21: Sequential bits high (0xF8000000) -> 5 ones
    li   x11, 0xF8000000
    cpop x12, x11
    # Expected: 5

    # Test 22: Middle bits (0x00FFFF00) -> 16 ones
    li   x13, 0x00FFFF00
    cpop x14, x13
    # Expected: 16

    # Test 23: Sparse pattern (0x11111111) -> 8 ones
    li   x15, 0x11111111
    cpop x16, x15
    # Expected: 8

    # Test 24: Dense pattern (0xEEEEEEEE) -> 24 ones
    li   x17, 0xEEEEEEEE
    cpop x18, x17
    # Expected: 24

    # Test 25: Single bit at position 16 (0x00010000) -> 1 one
    li   x19, 0x00010000
    cpop x20, x19
    # Expected: 1

    # Test 26: Two bits at positions 0 and 31 (0x80000001) -> 2 ones
    li   x21, 0x80000001
    cpop x22, x21
    # Expected: 2

    # Test 27: 7 consecutive bits (0x0000007F) -> 7 ones
    li   x23, 0x0000007F
    cpop x24, x23
    # Expected: 7

    # Test 28: 9 consecutive bits (0x000001FF) -> 9 ones
    li   x25, 0x000001FF
    cpop x26, x25
    # Expected: 9

    # Test 29: Symmetric pattern (0x18244281) -> 8 ones
    li   x27, 0x18244281
    cpop x28, x27
    # Expected: 8

    # Test 30: Almost all ones (0xFFFFFFFE) -> 31 ones
    li   x29, 0xFFFFFFFE
    cpop x30, x29
    # Expected: 31

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
