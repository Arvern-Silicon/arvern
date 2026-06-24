#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_add
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ADD
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
    # 1. Simple positive addition
    #------------------------------------------------
    li    x1, 10
    li    x2, 20
    add   x3, x1, x2          # expect 30

    #------------------------------------------------
    # 2. Adding a number and its negative (should be 0)
    #------------------------------------------------
    li    x4, 1234
    li    x5, -1234
    add   x6, x4, x5          # expect 0

    #------------------------------------------------
    # 3. Adding two negative numbers
    #------------------------------------------------
    li    x7, -100
    li    x8, -200
    add   x9, x7, x8          # expect -300 (0xFFFFFED4)

    #------------------------------------------------
    # 4. Adding with zero
    #------------------------------------------------
    li    x10, 0
    li    x11, 0xABCDEF01
    add   x12, x10, x11       # expect 0xABCDEF01
    add   x13, x11, x10       # expect 0xABCDEF01

    #------------------------------------------------
    # 5. Positive overflow
    # (0x7FFFFFFF + 1 = 0x80000000)
    #------------------------------------------------
    li    x14, 0x7FFFFFFF
    li    x15, 1
    add   x16, x14, x15       # expect 0x80000000

    #------------------------------------------------
    # 6. Negative overflow (wrap around)
    # (0x80000000 + -1 = 0x7FFFFFFF)
    #------------------------------------------------
    li    x17, 0x80000000
    li    x18, -1
    add   x19, x17, x18       # expect 0x7FFFFFFF

    #------------------------------------------------
    # 7. Mixed sign
    # (100 + -50 = 50)
    #------------------------------------------------
    li    x20, 100
    li    x21, -50
    add   x22, x20, x21       # expect 50


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


