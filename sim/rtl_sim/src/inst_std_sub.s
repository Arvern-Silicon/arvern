#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_sub
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SUB
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

	#-------------------------------------------------
	# WRITE SOME VALUES IN THE REGISTERS
	#-------------------------------------------------
 
	li  x1,  0xFFFFFFFF
 	li  x2,  0xFFFFFFFF
 	li  x3,  0xFFFFFFFF
 	li  x4,  0xFFFFFFFF
	li  x5,  0xFFFFFFFF
	li  x6,  0xFFFFFFFF
	li  x7,  0xFFFFFFFF
	li  x8,  0xFFFFFFFF
	li  x9,  0xFFFFFFFF
	li  x10, 0xFFFFFFFF
	li  x11, 0xFFFFFFFF
	li  x12, 0xFFFFFFFF
	li  x13, 0xFFFFFFFF
	li  x14, 0xFFFFFFFF
	li  x15, 0xFFFFFFFF
	li  x16, 0xFFFFFFFF
	li  x17, 0xFFFFFFFF
	li  x18, 0xFFFFFFFF
	li  x19, 0xFFFFFFFF
	li  x20, 0xFFFFFFFF
	li  x21, 0xFFFFFFFF
	li  x22, 0xFFFFFFFF
	li  x23, 0xFFFFFFFF
	li  x24, 0xFFFFFFFF
	li  x25, 0xFFFFFFFF
	li  x26, 0xFFFFFFFF
	li  x27, 0xFFFFFFFF
	li  x28, 0xFFFFFFFF
	li  x29, 0xFFFFFFFF
	li  x30, 0xFFFFFFFF
	li  x31, 0xFFFFFFFF

    #------------------------------------------------
    # 1. Zero minus Zero
    #------------------------------------------------
    li    x1, 0
    sub   x2, x1, x1         # expect 0x00000000

    #------------------------------------------------
    # 2. Zero minus Positive
    #------------------------------------------------
    li    x3, 0
    li    x4, 1234
    sub   x5, x3, x4         # expect -1234 (0xFFFFFB2E)

    #------------------------------------------------
    # 3. Zero minus Negative
    #------------------------------------------------
    li    x6, 0
    li    x7, -5678
    sub   x8, x6, x7         # expect 5678 (0x0000162E)

    #------------------------------------------------
    # 4. Positive minus Zero
    #------------------------------------------------
    li    x9, 8765
    li    x10, 0
    sub   x11, x9, x10       # expect 8765 (0x0000223D)

    #------------------------------------------------
    # 5. Negative minus Zero
    #------------------------------------------------
    li    x12, -3333
    li    x13, 0
    sub   x14, x12, x13      # expect -3333 (0xFFFFF2CB)

    #------------------------------------------------
    # 6. Positive minus Positive (A > B)
    #------------------------------------------------
    li    x15, 100000
    li    x16, 23456
    sub   x17, x15, x16      # expect 76544 (0x00012B60)

    #------------------------------------------------
    # 7. Positive minus Positive (A < B)
    #------------------------------------------------
    li    x18, 23456
    li    x19, 100000
    sub   x20, x18, x19      # expect -76544 (0xFFFE D4A0)

    #------------------------------------------------
    # 8. Negative minus Positive
    #------------------------------------------------
    li    x21, -1
    li    x22, 123
    sub   x23, x21, x22      # expect -124 (0xFFFFFF84)

    #------------------------------------------------
    # 9. Positive minus Negative
    #------------------------------------------------
    li    x24, 123
    li    x25, -1
    sub   x26, x24, x25      # expect 124 (0x0000007C)

    #------------------------------------------------
    # 10. (-2^31) - 1 = 0x7FFFFFFF (overflow wrap)
    #------------------------------------------------
    li    x27, 0x80000000
    li    x28, 1
    sub   x29, x27, x28      # expect 0x7FFFFFFF

    #------------------------------------------------
    # 11. (2^31-1) - (-1) = 0x80000000 (overflow wrap)
    #------------------------------------------------
    li    x30, 0x7FFFFFFF
    li    x31, -1
    sub   x1, x30, x31       # expect 0x80000000


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


