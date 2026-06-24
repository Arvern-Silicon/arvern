#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_srli
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SRLI
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
    # 1. Shift by 0 (no change)
    #------------------------------------------------
    li    x1, 0x12345678
    srli  x2, x1, 0           # expect 0x12345678

    #------------------------------------------------
    # 2. Shift by 1 (logical shift)
    #------------------------------------------------
    li    x1, 0x80000001
    srli  x3, x1, 1           # expect 0x40000000

    #------------------------------------------------
    # 3. Shift by 4
    #------------------------------------------------
    li    x1, 0x12345678
    srli  x4, x1, 4           # expect 0x01234567

    #------------------------------------------------
    # 4. Shift by 7
    #------------------------------------------------
    li    x1, 0x0000FF00
    srli  x5, x1, 7           # expect 0x000001FE

    #------------------------------------------------
    # 5. Shift by 31 (max shift amount)
    #------------------------------------------------
    li    x1, 0x80000001
    srli  x6, x1, 31          # expect 0x00000001

    #------------------------------------------------
    # 6. Shift negative number logically
    # (0xFFFFFFFF >> 1 = 0x7FFFFFFF)
    #------------------------------------------------
    li    x1, -1
    srli  x7, x1, 1           # expect 0x7FFFFFFF


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


