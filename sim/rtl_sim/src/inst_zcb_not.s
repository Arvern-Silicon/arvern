#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_not
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.NOT
#----------------------------------------------------------------------------

.section .text
.option norvc        # disable all compressed instructions in this section
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP
    #-------------------------------------------------

    # Load compressed registers (x8-x15) with test patterns
    li  x8,  0xAAAAAAAA  # Alternating pattern 1010...
    li  x9,  0x55555555  # Alternating pattern 0101...
    li  x10, 0xFFFFFFFF  # All 1s
    li  x11, 0x00000000  # All 0s
    li  x12, 0xF0F0F0F0  # Nibble pattern
    li  x13, 0x0F0F0F0F  # Inverse nibble
    li  x14, 0x12345678  # Test pattern
    li  x15, 0xABCDEF01  # Test pattern

    # Setup markers
    li  x1,  0xB171AB1E
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.NOT (Compressed NOT / Bitwise complement)
    # Format: c.not rd'/rs1'
    # Function: rd' = ~rd'
    # Registers: rd'/rs1' are x8-x15 (compressed register encoding)
    # Encoding: 100_111_rs1'/rd'[2:0]_11100_01
    #
    # NOT operation: inverts all bits
    # 0 → 1
    # 1 → 0
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Basic NOT operations on all compressed registers
    #-------------------------------------------------
    c.not x8         # 0xAAAAAAAA → 0x55555555
    c.not x9         # 0x55555555 → 0xAAAAAAAA
    c.not x10        # 0xFFFFFFFF → 0x00000000
    c.not x11        # 0x00000000 → 0xFFFFFFFF
    c.not x12        # 0xF0F0F0F0 → 0x0F0F0F0F
    c.not x13        # 0x0F0F0F0F → 0xF0F0F0F0
    c.not x14        # 0x12345678 → 0xEDCBA987
    c.not x15        # 0xABCDEF01 → 0x543210FE

.option norvc
    # Backup first set of results to x16-x23
    addi x16, x8,  0     # Backup x8:  0x55555555
    addi x17, x9,  0     # Backup x9:  0xAAAAAAAA
    addi x18, x10, 0     # Backup x10: 0x00000000
    addi x19, x11, 0     # Backup x11: 0xFFFFFFFF
    addi x20, x12, 0     # Backup x12: 0x0F0F0F0F
    addi x21, x13, 0     # Backup x13: 0xF0F0F0F0
    addi x22, x14, 0     # Backup x14: 0xEDCBA987
    addi x23, x15, 0     # Backup x15: 0x543210FE

.option rvc

    #-------------------------------------------------
    # Test Set 2: Double NOT (idempotency: ~~x = x)
    # Apply NOT twice to verify we get back original value
    #-------------------------------------------------
    c.not x8         # 0x55555555 → 0xAAAAAAAA (back to original!)
    c.not x10        # 0x00000000 → 0xFFFFFFFF (back to original!)
    c.not x12        # 0x0F0F0F0F → 0xF0F0F0F0 (back to original!)
    c.not x14        # 0xEDCBA987 → 0x12345678 (back to original!)

.option norvc
    # Backup second set of results to x24-x27
    addi x24, x8,  0     # Backup x8:  0xAAAAAAAA (original restored)
    addi x25, x10, 0     # Backup x10: 0xFFFFFFFF (original restored)
    addi x26, x12, 0     # Backup x12: 0xF0F0F0F0 (original restored)
    addi x27, x14, 0     # Backup x14: 0x12345678 (original restored)

    # Reload for third set
    li  x8,  0x80000000  # MSB set
    li  x9,  0x00000001  # LSB set
    li  x10, 0xFF00FF00  # Byte pattern
    li  x11, 0x00FF00FF  # Inverse byte pattern
.option rvc

    #-------------------------------------------------
    # Test Set 3: Boundary and special bit patterns
    #-------------------------------------------------
    c.not x8         # 0x80000000 → 0x7FFFFFFF
    c.not x9         # 0x00000001 → 0xFFFFFFFE
    c.not x10        # 0xFF00FF00 → 0x00FF00FF
    c.not x11        # 0x00FF00FF → 0xFF00FF00

.option norvc
    # Backup third set of results to x28-x30, x2
    addi x28, x8,  0     # Backup x8:  0x7FFFFFFF
    addi x29, x9,  0     # Backup x9:  0xFFFFFFFE
    addi x30, x10, 0     # Backup x10: 0x00FF00FF
    addi x2,  x11, 0     # Backup x11: 0xFF00FF00

    # Reload for fourth set (nibble patterns)
    li  x12, 0xA5A5A5A5  # Alternating nibble pattern
    li  x13, 0x5A5A5A5A  # Inverse alternating nibble
    li  x14, 0xC3C3C3C3  # 2-bit pattern
    li  x15, 0x3C3C3C3C  # Inverse 2-bit pattern
.option rvc

    #-------------------------------------------------
    # Test Set 4: Complex bit patterns
    #-------------------------------------------------
    c.not x12        # 0xA5A5A5A5 → 0x5A5A5A5A
    c.not x13        # 0x5A5A5A5A → 0xA5A5A5A5
    c.not x14        # 0xC3C3C3C3 → 0x3C3C3C3C
    c.not x15        # 0x3C3C3C3C → 0xC3C3C3C3

.option norvc
    # Backup fourth set of results to x3-x6
    addi x3, x12, 0      # Backup x12: 0x5A5A5A5A
    addi x4, x13, 0      # Backup x13: 0xA5A5A5A5
    addi x5, x14, 0      # Backup x14: 0x3C3C3C3C
    addi x6, x15, 0      # Backup x15: 0xC3C3C3C3

    # Reload for fifth set (triple NOT test)
    li  x8,  0xDEADBEEF
    li  x9,  0xCAFEBABE
.option rvc

    #-------------------------------------------------
    # Test Set 5: Triple NOT (should invert once: ~~~x = ~x)
    #-------------------------------------------------
    c.not x8         # 0xDEADBEEF → 0x21524110
    c.not x8         # 0x21524110 → 0xDEADBEEF
    c.not x8         # 0xDEADBEEF → 0x21524110

    c.not x9         # 0xCAFEBABE → 0x35014541
    c.not x9         # 0x35014541 → 0xCAFEBABE
    c.not x9         # 0xCAFEBABE → 0x35014541

.option norvc
    # Backup fifth set of results to x7, x28
    addi x7, x8, 0       # Backup x8: 0x21524110 (inverted once)
    addi x28, x9, 0      # Backup x9: 0x35014541 (inverted once)

    # Reload for sixth set (known patterns with predictable complements)
    li  x10, 0x00000000  # Zero
    li  x11, 0xFFFFFFFF  # All ones
    li  x12, 0x01010101  # Sparse pattern
    li  x13, 0x80808080  # Sparse high bits
.option rvc

    #-------------------------------------------------
    # Test Set 6: Simple predictable patterns
    #-------------------------------------------------
    c.not x10        # 0x00000000 → 0xFFFFFFFF
    c.not x11        # 0xFFFFFFFF → 0x00000000
    c.not x12        # 0x01010101 → 0xFEFEFEFE
    c.not x13        # 0x80808080 → 0x7F7F7F7F

.option norvc
    # Backup sixth set of results - final values
    # x10 = 0xFFFFFFFF, x11 = 0x00000000, x12 = 0xFEFEFEFE, x13 = 0x7F7F7F7F
    # Note: Some registers like x8, x9 from Test Set 5 remain unchanged

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
