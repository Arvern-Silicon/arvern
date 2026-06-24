#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_lbu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.LBU
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
    # Test data contains various byte patterns for verification
    li  x1,  0xAABBCCDD
    li  x2,  0x11223344
    li  x3,  0x55667788
    li  x4,  0x99AABBCC
    li  x5,  0xDEADBEEF
    li  x6,  0xCAFEBABE
    li  x7,  0x12345678
    li  x16, 0x87654321

    # Store to SRAM using standard SW instructions
    sw  x1,   0(x29)    # 0xAABBCCDD  -->  SRAM+0  (bytes: DD CC BB AA)
    sw  x2,   4(x29)    # 0x11223344  -->  SRAM+4  (bytes: 44 33 22 11)
    sw  x3,   8(x29)    # 0x55667788  -->  SRAM+8  (bytes: 88 77 66 55)
    sw  x4,  12(x29)    # 0x99AABBCC  -->  SRAM+12 (bytes: CC BB AA 99)
    sw  x5,  16(x29)    # 0xDEADBEEF  -->  SRAM+16 (bytes: EF BE AD DE)
    sw  x6,  20(x29)    # 0xCAFEBABE  -->  SRAM+20 (bytes: BE BA FE CA)
    sw  x7,  24(x29)    # 0x12345678  -->  SRAM+24 (bytes: 78 56 34 12)
    sw  x16, 28(x29)    # 0x87654321  -->  SRAM+28 (bytes: 21 43 65 87)

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
    # TEST C.LBU (Compressed Load Byte Unsigned)
    # Format: c.lbu rd', offset(rs1')
    # Function: rd' = zero_extend(memory[rs1' + zero_extended(offset)])
    # Registers: rd' and rs1' are x8-x15 (compressed register encoding)
    # Offset range: 0 to 3 (2-bit unsigned)
    # Encoding: 100_000_rs1'[2:0]_imm[0:1]_rd'[2:0]_00
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Test SET 1: Load all 4 bytes from SRAM+0 using x8 as base
    c.lbu  x9,  0(x8)   # x9  = 0x000000DD  <--  SRAM+0 (byte 0)
    c.lbu  x10, 1(x8)   # x10 = 0x000000CC  <--  SRAM+1 (byte 1)
    c.lbu  x11, 2(x8)   # x11 = 0x000000BB  <--  SRAM+2 (byte 2)
    c.lbu  x12, 3(x8)   # x12 = 0x000000AA  <--  SRAM+3 (byte 3)

.option norvc
    # Backup first set of loads to x17-x20
    addi x17, x9,  0    # Backup x9  = 0xDD
    addi x18, x10, 0    # Backup x10 = 0xCC
    addi x19, x11, 0    # Backup x11 = 0xBB
    addi x20, x12, 0    # Backup x12 = 0xAA

    # Test SET 2: Load bytes from SRAM+4 using x9 as base
    addi  x9, x29, 4    # x9 = SRAM base + 4
.option rvc
    c.lbu  x10, 0(x9)   # x10 = 0x00000044  <--  SRAM+4 (byte 0)
    c.lbu  x11, 1(x9)   # x11 = 0x00000033  <--  SRAM+5 (byte 1)
    c.lbu  x12, 2(x9)   # x12 = 0x00000022  <--  SRAM+6 (byte 2)
    c.lbu  x13, 3(x9)   # x13 = 0x00000011  <--  SRAM+7 (byte 3)

.option norvc
    # Backup second set of loads to x21-x24
    addi x21, x10, 0    # Backup x10 = 0x44
    addi x22, x11, 0    # Backup x11 = 0x33
    addi x23, x12, 0    # Backup x12 = 0x22
    addi x24, x13, 0    # Backup x13 = 0x11

    # Test SET 3: Load bytes from SRAM+8 using x10 as base
    addi  x10, x29, 8   # x10 = SRAM base + 8
.option rvc
    c.lbu  x11, 0(x10)  # x11 = 0x00000088  <--  SRAM+8  (byte 0)
    c.lbu  x12, 1(x10)  # x12 = 0x00000077  <--  SRAM+9  (byte 1)
    c.lbu  x13, 2(x10)  # x13 = 0x00000066  <--  SRAM+10 (byte 2)
    c.lbu  x14, 3(x10)  # x14 = 0x00000055  <--  SRAM+11 (byte 3)

.option norvc
    # Backup third set of loads to x25-x28
    addi x25, x11, 0    # Backup x11 = 0x88
    addi x26, x12, 0    # Backup x12 = 0x77
    addi x27, x13, 0    # Backup x13 = 0x66
    addi x28, x14, 0    # Backup x14 = 0x55

    # Test SET 4: Load bytes from SRAM+12 using x11 as base
    addi  x11, x29, 12  # x11 = SRAM base + 12
.option rvc
    c.lbu  x12, 0(x11)  # x12 = 0x000000CC  <--  SRAM+12 (byte 0)
    c.lbu  x13, 1(x11)  # x13 = 0x000000BB  <--  SRAM+13 (byte 1)
    c.lbu  x14, 2(x11)  # x14 = 0x000000AA  <--  SRAM+14 (byte 2)
    c.lbu  x15, 3(x11)  # x15 = 0x00000099  <--  SRAM+15 (byte 3)

.option norvc
    # Backup fourth set of loads to x1-x4
    addi x1, x12, 0     # Backup x12 = 0xCC
    addi x2, x13, 0     # Backup x13 = 0xBB
    addi x3, x14, 0     # Backup x14 = 0xAA
    addi x4, x15, 0     # Backup x15 = 0x99

    # Test SET 5: Load bytes from SRAM+16 using x12 as base
    addi  x12, x29, 16  # x12 = SRAM base + 16
.option rvc
    c.lbu  x13, 0(x12)  # x13 = 0x000000EF  <--  SRAM+16 (byte 0)
    c.lbu  x14, 1(x12)  # x14 = 0x000000BE  <--  SRAM+17 (byte 1)
    c.lbu  x15, 2(x12)  # x15 = 0x000000AD  <--  SRAM+18 (byte 2)
    c.lbu  x8,  3(x12)  # x8  = 0x000000DE  <--  SRAM+19 (byte 3)

.option norvc
    # Backup fifth set of loads to x5-x7, x30
    addi x5,  x13, 0    # Backup x13 = 0xEF
    addi x6,  x14, 0    # Backup x14 = 0xBE
    addi x7,  x15, 0    # Backup x15 = 0xAD
    addi x30, x8,  0    # Backup x8  = 0xDE

    # Test SET 6: Load bytes from SRAM+20 using x13 as base
    addi  x13, x29, 20  # x13 = SRAM base + 20
.option rvc
    c.lbu  x14, 0(x13)  # x14 = 0x000000BE  <--  SRAM+20 (byte 0)
    c.lbu  x15, 1(x13)  # x15 = 0x000000BA  <--  SRAM+21 (byte 1)
    c.lbu  x8,  2(x13)  # x8  = 0x000000FE  <--  SRAM+22 (byte 2)
    c.lbu  x9,  3(x13)  # x9  = 0x000000CA  <--  SRAM+23 (byte 3)

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
