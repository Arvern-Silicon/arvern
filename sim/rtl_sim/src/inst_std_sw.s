#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_sw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SW
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
	li  x11, 0x7778800F
	li  x12, 0x99999CCB
	li  x13, 0xBBBCC887
	li  x14, 0xDDDDD443
	li  x15, 0xFFF00135
	li  x16, 0x11223024
	li  x17, 0x55667451
	li  x18, 0x99AAB234
	li  x19, 0xDDEEFead
	li  x20, 0x01234000
	li  x21, 0x89ABCbcd
	li  x22, 0xFEDCBbad
	li  x23, 0x76543000
	li  x24, 0x00FFEfff
	li  x25, 0xCCBBA111
	li  x26, 0x88776334
	li  x27, 0x44332555
	li  x28, 0x13579778

	# Prepare target pointers to SRAM, Periph #0 and Periph #1
	li  x29, 0x80000010
	li  x30, 0x10040010
	li  x31, 0x10041010

	#-------------------------------------------------
	# STORE COMMANDS
	#-------------------------------------------------
 
	# Store data
	sw  x1,  -16(x29)   # 0x12345DDD  -->  SRAM
	sw  x2,    0(x30)   # 0xdeadbFFF  -->  Periph #0
	sw  x3,   16(x31)   # 0x10000112  -->  Periph #1  --> not writable

	sw  x4,  -12(x29)   # 0xabcd1556  -->  SRAM
	sw  x5,    4(x30)   # 0x0bad099A  -->  Periph #0
	sw  x6,   12(x31)   # 0x0000fDDE  -->  Periph #1

	sw  x7,   -8(x29)   # 0xffff0012  -->  SRAM
	sw  x8,   -4(x30)   # 0x1111189A  -->  Periph #0
	sw  x9,    8(x31)   # 0x33344FED  -->  Periph #1

	sw  x10,  -4(x29)   # 0x55555765  -->  SRAM
	sw  x11,   8(x30)   # 0x7778800F  -->  Periph #0
	sw  x12,   4(x31)   # 0x99999CCB  -->  Periph #1

	sw  x13,   0(x29)   # 0xBBBCC887  -->  SRAM
	sw  x14,  -8(x30)   # 0xDDDDD443  -->  Periph #0
	sw  x15,   0(x31)   # 0xFFF00135  -->  Periph #1

	sw  x16,   4(x29)   # 0x11223024  -->  SRAM
	sw  x17,  12(x30)   # 0x55667451  -->  Periph #0
	sw  x18,  -4(x31)   # 0x99AAB234  -->  Periph #1

	sw  x19,   8(x29)   # 0xDDEEFead  -->  SRAM
	sw  x20, -12(x30)   # 0x01234000  -->  Periph #0
	sw  x21,  -8(x31)   # 0x89ABCbcd  -->  Periph #1

	sw  x22,  12(x29)   # 0xFEDCBbad  -->  SRAM
	sw  x23,  16(x30)   # 0x76543000  -->  Periph #0  --> not writable
	sw  x24, -12(x31)   # 0x00FFEfff  -->  Periph #1

	sw  x25,  16(x29)   # 0xCCBBA111  -->  SRAM
	sw  x26, -16(x30)   # 0x88776334  -->  Periph #0
	sw  x27, -16(x31)   # 0x44332555  -->  Periph #1

	lw   x0, -16(x31)

	#-------------------------------------------------
	# TRY SOME MISALINGED ADDRESS ACCESSES
	#-------------------------------------------------

	li  x25, 0x32435465
	sw  x25, 0(x29)   # SRAM  (offset 0 - aligned)


	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------
    
end_of_test:
	nop
    j end_of_test   # infinite loop


