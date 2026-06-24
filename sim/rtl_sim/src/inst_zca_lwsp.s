#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_lwsp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.LWSP
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

    # Setup stack pointer and prepare test data
    li  x2,  0x80000400  # SP pointing to SRAM

    # Store test patterns to stack (using standard SW)
    li  x8,  0x12345678
    sw  x8,  0(x2)       # [SP+0]   = 0x12345678

    li  x9,  0xABCDEF01
    sw  x9,  4(x2)       # [SP+4]   = 0xABCDEF01

    li  x10, 0xFFFFFFFF
    sw  x10, 8(x2)       # [SP+8]   = 0xFFFFFFFF

    li  x11, 0x00000000
    sw  x11, 12(x2)      # [SP+12]  = 0x00000000

    li  x12, 0x80000000
    sw  x12, 16(x2)      # [SP+16]  = 0x80000000

    li  x13, 0x7FFFFFFF
    sw  x13, 20(x2)      # [SP+20]  = 0x7FFFFFFF

    li  x14, 0xAAAAAAAA
    sw  x14, 24(x2)      # [SP+24]  = 0xAAAAAAAA

    li  x15, 0x55555555
    sw  x15, 28(x2)      # [SP+28]  = 0x55555555

    li  x16, 0x11111111
    sw  x16, 32(x2)      # [SP+32]  = 0x11111111

    li  x17, 0x22222222
    sw  x17, 36(x2)      # [SP+36]  = 0x22222222

    li  x18, 0x33333333
    sw  x18, 64(x2)      # [SP+64]  = 0x33333333

    li  x19, 0x44444444
    sw  x19, 128(x2)     # [SP+128] = 0x44444444

    li  x20, 0xDEADCAFE
    sw  x20, 252(x2)     # [SP+252] = 0xDEADCAFE (max offset for C.LWSP)

    # Clear registers for testing
    li  x8,  0x00000000
    li  x9,  0x00000000
    li  x10, 0x00000000
    li  x11, 0x00000000
    li  x12, 0x00000000
    li  x13, 0x00000000
    li  x14, 0x00000000
    li  x15, 0x00000000
    li  x16, 0x00000000
    li  x17, 0x00000000
    li  x18, 0x00000000
    li  x19, 0x00000000
    li  x20, 0x00000000

    # Setup markers
    li  x1,  0x1E570001
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.LWSP (Compressed Load Word Stack Pointer)
    # Format: c.lwsp rd, offset(sp)
    # Function: rd = M[sp + offset]
    # Registers: rd can be any x1-x31 (not x0)
    # Offset: 6-bit unsigned scaled by 4 (0-252 in steps of 4)
    # Encoding: 010_offset[5]_rd[4:0]_offset[4:2|7:6]_10
    #
    # Key behavior:
    # - Loads word from memory at address SP + offset
    # - Offset is zero-extended and multiplied by 4
    # - SP register remains unchanged
    # - No sign extension (loads full 32-bit word)
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Basic loads with small offsets
    #-------------------------------------------------
    c.lwsp x8,  0(sp)    # Load [SP+0]  = 0x12345678
    c.lwsp x9,  4(sp)    # Load [SP+4]  = 0xABCDEF01
    c.lwsp x10, 8(sp)    # Load [SP+8]  = 0xFFFFFFFF
    c.lwsp x11, 12(sp)   # Load [SP+12] = 0x00000000

.option norvc
    # Backup first set of results to x21-x24
    addi x21, x8,  0     # Backup x8:  0x12345678
    addi x22, x9,  0     # Backup x9:  0xABCDEF01
    addi x23, x10, 0     # Backup x10: 0xFFFFFFFF
    addi x24, x11, 0     # Backup x11: 0x00000000

    # Verify SP unchanged
    addi x25, x2,  0     # Backup SP: should still be 0x80000400
.option rvc

    #-------------------------------------------------
    # Test Set 2: Boundary values
    #-------------------------------------------------
    c.lwsp x12, 16(sp)   # Load [SP+16] = 0x80000000 (min negative)
    c.lwsp x13, 20(sp)   # Load [SP+20] = 0x7FFFFFFF (max positive)

.option norvc
    # Backup second set of results to x26-x27
    addi x26, x12, 0     # Backup x12: 0x80000000
    addi x27, x13, 0     # Backup x13: 0x7FFFFFFF
.option rvc

    #-------------------------------------------------
    # Test Set 3: Alternating patterns
    #-------------------------------------------------
    c.lwsp x14, 24(sp)   # Load [SP+24] = 0xAAAAAAAA
    c.lwsp x15, 28(sp)   # Load [SP+28] = 0x55555555

.option norvc
    # Backup third set of results to x28-x29
    addi x28, x14, 0     # Backup x14: 0xAAAAAAAA
    addi x29, x15, 0     # Backup x15: 0x55555555
.option rvc

    #-------------------------------------------------
    # Test Set 4: Medium offsets
    #-------------------------------------------------
    c.lwsp x16, 32(sp)   # Load [SP+32] = 0x11111111
    c.lwsp x17, 36(sp)   # Load [SP+36] = 0x22222222

.option norvc
    # Backup fourth set of results to x3-x4
    addi x3, x16, 0      # Backup x16: 0x11111111
    addi x4, x17, 0      # Backup x17: 0x22222222
.option rvc

    #-------------------------------------------------
    # Test Set 5: Larger offset
    #-------------------------------------------------
    c.lwsp x18, 64(sp)   # Load [SP+64] = 0x33333333

.option norvc
    # Backup fifth set result to x5
    addi x5, x18, 0      # Backup x18: 0x33333333
.option rvc

    #-------------------------------------------------
    # Test Set 6: Even larger offset
    #-------------------------------------------------
    c.lwsp x19, 128(sp)  # Load [SP+128] = 0x44444444

.option norvc
    # Backup sixth set result to x6
    addi x6, x19, 0      # Backup x19: 0x44444444
.option rvc

    #-------------------------------------------------
    # Test Set 7: Maximum offset (252)
    #-------------------------------------------------
    c.lwsp x20, 252(sp)  # Load [SP+252] = 0xDEADCAFE (max offset)

.option norvc
    # Backup seventh set result to x7
    addi x7, x20, 0      # Backup x20: 0xDEADCAFE
.option rvc

    #-------------------------------------------------
    # Test Set 8: Load to x1 (return address)
    #-------------------------------------------------
    c.lwsp x1,  0(sp)    # Load [SP+0] = 0x12345678 to x1

.option norvc
    # Backup eighth set result to x30
    addi x30, x1, 0      # Backup x1: 0x12345678
.option rvc

    #-------------------------------------------------
    # Test Set 9: Multiple loads from same location
    #-------------------------------------------------
    c.lwsp x8,  4(sp)    # Load [SP+4] = 0xABCDEF01
    c.lwsp x9,  4(sp)    # Load [SP+4] = 0xABCDEF01 (same location)

.option norvc
    # Final values will be checked directly (both should be 0xABCDEF01)
.option rvc

    #-------------------------------------------------
    # Test Set 10: Non-compressed registers
    #-------------------------------------------------
    c.lwsp x25, 8(sp)    # Load [SP+8] = 0xFFFFFFFF to non-compressed reg
    c.lwsp x26, 12(sp)   # Load [SP+12] = 0x00000000 to non-compressed reg

.option norvc
    # Final values will be checked directly

    # Barrier: ensure all loads complete before test end marker
    addi x0, x26, 0      # Use last loaded register to create dependency
    nop
    nop

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
