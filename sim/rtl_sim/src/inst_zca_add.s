#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_add
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.ADD
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
    li  x8,  0x00000100  # 256
    li  x9,  0x00000050  # 80
    li  x10, 0x00000001  # 1
    li  x11, 0x00000002  # 2
    li  x12, 0x7FFFFFFF  # Max positive
    li  x13, 0x00000001  # 1
    li  x14, 0x80000000  # Min negative
    li  x15, 0xFFFFFFFF  # -1

    # Setup markers
    li  x1,  0xADD1711E
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.ADD (Compressed ADD)
    # Format: c.add rd, rs2
    # Function: rd = rd + rs2
    # Registers: rd and rs2 can be any x1-x31 (not x0)
    # Encoding: 100_1_rd[4:0]_rs2[4:0]_10 (rd != 0, rs2 != 0, bit[12]=1)
    #
    # Key behavior:
    # - Adds rs2 to rd, stores result in rd
    # - Source register (rs2) remains unchanged
    # - Overflow wraps around (no exception)
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Basic addition (positive + positive)
    #-------------------------------------------------
    c.add x8,  x9        # 0x00000100 + 0x00000050 = 0x00000150 (256 + 80 = 336)
    c.add x10, x11       # 0x00000001 + 0x00000002 = 0x00000003 (1 + 2 = 3)

.option norvc
    # Backup first set of results to x16-x17
    addi x16, x8,  0     # Backup x8:  0x00000150
    addi x17, x10, 0     # Backup x10: 0x00000003

    # Verify source registers unchanged
    addi x18, x9,  0     # Backup x9:  0x00000050 (should be unchanged)
    addi x19, x11, 0     # Backup x11: 0x00000002 (should be unchanged)

    # Reload for second set
    li  x8,  0x7FFFFFFF  # Max positive
    li  x9,  0x00000001  # 1
.option rvc

    #-------------------------------------------------
    # Test Set 2: Overflow (positive + positive = negative)
    #-------------------------------------------------
    c.add x12, x13       # 0x7FFFFFFF + 0x00000001 = 0x80000000 (overflow to min negative)
    c.add x8,  x9        # 0x7FFFFFFF + 0x00000001 = 0x80000000

.option norvc
    # Backup second set of results to x20-x21
    addi x20, x12, 0     # Backup x12: 0x80000000
    addi x21, x8,  0     # Backup x8:  0x80000000

    # Verify source unchanged
    addi x22, x13, 0     # Backup x13: 0x00000001 (should be unchanged)

    # Reload for third set
    li  x10, 0x80000000  # Min negative
    li  x11, 0x80000000  # Min negative
.option rvc

    #-------------------------------------------------
    # Test Set 3: Underflow (negative + negative = positive)
    #-------------------------------------------------
    c.add x10, x11       # 0x80000000 + 0x80000000 = 0x00000000 (underflow wraps)

.option norvc
    # Backup third set result
    addi x23, x10, 0     # Backup x10: 0x00000000

    # Reload for fourth set
    li  x8,  0xFFFFFFFF  # -1
    li  x9,  0x00000001  # 1
    li  x10, 0xFFFFFFFF  # -1
    li  x11, 0xFFFFFFFF  # -1
.option rvc

    #-------------------------------------------------
    # Test Set 4: Adding with -1
    #-------------------------------------------------
    c.add x8,  x9        # 0xFFFFFFFF + 0x00000001 = 0x00000000 (-1 + 1 = 0)
    c.add x10, x11       # 0xFFFFFFFF + 0xFFFFFFFF = 0xFFFFFFFE (-1 + -1 = -2)

.option norvc
    # Backup fourth set of results to x24-x25
    addi x24, x8,  0     # Backup x8:  0x00000000
    addi x25, x10, 0     # Backup x10: 0xFFFFFFFE

    # Reload for fifth set
    li  x12, 0x12345678
    li  x13, 0x00000000  # Zero
    li  x14, 0xABCDEF01
    li  x15, 0x00000000  # Zero
.option rvc

    #-------------------------------------------------
    # Test Set 5: Adding with zero (identity: n + 0 = n)
    #-------------------------------------------------
    c.add x12, x13       # 0x12345678 + 0x00000000 = 0x12345678
    c.add x14, x15       # 0xABCDEF01 + 0x00000000 = 0xABCDEF01

.option norvc
    # Note: Test Set 5 results not backed up (identity property doesn't need verification)

    # Reload for sixth set (consecutive additions)
    li  x8,  0x00000001  # 1
    li  x9,  0x00000001  # 1
.option rvc

    #-------------------------------------------------
    # Test Set 6: Multiple consecutive additions
    #-------------------------------------------------
    c.add x8,  x9        # 0x00000001 + 0x00000001 = 0x00000002
    c.add x8,  x9        # 0x00000002 + 0x00000001 = 0x00000003
    c.add x8,  x9        # 0x00000003 + 0x00000001 = 0x00000004
    c.add x8,  x9        # 0x00000004 + 0x00000001 = 0x00000005

.option norvc
    # Backup sixth set result
    addi x28, x8, 0      # Backup x8: 0x00000005

    # Reload for seventh set (mixed positive/negative)
    li  x10, 0x00001000  # 4096
    li  x11, 0xFFFFFFFF  # -1
    li  x12, 0x7FFFFFFF  # Max positive
    li  x13, 0x80000000  # Min negative
.option rvc

    #-------------------------------------------------
    # Test Set 7: Mixed positive/negative
    #-------------------------------------------------
    c.add x10, x11       # 0x00001000 + 0xFFFFFFFF = 0x00000FFF (4096 + -1 = 4095)
    c.add x12, x13       # 0x7FFFFFFF + 0x80000000 = 0xFFFFFFFF (max_pos + min_neg = -1)

.option norvc
    # Backup seventh set results
    addi x29, x10, 0     # Backup x10: 0x00000FFF
    addi x30, x12, 0     # Backup x12: 0xFFFFFFFF

    # Reload for eighth set (non-compressed registers)
    li  x25, 0x00000100  # 256
    li  x26, 0x00000200  # 512
    li  x27, 0xFFFFFFFF  # -1
.option rvc

    #-------------------------------------------------
    # Test Set 8: Non-compressed registers
    #-------------------------------------------------
    c.add x25, x26       # 0x00000100 + 0x00000200 = 0x00000300
    c.add x1,  x27       # x1 + 0xFFFFFFFF (x1 was 0xADD1711E)

.option norvc
    # Backup eighth set results
    addi x2, x25, 0      # Backup x25: 0x00000300
    addi x3, x1,  0      # Backup x1:  0xADD1711D (was 0xADD1711E, added -1)

    # Reload for ninth set (self-addition: rd = rd + rd)
    li  x14, 0x00000010  # 16
    li  x15, 0x80000000  # Min negative
.option rvc

    #-------------------------------------------------
    # Test Set 9: Self-addition (rd = rd + rd, i.e., multiply by 2)
    #-------------------------------------------------
    c.add x14, x14       # 0x00000010 + 0x00000010 = 0x00000020 (16 * 2 = 32)
    c.add x15, x15       # 0x80000000 + 0x80000000 = 0x00000000 (overflow)

.option norvc
    # Backup ninth set results
    addi x4, x14, 0      # Backup x14: 0x00000020
    addi x5, x15, 0      # Backup x15: 0x00000000

    # Reload for tenth set (pattern addition)
    li  x8,  0x12345678
    li  x9,  0x11111111
    li  x10, 0xAAAAAAAA
    li  x11, 0x55555555
.option rvc

    #-------------------------------------------------
    # Test Set 10: Pattern addition
    #-------------------------------------------------
    c.add x8,  x9        # 0x12345678 + 0x11111111 = 0x23456789
    c.add x10, x11       # 0xAAAAAAAA + 0x55555555 = 0xFFFFFFFF

.option norvc
    # Backup tenth set results
    addi x6, x8,  0      # Backup x8:  0x23456789
    addi x7, x10, 0      # Backup x10: 0xFFFFFFFF

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
