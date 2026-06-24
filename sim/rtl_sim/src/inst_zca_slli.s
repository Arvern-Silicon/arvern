#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_slli
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SLLI
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

    # Load registers with test patterns
    li  x8,  0x00000001  # Single bit
    li  x9,  0x00000080  # Bit 7 set
    li  x10, 0x00005555  # Alternating pattern (low)
    li  x11, 0x12345678  # Test pattern
    li  x12, 0x0F0F0F0F  # Nibble pattern
    li  x13, 0x000000FF  # Byte
    li  x14, 0x00000001  # Single bit
    li  x15, 0xFEDCBA98  # Test pattern

    # Setup markers
    li  x1,  0x511ED111
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.SLLI (Compressed Shift Left Logical Immediate)
    # Format: c.slli rd, shamt
    # Function: rd = rd << shamt (logical shift left, zero-fill)
    # Registers: rd can be any register x0-x31 (not just x8-x15)
    # Shift amount: 5-bit unsigned (1-31, shift by 0 is illegal)
    # Encoding: 000_0_rd[4:0]_shamt[4:0]_10
    #
    # Key behavior:
    # - Always zero-fills from the right
    # - Upper bits are discarded
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Basic shifts with different amounts
    #-------------------------------------------------
    c.slli x8,  1        # 0x00000001 << 1  = 0x00000002
    c.slli x9,  4        # 0x00000080 << 4  = 0x00000800
    c.slli x10, 8        # 0x00005555 << 8  = 0x00555500
    c.slli x11, 12       # 0x12345678 << 12 = 0x45678000
    c.slli x12, 16       # 0x0F0F0F0F << 16 = 0x0F0F0000
    c.slli x13, 20       # 0x000000FF << 20 = 0x0FF00000
    c.slli x14, 24       # 0x00000001 << 24 = 0x01000000
    c.slli x15, 28       # 0xFEDCBA98 << 28 = 0x80000000

.option norvc
    # Backup first set of results to x16-x23
    addi x16, x8,  0     # Backup x8:  0x00000002
    addi x17, x9,  0     # Backup x9:  0x00000800
    addi x18, x10, 0     # Backup x10: 0x00555500
    addi x19, x11, 0     # Backup x11: 0x45678000
    addi x20, x12, 0     # Backup x12: 0x0F0F0000
    addi x21, x13, 0     # Backup x13: 0x0FF00000
    addi x22, x14, 0     # Backup x14: 0x01000000
    addi x23, x15, 0     # Backup x15: 0x80000000

    # Reload for second set
    li  x8,  0xFFFFFFFF  # All 1s
    li  x9,  0x00000001  # Single bit
    li  x10, 0xAAAAAAAA  # Alternating pattern
    li  x11, 0xF0000000  # Upper nibble
    li  x12, 0x0000FFFF  # Lower halfword
    li  x13, 0xC0C0C0C0  # Pattern
    li  x14, 0x12345678  # Test value
    li  x15, 0xABCDEF01  # Test value
.option rvc

    #-------------------------------------------------
    # Test Set 2: Boundary and special cases
    #-------------------------------------------------
    c.slli x8,  1        # 0xFFFFFFFF << 1  = 0xFFFFFFFE (min shift)
    c.slli x9,  31       # 0x00000001 << 31 = 0x80000000 (max shift, MSB set)
    c.slli x10, 16       # 0xAAAAAAAA << 16 = 0xAAAA0000
    c.slli x11, 4        # 0xF0000000 << 4  = 0x00000000 (overflow)
    c.slli x12, 8        # 0x0000FFFF << 8  = 0x00FFFF00
    c.slli x13, 2        # 0xC0C0C0C0 << 2  = 0x03030300
    c.slli x14, 15       # 0x12345678 << 15 = 0x2B3C0000
    c.slli x15, 17       # 0xABCDEF01 << 17 = 0xDE020000

.option norvc
    # Backup second set of results to x24-x30, x2-x4
    addi x24, x8,  0     # Backup x8:  0xFFFFFFFE
    addi x25, x9,  0     # Backup x9:  0x80000000
    addi x26, x10, 0     # Backup x10: 0xAAAA0000
    addi x27, x11, 0     # Backup x11: 0x00000000
    addi x28, x12, 0     # Backup x12: 0x00FFFF00
    addi x29, x13, 0     # Backup x13: 0x03030300
    addi x30, x14, 0     # Backup x14: 0x2B3C0000
    addi x2,  x15, 0     # Backup x15: 0xDE020000

    # Reload for third set (consecutive shifts)
    li  x8,  0x00000001  # Start with 1
.option rvc

    #-------------------------------------------------
    # Test Set 3: Multiple consecutive shifts
    #-------------------------------------------------
    c.slli x8,  1        # 0x00000001 << 1  = 0x00000002
    c.slli x8,  1        # 0x00000002 << 1  = 0x00000004
    c.slli x8,  1        # 0x00000004 << 1  = 0x00000008
    c.slli x8,  1        # 0x00000008 << 1  = 0x00000010

.option norvc
    # Backup third set result
    addi x3, x8, 0       # Backup x8: 0x00000010

    # Reload for fourth set (overflow behavior)
    li  x9,  0x80000000  # MSB set
    li  x10, 0x00000001  # Single bit
.option rvc

    #-------------------------------------------------
    # Test Set 4: Overflow and wrap behavior
    #-------------------------------------------------
    c.slli x9,  1        # 0x80000000 << 1  = 0x00000000 (overflow to zero)
    c.slli x10, 31       # 0x00000001 << 31 = 0x80000000 (set MSB)

.option norvc
    # Backup fourth set results
    addi x4, x9,  0      # Backup x9:  0x00000000
    addi x5, x10, 0      # Backup x10: 0x80000000

    # Reload for fifth set (zero value)
    li  x11, 0x00000000  # Zero
.option rvc

    #-------------------------------------------------
    # Test Set 5: Zero value shifts
    #-------------------------------------------------
    c.slli x11, 16       # 0x00000000 << 16 = 0x00000000 (zero stays zero)

.option norvc
    # Backup fifth set result
    addi x6, x11, 0      # Backup x11: 0x00000000

    # Test with non-compressed registers
    li  x25, 0x00000055  # Use x25 (not compressed)
    li  x26, 0x000000AA  # Use x26 (not compressed)
    li  x27, 0x12345678  # Use x27
.option rvc

    #-------------------------------------------------
    # Test Set 6: Non-compressed registers (x16-x31)
    #-------------------------------------------------
    c.slli x25, 8        # 0x00000055 << 8  = 0x00005500
    c.slli x26, 12       # 0x000000AA << 12 = 0x000AA000
    c.slli x27, 4        # 0x12345678 << 4  = 0x23456780

.option norvc
    # Backup sixth set results
    addi x7, x25, 0      # Backup x25: 0x00005500
    addi x18, x26, 0     # Backup x26: 0x000AA000 (reuse x18)
    addi x19, x27, 0     # Backup x27: 0x23456780 (reuse x19)

    # Test odd shift amounts
    li  x12, 0x000F0F0F
    li  x13, 0x11111111
.option rvc

    #-------------------------------------------------
    # Test Set 7: Odd shift amounts
    #-------------------------------------------------
    c.slli x12, 7        # 0x000F0F0F << 7  = 0x07878780
    c.slli x13, 9        # 0x11111111 << 9  = 0x22222200

.option norvc
    # Backup seventh set results
    addi x20, x12, 0     # Backup x12: 0x07878780 (reuse x20)
    addi x21, x13, 0     # Backup x13: 0x22222200 (reuse x21)

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
