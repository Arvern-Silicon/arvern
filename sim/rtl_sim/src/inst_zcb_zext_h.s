#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_zext_h
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.ZEXT.H
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
    # Each value has different upper 16 bits to test zero-extension
    li  x8,  0xFFFF0000  # Lower halfword: 0x0000, upper bits all 1s
    li  x9,  0x12340001  # Lower halfword: 0x0001
    li  x10, 0xABCD7FFF  # Lower halfword: 0x7FFF (max positive in signed halfword)
    li  x11, 0x87658000  # Lower halfword: 0x8000 (min negative in signed halfword, but should zero-extend)
    li  x12, 0xDEADFFFF  # Lower halfword: 0xFFFF (max unsigned halfword)
    li  x13, 0xCAFE5555  # Lower halfword: 0x5555
    li  x14, 0x9999AAAA  # Lower halfword: 0xAAAA
    li  x15, 0x33335A5A  # Lower halfword: 0x5A5A

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST C.ZEXT.H (Compressed Zero-Extend Halfword)
    # Format: c.zext.h rd'/rs1'
    # Function: rd' = zero_extend(rd'[15:0])
    # Effect: rd'[31:16] = 0, rd'[15:0] = original rd'[15:0]
    # Registers: rd'/rs1' are x8-x15 (compressed register encoding)
    # Encoding: 100_111_rs1'/rd'[2:0]_11010_01
    # Implemented as: rd' = rd' AND 0x0000FFFF
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Backup original values to non-compressed registers before zero-extension
    # This allows verification that only lower halfword is preserved
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
    # Test C.ZEXT.H on all compressed registers
    #c.zext.h  x8     # x8  = 0x00000000 (0x0000 zero-extended)
    #c.zext.h  x9     # x9  = 0x00000001 (0x0001 zero-extended)
    #c.zext.h  x10    # x10 = 0x00007FFF (0x7FFF zero-extended)
    #c.zext.h  x11    # x11 = 0x00008000 (0x8000 zero-extended, NOT sign-extended!)
    #c.zext.h  x12    # x12 = 0x0000FFFF (0xFFFF zero-extended, NOT sign-extended!)
    #c.zext.h  x13    # x13 = 0x00005555 (0x5555 zero-extended)
    #c.zext.h  x14    # x14 = 0x0000AAAA (0xAAAA zero-extended, NOT sign-extended!)
    #c.zext.h  x15    # x15 = 0x00005A5A (0x5A5A zero-extended)

    # Test C.ZEXT.H on all compressed registers
    # (using manual encoding because GCC has an artificial constrain that Zbb should be enabled)
    .hword 0x9C69     # c.zext.h x8  -> x8  = 0x00000000 (0x0000 zero-extended)
    c.nop
    .hword 0x9CE9     # c.zext.h x9  -> x9  = 0x00000001 (0x0001 zero-extended)
    c.nop
    .hword 0x9D69     # c.zext.h x10 -> x10 = 0x00007FFF (0x7FFF zero-extended)
    c.nop
    .hword 0x9DE9     # c.zext.h x11 -> x11 = 0x00008000 (0x8000 zero-extended, NOT sign-extended!)
    c.nop
    .hword 0x9E69     # c.zext.h x12 -> x12 = 0x0000FFFF (0xFFFF zero-extended, NOT sign-extended!)
    c.nop
    .hword 0x9EE9     # c.zext.h x13 -> x13 = 0x00005555 (0x5555 zero-extended)
    c.nop
    .hword 0x9F69     # c.zext.h x14 -> x14 = 0x0000AAAA (0xAAAA zero-extended, NOT sign-extended!)
    c.nop
    .hword 0x9FE9     # c.zext.h x15 -> x15 = 0x00005A5A (0x5A5A zero-extended)

.option norvc

    #-------------------------------------------------
    # TEST EDGE CASES WITH ADDITIONAL VALUES
    #-------------------------------------------------

    # Test with all 1s (should preserve lower halfword)
    li  x8,  0xFFFFFFFF
    li  x1,  0xFFFFFFFF
.option rvc
    .hword 0x9C69    # c.zext.h  x8     # x8 = 0x0000FFFF (all 1s in halfword)
.option norvc
    addi x1, x8, 0   # Backup result to x1

    # Test with 0x00000000 (should remain zero)
    li  x9,  0x00000000
    li  x2,  0x12345678
.option rvc
    .hword 0x9CE9    # c.zext.h  x9     # x9 = 0x00000000
.option norvc
    addi x2, x9, 0   # Backup result to x2

    # Test idempotency: c.zext.h applied twice should give same result
    li  x10, 0xABCD1234
    li  x3,  0x11111111
    li  x4,  0x22222222
.option rvc
    .hword 0x9D69    # c.zext.h  x10    # x10 = 0x00001234 (first application)
.option norvc
    addi x3, x10, 0  # Backup first result
.option rvc
    .hword 0x9D69    # c.zext.h  x10    # x10 = 0x00001234 (second application - should be same)
.option norvc
    addi x4, x10, 0  # Backup second result

    # Test with alternating bit patterns
    li  x11, 0x5555A5A5
    li  x5,  0x33333333
.option rvc
    .hword 0x9DE9    # c.zext.h  x11    # x11 = 0x0000A5A5
.option norvc
    addi x5, x11, 0  # Backup result to x5

    # Test with byte boundaries
    li  x12, 0x03020100
    li  x6,  0x44444444
.option rvc
    .hword 0x9E69    # c.zext.h  x12    # x12 = 0x00000100 (lower halfword is 0x0100)
.option norvc
    addi x6, x12, 0  # Backup result to x6

    # Test with negative-looking halfword that should NOT become negative
    li  x13, 0x12349876
    li  x7,  0x55555555
.option rvc
    .hword 0x9EE9    # c.zext.h  x13    # x13 = 0x00009876 (NOT 0xFFFF9876!)
.option norvc
    addi x7, x13, 0  # Backup result to x7

    # Test with 0x8001 (just above most negative signed halfword)
    li  x14, 0xDEAD8001
    li  x25, 0x66666666
.option rvc
    .hword 0x9F69    # c.zext.h  x14    # x14 = 0x00008001 (NOT 0xFFFF8001!)
.option norvc
    addi x25, x14, 0 # Backup result to x25

    # Test with 0x7FFE (just below most positive signed halfword)
    li  x15, 0xCAFE7FFE
    li  x26, 0x77777777
.option rvc
    .hword 0x9FE9    # c.zext.h  x15    # x15 = 0x00007FFE
.option norvc
    addi x26, x15, 0 # Backup result to x26

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
