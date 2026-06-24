#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_zext_b
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.ZEXT.B
#----------------------------------------------------------------------------

.section .text
.option norvc        # disable all compressed instructions in this section
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - PREPARE TEST DATA
    #-------------------------------------------------

    # Load compressed registers with test patterns
    # Each value has different upper 24 bits to test zero-extension
    li  x8,  0xFFFFFF00  # Lower byte: 0x00, upper bits all 1s
    li  x9,  0x12345601  # Lower byte: 0x01
    li  x10, 0xABCDEF7F  # Lower byte: 0x7F (max positive in signed byte)
    li  x11, 0x87654380  # Lower byte: 0x80 (min negative in signed byte, but should zero-extend)
    li  x12, 0xDEADBEFF  # Lower byte: 0xFF (max unsigned byte)
    li  x13, 0xCAFEBA55  # Lower byte: 0x55
    li  x14, 0x9999AAAA  # Lower byte: 0xAA
    li  x15, 0x33335A5A  # Lower byte: 0x5A

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST C.ZEXT.B (Compressed Zero-Extend Byte)
    # Format: c.zext.b rd'/rs1'
    # Function: rd' = zero_extend(rd'[7:0])
    # Effect: rd'[31:8] = 0, rd'[7:0] = original rd'[7:0]
    # Registers: rd'/rs1' are x8-x15 (compressed register encoding)
    # Encoding: 100_111_rs1'/rd'[2:0]_11000_01
    # Implemented as: rd' = rd' AND 0x000000FF
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Backup original values to non-compressed registers before zero-extension
    # This allows verification that only lower byte is preserved
.option norvc
    addi x17, x8,  0    # Backup x8  = 0xFFFFFF00
    addi x18, x9,  0    # Backup x9  = 0x12345601
    addi x19, x10, 0    # Backup x10 = 0xABCDEF7F
    addi x20, x11, 0    # Backup x11 = 0x87654380
    addi x21, x12, 0    # Backup x12 = 0xDEADBEFF
    addi x22, x13, 0    # Backup x13 = 0xCAFEBA55
    addi x23, x14, 0    # Backup x14 = 0x9999AAAA
    addi x24, x15, 0    # Backup x15 = 0x33335A5A

.option rvc
    # Test C.ZEXT.B on all compressed registers
    c.zext.b  x8     # x8  = 0x00000000 (0x00 zero-extended)
    c.zext.b  x9     # x9  = 0x00000001 (0x01 zero-extended)
    c.zext.b  x10    # x10 = 0x0000007F (0x7F zero-extended)
    c.zext.b  x11    # x11 = 0x00000080 (0x80 zero-extended, NOT sign-extended!)
    c.zext.b  x12    # x12 = 0x000000FF (0xFF zero-extended, NOT sign-extended!)
    c.zext.b  x13    # x13 = 0x00000055 (0x55 zero-extended)
    c.zext.b  x14    # x14 = 0x000000AA (0xAA zero-extended, NOT sign-extended!)
    c.zext.b  x15    # x15 = 0x0000005A (0x5A zero-extended)

.option norvc

    #-------------------------------------------------
    # TEST EDGE CASES WITH ADDITIONAL VALUES
    #-------------------------------------------------

    # Test with zero (should remain zero)
    li  x8,  0xFFFFFFFF
    li  x1,  0xFFFFFFFF
.option rvc
    c.zext.b  x8     # x8 = 0x000000FF (all 1s in byte)
.option norvc
    addi x1, x8, 0   # Backup result to x1

    # Test with 0x00000000 (should remain zero)
    li  x9,  0x00000000
    li  x2,  0x12345678
.option rvc
    c.zext.b  x9     # x9 = 0x00000000
.option norvc
    addi x2, x9, 0   # Backup result to x2

    # Test idempotency: c.zext.b applied twice should give same result
    li  x10, 0xABCDEF42
    li  x3,  0x11111111
    li  x4,  0x22222222
.option rvc
    c.zext.b  x10    # x10 = 0x00000042 (first application)
.option norvc
    addi x3, x10, 0  # Backup first result
.option rvc
    c.zext.b  x10    # x10 = 0x00000042 (second application - should be same)
.option norvc
    addi x4, x10, 0  # Backup second result

    # Test with alternating bit patterns
    li  x11, 0x5555A5A5
    li  x5,  0x33333333
.option rvc
    c.zext.b  x11    # x11 = 0x000000A5
.option norvc
    addi x5, x11, 0  # Backup result to x5

    # Test with sequential bytes
    li  x12, 0x03020100
    li  x6,  0x44444444
.option rvc
    c.zext.b  x12    # x12 = 0x00000000 (lower byte is 0x00)
.option norvc
    addi x6, x12, 0  # Backup result to x6

    # Test with negative-looking byte that should NOT become negative
    li  x13, 0x123456FF
    li  x7,  0x55555555
.option rvc
    c.zext.b  x13    # x13 = 0x000000FF (NOT 0xFFFFFFFF!)
.option norvc
    addi x7, x13, 0  # Backup result to x7

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
