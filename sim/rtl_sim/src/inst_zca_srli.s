#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_srli
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SRLI
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
    li  x8,  0xFFFFFFFF  # All 1s
    li  x9,  0x80000000  # MSB set
    li  x10, 0xAAAAAAAA  # Alternating bits
    li  x11, 0x12345678  # Mixed pattern
    li  x12, 0xF0F0F0F0  # Nibble pattern
    li  x13, 0x0F0F0F0F  # Inverse nibble
    li  x14, 0x00000001  # Single bit
    li  x15, 0xFEDCBA98  # Test pattern

    # Setup markers
    li  x1,  0xDEADBEEF
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.SRLI (Compressed Shift Right Logical Immediate)
    # Format: c.srli rd', shamt
    # Function: rd' = rd' >> shamt (logical, zero-fill)
    # Registers: rd' is x8-x15 (compressed register encoding)
    # Shift amount: 5-bit unsigned (0-31)
    # Encoding: 100_0_00_rd'[2:0]_shamt[4:0]_01
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Basic shifts with different amounts
    #-------------------------------------------------
    c.srli x8,  1        # 0xFFFFFFFF >> 1  = 0x7FFFFFFF
    c.srli x9,  4        # 0x80000000 >> 4  = 0x08000000
    c.srli x10, 8        # 0xAAAAAAAA >> 8  = 0x00AAAAAA
    c.srli x11, 12       # 0x12345678 >> 12 = 0x00012345
    c.srli x12, 16       # 0xF0F0F0F0 >> 16 = 0x0000F0F0
    c.srli x13, 20       # 0x0F0F0F0F >> 20 = 0x000000F0
    c.srli x14, 24       # 0x00000001 >> 24 = 0x00000000
    c.srli x15, 28       # 0xFEDCBA98 >> 28 = 0x0000000F

.option norvc
    # Backup first set of results to x16-x23
    addi x16, x8,  0     # Backup x8
    addi x17, x9,  0     # Backup x9
    addi x18, x10, 0     # Backup x10
    addi x19, x11, 0     # Backup x11
    addi x20, x12, 0     # Backup x12
    addi x21, x13, 0     # Backup x13
    addi x22, x14, 0     # Backup x14
    addi x23, x15, 0     # Backup x15

    # Reload for second set of tests
    li  x8,  0xFFFFFFFF  # All 1s
    li  x9,  0x80000000  # MSB set
    li  x10, 0x55555555  # Alternating pattern
    li  x11, 0xF0000000  # Upper nibble
    li  x12, 0x0000FFFF  # Lower halfword
    li  x13, 0xC0C0C0C0  # Pattern
    li  x14, 0x12345678  # Test value
    li  x15, 0xABCDEF01  # Test value
.option rvc

    #-------------------------------------------------
    # Test Set 2: Boundary and special cases
    #-------------------------------------------------
    c.srli x8,  1        # 0xFFFFFFFF >> 1  = 0x7FFFFFFF (min shift)
    c.srli x9,  31       # 0x80000000 >> 31 = 0x00000001 (max shift)
    c.srli x10, 16       # 0x55555555 >> 16 = 0x00005555
    c.srli x11, 4        # 0xF0000000 >> 4  = 0x0F000000
    c.srli x12, 8        # 0x0000FFFF >> 8  = 0x000000FF
    c.srli x13, 2        # 0xC0C0C0C0 >> 2  = 0x30303030
    c.srli x14, 15       # 0x12345678 >> 15 = 0x000091A2 (odd shift)
    c.srli x15, 17       # 0xABCDEF01 >> 17 = 0x000055E6 (odd shift)

.option norvc
    # Backup second set of results to x24-x30, x2-x4
    addi x24, x8,  0     # Backup x8
    addi x25, x9,  0     # Backup x9
    addi x26, x10, 0     # Backup x10
    addi x27, x11, 0     # Backup x11
    addi x28, x12, 0     # Backup x12
    addi x29, x13, 0     # Backup x13
    addi x30, x14, 0     # Backup x14
    addi x2,  x15, 0     # Backup x15

    # Reload for third set - test multiple shifts on same register
    li  x8,  0x80000000  # Start value
.option rvc

    #-------------------------------------------------
    # Test Set 3: Multiple shifts on same register
    #-------------------------------------------------
    c.srli x8,  1        # 0x80000000 >> 1  = 0x40000000
    c.srli x8,  1        # 0x40000000 >> 1  = 0x20000000
    c.srli x8,  1        # 0x20000000 >> 1  = 0x10000000
    c.srli x8,  1        # 0x10000000 >> 1  = 0x08000000

.option norvc
    # Backup third set result
    addi x3, x8, 0       # Backup x8 (final result)

    # Reload for fourth set - test sign bit preservation (should be 0-filled)
    li  x9,  0xF0000000  # Negative-looking value
    li  x10, 0x80000001  # MSB and LSB set
.option rvc

    #-------------------------------------------------
    # Test Set 4: Verify logical shift (zero-fill, not sign-extend)
    #-------------------------------------------------
    c.srli x9,  4        # 0xF0000000 >> 4  = 0x0F000000 (zero-fill)
    c.srli x10, 1        # 0x80000001 >> 1  = 0x40000000 (loses LSB)

.option norvc
    # Backup fourth set results
    addi x4, x9,  0      # Backup x9
    addi x5, x10, 0      # Backup x10

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
