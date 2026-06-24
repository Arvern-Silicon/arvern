#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_mul
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.MUL
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
    li  x8,  0x00000002  # 2
    li  x9,  0x00000003  # 3
    li  x10, 0x00000005  # 5
    li  x11, 0x00000007  # 7
    li  x12, 0x0000000A  # 10
    li  x13, 0x00000064  # 100
    li  x14, 0x000003E8  # 1000
    li  x15, 0x00002710  # 10000

    # Setup markers
    li  x1,  0xBADC0FFE
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.MUL (Compressed Multiply)
    # Format: c.mul rd', rs2'
    # Function: rd' = (rd' * rs2')[31:0]  (lower 32 bits of product)
    # Registers: rd' and rs2' are x8-x15 (compressed register encoding)
    # Encoding: 100_1_11_rd'[2:0]_10_rs2'[2:0]_01
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Basic small multiplications
    #-------------------------------------------------
    c.mul x8,  x9        # 2 * 3 = 6
    c.mul x10, x11       # 5 * 7 = 35
    c.mul x12, x13       # 10 * 100 = 1000

.option norvc
    # Backup first set of results to x16-x18
    addi x16, x8,  0     # Backup x8:  6 (0x00000006)
    addi x17, x10, 0     # Backup x10: 35 (0x00000023)
    addi x18, x12, 0     # Backup x12: 1000 (0x000003E8)

    # Reload for second set
    li  x8,  0x12345678
    li  x9,  0x00000000  # Zero
    li  x10, 0xABCDEF01
    li  x11, 0x00000000  # Zero
.option rvc

    #-------------------------------------------------
    # Test Set 2: Multiply by zero (annihilation: n * 0 = 0)
    #-------------------------------------------------
    c.mul x8,  x9        # 0x12345678 * 0 = 0
    c.mul x10, x11       # 0xABCDEF01 * 0 = 0

.option norvc
    # Backup second set of results to x19-x20
    addi x19, x8,  0     # Backup x8:  0x00000000
    addi x20, x10, 0     # Backup x10: 0x00000000

    # Reload for third set
    li  x8,  0x12345678
    li  x9,  0x00000001  # One
    li  x10, 0xABCDEF01
    li  x11, 0x00000001  # One
.option rvc

    #-------------------------------------------------
    # Test Set 3: Multiply by one (identity: n * 1 = n)
    #-------------------------------------------------
    c.mul x8,  x9        # 0x12345678 * 1 = 0x12345678
    c.mul x10, x11       # 0xABCDEF01 * 1 = 0xABCDEF01

.option norvc
    # Backup third set of results to x21-x22
    addi x21, x8,  0     # Backup x8:  0x12345678
    addi x22, x10, 0     # Backup x10: 0xABCDEF01

    # Reload for fourth set
    li  x12, 0xFFFFFFFF  # -1
    li  x13, 0x00000005  # 5
    li  x14, 0xFFFFFFFF  # -1
    li  x15, 0xFFFFFFFF  # -1
.option rvc

    #-------------------------------------------------
    # Test Set 4: Negative numbers
    #-------------------------------------------------
    c.mul x12, x13       # -1 * 5 = -5 (0xFFFFFFFB)
    c.mul x14, x15       # -1 * -1 = 1 (0x00000001)

.option norvc
    # Backup fourth set of results to x23-x24
    addi x23, x12, 0     # Backup x12: 0xFFFFFFFB (-5)
    addi x24, x14, 0     # Backup x14: 0x00000001 (1)

    # Reload for fifth set
    li  x8,  0x00000010  # 16
    li  x9,  0x00000004  # 4
    li  x10, 0x00000100  # 256
    li  x11, 0x00000008  # 8
.option rvc

    #-------------------------------------------------
    # Test Set 5: Powers of two
    #-------------------------------------------------
    c.mul x8,  x9        # 16 * 4 = 64 (0x00000040)
    c.mul x10, x11       # 256 * 8 = 2048 (0x00000800)

.option norvc
    # Backup fifth set of results to x25-x26
    addi x25, x8,  0     # Backup x8:  0x00000040 (64)
    addi x26, x10, 0     # Backup x10: 0x00000800 (2048)

    # Reload for sixth set (large numbers that overflow)
    li  x12, 0x10000000  # Large number
    li  x13, 0x00000010  # 16
    li  x14, 0xFFFFFFFF  # -1 (max negative as unsigned)
    li  x15, 0x00000002  # 2
.option rvc

    #-------------------------------------------------
    # Test Set 6: Large numbers and overflow
    #-------------------------------------------------
    c.mul x12, x13       # 0x10000000 * 16 = 0x00000000 (overflows, wraps to 0)
    c.mul x14, x15       # 0xFFFFFFFF * 2 = 0xFFFFFFFE (lower 32 bits)

.option norvc
    # Backup sixth set of results to x27-x28
    addi x27, x12, 0     # Backup x12: 0x00000000 (overflow)
    addi x28, x14, 0     # Backup x14: 0xFFFFFFFE

    # Reload for seventh set (boundary values)
    li  x8,  0x7FFFFFFF  # INT32_MAX
    li  x9,  0x00000002  # 2
    li  x10, 0x80000000  # INT32_MIN
    li  x11, 0x00000002  # 2
.option rvc

    #-------------------------------------------------
    # Test Set 7: Boundary values (INT32_MAX, INT32_MIN)
    #-------------------------------------------------
    c.mul x8,  x9        # 0x7FFFFFFF * 2 = 0xFFFFFFFE (overflows to negative)
    c.mul x10, x11       # 0x80000000 * 2 = 0x00000000 (overflows, wraps to 0)

.option norvc
    # Backup seventh set results to x29-x30
    addi x29, x8,  0     # Backup x8:  0xFFFFFFFE
    addi x30, x10, 0     # Backup x10: 0x00000000

    # Reload for eighth set (squares)
    li  x12, 0x00000002  # 2
    li  x13, 0x00000002  # 2
    li  x14, 0x0000000A  # 10
    li  x15, 0x0000000A  # 10
.option rvc

    #-------------------------------------------------
    # Test Set 8: Squares (x * x)
    #-------------------------------------------------
    c.mul x12, x13       # 2 * 2 = 4
    c.mul x14, x15       # 10 * 10 = 100

.option norvc
    # Backup eighth set results to x2-x3
    addi x2, x12, 0      # Backup x12: 0x00000004 (4)
    addi x3, x14, 0      # Backup x14: 0x00000064 (100)

    # Reload for ninth set (specific test patterns)
    li  x8,  0x0000FFFF  # 65535
    li  x9,  0x00010001  # 65537
    li  x10, 0x00000100  # 256
    li  x11, 0x01000000  # 16777216
.option rvc

    #-------------------------------------------------
    # Test Set 9: Specific multiplication patterns
    #-------------------------------------------------
    c.mul x8,  x9        # 0xFFFF * 0x10001 = 0xFFFFFFFF (lower 32 bits: (2^16-1)*(2^16+1) = 2^32-1)
    c.mul x10, x11       # 256 * 16777216 = 0 (overflow)

.option norvc
    # Backup ninth set results to x4-x5
    addi x4, x8,  0      # Backup x8:  0xFFFFFFFF
    addi x5, x10, 0      # Backup x10: 0x00000000

    # Reload for tenth set (consecutive multiplications)
    li  x12, 0x00000002  # 2
    li  x13, 0x00000003  # 3
    li  x14, 0x00000005  # 5
.option rvc

    #-------------------------------------------------
    # Test Set 10: Consecutive multiplications (2 * 3 * 5)
    #-------------------------------------------------
    c.mul x12, x13       # 2 * 3 = 6
    c.mul x12, x14       # 6 * 5 = 30

.option norvc
    # Backup tenth set result to x6
    addi x6, x12, 0      # Backup x12: 0x0000001E (30)

    # Reload for eleventh set (small negatives)
    li  x8,  0xFFFFFFFE  # -2
    li  x9,  0x00000003  # 3
    li  x10, 0xFFFFFFFA  # -6
    li  x11, 0x00000005  # 5
.option rvc

    #-------------------------------------------------
    # Test Set 11: Small negative multiplications
    #-------------------------------------------------
    c.mul x8,  x9        # -2 * 3 = -6 (0xFFFFFFFA)
    c.mul x10, x11       # -6 * 5 = -30 (0xFFFFFFE2)

.option norvc
    # Backup eleventh set results to x7, x28 (reuse)
    addi x7, x8,  0      # Backup x8:  0xFFFFFFFA (-6)
    addi x28, x10, 0     # Backup x10: 0xFFFFFFE2 (-30) - overwrites earlier value

    # Reload for twelfth set (bit patterns)
    li  x12, 0xAAAAAAAA  # Alternating pattern
    li  x13, 0x00000002  # 2
    li  x14, 0x55555555  # Alternating pattern
    li  x15, 0x00000003  # 3
.option rvc

    #-------------------------------------------------
    # Test Set 12: Bit pattern multiplications
    #-------------------------------------------------
    c.mul x12, x13       # 0xAAAAAAAA * 2 = 0x55555554
    c.mul x14, x15       # 0x55555555 * 3 = 0xFFFFFFFF

.option norvc
    # Final values remain in x12, x14
    # x12 = 0x55555554, x14 = 0xFFFFFFFF

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
