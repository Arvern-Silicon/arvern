#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_slti
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SLTI
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    .section .text
    .globl  _start
_start:

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


    #------------------------------------------
    # 1. Positive < Positive  (expect 1)
    #------------------------------------------
    li   x1, 5
    slti x2, x1, 10       # 5 < 10 -> x2 = 1

    #------------------------------------------
    # 2. Positive == Positive (expect 0)
    #------------------------------------------
    li   x1, 5
    slti x3, x1, 5        # 5 < 5 -> x3 = 0

    #------------------------------------------
    # 3. Positive > Positive  (expect 0)
    #------------------------------------------
    li   x1, 10
    slti x4, x1, 5        # 10 < 5 -> x4 = 0

    #------------------------------------------
    # 4. Negative < Positive (expect 1)
    #------------------------------------------
    li   x1, -1
    slti x5, x1, 0        # -1 < 0 -> x5 = 1

    #------------------------------------------
    # 5. Positive < Negative (expect 0)
    #------------------------------------------
    li   x1, 1
    slti x6, x1, -1       # 1 < -1 -> x6 = 0

    #------------------------------------------
    # 6. Negative == Negative (expect 0)
    #------------------------------------------
    li   x1, -10
    slti x7, x1, -10      # -10 < -10 -> x7 = 0

    #------------------------------------------
    # 7. Negative < Negative (expect 1)
    #------------------------------------------
    li   x1, -20
    slti x8, x1, -10      # -20 < -10 -> x8 = 1

    #------------------------------------------
    # 8. Edge immediate -2048 (expect 0, since 0 < -2048 is false)
    #------------------------------------------
    li   x1, 0
    slti x9, x1, -2048    # 0 < -2048 -> x9 = 0

    #------------------------------------------
    # 9. Edge immediate 2047 (expect 1, since 0 < 2047 is true)
    #------------------------------------------
    li   x1, 0
    slti x10, x1, 2047    # 0 < 2047 -> x10 = 1


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


