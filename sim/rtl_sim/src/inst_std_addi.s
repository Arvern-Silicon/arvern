#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_addi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ADDI
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

	#-------------------------------------------------
	# WRITE SOME VALUES IN THE REGISTERS
	#-------------------------------------------------
 
	# Prepare some data to be written
	li  x1,  0x12345DDD
 	li  x2,  0xdeadbFFF
 	li  x3,  0x10000112
 	li  x4,  0xabcd1556
	li  x5,  0x0bad099A
	li  x6,  0x0000fDDE
	li  x7,  0xffff0012
	li  x8,  0x1111189A
	li  x9,  0x33344FED
	li  x10, 0x55555765

	#--------------------------------------------------------------------
	# SOME ADDI INSTRUCTIONS (Imm range: -2048 to 2047  / 0x800 to 0x7FF
	#--------------------------------------------------------------------
 
	addi	x16, x1,  -1
	addi	x17, x2,   1
	addi	x18, x3,   0x700
	addi	x19, x4,  -0x556
	addi	x20, x5,  -16
	addi	x21, x6,  0x60f
	addi	x22, x7,  -230
	addi	x23, x8,  1234
	addi	x24, x9,  0x678
	addi	x25, x10, -568
	addi	x26, x25, -0xC0
	addi	x27, x26, -1


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


