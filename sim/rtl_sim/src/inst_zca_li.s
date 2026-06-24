#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_li
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.LI
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
    li  x2,  0xFFFFFFFF  # marker - will be overwritten
    li  x3,  0xFFFFFFFF  # marker - will be overwritten
    li  x4,  0xFFFFFFFF  # marker - will be overwritten
    li  x5,  0xFFFFFFFF  # marker - will be overwritten
    li  x6,  0xFFFFFFFF  # marker - will be overwritten
    li  x7,  0xFFFFFFFF  # marker - will be overwritten
    li  x8,  0xFFFFFFFF  # marker - will be overwritten
    li  x9,  0xFFFFFFFF  # marker - will be overwritten
    li  x10, 0xDEADBEEF  # marker - used for sync
    nop

    #-------------------------------------------------
    # TEST C.LI (Compressed Load Immediate)
    # Format: c.li rd, imm
    # Function: rd = sign_extended(imm)
    # Immediate range: -32 to +31 (6-bit signed)
    # rd can be any register x1-x31 (x0 is HINT)
    #-------------------------------------------------
.option rvc          # re-enable compressed instructions

    # Positive immediate values
    c.li  x1,  1      # Load +1
    c.li  x2,  5      # Load +5
    c.li  x3,  10     # Load +10
    c.li  x4,  15     # Load +15
    c.li  x5,  20     # Load +20
    c.li  x6,  25     # Load +25
    c.li  x7,  30     # Load +30
    c.li  x8,  31     # Load +31 (maximum positive)

    # Negative immediate values (sign-extended to 32 bits)
    c.li  x9,  -1     # Load -1 (0xFFFFFFFF)
    c.li  x11, -5     # Load -5 (0xFFFFFFFB)
    c.li  x12, -10    # Load -10 (0xFFFFFFF6)
    c.li  x13, -15    # Load -15 (0xFFFFFFF1)
    c.li  x14, -20    # Load -20 (0xFFFFFFEC)
    c.li  x15, -25    # Load -25 (0xFFFFFFE7)
    c.li  x16, -30    # Load -30 (0xFFFFFFE2)
    c.li  x17, -32    # Load -32 (0xFFFFFFE0, minimum)

    # Zero immediate
    c.li  x18, 0      # Load 0

    # Test various registers across the range
    c.li  x19, 7      # Load +7
    c.li  x20, -7     # Load -7
    c.li  x21, 12     # Load +12
    c.li  x22, -12    # Load -12

    # Special case: x0 (should remain zero - HINT instruction)
    c.li  x0,  15     # HINT: x0 should stay 0

.option norvc

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31,  0xdeadbeef

end_of_test:
    nop
    j end_of_test     # infinite loop

