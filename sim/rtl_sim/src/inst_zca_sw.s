#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_sw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SW
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

    # Load compressed registers (x8-x15) with unique test data
    li  x8,  0xAABBCCDD
    li  x9,  0x11223344
    li  x10, 0x55667788
    li  x11, 0x99AABBCC
    li  x12, 0xDEADBEEF
    li  x13, 0xCAFEBABE
    li  x14, 0x12345678
    li  x15, 0x87654321

    # Setup SRAM base pointer in x29
    li  x29, 0x80000010

    # Save original data values for later verification
    li  x1,  0xAABBCCDD
    li  x2,  0x11223344
    li  x3,  0x55667788
    li  x4,  0x99AABBCC
    li  x5,  0xDEADBEEF
    li  x6,  0xCAFEBABE
    li  x7,  0x12345678

    # Signal initial setup complete
    li  x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST C.SW (Compressed Store Word)
    # Format: c.sw rs2', offset(rs1')
    # Function: memory[rs1' + zero_extended(offset << 2)] = rs2'
    # Registers: rs2' and rs1' are x8-x15 (compressed register encoding)
    # Offset range: 0 to 124 (5-bit unsigned, multiple of 4)
    # Encoding: 110_imm[5:3]_rs1'[2:0]_imm[2|6]_rs2'[2:0]_00
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Setup base pointer in compressed register x10
.option norvc
    addi x10, x29, 0    # x10 = SRAM base pointer
.option rvc

    # Test various offsets with data in x8-x15, base in x10
    c.sw  x8,   0(x10)  # 0xAABBCCDD  -->  SRAM+0
    c.sw  x9,   4(x10)  # 0x11223344  -->  SRAM+4
    c.sw  x11,  8(x10)  # 0x99AABBCC  -->  SRAM+8
    c.sw  x12, 12(x10)  # 0xDEADBEEF  -->  SRAM+12
    c.sw  x13, 16(x10)  # 0xCAFEBABE  -->  SRAM+16
    c.sw  x14, 20(x10)  # 0x12345678  -->  SRAM+20
    c.sw  x15, 24(x10)  # 0x87654321  -->  SRAM+24

    # Test with different base register (use x11 as base)
.option norvc
    addi x11, x29, 28   # x11 = SRAM base + 28
.option rvc
    c.sw  x8,   0(x11)  # 0xAABBCCDD  -->  SRAM+28
    c.sw  x9,   4(x11)  # 0x11223344  -->  SRAM+32
    c.sw  x10,  8(x11)  # 0x55667788  -->  SRAM+36 (x10 now contains SRAM base)

    # Test using x12 as base pointer
.option norvc
    addi x12, x29, 40   # x12 = SRAM base + 40
.option rvc
    c.sw  x13,  0(x12)  # 0xCAFEBABE  -->  SRAM+40
    c.sw  x14,  4(x12)  # 0x12345678  -->  SRAM+44
    c.sw  x15,  8(x12)  # 0x87654321  -->  SRAM+48

    # Test with larger offsets using x13 as base
.option norvc
    addi x13, x29, 0    # x13 = SRAM base
.option rvc
    c.sw  x8,  52(x13)  # 0xAABBCCDD  -->  SRAM+52
    c.sw  x9,  56(x13)  # 0x11223344  -->  SRAM+56
    c.sw  x14, 60(x13)  # 0x12345678  -->  SRAM+60

    # Test maximum offset (124 = 31*4)
.option norvc
    addi x14, x29, -60  # x14 = SRAM base - 60
.option rvc
    c.sw  x15, 124(x14) # 0x87654321  -->  SRAM+64

    # Test all compressed registers as data sources with x15 as base
.option norvc
    addi x15, x29, 68   # x15 = SRAM base + 68
.option rvc
    c.sw  x8,   0(x15)  # 0xAABBCCDD  -->  SRAM+68
    c.sw  x9,   4(x15)  # 0x11223344  -->  SRAM+72
    c.sw  x10,  8(x15)  # 0x55667788  -->  SRAM+76
    c.sw  x11, 12(x15)  # 0x99AABBCC  -->  SRAM+80 (x11 contains SRAM+28)
    c.sw  x12, 16(x15)  # 0xDEADBEEF  -->  SRAM+84 (x12 contains SRAM+40)
    c.sw  x13, 20(x15)  # 0xCAFEBABE  -->  SRAM+88 (x13 contains SRAM+0)
    c.sw  x14, 24(x15)  # 0x12345678  -->  SRAM+92 (x14 contains SRAM-60)

    # Test boundary case with offset 0
.option norvc
    addi x8, x29, 96    # x8 = SRAM base + 96
.option rvc
    c.sw  x9,   0(x8)   # 0x11223344  -->  SRAM+96

.option norvc
    # Load to ensure the last store completes before testbench checks
    lw   x30, 0(x8)     # Read back last stored value (synchronization)

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    # Mark test complete
    li  x31, 0x12345678

end_of_test:
    nop
    j end_of_test     # infinite loop
