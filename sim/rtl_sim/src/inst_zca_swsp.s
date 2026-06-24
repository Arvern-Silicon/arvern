#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_swsp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SWSP
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

    # Setup stack pointer
    li  x2,  0x80000400  # SP pointing to SRAM

    # Load source registers with test patterns
    li  x8,  0x12345678
    li  x9,  0xABCDEF01
    li  x10, 0xFFFFFFFF
    li  x11, 0x00000000
    li  x12, 0x80000000
    li  x13, 0x7FFFFFFF
    li  x14, 0xAAAAAAAA
    li  x15, 0x55555555
    li  x16, 0x11111111
    li  x17, 0x22222222
    li  x18, 0x33333333
    li  x19, 0x44444444
    li  x20, 0xDEADCAFE

    # Setup markers
    li  x1,  0x57050001
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.SWSP (Compressed Store Word Stack Pointer)
    # Format: c.swsp rs2, offset(sp)
    # Function: M[sp + offset] = rs2
    # Registers: rs2 can be any x0-x31
    # Offset: 6-bit unsigned scaled by 4 (0-252 in steps of 4)
    # Encoding: 110_offset[5:2|7:6]_rs2[4:0]_10
    #
    # Key behavior:
    # - Stores word to memory at address SP + offset
    # - Offset is zero-extended and multiplied by 4
    # - SP register remains unchanged
    # - Source register (rs2) remains unchanged
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Basic stores with small offsets
    #-------------------------------------------------
    c.swsp x8,  0(sp)    # Store 0x12345678 to [SP+0]
    c.swsp x9,  4(sp)    # Store 0xABCDEF01 to [SP+4]
    c.swsp x10, 8(sp)    # Store 0xFFFFFFFF to [SP+8]
    c.swsp x11, 12(sp)   # Store 0x00000000 to [SP+12]

.option norvc
    # Load back and verify
    lw  x21, 0(x2)       # Load [SP+0]  should be 0x12345678
    lw  x22, 4(x2)       # Load [SP+4]  should be 0xABCDEF01
    lw  x23, 8(x2)       # Load [SP+8]  should be 0xFFFFFFFF
    lw  x24, 12(x2)      # Load [SP+12] should be 0x00000000

    # Verify SP unchanged
    addi x25, x2,  0     # Backup SP: should still be 0x80000400

    # Verify source registers unchanged
    addi x26, x8,  0     # Backup x8:  should still be 0x12345678
    addi x27, x9,  0     # Backup x9:  should still be 0xABCDEF01
.option rvc

    #-------------------------------------------------
    # Test Set 2: Boundary values
    #-------------------------------------------------
    c.swsp x12, 16(sp)   # Store 0x80000000 to [SP+16] (min negative)
    c.swsp x13, 20(sp)   # Store 0x7FFFFFFF to [SP+20] (max positive)

.option norvc
    # Load back and verify
    lw  x28, 16(x2)      # Load [SP+16] should be 0x80000000
    lw  x29, 20(x2)      # Load [SP+20] should be 0x7FFFFFFF
.option rvc

    #-------------------------------------------------
    # Test Set 3: Alternating patterns
    #-------------------------------------------------
    c.swsp x14, 24(sp)   # Store 0xAAAAAAAA to [SP+24]
    c.swsp x15, 28(sp)   # Store 0x55555555 to [SP+28]

.option norvc
    # Load back and verify
    lw  x30, 24(x2)      # Load [SP+24] should be 0xAAAAAAAA
    lw  x3,  28(x2)      # Load [SP+28] should be 0x55555555
.option rvc

    #-------------------------------------------------
    # Test Set 4: Medium offsets
    #-------------------------------------------------
    c.swsp x16, 32(sp)   # Store 0x11111111 to [SP+32]
    c.swsp x17, 36(sp)   # Store 0x22222222 to [SP+36]

.option norvc
    # Load back and verify
    lw  x4, 32(x2)       # Load [SP+32] should be 0x11111111
    lw  x5, 36(x2)       # Load [SP+36] should be 0x22222222
.option rvc

    #-------------------------------------------------
    # Test Set 5: Larger offset
    #-------------------------------------------------
    c.swsp x18, 64(sp)   # Store 0x33333333 to [SP+64]

.option norvc
    # Load back and verify
    lw  x6, 64(x2)       # Load [SP+64] should be 0x33333333
.option rvc

    #-------------------------------------------------
    # Test Set 6: Even larger offset
    #-------------------------------------------------
    c.swsp x19, 128(sp)  # Store 0x44444444 to [SP+128]

.option norvc
    # Load back and verify
    lw  x7, 128(x2)      # Load [SP+128] should be 0x44444444
.option rvc

    #-------------------------------------------------
    # Test Set 7: Maximum offset (252)
    #-------------------------------------------------
    c.swsp x20, 252(sp)  # Store 0xDEADCAFE to [SP+252] (max offset)

.option norvc
    # Load back and verify
    lw  x11, 252(x2)     # Load [SP+252] should be 0xDEADCAFE
.option rvc

    #-------------------------------------------------
    # Test Set 8: Store from x1 (return address)
    #-------------------------------------------------
    c.swsp x1,  40(sp)   # Store x1 (0x57050001) to [SP+40]

.option norvc
    # Load back and verify
    lw  x13, 40(x2)      # Load [SP+40] should be 0x57050001
.option rvc

    #-------------------------------------------------
    # Test Set 9: Multiple stores to same location (overwrite)
    #-------------------------------------------------
    c.swsp x8,  44(sp)   # Store 0x12345678 to [SP+44]
    c.swsp x9,  44(sp)   # Store 0xABCDEF01 to [SP+44] (overwrite)

.option norvc
    # Load back and verify (should be last written value)
    lw  x14, 44(x2)      # Load [SP+44] should be 0xABCDEF01
.option rvc

    #-------------------------------------------------
    # Test Set 10: Store from non-compressed registers
    #-------------------------------------------------
    c.swsp x25, 48(sp)   # Store SP value (0x80000400) to [SP+48]
    c.swsp x26, 52(sp)   # Store x8 value (0x12345678) to [SP+52]

.option norvc
    # Load back and verify
    lw  x15, 48(x2)      # Load [SP+48] should be 0x80000400
    lw  x16, 52(x2)      # Load [SP+52] should be 0x12345678
.option rvc

    #-------------------------------------------------
    # Test Set 11: Store zero from x0
    #-------------------------------------------------
    c.swsp x0,  56(sp)   # Store 0x00000000 to [SP+56] (x0 is always zero)

.option norvc
    # Load back and verify
    lw  x17, 56(x2)      # Load [SP+56] should be 0x00000000

    # Barrier: ensure all loads complete before test end marker
    addi x0, x17, 0      # Use last loaded register to create dependency
    nop
    nop

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
