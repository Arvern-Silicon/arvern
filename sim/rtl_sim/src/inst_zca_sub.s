#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_sub
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SUB
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
    li  x8,  0x00000100  # 256
    li  x9,  0x00000050  # 80
    li  x10, 0x7FFFFFFF  # Max positive
    li  x11, 0x00000001  # 1
    li  x12, 0x80000000  # Min negative
    li  x13, 0xFFFFFFFF  # -1
    li  x14, 0x12345678  # Test pattern
    li  x15, 0xABCDEF01  # Test pattern

    # Setup markers
    li  x1,  0xC0FFEE00
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.SUB (Compressed SUBtract)
    # Format: c.sub rd', rs2'
    # Function: rd' = rd' - rs2'
    # Registers: rd' and rs2' are x8-x15 (compressed register encoding)
    # Encoding: 100_0_11_rd'[2:0]_00_rs2'[2:0]_01
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Basic subtraction (positive - positive)
    #-------------------------------------------------
    c.sub x8,  x9        # 0x00000100 - 0x00000050 = 0x000000B0 (256 - 80 = 176)
    c.sub x10, x11       # 0x7FFFFFFF - 0x00000001 = 0x7FFFFFFE (max_pos - 1)
    c.sub x14, x9        # 0x12345678 - 0x00000050 = 0x12345628

.option norvc
    # Backup first set of results to x16-x18
    addi x16, x8,  0     # Backup x8:  0x000000B0
    addi x17, x10, 0     # Backup x10: 0x7FFFFFFE
    addi x18, x14, 0     # Backup x14: 0x12345628

    # Reload for second set
    li  x8,  0x00000050  # 80
    li  x9,  0x00000100  # 256
    li  x10, 0x00000000  # 0
    li  x11, 0x00000001  # 1
.option rvc

    #-------------------------------------------------
    # Test Set 2: Subtraction resulting in negative (smaller - larger)
    #-------------------------------------------------
    c.sub x8,  x9        # 0x00000050 - 0x00000100 = 0xFFFFFF50 (80 - 256 = -176)
    c.sub x10, x11       # 0x00000000 - 0x00000001 = 0xFFFFFFFF (0 - 1 = -1)

.option norvc
    # Backup second set of results to x19-x20
    addi x19, x8,  0     # Backup x8:  0xFFFFFF50
    addi x20, x10, 0     # Backup x10: 0xFFFFFFFF

    # Reload for third set
    li  x8,  0x80000000  # Min negative
    li  x9,  0x00000001  # 1
    li  x10, 0x7FFFFFFF  # Max positive
    li  x11, 0xFFFFFFFF  # -1
.option rvc

    #-------------------------------------------------
    # Test Set 3: Underflow cases (going more negative)
    #-------------------------------------------------
    c.sub x8,  x9        # 0x80000000 - 0x00000001 = 0x7FFFFFFF (underflow!)
    c.sub x10, x11       # 0x7FFFFFFF - 0xFFFFFFFF = 0x80000000 (max_pos - (-1) = overflow!)

.option norvc
    # Backup third set of results to x21-x22
    addi x21, x8,  0     # Backup x8:  0x7FFFFFFF
    addi x22, x10, 0     # Backup x10: 0x80000000

    # Reload for fourth set
    li  x12, 0xFFFFFFFF  # -1
    li  x13, 0xFFFFFFFF  # -1
    li  x14, 0x80000000  # Min negative
    li  x15, 0x80000000  # Min negative
.option rvc

    #-------------------------------------------------
    # Test Set 4: Negative - Negative
    #-------------------------------------------------
    c.sub x12, x13       # 0xFFFFFFFF - 0xFFFFFFFF = 0x00000000 (-1 - (-1) = 0)
    c.sub x14, x15       # 0x80000000 - 0x80000000 = 0x00000000 (same - same = 0)

.option norvc
    # Backup fourth set of results to x23-x24
    addi x23, x12, 0     # Backup x12: 0x00000000
    addi x24, x14, 0     # Backup x14: 0x00000000

    # Reload for fifth set
    li  x8,  0x12345678
    li  x9,  0x11111111
    li  x10, 0xAAAAAAAA
    li  x11, 0x55555555
.option rvc

    #-------------------------------------------------
    # Test Set 5: Pattern subtraction
    #-------------------------------------------------
    c.sub x8,  x9        # 0x12345678 - 0x11111111 = 0x01234567
    c.sub x10, x11       # 0xAAAAAAAA - 0x55555555 = 0x55555555

.option norvc
    # Backup fifth set of results to x25-x26
    addi x25, x8,  0     # Backup x8:  0x01234567
    addi x26, x10, 0     # Backup x10: 0x55555555

    # Reload for zero tests
    li  x12, 0x00000000  # 0
    li  x13, 0x00000000  # 0
    li  x14, 0x12345678
    li  x15, 0x00000000  # 0
.option rvc

    #-------------------------------------------------
    # Test Set 6: Zero operands
    #-------------------------------------------------
    c.sub x12, x13       # 0x00000000 - 0x00000000 = 0x00000000 (0 - 0 = 0)
    c.sub x14, x15       # 0x12345678 - 0x00000000 = 0x12345678 (n - 0 = n)

.option norvc
    # Backup sixth set of results to x27-x28
    addi x27, x12, 0     # Backup x12: 0x00000000
    addi x28, x14, 0     # Backup x14: 0x12345678

    # Reload for consecutive operations
    li  x8,  0x00001000  # 4096
    li  x9,  0x00000100  # 256
    li  x10, 0x00000010  # 16
    li  x11, 0x00000001  # 1
.option rvc

    #-------------------------------------------------
    # Test Set 7: Multiple consecutive subtractions
    #-------------------------------------------------
    c.sub x8,  x9        # 0x00001000 - 0x00000100 = 0x00000F00 (4096 - 256 = 3840)
    c.sub x8,  x10       # 0x00000F00 - 0x00000010 = 0x00000EF0 (3840 - 16 = 3824)
    c.sub x8,  x11       # 0x00000EF0 - 0x00000001 = 0x00000EEF (3824 - 1 = 3823)

.option norvc
    # Backup seventh set result
    addi x29, x8, 0      # Backup x8: 0x00000EEF

    # Test same register subtraction
    li  x9,  0xDEADBEEF
    li  x10, 0x7FFFFFFF
.option rvc

    #-------------------------------------------------
    # Test Set 8: Self-subtraction and edge cases
    #-------------------------------------------------
    c.sub x9,  x9        # 0xDEADBEEF - 0xDEADBEEF = 0x00000000 (self - self = 0)
    c.sub x10, x10       # 0x7FFFFFFF - 0x7FFFFFFF = 0x00000000 (self - self = 0)

.option norvc
    # Backup eighth set results
    addi x30, x9,  0     # Backup x9:  0x00000000
    addi x2,  x10, 0     # Backup x10: 0x00000000

    # Test with all compressed registers
    li  x8,  0xF0000000
    li  x9,  0x10000000
    li  x10, 0xFFFFFF00
    li  x11, 0x000000FF
    li  x12, 0xCAFEBABE
    li  x13, 0x0000CAFE
.option rvc

    #-------------------------------------------------
    # Test Set 9: All register combinations
    #-------------------------------------------------
    c.sub x8,  x9        # 0xF0000000 - 0x10000000 = 0xE0000000
    c.sub x10, x11       # 0xFFFFFF00 - 0x000000FF = 0xFFFFFE01
    c.sub x12, x13       # 0xCAFEBABE - 0x0000CAFE = 0xCAFDAFC0

.option norvc
    # Backup ninth set results
    addi x3, x8,  0      # Backup x8:  0xE0000000
    addi x4, x10, 0      # Backup x10: 0xFFFFFE01
    addi x5, x12, 0      # Backup x12: 0xCAFDAFC0

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
