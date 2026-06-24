#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_sll
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SLL
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
    # 1. Basic: shifting a positive number
    #---------------------------------------------------
    li    x1, 0x00000001
    li    x2, 0
    sll   x3, x1, x2         # expect 0x00000001

    li    x4, 0x00000001
    li    x5, 1
    sll   x6, x4, x5         # expect 0x00000002

    li    x7, 0x00000001
    li    x8, 31
    sll   x9, x7, x8         # expect 0x80000000

    #---------------------------------------------------
    # 2. Shifting a pattern 0x0000FFFF
    #---------------------------------------------------
    li    x10, 0x0000FFFF
    li    x11, 4
    sll   x12, x10, x11      # expect 0x000FFFF0

    li    x13, 0x0000FFFF
    li    x14, 16
    sll   x15, x13, x14      # expect 0xFFFF0000

    #---------------------------------------------------
    # 3. Alternating bits (0xAAAAAAAA/0x55555555)
    #---------------------------------------------------
    li    x16, 0xAAAAAAAA
    li    x17, 1
    sll   x18, x16, x17      # expect 0x55555554

    li    x19, 0xAAAAAAAA
    li    x20, 2
    sll   x21, x19, x20      # expect 0xAAAAAAAA << 2 = 0xAAAAAAAA * 4

    li    x22, 0x55555555
    li    x23, 31
    sll   x24, x22, x23      # expect 0x80000000

    #---------------------------------------------------
    # 4. Negative number (0x80000001)
    #---------------------------------------------------
    li    x25, 0x80000001
    li    x26, 1
    sll   x27, x25, x26      # expect 0x00000002

    li    x28, 0x80000001
    li    x29, 4
    sll   x30, x28, x29      # expect 0x00000010

    #---------------------------------------------------
    # 5. Zero shifted
    #---------------------------------------------------
    li    x31, 0
    sll   x1, x31, x2        # expect 0x00000000

	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


