#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_srai
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SRAI
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
    # Mix of positive (MSB=0) and negative (MSB=1) values
    li  x8,  0xFFFFFFFF  # -1 (all 1s, negative)
    li  x9,  0x80000000  # Minimum negative
    li  x10, 0xAAAAAAAA  # Negative alternating
    li  x11, 0x12345678  # Positive mixed pattern
    li  x12, 0xF0F0F0F0  # Negative nibble pattern
    li  x13, 0x0F0F0F0F  # Positive nibble pattern
    li  x14, 0x00000001  # Positive single bit
    li  x15, 0xFEDCBA98  # Negative test pattern

    # Setup markers
    li  x1,  0xDEADBEEF
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.SRAI (Compressed Shift Right Arithmetic Immediate)
    # Format: c.srai rd', shamt
    # Function: rd' = rd' >> shamt (arithmetic, sign-extend)
    # Registers: rd' is x8-x15 (compressed register encoding)
    # Shift amount: 5-bit unsigned (0-31)
    # Encoding: 100_0_01_rd'[2:0]_shamt[4:0]_01
    #
    # Key difference from C.SRLI:
    # - C.SRAI sign-extends (fills with MSB)
    # - C.SRLI zero-fills
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Negative numbers (MSB=1) - should sign-extend
    #-------------------------------------------------
    c.srai x8,  1        # 0xFFFFFFFF >> 1  = 0xFFFFFFFF (all 1s preserved)
    c.srai x9,  4        # 0x80000000 >> 4  = 0xF8000000 (sign-extended)
    c.srai x10, 8        # 0xAAAAAAAA >> 8  = 0xFFAAAAAA (sign-extended)
    c.srai x12, 16       # 0xF0F0F0F0 >> 16 = 0xFFFFF0F0 (sign-extended)
    c.srai x15, 28       # 0xFEDCBA98 >> 28 = 0xFFFFFFFF (sign-extended)

.option norvc
    # Backup first set of results to x16-x20
    addi x16, x8,  0     # Backup x8
    addi x17, x9,  0     # Backup x9
    addi x18, x10, 0     # Backup x10
    addi x19, x12, 0     # Backup x12
    addi x20, x15, 0     # Backup x15

    # Reload with positive patterns
    li  x8,  0x7FFFFFFF  # Maximum positive
    li  x9,  0x12345678  # Positive pattern
    li  x10, 0x0F0F0F0F  # Positive pattern
    li  x11, 0x00000001  # Minimal positive
.option rvc

    #-------------------------------------------------
    # Test Set 2: Positive numbers (MSB=0) - should zero-fill
    #-------------------------------------------------
    c.srai x8,  1        # 0x7FFFFFFF >> 1  = 0x3FFFFFFF (zero-filled, positive)
    c.srai x9,  12       # 0x12345678 >> 12 = 0x00012345 (zero-filled, positive)
    c.srai x10, 20       # 0x0F0F0F0F >> 20 = 0x000000F0 (zero-filled, positive)
    c.srai x11, 24       # 0x00000001 >> 24 = 0x00000000 (zero-filled, positive)

.option norvc
    # Backup second set of results to x21-x24
    addi x21, x8,  0     # Backup x8
    addi x22, x9,  0     # Backup x9
    addi x23, x10, 0     # Backup x10
    addi x24, x11, 0     # Backup x11

    # Reload for boundary tests
    li  x8,  0x80000000  # Min negative
    li  x9,  0x80000001  # Almost min negative
    li  x10, 0xFFFFFFFF  # -1
    li  x11, 0x00000000  # Zero
.option rvc

    #-------------------------------------------------
    # Test Set 3: Boundary and special cases
    #-------------------------------------------------
    c.srai x8,  31       # 0x80000000 >> 31 = 0xFFFFFFFF (becomes -1)
    c.srai x9,  1        # 0x80000001 >> 1  = 0xC0000000 (sign-extended)
    c.srai x10, 1        # 0xFFFFFFFF >> 1  = 0xFFFFFFFF (sign-extended, stays -1)
    c.srai x11, 16       # 0x00000000 >> 16 = 0x00000000 (zero stays zero)

.option norvc
    # Backup third set of results to x25-x28
    addi x25, x8,  0     # Backup x8
    addi x26, x9,  0     # Backup x9
    addi x27, x10, 0     # Backup x10
    addi x28, x11, 0     # Backup x11

    # Reload for multiple shift test
    li  x12, 0x80000000  # Start with min negative
.option rvc

    #-------------------------------------------------
    # Test Set 4: Multiple consecutive shifts (negative value)
    #-------------------------------------------------
    c.srai x12, 1        # 0x80000000 >> 1  = 0xC0000000
    c.srai x12, 1        # 0xC0000000 >> 1  = 0xE0000000
    c.srai x12, 1        # 0xE0000000 >> 1  = 0xF0000000
    c.srai x12, 1        # 0xF0000000 >> 1  = 0xF8000000

.option norvc
    # Backup fourth set result
    addi x29, x12, 0     # Backup x12

    # Reload for sign-extension verification
    li  x13, 0xF0000000  # Negative value
    li  x14, 0xC0000000  # Negative value
    li  x15, 0x7FFFFFFF  # Positive value (for comparison)
.option rvc

    #-------------------------------------------------
    # Test Set 5: Verify arithmetic vs logical shift difference
    #-------------------------------------------------
    c.srai x13, 4        # 0xF0000000 >> 4  = 0xFF000000 (sign-extended)
    c.srai x14, 2        # 0xC0000000 >> 2  = 0xF0000000 (sign-extended)
    c.srai x15, 4        # 0x7FFFFFFF >> 4  = 0x07FFFFFF (zero-filled, positive)

.option norvc
    # Backup fifth set results
    addi x30, x13, 0     # Backup x13
    addi x2,  x14, 0     # Backup x14
    addi x3,  x15, 0     # Backup x15

    # Test odd shift amounts
    li  x8,  0xABCDEF01  # Negative pattern
    li  x9,  0x12345678  # Positive pattern
.option rvc

    #-------------------------------------------------
    # Test Set 6: Odd shift amounts
    #-------------------------------------------------
    c.srai x8,  15       # 0xABCDEF01 >> 15 = 0xFFFF579B (sign-extended)
    c.srai x9,  17       # 0x12345678 >> 17 = 0x0000091A (zero-filled)

.option norvc
    # Backup sixth set results
    addi x4, x8, 0       # Backup x8
    addi x5, x9, 0       # Backup x9

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
