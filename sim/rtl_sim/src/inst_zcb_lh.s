#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_lh
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.LH
#----------------------------------------------------------------------------

.section .text
.option norvc        # disable all compressed instructions in this section
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP - STORE TEST DATA
    #-------------------------------------------------

    # Prepare base pointer for SRAM (using x29)
    li  x29, 0x80000010

    # Store test data pattern in SRAM using standard instructions
    # Test data contains various halfword patterns for verification
    # Mix of positive (bit 15=0) and negative (bit 15=1) values to test sign-extension
    # Note: Little-endian - lowest byte at lowest address
    li  x1,  0x7FFF0001  # Positive max (0x7FFF) and small positive (0x0001)
    li  x2,  0x80007FFE  # Negative (0x8000) and positive (0x7FFE)
    li  x3,  0xFFFF1234  # Negative (0xFFFF=-1) and positive (0x1234)
    li  x4,  0xABCD5678  # Negative (0xABCD) and positive (0x5678)
    li  x5,  0xDEADBEEF  # Both negative (0xDEAD, 0xBEEF)
    li  x6,  0xCAFEBABE  # Both negative (0xCAFE, 0xBABE)
    li  x7,  0x87654321  # Negative (0x8765) and positive (0x4321)
    li  x16, 0x9ABC0123  # Negative (0x9ABC) and positive (0x0123)

    # Store to SRAM using standard SW instructions
    sw  x1,   0(x29)    # 0x7FFF0001  -->  SRAM+0  (halfwords: 0x0001 at +0, 0x7FFF at +2)
    sw  x2,   4(x29)    # 0x80007FFE  -->  SRAM+4  (halfwords: 0x7FFE at +4, 0x8000 at +6)
    sw  x3,   8(x29)    # 0xFFFF1234  -->  SRAM+8  (halfwords: 0x1234 at +8, 0xFFFF at +10)
    sw  x4,  12(x29)    # 0xABCD5678  -->  SRAM+12 (halfwords: 0x5678 at +12, 0xABCD at +14)
    sw  x5,  16(x29)    # 0xDEADBEEF  -->  SRAM+16 (halfwords: 0xBEEF at +16, 0xDEAD at +18)
    sw  x6,  20(x29)    # 0xCAFEBABE  -->  SRAM+20 (halfwords: 0xBABE at +20, 0xCAFE at +22)
    sw  x7,  24(x29)    # 0x87654321  -->  SRAM+24 (halfwords: 0x4321 at +24, 0x8765 at +26)
    sw  x16, 28(x29)    # 0x9ABC0123  -->  SRAM+28 (halfwords: 0x0123 at +28, 0x9ABC at +30)

    # Clear registers x8-x15 (compressed register range) for testing
    li  x8,  0x00000000
    li  x9,  0x00000000
    li  x10, 0x00000000
    li  x11, 0x00000000
    li  x12, 0x00000000
    li  x13, 0x00000000
    li  x14, 0x00000000
    li  x15, 0x00000000

    # Setup base pointers in compressed registers (x8-x15)
    # x8 will point to SRAM base for testing
    addi x8, x29, 0     # x8 = SRAM base pointer

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST C.LH (Compressed Load Halfword)
    # Format: c.lh rd', offset(rs1')
    # Function: rd' = sign_extend(memory[rs1' + offset])
    # Registers: rd' and rs1' are x8-x15 (compressed register encoding)
    # Offset range: 0 or 2 (1-bit unsigned, left-shifted by 1)
    # Encoding: 100_001_rs1'[2:0]_uimm[1]_1_rd'[2:0]_00
    #           bit [6] = 1 for C.LH (vs C.LHU where bit [6] = 0)
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Test SET 1: Load halfwords from SRAM+0 using x8 as base
    # 0x0001 (positive) → 0x00000001
    # 0x7FFF (positive max) → 0x00007FFF
    c.lh  x9,  0(x8)   # x9  = 0x00000001  <--  SRAM+0 (sign-extend 0x0001)
    c.lh  x10, 2(x8)   # x10 = 0x00007FFF  <--  SRAM+2 (sign-extend 0x7FFF)

.option norvc
    # Backup first set of loads to x17-x18
    addi x17, x9,  0    # Backup x9  = 0x00000001
    addi x18, x10, 0    # Backup x10 = 0x00007FFF

    # Test SET 2: Load halfwords from SRAM+4 using x9 as base
    # 0x7FFE (positive) → 0x00007FFE
    # 0x8000 (negative min) → 0xFFFF8000
    addi  x9, x29, 4    # x9 = SRAM base + 4
.option rvc
    c.lh  x10, 0(x9)   # x10 = 0x00007FFE  <--  SRAM+4 (sign-extend 0x7FFE)
    c.lh  x11, 2(x9)   # x11 = 0xFFFF8000  <--  SRAM+6 (sign-extend 0x8000)

.option norvc
    # Backup second set of loads to x19-x20
    addi x19, x10, 0    # Backup x10 = 0x00007FFE
    addi x20, x11, 0    # Backup x11 = 0xFFFF8000

    # Test SET 3: Load halfwords from SRAM+8 using x10 as base
    # 0x1234 (positive) → 0x00001234
    # 0xFFFF (negative -1) → 0xFFFFFFFF
    addi  x10, x29, 8   # x10 = SRAM base + 8
.option rvc
    c.lh  x11, 0(x10)  # x11 = 0x00001234  <--  SRAM+8  (sign-extend 0x1234)
    c.lh  x12, 2(x10)  # x12 = 0xFFFFFFFF  <--  SRAM+10 (sign-extend 0xFFFF)

.option norvc
    # Backup third set of loads to x21-x22
    addi x21, x11, 0    # Backup x11 = 0x00001234
    addi x22, x12, 0    # Backup x12 = 0xFFFFFFFF

    # Test SET 4: Load halfwords from SRAM+12 using x11 as base
    # 0x5678 (positive) → 0x00005678
    # 0xABCD (negative) → 0xFFFFABCD
    addi  x11, x29, 12  # x11 = SRAM base + 12
.option rvc
    c.lh  x12, 0(x11)  # x12 = 0x00005678  <--  SRAM+12 (sign-extend 0x5678)
    c.lh  x13, 2(x11)  # x13 = 0xFFFFABCD  <--  SRAM+14 (sign-extend 0xABCD)

.option norvc
    # Backup fourth set of loads to x23-x24
    addi x23, x12, 0    # Backup x12 = 0x00005678
    addi x24, x13, 0    # Backup x13 = 0xFFFFABCD

    # Test SET 5: Load halfwords from SRAM+16 using x12 as base
    # 0xBEEF (negative) → 0xFFFFBEEF
    # 0xDEAD (negative) → 0xFFFFDEAD
    addi  x12, x29, 16  # x12 = SRAM base + 16
.option rvc
    c.lh  x13, 0(x12)  # x13 = 0xFFFFBEEF  <--  SRAM+16 (sign-extend 0xBEEF)
    c.lh  x14, 2(x12)  # x14 = 0xFFFFDEAD  <--  SRAM+18 (sign-extend 0xDEAD)

.option norvc
    # Backup fifth set of loads to x25-x26
    addi x25, x13, 0    # Backup x13 = 0xFFFFBEEF
    addi x26, x14, 0    # Backup x14 = 0xFFFFDEAD

    # Test SET 6: Load halfwords from SRAM+20 using x13 as base
    # 0xBABE (negative) → 0xFFFFBABE
    # 0xCAFE (negative) → 0xFFFFCAFE
    addi  x13, x29, 20  # x13 = SRAM base + 20
.option rvc
    c.lh  x14, 0(x13)  # x14 = 0xFFFFBABE  <--  SRAM+20 (sign-extend 0xBABE)
    c.lh  x15, 2(x13)  # x15 = 0xFFFFCAFE  <--  SRAM+22 (sign-extend 0xCAFE)

.option norvc
    # Backup sixth set of loads to x27-x28
    addi x27, x14, 0    # Backup x14 = 0xFFFFBABE
    addi x28, x15, 0    # Backup x15 = 0xFFFFCAFE

    # Test SET 7: Load halfwords from SRAM+24 using x14 as base (final values)
    # 0x4321 (positive) → 0x00004321
    # 0x8765 (negative) → 0xFFFF8765
    addi  x14, x29, 24  # x14 = SRAM base + 24
.option rvc
    c.lh  x15, 0(x14)  # x15 = 0x00004321  <--  SRAM+24 (sign-extend 0x4321)
    c.lh  x8,  2(x14)  # x8  = 0xFFFF8765  <--  SRAM+26 (sign-extend 0x8765)

.option norvc
    # Backup seventh set of loads to x1-x2
    addi x1, x15, 0     # Backup x15 = 0x00004321
    addi x2, x8,  0     # Backup x8  = 0xFFFF8765

    # Test SET 8: Final load from SRAM+28 using x15 as base
    # 0x0123 (positive) → 0x00000123
    # 0x9ABC (negative) → 0xFFFF9ABC
    addi  x15, x29, 28  # x15 = SRAM base + 28
.option rvc
    c.lh  x8,  0(x15)  # x8  = 0x00000123  <--  SRAM+28 (sign-extend 0x0123)
    c.lh  x9,  2(x15)  # x9  = 0xFFFF9ABC  <--  SRAM+30 (sign-extend 0x9ABC)

.option norvc

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    # Ensure all memory operations complete before marking test done
    fence

    # Mark test complete
    li  x31, 0x12345678

end_of_test:
    nop
    j end_of_test     # infinite loop
