#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_sext_h
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SEXT.H
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
    # Mix of positive (bit 15=0) and negative (bit 15=1) halfword values
    li  x8,  0xFFFF0000  # Lower halfword: 0x0000 (positive zero), upper bits all 1s
    li  x9,  0x12340001  # Lower halfword: 0x0001 (positive)
    li  x10, 0xABCD7FFF  # Lower halfword: 0x7FFF (max positive signed halfword)
    li  x11, 0x87658000  # Lower halfword: 0x8000 (min negative signed halfword)
    li  x12, 0xDEADFFFF  # Lower halfword: 0xFFFF (negative -1)
    li  x13, 0xCAFE5555  # Lower halfword: 0x5555 (positive)
    li  x14, 0x9999AAAA  # Lower halfword: 0xAAAA (negative)
    li  x15, 0x33335A5A  # Lower halfword: 0x5A5A (positive)

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST C.SEXT.H (Compressed Sign-Extend Halfword)
    # Format: c.sext.h rd'/rs1'
    # Function: rd' = sign_extend(rd'[15:0])
    # Effect: rd'[31:16] = replicate rd'[15], rd'[15:0] = original rd'[15:0]
    # Registers: rd'/rs1' are x8-x15 (compressed register encoding)
    # Encoding: 100_111_rs1'/rd'[2:0]_11011_01
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Backup original values to non-compressed registers before sign-extension
    # This allows verification of sign vs zero extension
.option norvc
    addi x17, x8,  0    # Backup x8  = 0xFFFF0000
    addi x18, x9,  0    # Backup x9  = 0x12340001
    addi x19, x10, 0    # Backup x10 = 0xABCD7FFF
    addi x20, x11, 0    # Backup x11 = 0x87658000
    addi x21, x12, 0    # Backup x12 = 0xDEADFFFF
    addi x22, x13, 0    # Backup x13 = 0xCAFE5555
    addi x23, x14, 0    # Backup x14 = 0x9999AAAA
    addi x24, x15, 0    # Backup x15 = 0x33335A5A

.option rvc
    # Test C.SEXT.H on all compressed registers
    #c.sext.h  x8     # x8  = 0x00000000 (0x0000 sign-extended, positive)
    #c.sext.h  x9     # x9  = 0x00000001 (0x0001 sign-extended, positive)
    #c.sext.h  x10    # x10 = 0x00007FFF (0x7FFF sign-extended, positive)
    #c.sext.h  x11    # x11 = 0xFFFF8000 (0x8000 sign-extended, negative!)
    #c.sext.h  x12    # x12 = 0xFFFFFFFF (0xFFFF sign-extended, negative -1!)
    #c.sext.h  x13    # x13 = 0x00005555 (0x5555 sign-extended, positive)
    #c.sext.h  x14    # x14 = 0xFFFFAAAA (0xAAAA sign-extended, negative!)
    #c.sext.h  x15    # x15 = 0x00005A5A (0x5A5A sign-extended, positive)

    .hword 0x9c6d     # c.sext.h x8  -> x8  = 0x00000000 (0x0000 sign-extended, positive)
    c.nop
    .hword 0x9ced     # c.sext.h x9  -> x9  = 0x00000001 (0x0001 sign-extended, positive)
    c.nop
    .hword 0x9d6d     # c.sext.h x10 -> x10 = 0x00007FFF (0x7FFF sign-extended, positive)
    c.nop
    .hword 0x9ded     # c.sext.h x11 -> x11 = 0xFFFF8000 (0x8000 sign-extended, negative!)
    c.nop
    .hword 0x9e6d     # c.sext.h x12 -> x12 = 0xFFFFFFFF (0xFFFF sign-extended, negative -1!)
    c.nop
    .hword 0x9eed     # c.sext.h x13 -> x13 = 0x00005555 (0x5555 sign-extended, positive)
    c.nop
    .hword 0x9f6d     # c.sext.h x14 -> x14 = 0xFFFFAAAA (0xAAAA sign-extended, negative!)
    c.nop
    .hword 0x9fed     # c.sext.h x15 -> x15 = 0x00005A5A (0x5A5A sign-extended, positive)

.option norvc

    #-------------------------------------------------
    # TEST EDGE CASES WITH ADDITIONAL VALUES
    #-------------------------------------------------

    # Test with all 1s (0xFFFF should become 0xFFFFFFFF = -1)
    li  x8,  0xFFFFFFFF
    li  x1,  0xFFFFFFFF
.option rvc
    .hword 0x9c6d     # c.sext.h  x8     # x8 = 0xFFFFFFFF (0xFFFF sign-extended to -1)
.option norvc
    addi x1, x8, 0   # Backup result to x1

    # Test with 0x00000000 (should remain zero)
    li  x9,  0x00000000
    li  x2,  0x12345678
.option rvc
    .hword 0x9ced     # c.sext.h  x9     # x9 = 0x00000000
.option norvc
    addi x2, x9, 0   # Backup result to x2

    # Test idempotency with positive value
    li  x10, 0xABCD1234
    li  x3,  0x11111111
    li  x4,  0x22222222
.option rvc
    .hword 0x9d6d     # c.sext.h  x10    # x10 = 0x00001234 (first application, positive)
.option norvc
    addi x3, x10, 0  # Backup first result
.option rvc
    .hword 0x9d6d     # c.sext.h  x10    # x10 = 0x00001234 (second application - should be same)
.option norvc
    addi x4, x10, 0  # Backup second result

    # Test idempotency with negative value
    li  x11, 0x5555A5A5
    li  x5,  0x33333333
    li  x25, 0x44444444
.option rvc
    .hword 0x9ded     # c.sext.h  x11    # x11 = 0xFFFFA5A5 (first application, negative)
.option norvc
    addi x5, x11, 0  # Backup first result
.option rvc
    .hword 0x9ded     # c.sext.h  x11    # x11 = 0xFFFFA5A5 (second application - should be same)
.option norvc
    addi x25, x11, 0 # Backup second result

    # Test boundary: 0x7FFE (just below max positive)
    li  x12, 0x03027FFE
    li  x6,  0x55555555
.option rvc
    .hword 0x9e6d     # c.sext.h  x12    # x12 = 0x00007FFE (positive)
.option norvc
    addi x6, x12, 0  # Backup result to x6

    # Test boundary: 0x8001 (just above min negative)
    li  x13, 0x12348001
    li  x7,  0x66666666
.option rvc
    .hword 0x9eed     # c.sext.h  x13    # x13 = 0xFFFF8001 (negative!)
.option norvc
    addi x7, x13, 0  # Backup result to x7

    # Test with 0x9876 (negative halfword)
    li  x14, 0xDEAD9876
    li  x26, 0x77777777
.option rvc
    .hword 0x9f6d     # c.sext.h  x14    # x14 = 0xFFFF9876 (negative)
.option norvc
    addi x26, x14, 0 # Backup result to x26

    # Test with 0x0001 (positive 1)
    li  x15, 0xCAFE0001
    li  x27, 0x88888888
.option rvc
    .hword 0x9fed     # c.sext.h  x15    # x15 = 0x00000001 (positive)
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
