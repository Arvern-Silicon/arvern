#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_lui
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.LUI
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

    li  x1,  0xFFFFFFFF  # marker - will be overwritten
    li  x3,  0xFFFFFFFF  # marker - will be overwritten (skip x2/sp)
    li  x4,  0xFFFFFFFF  # marker - will be overwritten
    li  x5,  0xFFFFFFFF  # marker - will be overwritten
    li  x6,  0xFFFFFFFF  # marker - will be overwritten
    li  x7,  0xFFFFFFFF  # marker - will be overwritten
    li  x8,  0xFFFFFFFF  # marker - will be overwritten
    li  x9,  0xFFFFFFFF  # marker - will be overwritten
    li  x10, 0xDEADBEEF  # marker - used for sync
    nop

    #-------------------------------------------------
    # TEST C.LUI (Compressed Load Upper Immediate)
    # Format: c.lui rd, imm
    # Function: rd = sign_extend(imm[5:0]) << 12
    # Immediate range: 6-bit signed (-32 to +31, excluding 0)
    # rd can be x1, x3-x31 (x0 is HINT, x2 uses C.ADDI16SP instead)
    # NOTE: imm=0 is illegal/reserved
    # NOTE: GNU assembler only accepts positive syntax (1-31)
    #       For negative values, use .hword directive with manual encoding:
    #       Format: 011_imm[5]_rd[4:0]_imm[4:0]_01
    #       Example: .hword 0x75FD  # c.lui x11, -1
    #-------------------------------------------------
.option rvc          # re-enable compressed instructions

    # Positive immediate values (shifted left by 12 bits)
    # Note: C.LUI immediate range is 1-31 (0 is illegal, x2 uses C.ADDI16SP instead)
    c.lui  x1,  1      # Load 0x00001000
    c.lui  x3,  2      # Load 0x00002000 (skip x2/sp - uses c.addi16sp)
    c.lui  x4,  5      # Load 0x00005000
    c.lui  x5,  10     # Load 0x0000A000
    c.lui  x6,  15     # Load 0x0000F000
    c.lui  x7,  20     # Load 0x00014000
    c.lui  x8,  25     # Load 0x00019000
    c.lui  x9,  31     # Load 0x0001F000 (maximum)

    # Negative immediate values (manually encoded - GNU assembler doesn't support negative syntax)
    # Format: 011_imm[5]_rd[4:0]_imm[4:0]_01
    # These test the sign-extension behavior of the 6-bit immediate field
    .hword 0x75FD        # c.lui x11, -1  (imm=0x3F) -> Load 0xFFFFF000
    .hword 0x7679        # c.lui x12, -2  (imm=0x3E) -> Load 0xFFFFE000
    .hword 0x76ED        # c.lui x13, -5  (imm=0x3B) -> Load 0xFFFFB000
    .hword 0x7759        # c.lui x14, -10 (imm=0x36) -> Load 0xFFFF6000
    .hword 0x77C5        # c.lui x15, -15 (imm=0x31) -> Load 0xFFFF1000
    .hword 0x7831        # c.lui x16, -20 (imm=0x2C) -> Load 0xFFFEC000
    .hword 0x789D        # c.lui x17, -25 (imm=0x27) -> Load 0xFFFE7000
    .hword 0x7901        # c.lui x18, -32 (imm=0x20) -> Load 0xFFFE0000 (minimum)

    # Additional tests with mixed values
    c.lui  x19, 7        # Load 0x00007000
    .hword 0x7A65        # c.lui x20, -7  (imm=0x39) -> Load 0xFFFF9000
    c.lui  x21, 12       # Load 0x0000C000
    .hword 0x7B51        # c.lui x22, -12 (imm=0x34) -> Load 0xFFFF4000

    # Special case: x0 (should remain zero - HINT instruction)
    c.lui  x0,  15     # HINT: x0 should stay 0

.option norvc

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31,  0xdeadbeef

end_of_test:
    nop
    j end_of_test     # infinite loop

