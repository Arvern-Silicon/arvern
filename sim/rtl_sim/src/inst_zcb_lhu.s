#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcb_lhu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.LHU
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
    # Note: Little-endian - lowest byte at lowest address
    li  x1,  0xAABBCCDD
    li  x2,  0x11223344
    li  x3,  0x55667788
    li  x4,  0x99AABBCC
    li  x5,  0xDEADBEEF
    li  x6,  0xCAFEBABE
    li  x7,  0x12345678
    li  x16, 0x87654321

    # Store to SRAM using standard SW instructions
    sw  x1,   0(x29)    # 0xAABBCCDD  -->  SRAM+0  (halfwords: 0xCCDD at +0, 0xAABB at +2)
    sw  x2,   4(x29)    # 0x11223344  -->  SRAM+4  (halfwords: 0x3344 at +4, 0x1122 at +6)
    sw  x3,   8(x29)    # 0x55667788  -->  SRAM+8  (halfwords: 0x7788 at +8, 0x5566 at +10)
    sw  x4,  12(x29)    # 0x99AABBCC  -->  SRAM+12 (halfwords: 0xBBCC at +12, 0x99AA at +14)
    sw  x5,  16(x29)    # 0xDEADBEEF  -->  SRAM+16 (halfwords: 0xBEEF at +16, 0xDEAD at +18)
    sw  x6,  20(x29)    # 0xCAFEBABE  -->  SRAM+20 (halfwords: 0xBABE at +20, 0xCAFE at +22)
    sw  x7,  24(x29)    # 0x12345678  -->  SRAM+24 (halfwords: 0x5678 at +24, 0x1234 at +26)
    sw  x16, 28(x29)    # 0x87654321  -->  SRAM+28 (halfwords: 0x4321 at +28, 0x8765 at +30)

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
    # TEST C.LHU (Compressed Load Halfword Unsigned)
    # Format: c.lhu rd', offset(rs1')
    # Function: rd' = zero_extend(memory[rs1' + offset])
    # Registers: rd' and rs1' are x8-x15 (compressed register encoding)
    # Offset range: 0 or 2 (1-bit unsigned, left-shifted by 1)
    # Encoding: 100_001_rs1'[2:0]_uimm[1]_0_rd'[2:0]_00
    #           bit [6] = 0 for C.LHU (vs C.LH where bit [6] = 1)
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Test SET 1: Load halfwords from SRAM+0 using x8 as base
    c.lhu  x9,  0(x8)   # x9  = 0x0000CCDD  <--  SRAM+0 (halfword at offset 0)
    c.lhu  x10, 2(x8)   # x10 = 0x0000AABB  <--  SRAM+2 (halfword at offset 2)

.option norvc
    # Backup first set of loads to x17-x18
    addi x17, x9,  0    # Backup x9  = 0xCCDD
    addi x18, x10, 0    # Backup x10 = 0xAABB

    # Test SET 2: Load halfwords from SRAM+4 using x9 as base
    addi  x9, x29, 4    # x9 = SRAM base + 4
.option rvc
    c.lhu  x10, 0(x9)   # x10 = 0x00003344  <--  SRAM+4 (halfword at offset 0)
    c.lhu  x11, 2(x9)   # x11 = 0x00001122  <--  SRAM+6 (halfword at offset 2)

.option norvc
    # Backup second set of loads to x19-x20
    addi x19, x10, 0    # Backup x10 = 0x3344
    addi x20, x11, 0    # Backup x11 = 0x1122

    # Test SET 3: Load halfwords from SRAM+8 using x10 as base
    addi  x10, x29, 8   # x10 = SRAM base + 8
.option rvc
    c.lhu  x11, 0(x10)  # x11 = 0x00007788  <--  SRAM+8  (halfword at offset 0)
    c.lhu  x12, 2(x10)  # x12 = 0x00005566  <--  SRAM+10 (halfword at offset 2)

.option norvc
    # Backup third set of loads to x21-x22
    addi x21, x11, 0    # Backup x11 = 0x7788
    addi x22, x12, 0    # Backup x12 = 0x5566

    # Test SET 4: Load halfwords from SRAM+12 using x11 as base
    addi  x11, x29, 12  # x11 = SRAM base + 12
.option rvc
    c.lhu  x12, 0(x11)  # x12 = 0x0000BBCC  <--  SRAM+12 (halfword at offset 0)
    c.lhu  x13, 2(x11)  # x13 = 0x000099AA  <--  SRAM+14 (halfword at offset 2)

.option norvc
    # Backup fourth set of loads to x23-x24
    addi x23, x12, 0    # Backup x12 = 0xBBCC
    addi x24, x13, 0    # Backup x13 = 0x99AA

    # Test SET 5: Load halfwords from SRAM+16 using x12 as base
    addi  x12, x29, 16  # x12 = SRAM base + 16
.option rvc
    c.lhu  x13, 0(x12)  # x13 = 0x0000BEEF  <--  SRAM+16 (halfword at offset 0)
    c.lhu  x14, 2(x12)  # x14 = 0x0000DEAD  <--  SRAM+18 (halfword at offset 2)

.option norvc
    # Backup fifth set of loads to x25-x26
    addi x25, x13, 0    # Backup x13 = 0xBEEF
    addi x26, x14, 0    # Backup x14 = 0xDEAD

    # Test SET 6: Load halfwords from SRAM+20 using x13 as base
    addi  x13, x29, 20  # x13 = SRAM base + 20
.option rvc
    c.lhu  x14, 0(x13)  # x14 = 0x0000BABE  <--  SRAM+20 (halfword at offset 0)
    c.lhu  x15, 2(x13)  # x15 = 0x0000CAFE  <--  SRAM+22 (halfword at offset 2)

.option norvc
    # Backup sixth set of loads to x27-x28
    addi x27, x14, 0    # Backup x14 = 0xBABE
    addi x28, x15, 0    # Backup x15 = 0xCAFE

    # Test SET 7: Load halfwords from SRAM+24 using x14 as base (final values)
    addi  x14, x29, 24  # x14 = SRAM base + 24
.option rvc
    c.lhu  x15, 0(x14)  # x15 = 0x00005678  <--  SRAM+24 (halfword at offset 0)
    c.lhu  x8,  2(x14)  # x8  = 0x00001234  <--  SRAM+26 (halfword at offset 2)

.option norvc
    # Backup seventh set of loads to x1-x2
    addi x1, x15, 0     # Backup x15 = 0x5678
    addi x2, x8,  0     # Backup x8  = 0x1234

    # Test SET 8: Final load from SRAM+28 using x15 as base
    addi  x15, x29, 28  # x15 = SRAM base + 28
.option rvc
    c.lhu  x8,  0(x15)  # x8  = 0x00004321  <--  SRAM+28 (halfword at offset 0)
    c.lhu  x9,  2(x15)  # x9  = 0x00008765  <--  SRAM+30 (halfword at offset 2)

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
