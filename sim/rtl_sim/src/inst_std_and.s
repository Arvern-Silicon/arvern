#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_and
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: AND
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
    # 1. AND with zero (result = 0)
    #---------------------------------------------------
    li    x1,  0x12345678
    li    x2,  0x00000000
    and   x3,  x1, x2        # expect 0x00000000

    #---------------------------------------------------
    # 2. AND with itself (result = itself)
    #---------------------------------------------------
    li    x4,  0xFFFFFFFF
    and   x5,  x4, x4        # expect 0xFFFFFFFF

    #---------------------------------------------------
    # 3. AND of two non-overlapping patterns
    #---------------------------------------------------
    li    x6,  0xAAAAAAAA
    li    x7,  0x55555555
    and   x8,  x6, x7        # expect 0x00000000

    #---------------------------------------------------
    # 4. AND with negative number (-1 & 1)
    #---------------------------------------------------
    li    x9,  -1            # 0xFFFFFFFF
    li    x10, 1
    and   x11, x9, x10       # expect 0x00000001

    #---------------------------------------------------
    # 5. Edge: 0x80000000 & 0x7FFFFFFF
    #---------------------------------------------------
    li    x12, 0x80000000
    li    x13, 0x7FFFFFFF
    and   x14, x12, x13      # expect 0x00000000

    #---------------------------------------------------
    # 6. Random numbers
    #---------------------------------------------------
    li    x15, 0x12345678
    li    x16, 0x87654321
    and   x17, x15, x16      # expect 0x02244220

    #---------------------------------------------------
    # 7. AND with mask
    #---------------------------------------------------
    li    x18, 0x0000FFFF
    li    x19, 0x12345678
    and   x20, x18, x19      # expect 0x00005678

    #---------------------------------------------------
    # 8. Pattern test (overlapping)
    #---------------------------------------------------
    li    x21, 0xF0F0F0F0
    li    x22, 0x0F0F0F0F
    and   x23, x21, x22      # expect 0x00000000

	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


