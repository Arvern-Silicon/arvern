#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_sb
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SB
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

    # Prepare base pointer for SRAM (using x29)
    li  x29, 0x80000010

    # Initialize SRAM to known pattern (all 0xAA) for verification
    li  x16, 0xAAAAAAAA
    sw  x16,  0(x29)    # SRAM+0
    sw  x16,  4(x29)    # SRAM+4
    sw  x16,  8(x29)    # SRAM+8
    sw  x16, 12(x29)    # SRAM+12
    sw  x16, 16(x29)    # SRAM+16
    sw  x16, 20(x29)    # SRAM+20
    sw  x16, 24(x29)    # SRAM+24
    sw  x16, 28(x29)    # SRAM+28

    # Load compressed registers with test byte patterns
    # Each register has a unique byte value in the lower 8 bits
    li  x8,  0xDEADBE08  # Lower byte: 0x08
    li  x9,  0xCAFEBA09  # Lower byte: 0x09
    li  x10, 0x1234560A  # Lower byte: 0x0A
    li  x11, 0x9876540B  # Lower byte: 0x0B
    li  x12, 0xABCDEF0C  # Lower byte: 0x0C
    li  x13, 0x5555550D  # Lower byte: 0x0D
    li  x14, 0xCCCCCC0E  # Lower byte: 0x0E
    li  x15, 0x33333F0F  # Lower byte: 0x0F

    # x29 will be used as base pointer
    # It's already set to SRAM base (0x80000010)

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST C.SB (Compressed Store Byte)
    # Format: c.sb rs2', offset(rs1')
    # Function: memory[rs1' + offset] = rs2'[7:0]
    # Registers: rs1' and rs2' are x8-x15 (compressed register encoding)
    # Offset range: 0 to 3 (2-bit unsigned)
    # Encoding: 100_010_rs1'[2:0]_imm[0:1]_rs2'[2:0]_00
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Test SET 1: Store 4 different bytes to SRAM+0 using x8 as base
.option norvc
    # Keep x8-x15 as data, use x17 as temporary base pointer
    addi  x17, x29, 0    # x17 = SRAM base + 0
    # Move base to x8 for compressed store
    addi  x8, x17, 0     # x8 = base pointer
.option rvc
    c.sb  x9,  0(x8)    # Store 0x09 --> SRAM+0 (byte 0)
    c.sb  x10, 1(x8)    # Store 0x0A --> SRAM+1 (byte 1)
    c.sb  x11, 2(x8)    # Store 0x0B --> SRAM+2 (byte 2)
    c.sb  x12, 3(x8)    # Store 0x0C --> SRAM+3 (byte 3)
    # Expected word at SRAM+0: 0x0C0B0A09

    # Restore x8 with original test data
.option norvc
    li  x8,  0xDEADBE08  # Restore: Lower byte = 0x08

    # Test SET 2: Store 4 different bytes to SRAM+4 using x9 as base
    addi  x17, x29, 4    # x17 = SRAM base + 4
    addi  x9, x17, 0     # x9 = base pointer
.option rvc
    c.sb  x13, 0(x9)    # Store 0x0D --> SRAM+4 (byte 0)
    c.sb  x14, 1(x9)    # Store 0x0E --> SRAM+5 (byte 1)
    c.sb  x15, 2(x9)    # Store 0x0F --> SRAM+6 (byte 2)
    c.sb  x8,  3(x9)    # Store 0x08 --> SRAM+7 (byte 3)
    # Expected word at SRAM+4: 0x080F0E0D

.option norvc
    li  x9,  0xCAFEBA09  # Restore: Lower byte = 0x09

    # Test SET 3: Store 4 different bytes to SRAM+8 using x10 as base
    addi  x17, x29, 8   # x17 = SRAM base + 8
    addi  x10, x17, 0   # x10 = base pointer
.option rvc
    c.sb  x15, 0(x10)   # Store 0x0F --> SRAM+8  (byte 0)
    c.sb  x14, 1(x10)   # Store 0x0E --> SRAM+9  (byte 1)
    c.sb  x13, 2(x10)   # Store 0x0D --> SRAM+10 (byte 2)
    c.sb  x12, 3(x10)   # Store 0x0C --> SRAM+11 (byte 3)
    # Expected word at SRAM+8: 0x0C0D0E0F

.option norvc
    li  x10, 0x1234560A  # Restore: Lower byte = 0x0A

    # Test SET 4: Store 4 different bytes to SRAM+12 using x12 as base
    # (Store x11, x10, x9, x8 - so use x12-x15 as base to avoid conflict)
    addi  x17, x29, 12  # x17 = SRAM base + 12
    addi  x12, x17, 0   # x12 = base pointer
.option rvc
    c.sb  x11, 0(x12)   # Store 0x0B --> SRAM+12 (byte 0)
    c.sb  x10, 1(x12)   # Store 0x0A --> SRAM+13 (byte 1)
    c.sb  x9,  2(x12)   # Store 0x09 --> SRAM+14 (byte 2)
    c.sb  x8,  3(x12)   # Store 0x08 --> SRAM+15 (byte 3)
    # Expected word at SRAM+12: 0x08090A0B

.option norvc
    li  x12, 0xABCDEF0C  # Restore: Lower byte = 0x0C

    # Test SET 5: Store 4 different bytes to SRAM+16 using x12 as base
    addi  x17, x29, 16  # x17 = SRAM base + 16
    addi  x12, x17, 0   # x12 = base pointer
.option rvc
    c.sb  x8,  0(x12)   # Store 0x08 --> SRAM+16 (byte 0)
    c.sb  x9,  1(x12)   # Store 0x09 --> SRAM+17 (byte 1)
    c.sb  x10, 2(x12)   # Store 0x0A --> SRAM+18 (byte 2)
    c.sb  x11, 3(x12)   # Store 0x0B --> SRAM+19 (byte 3)
    # Expected word at SRAM+16: 0x0B0A0908

.option norvc
    li  x12, 0xABCDEF0C  # Restore: Lower byte = 0x0C

    # Test SET 6: Store 4 different bytes to SRAM+20 using x8 as base
    # (Store x12, x13, x14, x15 - so use x8-x11 as base to avoid conflict)
    addi  x17, x29, 20  # x17 = SRAM base + 20
    addi  x8, x17, 0    # x8 = base pointer
.option rvc
    c.sb  x12, 0(x8)    # Store 0x0C --> SRAM+20 (byte 0)
    c.sb  x13, 1(x8)    # Store 0x0D --> SRAM+21 (byte 1)
    c.sb  x14, 2(x8)    # Store 0x0E --> SRAM+22 (byte 2)
    c.sb  x15, 3(x8)    # Store 0x0F --> SRAM+23 (byte 3)
    # Expected word at SRAM+20: 0x0F0E0D0C

.option norvc
    li  x8,  0xDEADBE08  # Restore: Lower byte = 0x08

    # Test SET 7: Store 4 different bytes to SRAM+24 using x14 as base
    addi  x17, x29, 24  # x17 = SRAM base + 24
    addi  x14, x17, 0   # x14 = base pointer
.option rvc
    c.sb  x15, 0(x14)   # Store 0x0F --> SRAM+24 (byte 0)
    c.sb  x15, 1(x14)   # Store 0x0F --> SRAM+25 (byte 1)
    c.sb  x15, 2(x14)   # Store 0x0F --> SRAM+26 (byte 2)
    c.sb  x15, 3(x14)   # Store 0x0F --> SRAM+27 (byte 3)
    # Expected word at SRAM+24: 0x0F0F0F0F

.option norvc
    li  x14, 0xCCCCCC0E  # Restore: Lower byte = 0x0E

    # Test SET 8: Store 4 different bytes to SRAM+28 using x15 as base
    addi  x17, x29, 28  # x17 = SRAM base + 28
    addi  x15, x17, 0   # x15 = base pointer
.option rvc
    c.sb  x8,  0(x15)   # Store 0x08 --> SRAM+28 (byte 0)
    c.sb  x8,  1(x15)   # Store 0x08 --> SRAM+29 (byte 1)
    c.sb  x8,  2(x15)   # Store 0x08 --> SRAM+30 (byte 2)
    c.sb  x8,  3(x15)   # Store 0x08 --> SRAM+31 (byte 3)
    # Expected word at SRAM+28: 0x08080808

.option norvc
    li  x15, 0x33333F0F  # Restore: Lower byte = 0x0F

.option norvc

    #-------------------------------------------------
    # READ BACK STORED VALUES FOR VERIFICATION
    #-------------------------------------------------

    # Load back the stored words to verify correct byte storage
    lw  x1,   0(x29)    # Read SRAM+0  -> x1
    lw  x2,   4(x29)    # Read SRAM+4  -> x2
    lw  x3,   8(x29)    # Read SRAM+8  -> x3
    lw  x4,  12(x29)    # Read SRAM+12 -> x4
    lw  x5,  16(x29)    # Read SRAM+16 -> x5
    lw  x6,  20(x29)    # Read SRAM+20 -> x6
    lw  x7,  24(x29)    # Read SRAM+24 -> x7
    lw  x16, 28(x29)    # Read SRAM+28 -> x16
    # x8-x15 have been restored to their original test data values
    # x17 contains last temporary base pointer (SRAM+28)
    # x18 contains last backup value (x13 backup)

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
