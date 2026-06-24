#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_addi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.ADDI
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

    li  x1,  0x12345DDD
    li  x2,  0xdeadbFFF
    li  x3,  0x10000112
    li  x4,  0xabcd1556
    li  x5,  0x0bad099A
    li  x6,  0x0000fDDE
    li  x7,  0xffff0012
    li  x8,  0x1111189A
    li  x9,  0x33344FED
    li  x10, 0x55555765
    li  x16, 0xAAAA5555
    li  x17, 0x7FFFFFFF
    li  x18, 0x80000000
    nop

    #-------------------------------------------------
    # TEST C.ADDI (Compressed ADD Immediate)
    # Immediate range: -32 to +31 (6-bit signed)
    #-------------------------------------------------
.option rvc          # re-enable compressed instructions

    # Basic positive/negative tests
    c.addi  x1,   1      # +1
    c.addi  x2,  -1      # -1
    c.addi  x3,   5      # +5
    c.addi  x4, -10      # -10
    c.addi  x5,  15      # +15
    c.addi  x6, -20      # -20
    c.addi  x7,  25      # +25
    c.addi  x8, -30      # -30
    c.addi  x9,  12      # +12
    c.addi  x10, -5      # -5
    c.addi  x11,  7      # +7
    c.addi  x12, -8      # -8
    c.addi  x13,  2      # +2
    c.addi  x14, -3      # -3
    c.addi  x15,  1      # +1

    # Boundary value tests
    c.addi  x16, 31      # Maximum positive immediate (+31)
    c.addi  x16, -32     # Minimum negative immediate (-32)

    # Overflow tests (32-bit wraparound)
    c.addi  x17,  1      # 0x7FFFFFFF + 1 = 0x80000000 (overflow to negative)
    c.addi  x18, -1      # 0x80000000 - 1 = 0x7FFFFFFF (underflow to positive)

    # Special case: x0 (should remain zero - HINT instruction)
    c.addi  x0,  10      # HINT: x0 should stay 0

    # Special case: zero immediate (canonical NOP when rd=x0)
    c.nop                # c.addi x0, 0

.option norvc

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31,  0xdeadbeef

end_of_test:
    nop
    j end_of_test     # infinite loop

