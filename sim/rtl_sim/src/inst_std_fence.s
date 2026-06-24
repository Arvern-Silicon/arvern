#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_fence
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: FENCE
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
	fence.tso
	li  x5,  0xFFFFFFFF
	li  x6,  0xFFFFFFFF
	fence
	fence.tso
	li  x7,  0xFFFFFFFF
	li  x8,  0xFFFFFFFF
	li  x9,  0xFFFFFFFF
	fence
	li  x10, 0xFFFFFFFF
	li  x11, 0xFFFFFFFF
	fence
	li  x12, 0xFFFFFFFF
	fence
	li  x13, 0xFFFFFFFF
	fence.tso
	li  x14, 0xFFFFFFFF
	li  x15, 0xFFFFFFFF
	fence.tso
	li  x16, 0xFFFFFFFF
	fence
	li  x17, 0xFFFFFFFF
	li  x18, 0xFFFFFFFF
	li  x19, 0xFFFFFFFF
	fence.tso
	li  x20, 0xFFFFFFFF
	li  x21, 0xFFFFFFFF
	li  x22, 0xFFFFFFFF
	fence.tso
	li  x23, 0xFFFFFFFF
	fence
	li  x24, 0xFFFFFFFF
	li  x25, 0xFFFFFFFF
	li  x26, 0xFFFFFFFF
	li  x27, 0xFFFFFFFF
	fence
	li  x28, 0xFFFFFFFF
	li  x29, 0xFFFFFFFF
	fence
	li  x30, 0xFFFFFFFF
	li  x31, 0xFFFFFFFF





	li  x0,  0x34512657
	li  x1,  0x12345874
	fence.tso
 	li  x2,  0xdeadbeef
	fence
 	li  x3,  0x10000543
 	li  x4,  0xabcd149d

	fence iorw, i
	fence iorw, o
	fence iorw, r
	fence iorw, w

	fence i, iorw
	fence o, iorw
	fence r, iorw
	fence w, iorw

	fence orw, i
	fence irw, o
	fence iow, r
	fence ior, w

	fence ow, ir
	fence ir, ow
	fence iw, rw
	fence or, iw

	fence i,i           # FENCE: 0880000F
	fence o,o           # FENCE: 0440000F
	fence r,r           # FENCE: 0220000F
	fence w,w           # FENCE: 0110000F

	.word 0x0100000f    # PAUSE: 0100000F encodes pred=1, succ=0 (I/O input only, no successor)

	li  x5,  0x0bad0db2
	fence.tso
	li  x6,  0x0000fa3f
	li  x7,  0xffff019c
	li  x8,  0x11111e48
	fence
	li  x9,  0x333447be
	li  x10, 0x55555123
	fence.tso
	li  x11, 0x77788234
	li  x12, 0x99999432
	fence
	fence
	fence
	li  x13, 0xBBBCC654
	li  x14, 0xDDDDD678
	fence
	li  x15, 0xFFF009ca
	li  x16, 0x11223aed
	fence
	li  x17, 0x55667dea
	li  x18, 0x99AABdbe
	li  x19, 0xDDEEFefd
	li  x20, 0x01234ead
	fence.tso
	fence
	li  x21, 0x89ABCbee
	li  x22, 0xFEDCBfde
	fence
	li  x23, 0x76543adb
	fence.tso
	li  x24, 0x00FFEeef
	li  x25, 0xCCBBAcaf
	fence
	fence.tso
	li  x26, 0x88776efa
	li  x27, 0x44332ce0
	fence
	li  x28, 0x135799de
	li  x29, 0x02468abc
	fence
	li  x30, 0xcba86420
	fence.tso

	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


