#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_xor
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.XOR
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
    li  x1,  0xBADC0FFE
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.XOR (Compressed XOR)
    # Format: c.xor rd', rs2'
    # Function: rd' = rd' ^ rs2'
    # Registers: rd' and rs2' are x8-x15 (compressed register encoding)
    # Encoding: 100_0_11_rd'[2:0]_01_rs2'[2:0]_01
    #
    # XOR truth table:
    # 0 ^ 0 = 0
    # 0 ^ 1 = 1
    # 1 ^ 0 = 1
    # 1 ^ 1 = 0
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Alternating patterns (should give all 1s)
    #-------------------------------------------------
    c.xor x8,  x9        # 0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF
    c.xor x12, x13       # 0xF0F0F0F0 ^ 0x0F0F0F0F = 0xFFFFFFFF

.option norvc
    # Backup first set of results to x16-x17
    addi x16, x8,  0     # Backup x8:  0xFFFFFFFF
    addi x17, x12, 0     # Backup x12: 0xFFFFFFFF

    # Reload for second set
    li  x8,  0x12345678
    li  x9,  0x00000000  # Zero
    li  x10, 0xABCDEF01
    li  x11, 0x00000000  # Zero
.option rvc

    #-------------------------------------------------
    # Test Set 2: XOR with zero (identity: n ^ 0 = n)
    #-------------------------------------------------
    c.xor x8,  x9        # 0x12345678 ^ 0x00000000 = 0x12345678
    c.xor x10, x11       # 0xABCDEF01 ^ 0x00000000 = 0xABCDEF01

.option norvc
    # Backup second set of results to x18-x19
    addi x18, x8,  0     # Backup x8:  0x12345678
    addi x19, x10, 0     # Backup x10: 0xABCDEF01

    # Reload for third set
    li  x8,  0x12345678
    li  x9,  0xFFFFFFFF  # All 1s
    li  x10, 0xAAAAAAAA
    li  x11, 0xFFFFFFFF  # All 1s
.option rvc

    #-------------------------------------------------
    # Test Set 3: XOR with all 1s (inversion: n ^ 0xFFFFFFFF = ~n)
    #-------------------------------------------------
    c.xor x8,  x9        # 0x12345678 ^ 0xFFFFFFFF = 0xEDCBA987
    c.xor x10, x11       # 0xAAAAAAAA ^ 0xFFFFFFFF = 0x55555555

.option norvc
    # Backup third set of results to x20-x21
    addi x20, x8,  0     # Backup x8:  0xEDCBA987
    addi x21, x10, 0     # Backup x10: 0x55555555

    # Reload for fourth set
    li  x12, 0xDEADBEEF
    li  x13, 0xDEADBEEF
    li  x14, 0x7FFFFFFF
    li  x15, 0x7FFFFFFF
.option rvc

    #-------------------------------------------------
    # Test Set 4: Self-XOR (n ^ n = 0)
    #-------------------------------------------------
    c.xor x12, x13       # 0xDEADBEEF ^ 0xDEADBEEF = 0x00000000
    c.xor x14, x15       # 0x7FFFFFFF ^ 0x7FFFFFFF = 0x00000000

.option norvc
    # Backup fourth set of results to x22-x23
    addi x22, x12, 0     # Backup x12: 0x00000000
    addi x23, x14, 0     # Backup x14: 0x00000000

    # Reload for fifth set
    li  x8,  0xFF00FF00
    li  x9,  0x00FF00FF
    li  x10, 0xF0F0F0F0
    li  x11, 0x0F0F0F0F
.option rvc

    #-------------------------------------------------
    # Test Set 5: Complementary patterns
    #-------------------------------------------------
    c.xor x8,  x9        # 0xFF00FF00 ^ 0x00FF00FF = 0xFFFFFFFF
    c.xor x10, x11       # 0xF0F0F0F0 ^ 0x0F0F0F0F = 0xFFFFFFFF

.option norvc
    # Backup fifth set of results to x24-x25
    addi x24, x8,  0     # Backup x8:  0xFFFFFFFF
    addi x25, x10, 0     # Backup x10: 0xFFFFFFFF

    # Reload for sixth set
    li  x12, 0x12345678
    li  x13, 0xABCDEF01
    li  x14, 0x80000000  # MSB set
    li  x15, 0x00000001  # LSB set
.option rvc

    #-------------------------------------------------
    # Test Set 6: Specific bit patterns
    #-------------------------------------------------
    c.xor x12, x13       # 0x12345678 ^ 0xABCDEF01 = 0xB9F9B979
    c.xor x14, x15       # 0x80000000 ^ 0x00000001 = 0x80000001

.option norvc
    # Backup sixth set of results to x26-x27
    addi x26, x12, 0     # Backup x12: 0xB9F9B979
    addi x27, x14, 0     # Backup x14: 0x80000001

    # Reload for seventh set (consecutive XOR)
    li  x8,  0xAAAAAAAA
    li  x9,  0x55555555
    li  x10, 0xFFFFFFFF
.option rvc

    #-------------------------------------------------
    # Test Set 7: Multiple consecutive XORs
    #-------------------------------------------------
    c.xor x8,  x9        # 0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF
    c.xor x8,  x10       # 0xFFFFFFFF ^ 0xFFFFFFFF = 0x00000000

.option norvc
    # Backup seventh set result
    addi x28, x8, 0      # Backup x8: 0x00000000

    # Reload for eighth set (toggle bits)
    li  x11, 0x00000000
    li  x12, 0x12345678
    li  x13, 0x80000000  # Toggle MSB
.option rvc

    #-------------------------------------------------
    # Test Set 8: Bit toggling
    #-------------------------------------------------
    c.xor x11, x12       # 0x00000000 ^ 0x12345678 = 0x12345678
    c.xor x11, x13       # 0x12345678 ^ 0x80000000 = 0x92345678 (MSB toggled)

.option norvc
    # Backup eighth set result
    addi x29, x11, 0     # Backup x11: 0x92345678

    # Reload for ninth set (all compressed regs)
    li  x8,  0x11111111
    li  x9,  0x22222222
    li  x10, 0x44444444
    li  x11, 0x88888888
    li  x12, 0xCCCCCCCC
    li  x13, 0x33333333
.option rvc

    #-------------------------------------------------
    # Test Set 9: Various patterns
    #-------------------------------------------------
    c.xor x8,  x9        # 0x11111111 ^ 0x22222222 = 0x33333333
    c.xor x10, x11       # 0x44444444 ^ 0x88888888 = 0xCCCCCCCC
    c.xor x12, x13       # 0xCCCCCCCC ^ 0x33333333 = 0xFFFFFFFF

.option norvc
    # Backup ninth set results
    addi x30, x8,  0     # Backup x8:  0x33333333
    addi x2,  x10, 0     # Backup x10: 0xCCCCCCCC
    addi x3,  x12, 0     # Backup x12: 0xFFFFFFFF

    # Reload for tenth set (boundary values)
    li  x14, 0x7FFFFFFF  # Max positive
    li  x15, 0x80000000  # Min negative
.option rvc

    #-------------------------------------------------
    # Test Set 10: Boundary values
    #-------------------------------------------------
    c.xor x14, x15       # 0x7FFFFFFF ^ 0x80000000 = 0xFFFFFFFF

.option norvc
    # Backup tenth set result
    addi x4, x14, 0      # Backup x14: 0xFFFFFFFF

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
