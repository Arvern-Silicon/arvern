#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_or
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: OR
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
    # 1. OR with zero (result = input)
    #---------------------------------------------------
    li    x1,  0x12345678
    li    x2,  0x00000000
    or    x3,  x1, x2        # expect 0x12345678

    #---------------------------------------------------
    # 2. OR with itself (result = itself)
    #---------------------------------------------------
    li    x4,  0xFFFFFFFF
    or    x5,  x4, x4        # expect 0xFFFFFFFF

    #---------------------------------------------------
    # 3. OR of two non-overlapping patterns
    #---------------------------------------------------
    li    x6,  0xAAAAAAAA
    li    x7,  0x55555555
    or    x8,  x6, x7        # expect 0xFFFFFFFF

    #---------------------------------------------------
    # 4. OR with negative number (-1 | 1)
    #---------------------------------------------------
    li    x9,  -1            # 0xFFFFFFFF
    li    x10, 1
    or    x11, x9, x10       # expect 0xFFFFFFFF

    #---------------------------------------------------
    # 5. Edge: 0x80000000 | 0x7FFFFFFF
    #---------------------------------------------------
    li    x12, 0x80000000
    li    x13, 0x7FFFFFFF
    or    x14, x12, x13      # expect 0xFFFFFFFF

    #---------------------------------------------------
    # 6. Random numbers
    #---------------------------------------------------
    li    x15, 0x12345678
    li    x16, 0x87654321
    or    x17, x15, x16      # expect 0x97755779

    #---------------------------------------------------
    # 7. OR with zero (again)
    #---------------------------------------------------
    li    x18, 0x0000FFFF
    li    x19, 0
    or    x20, x18, x19      # expect 0x0000FFFF

    #---------------------------------------------------
    # 8. Pattern test (overlapping)
    #---------------------------------------------------
    li    x21, 0xF0F0F0F0
    li    x22, 0x0F0F0F0F
    or    x23, x21, x22      # expect 0xFFFFFFFF

	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


