#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_sext_b
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SEXT.B
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
    # Mix of positive (bit 7=0) and negative (bit 7=1) values
    li  x8,  0xFFFFFF00  # Lower byte: 0x00 (positive zero)
    li  x9,  0x12345601  # Lower byte: 0x01 (positive)
    li  x10, 0xABCDEF7F  # Lower byte: 0x7F (max positive signed byte)
    li  x11, 0x87654380  # Lower byte: 0x80 (min negative signed byte)
    li  x12, 0xDEADBEFF  # Lower byte: 0xFF (negative -1)
    li  x13, 0xCAFEBA55  # Lower byte: 0x55 (positive)
    li  x14, 0x9999AAAA  # Lower byte: 0xAA (negative)
    li  x15, 0x33335A5A  # Lower byte: 0x5A (positive)

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST C.SEXT.B (Compressed Sign-Extend Byte)
    # Format: c.sext.b rd'/rs1'
    # Function: rd' = sign_extend(rd'[7:0])
    # Effect: rd'[31:8] = replicate rd'[7], rd'[7:0] = original rd'[7:0]
    # Registers: rd'/rs1' are x8-x15 (compressed register encoding)
    # Encoding: 100_111_rs1'/rd'[2:0]_11001_01
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Backup original values to non-compressed registers before sign-extension
    # This allows verification of sign vs zero extension
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
    # Test C.SEXT.B on all compressed registers
    #c.sext.b  x8     # x8  = 0x00000000 (0x00 sign-extended, positive)
    #c.sext.b  x9     # x9  = 0x00000001 (0x01 sign-extended, positive)
    #c.sext.b  x10    # x10 = 0x0000007F (0x7F sign-extended, positive)
    #c.sext.b  x11    # x11 = 0xFFFFFF80 (0x80 sign-extended, negative!)
    #c.sext.b  x12    # x12 = 0xFFFFFFFF (0xFF sign-extended, negative -1!)
    #c.sext.b  x13    # x13 = 0x00000055 (0x55 sign-extended, positive)
    #c.sext.b  x14    # x14 = 0xFFFFFFAA (0xAA sign-extended, negative!)
    #c.sext.b  x15    # x15 = 0x0000005A (0x5A sign-extended, positive)

    # Test C.SEXT.B on all compressed registers
    # (using manual encoding because GCC has an artificial constrain that Zbb should be enabled)
    .hword 0x9C65     # c.sext.b x8  -> x8  = 0x00000000 (0x00 sign-extended, positive)
    c.nop
    .hword 0x9CE5     # c.sext.b x9  -> x9  = 0x00000001 (0x01 sign-extended, positive)
    c.nop
    .hword 0x9D65     # c.sext.b x10 -> x10 = 0x0000007F (0x7F sign-extended, positive)
    c.nop
    .hword 0x9DE5     # c.sext.b x11 -> x11 = 0xFFFFFF80 (0x80 sign-extended, negative!)
    c.nop
    .hword 0x9E65     # c.sext.b x12 -> x12 = 0xFFFFFFFF (0xFF sign-extended, negative -1!)
    c.nop
    .hword 0x9EE5     # c.sext.b x13 -> x13 = 0x00000055 (0x55 sign-extended, positive)
    c.nop
    .hword 0x9F65     # c.sext.b x14 -> x14 = 0xFFFFFFAA (0xAA sign-extended, negative!)
    c.nop
    .hword 0x9FE5     # c.sext.b x15 -> x15 = 0x0000005A (0x5A sign-extended, positive)

.option norvc

    #-------------------------------------------------
    # TEST EDGE CASES WITH ADDITIONAL VALUES
    #-------------------------------------------------

    # Test with all 1s (0xFF should become 0xFFFFFFFF = -1)
    li  x8,  0xFFFFFFFF
    li  x1,  0xFFFFFFFF
.option rvc
    .hword 0x9C65     # c.sext.b  x8     # x8 = 0xFFFFFFFF (0xFF sign-extended to -1)
.option norvc
    addi x1, x8, 0   # Backup result to x1

    # Test with 0x00000000 (should remain zero)
    li  x9,  0x00000000
    li  x2,  0x12345678
.option rvc
    .hword 0x9CE5     # c.sext.b  x9     # x9 = 0x00000000
.option norvc
    addi x2, x9, 0   # Backup result to x2

    # Test idempotency with positive value
    li  x10, 0xABCDEF42
    li  x3,  0x11111111
    li  x4,  0x22222222
.option rvc
    .hword 0x9D65     # c.sext.b  x10    # x10 = 0x00000042 (first application, positive)
.option norvc
    addi x3, x10, 0  # Backup first result
.option rvc
    .hword 0x9D65     # c.sext.b  x10    # x10 = 0x00000042 (second application - should be same)
.option norvc
    addi x4, x10, 0  # Backup second result

    # Test idempotency with negative value
    li  x11, 0x5555A5A5
    li  x5,  0x33333333
    li  x25, 0x44444444
.option rvc
    .hword 0x9DE5     # c.sext.b  x11    # x11 = 0xFFFFFFA5 (first application, negative)
.option norvc
    addi x5, x11, 0  # Backup first result
.option rvc
    .hword 0x9DE5     # c.sext.b  x11    # x11 = 0xFFFFFFA5 (second application - should be same)
.option norvc
    addi x25, x11, 0 # Backup second result

    # Test boundary: 0x7E (just below max positive)
    li  x12, 0x0302017E
    li  x6,  0x55555555
.option rvc
    .hword 0x9E65     # c.sext.b  x12    # x12 = 0x0000007E (positive)
.option norvc
    addi x6, x12, 0  # Backup result to x6

    # Test boundary: 0x81 (just above min negative)
    li  x13, 0x12345681
    li  x7,  0x66666666
.option rvc
    .hword 0x9EE5     # c.sext.b  x13    # x13 = 0xFFFFFF81 (negative!)
.option norvc
    addi x7, x13, 0  # Backup result to x7

    # Test with 0xFE (-2 in signed byte)
    li  x14, 0xDEAD00FE
    li  x26, 0x77777777
.option rvc
    .hword 0x9F65     # c.sext.b  x14    # x14 = 0xFFFFFFFE (negative -2)
.option norvc
    addi x26, x14, 0 # Backup result to x26

    # Test with 0x01 (positive 1)
    li  x15, 0xCAFE0001
    li  x27, 0x88888888
.option rvc
    .hword 0x9FE5     # c.sext.b  x15    # x15 = 0x00000001 (positive)
.option norvc
    addi x27, x15, 0 # Backup result to x27

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
