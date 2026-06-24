#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_andi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.ANDI
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

    # Load compressed registers (x8-x15) with test patterns
    li  x8,  0xFFFFFFFF  # All 1s
    li  x9,  0xAAAAAAAA  # Alternating pattern
    li  x10, 0x12345678  # Mixed pattern
    li  x11, 0xF0F0F0F0  # Nibble pattern
    li  x12, 0x0F0F0F0F  # Inverse nibble
    li  x13, 0xDEADBEEF  # Test pattern
    li  x14, 0x80000001  # MSB and LSB set
    li  x15, 0x00000000  # Zero

    # Setup markers
    li  x1,  0xCAFEBABE
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.ANDI (Compressed AND Immediate)
    # Format: c.andi rd', imm
    # Function: rd' = rd' & sign_extend(imm)
    # Registers: rd' is x8-x15 (compressed register encoding)
    # Immediate: 6-bit signed (-32 to +31)
    # Encoding: 100_imm[5]_10_rd'[2:0]_imm[4:0]_01
    #
    # Sign-extension examples:
    # - Positive imm (0-31): extends with 0s, e.g., 15 -> 0x0000000F
    # - Negative imm (-32 to -1): extends with 1s, e.g., -1 -> 0xFFFFFFFF
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Positive immediate values
    #-------------------------------------------------
    c.andi x8,  31       # 0xFFFFFFFF & 0x0000001F = 0x0000001F
    c.andi x9,  15       # 0xAAAAAAAA & 0x0000000F = 0x0000000A
    c.andi x10, 7        # 0x12345678 & 0x00000007 = 0x00000000
    c.andi x11, 3        # 0xF0F0F0F0 & 0x00000003 = 0x00000000
    c.andi x12, 1        # 0x0F0F0F0F & 0x00000001 = 0x00000001

.option norvc
    # Backup first set of results to x16-x20
    addi x16, x8,  0     # Backup x8
    addi x17, x9,  0     # Backup x9
    addi x18, x10, 0     # Backup x10
    addi x19, x11, 0     # Backup x11
    addi x20, x12, 0     # Backup x12

    # Reload for second set
    li  x8,  0xFFFFFFFF  # All 1s
    li  x9,  0x12345678  # Mixed pattern
    li  x10, 0xAAAAAAAA  # Alternating
    li  x11, 0xF0F0F0F0  # Nibble pattern
    li  x12, 0x00000000  # Zero
.option rvc

    #-------------------------------------------------
    # Test Set 2: Negative immediate values (sign-extended to 0xFFFFFFxx)
    #-------------------------------------------------
    c.andi x8,  -1       # 0xFFFFFFFF & 0xFFFFFFFF = 0xFFFFFFFF
    c.andi x9,  -2       # 0x12345678 & 0xFFFFFFFE = 0x12345678
    c.andi x10, -4       # 0xAAAAAAAA & 0xFFFFFFFC = 0xAAAAAAA8
    c.andi x11, -8       # 0xF0F0F0F0 & 0xFFFFFFF8 = 0xF0F0F0F0
    c.andi x12, -16      # 0x00000000 & 0xFFFFFFF0 = 0x00000000

.option norvc
    # Backup second set of results to x21-x25
    addi x21, x8,  0     # Backup x8
    addi x22, x9,  0     # Backup x9
    addi x23, x10, 0     # Backup x10
    addi x24, x11, 0     # Backup x11
    addi x25, x12, 0     # Backup x12

    # Reload for third set
    li  x13, 0xFFFFFFFF  # All 1s
    li  x14, 0x80000001  # MSB and LSB set
    li  x15, 0xDEADBEEF  # Test pattern
.option rvc

    #-------------------------------------------------
    # Test Set 3: Boundary cases
    #-------------------------------------------------
    c.andi x13, 0        # 0xFFFFFFFF & 0x00000000 = 0x00000000
    c.andi x14, -32      # 0x80000001 & 0xFFFFFFE0 = 0x80000000 (min negative)
    c.andi x15, 31       # 0xDEADBEEF & 0x0000001F = 0x0000000F (max positive)

.option norvc
    # Backup third set of results to x26-x28
    addi x26, x13, 0     # Backup x13
    addi x27, x14, 0     # Backup x14
    addi x28, x15, 0     # Backup x15

    # Reload for masking tests
    li  x8,  0x12345678
    li  x9,  0xFFFFFFFF
    li  x10, 0xABCDEF01
.option rvc

    #-------------------------------------------------
    # Test Set 4: Bit masking patterns
    #-------------------------------------------------
    c.andi x8,  15       # 0x12345678 & 0x0000000F = 0x00000008 (isolate low nibble)
    c.andi x9,  -16      # 0xFFFFFFFF & 0xFFFFFFF0 = 0xFFFFFFF0 (clear low 4 bits)
    c.andi x10, -1       # 0xABCDEF01 & 0xFFFFFFFF = 0xABCDEF01 (no change)

.option norvc
    # Backup fourth set of results to x29, x30, x2
    addi x29, x8,  0     # Backup x8
    addi x30, x9,  0     # Backup x9
    addi x2,  x10, 0     # Backup x10

    # Reload for consecutive operations test
    li  x11, 0xFFFFFFFF
.option rvc

    #-------------------------------------------------
    # Test Set 5: Multiple consecutive ANDs
    #-------------------------------------------------
    c.andi x11, 31       # 0xFFFFFFFF & 0x0000001F = 0x0000001F
    c.andi x11, 15       # 0x0000001F & 0x0000000F = 0x0000000F
    c.andi x11, 7        # 0x0000000F & 0x00000007 = 0x00000007
    c.andi x11, 3        # 0x00000007 & 0x00000003 = 0x00000003

.option norvc
    # Backup fifth set result
    addi x3, x11, 0      # Backup x11

    # Test with specific bit patterns
    li  x12, 0x55555555  # 0101...
    li  x13, 0xAAAAAAAA  # 1010...
    li  x14, 0xF0F0F0F0
.option rvc

    #-------------------------------------------------
    # Test Set 6: Pattern masking
    #-------------------------------------------------
    c.andi x12, 15       # 0x55555555 & 0x0000000F = 0x00000005
    c.andi x13, -3       # 0xAAAAAAAA & 0xFFFFFFFD = 0xAAAAAAA8
    c.andi x14, 16       # 0xF0F0F0F0 & 0x00000010 = 0x00000010

.option norvc
    # Backup sixth set results
    addi x4, x12, 0      # Backup x12
    addi x5, x13, 0      # Backup x13
    addi x6, x14, 0      # Backup x14

    # Test odd immediate values
    li  x15, 0x12345678
    li  x8,  0xFFFFFFFF
.option rvc

    #-------------------------------------------------
    # Test Set 7: Odd immediate values
    #-------------------------------------------------
    c.andi x15, 21       # 0x12345678 & 0x00000015 = 0x00000010
    c.andi x8,  -17      # 0xFFFFFFFF & 0xFFFFFFEF = 0xFFFFFFEF

.option norvc
    # Backup seventh set results
    addi x7, x15, 0      # Backup x15
    addi x9, x8,  0      # Backup x8

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop
