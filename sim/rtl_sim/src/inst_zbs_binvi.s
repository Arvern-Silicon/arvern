#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbs_binvi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BINVI (Zbs)
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # BINVI operation: rd = rs1 ^ (1 << imm[4:0])
    # Inverts (toggles) a single bit at the immediate position

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
    # TEST BINVI (Bit Invert Immediate) INSTRUCTION
    # Format: binvi rd, rs1, imm
    # Operation: rd = rs1 ^ (1 << imm[4:0])
    # Encoding: 0110100 imm[4:0] rs1[4:0] 001 rd[4:0] 0010011
    # Use case: Toggle specific bit positions using immediate
    #-------------------------------------------------

    # Test 1: Invert bit 0 from all ones -> bit 0 becomes 0
    binvi x11, x1, 0
    # Expected: 0xFFFFFFFE

    # Test 2: Invert bit 31 from all ones -> bit 31 becomes 0
    binvi x12, x1, 31
    # Expected: 0x7FFFFFFF

    # Test 3: Invert bit 15 from all ones -> bit 15 becomes 0
    binvi x13, x1, 15
    # Expected: 0xFFFF7FFF

    # Test 4: Invert bit 0 from all zeros -> bit 0 becomes 1
    binvi x14, x2, 0
    # Expected: 0x00000001

    # Test 5: Invert bit 8 from pattern 0x12345678
    # Bit 8 of 0x12345678 is 0, so it becomes 1
    binvi x15, x3, 8
    # Expected: 0x12345778

    # Test 6: Invert bit 10 from 0x12345678
    # Bit 10 of 0x12345678 is 1, so it becomes 0
    binvi x16, x3, 10
    # Expected: 0x12345278

    # Test 7: Invert bit 4 from 0xAAAAAAAA
    # Bit 4 of 0xAAAAAAAA is 0 (pattern 10101010)
    binvi x17, x4, 4
    # Expected: 0xAAAAAABA

    # Test 8: Invert bit 7 from 0xAAAAAAAA
    # Bit 7 of 0xAAAAAAAA is 1
    binvi x18, x4, 7
    # Expected: 0xAAAAAA2A

    # Test 9: Invert bit 12 from 0x55555555
    # Bit 12 of 0x55555555 is 1 (pattern 01010101)
    binvi x19, x5, 12
    # Expected: 0x55554555

    # Test 10: Invert bit 16 from 0x55555555
    # Bit 16 of 0x55555555 is 1
    binvi x20, x5, 16
    # Expected: 0x55545555

    # Test 11: Invert bit 31 from 0x80000000 -> bit 31 becomes 0
    binvi x21, x6, 31
    # Expected: 0x00000000

    # Test 12: Invert bit 0 from 0x00000001 -> bit 0 becomes 0
    binvi x22, x7, 0
    # Expected: 0x00000000

    # Test 13: Invert bit 7 from 0xF0F0F0F0
    # Bit 7 of 0xF0F0F0F0 is 1 (pattern 11110000)
    binvi x23, x8, 7
    # Expected: 0xF0F0F070

    # Test 14: Invert bit 3 from 0xF0F0F0F0
    # Bit 3 of 0xF0F0F0F0 is 0
    binvi x24, x8, 3
    # Expected: 0xF0F0F0F8

    # Test 15: Invert bit 20 from 0x0F0F0F0F
    # Bit 20 of 0x0F0F0F0F is 0 (pattern 00001111)
    binvi x25, x9, 20
    # Expected: 0x0F1F0F0F

    # Test 16: Invert bit 24 from 0x0F0F0F0F
    # Bit 24 of 0x0F0F0F0F is 1
    binvi x26, x9, 24
    # Expected: 0x0E0F0F0F

    # Test 17: Invert bit 1 from 0xDEADBEEF
    # Bit 1 of 0xDEADBEEF is 1
    binvi x27, x10, 1
    # Expected: 0xDEADBEED

    # Test 18: Invert bit 5 from 0xDEADBEEF
    # Bit 5 of 0xDEADBEEF is 1
    binvi x28, x10, 5
    # Expected: 0xDEADBECF

    # Test 19: Invert bit 20 from 0xDEADBEEF
    # Bit 20 of 0xDEADBEEF is 0
    binvi x29, x10, 20
    # Expected: 0xDEBDBEEF

    # Test 20: Invert bit 27 from 0xDEADBEEF
    # Bit 27 of 0xDEADBEEF is 1
    binvi x30, x10, 27
    # Expected: 0xD6ADBEEF

    # Test 21-30: Additional edge cases and patterns

    # Test 21: Invert bit 1 from all ones
    li  x1, 0xFFFFFFFF
    binvi x1, x1, 1
    # Expected: 0xFFFFFFFD

    # Test 22: Invert bits 2, 3, 4 sequentially from all zeros
    li  x2, 0x00000000
    binvi x2, x2, 2
    binvi x2, x2, 3
    binvi x2, x2, 4
    # Expected: 0x0000001C (bits 2, 3, 4 set)

    # Test 23: Invert bit 30 from pattern
    li  x3, 0x7FFFFFFF
    binvi x3, x3, 30
    # Expected: 0x3FFFFFFF

    # Test 24: Invert bit 16 from pattern
    li  x4, 0x12345678
    binvi x4, x4, 16
    # Expected: 0x12355678

    # Test 25: Invert bit 25 from pattern
    li  x5, 0xAAAAAAAA
    binvi x5, x5, 25
    # Expected: 0xA8AAAAAA (bit 25 is 1, becomes 0)

    # Test 26: Invert bit 0 from pattern
    li  x6, 0x55555555
    binvi x6, x6, 0
    # Expected: 0x55555554

    # Test 27: Invert bit 29 from pattern
    li  x7, 0xF0F0F0F0
    binvi x7, x7, 29
    # Expected: 0xD0F0F0F0

    # Test 28: Invert bit 11 from pattern
    li  x8, 0x0F0F0F0F
    binvi x8, x8, 11
    # Expected: 0x0F0F0F0F ^ (1 << 11) = 0x0F0F070F

    # Test 29: Invert bit 17 from pattern
    li  x9, 0xABCDEF01
    binvi x9, x9, 17
    # Expected: 0xABCDEF01 ^ (1 << 17) = 0xABCFEF01

    # Test 30: Invert bit 22 from pattern
    li  x10, 0x87654321
    binvi x10, x10, 22
    # Expected: 0x87254321

    #-------------------------------------------------
    # END OF ORIGINAL TESTS (sync point 2)
    #-------------------------------------------------

    fence

    li  x31, 0x12345678

    #-------------------------------------------------
    # COVERAGE TESTS: patterns matching embench_minver
    #-------------------------------------------------

    # --- Gap 1: binvi rd, rd, 31 (in-place bit-31 flip) ---
    # Exact pattern used 3x in minver: binvi s0, s0, 0x1f
    # Tests 21-30 above cover rd=rs1 but never with imm=31; this fills that gap.

    # Test 31: positive float bit pattern -> negative (bit 31: 0 -> 1)
    li  x5, 0x3F800000      # +1.0 float bit pattern (bit 31 = 0)
    binvi x5, x5, 31        # Expected: 0xBF800000

    # Test 32: negative float bit pattern -> positive (bit 31: 1 -> 0)
    li  x6, 0xC0000000      # -2.0 float bit pattern (bit 31 = 1)
    binvi x6, x6, 31        # Expected: 0x40000000

    # Test 33: s0 (x8) register — exact minver register used in fabsf
    li  x8, 0xBF800000      # -1.0 float bit pattern (bit 31 = 1)
    binvi x8, x8, 31        # Expected: 0x3F800000

    # --- Gap 2: binvi as fall-through of a NOT-taken branch ---
    # Minver pattern: bgez a0, skip; binvi s0, s0, 0x1f   (fabsf implementation)
    # The binvi executes only on the not-taken (fall-through) path.

    # Test 34: branch NOT taken (value is negative signed int), binvi must execute
    li   x3, 0xC0000000     # -2.0 float (bit 31=1, negative as signed int)
    bgez x3, test34_skip    # NOT taken: x3 is negative
    binvi x3, x3, 31        # Expected: 0x40000000 (must execute)
test34_skip:

    # Test 35: branch TAKEN (value is positive signed int), binvi must NOT execute
    li   x4, 0x3F800000     # +1.0 float (bit 31=0, positive as signed int)
    bgez x4, test35_skip    # TAKEN: x4 is positive
    binvi x4, x4, 31        # Must NOT execute
test35_skip:
    # x4 must remain 0x3F800000

    # --- Gap 3: binvi immediately followed by jal ---
    # Minver pattern: binvi a0, s0, 0x1f; jal __divsf3  (no instructions between)

    # Test 36: in-place binvi (rd=rs1) then jal
    li   x9, 0xC0000000     # -2.0 float bit pattern
    binvi x9, x9, 31        # Expected: 0x40000000
    jal  x1, test36_return  # JAL immediately after binvi (x1/ra gets return addr)
    nop                     # skipped by JAL
    nop                     # skipped by JAL
test36_return:

    # Test 37: binvi rd!=rs1 then jal (matches: binvi a0,s0,0x1f; jal __divsf3)
    li   x2, 0xBF800000     # -1.0 float bit pattern (source, like s0 in minver)
    binvi x10, x2, 31       # x10 = 0x3F800000, x2 unchanged
    jal  x1, test37_return  # JAL immediately after binvi
    nop                     # skipped by JAL
    nop                     # skipped by JAL
test37_return:

    #-------------------------------------------------
    # END OF TEST (sync point 3)
    #-------------------------------------------------

    fence

    li  x31, 0xCAFEBABE

end_of_test:
    nop
    j end_of_test     # infinite loop
