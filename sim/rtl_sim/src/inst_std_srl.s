#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_srl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SRL
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
    # 1. SRL by 0 (should be unchanged)
    #---------------------------------------------------
    li    x1,  0x12345678
    li    x2,  0
    srl   x3,  x1, x2        # expect 0x12345678

    #---------------------------------------------------
    # 2. SRL by 1 (shift right 1)
    #---------------------------------------------------
    li    x4,  0x12345678
    li    x5,  1
    srl   x6,  x4, x5        # expect 0x091A2B3C

    #---------------------------------------------------
    # 3. SRL by 31 (edge case)
    #---------------------------------------------------
    li    x7,  0x12345678
    li    x8,  31
    srl   x9,  x7, x8        # expect 0x00000000 (MSB=0)

    #---------------------------------------------------
    # 4. SRL negative number (-1 >> 1 logical)
    #---------------------------------------------------
    li    x10, -1            # 0xFFFFFFFF
    li    x11, 1
    srl   x12, x10, x11      # expect 0x7FFFFFFF

    #---------------------------------------------------
    # 5. SRL of 0x80000000 (shift sign bit logically)
    #---------------------------------------------------
    li    x13, 0x80000000
    li    x14, 1
    srl   x15, x13, x14      # expect 0x40000000

    #---------------------------------------------------
    # 6. SRL of 0xAAAAAAAA by 4
    #---------------------------------------------------
    li    x16, 0xAAAAAAAA
    li    x17, 4
    srl   x18, x16, x17      # expect 0x0AAAAAAA

    #---------------------------------------------------
    # 7. SRL of 0xFFFFFFFF by 8
    #---------------------------------------------------
    li    x19, 0xFFFFFFFF
    li    x20, 8
    srl   x21, x19, x20      # expect 0x00FFFFFF

    #---------------------------------------------------
    # 8. Random value shift by 12
    #---------------------------------------------------
    li    x22, 0x12345678
    li    x23, 12
    srl   x24, x22, x23      # expect 0x00012345

	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


