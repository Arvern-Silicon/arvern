#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_slt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SLT
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

    #---------------------------------------------------
    # 1. Equal numbers (should be 0)
    #---------------------------------------------------
    li    x1,  5
    li    x2,  5
    slt   x3,  x1, x2        # expect 0

    #---------------------------------------------------
    # 2. A < B (positive)
    #---------------------------------------------------
    li    x4,  1
    li    x5,  2
    slt   x6,  x4, x5        # expect 1

    #---------------------------------------------------
    # 3. A > B (positive)
    #---------------------------------------------------
    li    x7,  10
    li    x8,  3
    slt   x9,  x7, x8        # expect 0

    #---------------------------------------------------
    # 4. A < B (negative < positive)
    #---------------------------------------------------
    li    x10, -1
    li    x11,  1
    slt   x12, x10, x11      # expect 1

    #---------------------------------------------------
    # 5. A > B (positive > negative)
    #---------------------------------------------------
    li    x13,  1
    li    x14, -1
    slt   x15, x13, x14      # expect 0

    #---------------------------------------------------
    # 6. A < B (both negative, -5 < -1)
    #---------------------------------------------------
    li    x16, -5
    li    x17, -1
    slt   x18, x16, x17      # expect 1

    #---------------------------------------------------
    # 7. A > B (both negative, -1 > -5)
    #---------------------------------------------------
    li    x19, -1
    li    x20, -5
    slt   x21, x19, x20      # expect 0

    #---------------------------------------------------
    # 8. Edge: smallest negative vs positive
    #---------------------------------------------------
    li    x22, 0x80000000    # -2^31
    li    x23, 0
    slt   x24, x22, x23      # expect 1

    #---------------------------------------------------
    # 9. Edge: positive vs smallest negative
    #---------------------------------------------------
    li    x25, 0
    li    x26, 0x80000000    # -2^31
    slt   x27, x25, x26      # expect 0

    #---------------------------------------------------
    # 10. Max positive vs Max positive (equal)
    #---------------------------------------------------
    li    x28, 0x7FFFFFFF
    li    x29, 0x7FFFFFFF
    slt   x30, x28, x29      # expect 0

    #---------------------------------------------------
    # 11. Max positive vs -1
    #---------------------------------------------------
    li    x31, 0x7FFFFFFF
    li    x1,  -1
    slt   x2,  x31, x1       # expect 0

    #---------------------------------------------------
    # 12. -1 vs Max positive
    #---------------------------------------------------
    li    x3,  -1
    li    x4,  0x7FFFFFFF
    slt   x5,  x3, x4        # expect 1

	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


