#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_lw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.LW
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
    # We'll store 8 different test values at different offsets
    li  x1,  0xAABBCCDD
    li  x2,  0x11223344
    li  x3,  0x55667788
    li  x4,  0x99AABBCC
    li  x5,  0xDEADBEEF
    li  x6,  0xCAFEBABE
    li  x7,  0x12345678
    li  x15, 0x87654321

    # Store to SRAM using standard SW instructions
    sw  x1,   0(x29)    # 0xAABBCCDD  -->  SRAM+0
    sw  x2,   4(x29)    # 0x11223344  -->  SRAM+4
    sw  x3,   8(x29)    # 0x55667788  -->  SRAM+8
    sw  x4,  12(x29)    # 0x99AABBCC  -->  SRAM+12
    sw  x5,  16(x29)    # 0xDEADBEEF  -->  SRAM+16
    sw  x6,  20(x29)    # 0xCAFEBABE  -->  SRAM+20
    sw  x7,  24(x29)    # 0x12345678  -->  SRAM+24
    sw  x15, 28(x29)    # 0x87654321  -->  SRAM+28

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
    # TEST C.LW (Compressed Load Word)
    # Format: c.lw rd', offset(rs1')
    # Function: rd' = memory[rs1' + zero_extended(offset << 2)]
    # Registers: rd' and rs1' are x8-x15 (compressed register encoding)
    # Offset range: 0 to 124 (5-bit unsigned, multiple of 4)
    # Encoding: 010_imm[5:3]_rs1'[2:0]_imm[2|6]_rd'[2:0]_00
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Test various offsets with base pointer in x8
    c.lw  x9,   0(x8)   # x9  = 0xAABBCCDD  <--  SRAM+0
    c.lw  x10,  4(x8)   # x10 = 0x11223344  <--  SRAM+4
    c.lw  x11,  8(x8)   # x11 = 0x55667788  <--  SRAM+8
    c.lw  x12, 12(x8)   # x12 = 0x99AABBCC  <--  SRAM+12
    c.lw  x13, 16(x8)   # x13 = 0xDEADBEEF  <--  SRAM+16
    c.lw  x14, 20(x8)   # x14 = 0xCAFEBABE  <--  SRAM+20
    c.lw  x15, 24(x8)   # x15 = 0x12345678  <--  SRAM+24

.option norvc
    # Backup first set of loads to x16-x22
    addi x16, x9,  0    # Backup x9
    addi x17, x10, 0    # Backup x10
    addi x18, x11, 0    # Backup x11
    addi x19, x12, 0    # Backup x12
    addi x20, x13, 0    # Backup x13
    addi x21, x14, 0    # Backup x14
    addi x22, x15, 0    # Backup x15

    # Test with different base register (use x9 as base)
    addi  x9, x29, 4     # x9 = SRAM base + 4
.option rvc
    c.lw  x10,  0(x9)   # x10 = 0x11223344  <--  SRAM+4  (reloaded)
    c.lw  x11,  4(x9)   # x11 = 0x55667788  <--  SRAM+8  (reloaded)
    c.lw  x12,  8(x9)   # x12 = 0x99AABBCC  <--  SRAM+12 (reloaded)

    # Test boundary offsets
    c.lw  x13, 24(x9)   # x13 = 0x87654321  <--  SRAM+28 (offset=24)

.option norvc
    # Backup second set of loads to x23-x26
    addi x23, x10, 0    # Backup x10
    addi x24, x11, 0    # Backup x11
    addi x25, x12, 0    # Backup x12
    addi x26, x13, 0    # Backup x13

    # Test using different compressed registers as base
    addi  x10, x29, 8    # x10 = SRAM base + 8
.option rvc
    c.lw  x14,  0(x10)  # x14 = 0x55667788  <--  SRAM+8
    c.lw  x15,  4(x10)  # x15 = 0x99AABBCC  <--  SRAM+12

.option norvc
    # Backup third set of loads to x27-x28
    addi x27, x14, 0    # Backup x14
    addi x28, x15, 0    # Backup x15

    # Test with various offsets using x11 as base
    addi  x11, x29, 0    # x11 = SRAM base
.option rvc
    c.lw  x12, 16(x11)  # x12 = 0xDEADBEEF  <--  SRAM+16
    c.lw  x13, 20(x11)  # x13 = 0xCAFEBABE  <--  SRAM+20
    c.lw  x14, 28(x11)  # x14 = 0x87654321  <--  SRAM+28

.option norvc
    # Backup fourth set of loads to x1-x3
    addi x1, x12, 0     # Backup x12
    addi x2, x13, 0     # Backup x13
    addi x3, x14, 0     # Backup x14

    # Test maximum offset (124 = 31*4)
    addi  x12, x29, -96  # x12 = SRAM base - 96
.option rvc
    c.lw  x15, 124(x12) # x15 = 0x87654321  <--  SRAM+28 (offset=124)

.option norvc
    # Backup final load to x4
    addi x4, x15, 0     # Backup x15

.option norvc

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    # Mark test complete
    li  x31, 0x12345678

end_of_test:
    nop
    j end_of_test     # infinite loop
