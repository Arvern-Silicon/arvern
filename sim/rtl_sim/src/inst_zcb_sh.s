#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_sh
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SH
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

    # Initialize SRAM to known pattern (all 0xAAAAAAAA) for verification
    li  x16, 0xAAAAAAAA
    sw  x16,  0(x29)    # SRAM+0
    sw  x16,  4(x29)    # SRAM+4
    sw  x16,  8(x29)    # SRAM+8
    sw  x16, 12(x29)    # SRAM+12
    sw  x16, 16(x29)    # SRAM+16
    sw  x16, 20(x29)    # SRAM+20
    sw  x16, 24(x29)    # SRAM+24
    sw  x16, 28(x29)    # SRAM+28

    # Load compressed registers with test halfword patterns
    # Each register has a unique halfword value in the lower 16 bits
    li  x8,  0xDEAD0108  # Lower halfword: 0x0108
    li  x9,  0xCAFE0209  # Lower halfword: 0x0209
    li  x10, 0x1234030A  # Lower halfword: 0x030A
    li  x11, 0x9876040B  # Lower halfword: 0x040B
    li  x12, 0xABCD050C  # Lower halfword: 0x050C
    li  x13, 0x5555060D  # Lower halfword: 0x060D
    li  x14, 0xCCCC070E  # Lower halfword: 0x070E
    li  x15, 0x3333080F  # Lower halfword: 0x080F

    # x29 will be used as base pointer
    # It's already set to SRAM base (0x80000010)

    # Signal initial setup complete
    li   x31, 0xDEADBEEF
    nop

    #-------------------------------------------------
    # TEST C.SH (Compressed Store Halfword)
    # Format: c.sh rs2', offset(rs1')
    # Function: memory[rs1' + offset] = rs2'[15:0]
    # Registers: rs1' and rs2' are x8-x15 (compressed register encoding)
    # Offset range: 0 or 2 (1-bit unsigned, left-shifted by 1)
    # Encoding: 100_011_rs1'[2:0]_uimm[1]_rs2'[2:0]_00
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Test SET 1: Store 2 different halfwords to SRAM+0 using x8 as base
.option norvc
    addi  x17, x29, 0    # x17 = SRAM base + 0
    addi  x8, x17, 0     # x8 = base pointer
.option rvc
    c.sh  x9,  0(x8)    # Store 0x0209 --> SRAM+0 (halfword at offset 0)
    c.sh  x10, 2(x8)    # Store 0x030A --> SRAM+2 (halfword at offset 2)
    # Expected word at SRAM+0: 0x030A0209

.option norvc
    li  x8,  0xDEAD0108  # Restore: Lower halfword = 0x0108

    # Test SET 2: Store 2 different halfwords to SRAM+4 using x9 as base
    addi  x17, x29, 4    # x17 = SRAM base + 4
    addi  x9, x17, 0     # x9 = base pointer
.option rvc
    c.sh  x11, 0(x9)    # Store 0x040B --> SRAM+4 (halfword at offset 0)
    c.sh  x12, 2(x9)    # Store 0x050C --> SRAM+6 (halfword at offset 2)
    # Expected word at SRAM+4: 0x050C040B

.option norvc
    li  x9,  0xCAFE0209  # Restore: Lower halfword = 0x0209

    # Test SET 3: Store 2 different halfwords to SRAM+8 using x10 as base
    addi  x17, x29, 8   # x17 = SRAM base + 8
    addi  x10, x17, 0   # x10 = base pointer
.option rvc
    c.sh  x13, 0(x10)   # Store 0x060D --> SRAM+8  (halfword at offset 0)
    c.sh  x14, 2(x10)   # Store 0x070E --> SRAM+10 (halfword at offset 2)
    # Expected word at SRAM+8: 0x070E060D

.option norvc
    li  x10, 0x1234030A  # Restore: Lower halfword = 0x030A

    # Test SET 4: Store 2 different halfwords to SRAM+12 using x11 as base
    # Use x12 as base to avoid overwriting x11 which is a data source
    addi  x17, x29, 12  # x17 = SRAM base + 12
    addi  x12, x17, 0   # x12 = base pointer
.option rvc
    c.sh  x15, 0(x12)   # Store 0x080F --> SRAM+12 (halfword at offset 0)
    c.sh  x11, 2(x12)   # Store 0x040B --> SRAM+14 (halfword at offset 2)
    # Expected word at SRAM+12: 0x040B080F

.option norvc
    li  x12, 0xABCD050C  # Restore: Lower halfword = 0x050C

    # Test SET 5: Store 2 different halfwords to SRAM+16
    # Use x11 as base to avoid overwriting x8 or x13 which are data sources
    addi  x17, x29, 16  # x17 = SRAM base + 16
    addi  x11, x17, 0   # x11 = base pointer
.option rvc
    c.sh  x8,  0(x11)   # Store 0x0108 --> SRAM+16 (halfword at offset 0)
    c.sh  x13, 2(x11)   # Store 0x060D --> SRAM+18 (halfword at offset 2)
    # Expected word at SRAM+16: 0x060D0108

.option norvc
    li  x11, 0x9876040B  # Restore: Lower halfword = 0x040B

    # Test SET 6: Store 2 different halfwords to SRAM+20 using x14 as base
    addi  x17, x29, 20  # x17 = SRAM base + 20
    addi  x14, x17, 0   # x14 = base pointer
.option rvc
    c.sh  x12, 0(x14)   # Store 0x050C --> SRAM+20 (halfword at offset 0)
    c.sh  x9,  2(x14)   # Store 0x0209 --> SRAM+22 (halfword at offset 2)
    # Expected word at SRAM+20: 0x0209050C

.option norvc
    li  x14, 0xCCCC070E  # Restore: Lower halfword = 0x070E

    # Test SET 7: Store 2 identical halfwords to SRAM+24 using x15 as base
    addi  x17, x29, 24  # x17 = SRAM base + 24
    addi  x15, x17, 0   # x15 = base pointer
.option rvc
    c.sh  x10, 0(x15)   # Store 0x030A --> SRAM+24 (halfword at offset 0)
    c.sh  x10, 2(x15)   # Store 0x030A --> SRAM+26 (halfword at offset 2)
    # Expected word at SRAM+24: 0x030A030A

.option norvc
    li  x15, 0x3333080F  # Restore: Lower halfword = 0x080F

    # Test SET 8: Store 2 identical halfwords to SRAM+28 using x9 as base
    addi  x17, x29, 28  # x17 = SRAM base + 28
    addi  x9, x17, 0    # x9 = base pointer
.option rvc
    c.sh  x11, 0(x9)    # Store 0x040B --> SRAM+28 (halfword at offset 0)
    c.sh  x11, 2(x9)    # Store 0x040B --> SRAM+30 (halfword at offset 2)
    # Expected word at SRAM+28: 0x040B040B

.option norvc
    li  x9,  0xCAFE0209  # Restore: Lower halfword = 0x0209

    #-------------------------------------------------
    # READ BACK STORED VALUES FOR VERIFICATION
    #-------------------------------------------------

    # Load back the stored words to verify correct halfword storage
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
    # x18 contains x8 backup value

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
