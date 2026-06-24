#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_addi16sp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.ADDI16SP
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

    li  x1,  0xDEADBEEF  # marker value
    li  x2,  0x20000400  # sp - stack pointer base (large enough for testing)
    nop

    #-------------------------------------------------
    # TEST C.ADDI16SP (Compressed Add Immediate 16*SP)
    # Format: c.addi16sp imm
    # Function: sp = sp + sign_extended(imm << 4)
    # Immediate range: -512 to 496 (6-bit signed, multiple of 16)
    # Always modifies x2 (stack pointer)
    # NOTE: imm=0 is illegal/reserved
    # NOTE: GNU assembler accepts both positive and negative values
    #       For values the assembler doesn't support, use .hword directive
    #       Format: 011_imm[9]_00010_imm[4|6|8:7|5]_01
    #-------------------------------------------------
.option rvc          # re-enable compressed instructions

    # Positive immediate values (multiples of 16)
    c.addi16sp sp, 16       # sp = sp + 16
    c.addi16sp sp, 32       # sp = sp + 32
    c.addi16sp sp, 64       # sp = sp + 64
    c.addi16sp sp, 128      # sp = sp + 128
    c.addi16sp sp, 256      # sp = sp + 256
    c.addi16sp sp, 496      # sp = sp + 496 (maximum positive)

    # Negative immediate values (multiples of 16)
    c.addi16sp sp, -16      # sp = sp - 16
    c.addi16sp sp, -32      # sp = sp - 32
    c.addi16sp sp, -64      # sp = sp - 64
    c.addi16sp sp, -128     # sp = sp - 128
    c.addi16sp sp, -256     # sp = sp - 256
    c.addi16sp sp, -512     # sp = sp - 512 (maximum negative)

    # Additional boundary tests
    c.addi16sp sp, 48       # sp = sp + 48
    c.addi16sp sp, -48      # sp = sp - 48
    c.addi16sp sp, 80       # sp = sp + 80
    c.addi16sp sp, -80      # sp = sp - 80

    # Mixed pattern
    c.addi16sp sp, 112      # sp = sp + 112
    c.addi16sp sp, -112     # sp = sp - 112
    c.addi16sp sp, 240      # sp = sp + 240
    c.addi16sp sp, -240     # sp = sp - 240

.option norvc

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31,  0xdeadbeef

end_of_test:
    nop
    j end_of_test     # infinite loop
