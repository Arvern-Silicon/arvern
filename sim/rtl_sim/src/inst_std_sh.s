#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_sh
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SH
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
	sh  x1,  -16(x29)   #        0x5DDD  -->  SRAM
	sh  x2,    0(x30)   #        0xbFFF  -->  Periph #0
	sh  x3,   16(x31)   #        0x0112  -->  Periph #1  --> not writable

	sh  x4,  -14(x29)   # 0x1556         -->  SRAM
	sh  x5,    2(x30)   # 0x099A         -->  Periph #0
	sh  x6,   14(x31)   # 0xfDDE         -->  Periph #1

	sh  x7,  -12(x29)   #        0x0012  -->  SRAM
	sh  x8,   -2(x30)   #        0x189A  -->  Periph #0
	sh  x9,   12(x31)   #        0x4FED  -->  Periph #1

	sh  x10, -10(x29)   # 0x5765         -->  SRAM
	sh  x11,   4(x30)   # 0x800F         -->  Periph #0
	sh  x12,  10(x31)   # 0x9CCB         -->  Periph #1

	sh  x13,  -8(x29)   #        0xC887  -->  SRAM
	sh  x14,  -4(x30)   #        0xD443  -->  Periph #0
	sh  x15,   8(x31)   #        0x0135  -->  Periph #1

	sh  x16,  -6(x29)   # 0x3024         -->  SRAM
	sh  x17,   6(x30)   # 0x7451         -->  Periph #0
	sh  x18,   6(x31)   # 0xB234         -->  Periph #1

	sh  x19,  -4(x29)   #        0xFead  -->  SRAM
	sh  x20,  -6(x30)   #        0x4000  -->  Periph #0
	sh  x21,   4(x31)   #        0xCbcd  -->  Periph #1

	sh  x22,  -2(x29)   # 0xBbad         -->  SRAM
	sh  x23,   8(x30)   # 0x3000         -->  Periph #0
	sh  x24,   2(x31)   # 0xEfff         -->  Periph #1

	sh  x25,   0(x29)   #        0xA111  -->  SRAM
	sh  x26,  -8(x30)   #        0x6334  -->  Periph #0
	sh  x27,   0(x31)   #        0x2555  -->  Periph #1

	lw   x0,   0(x31)

	#-------------------------------------------------
	# TRY SOME MISALINGED ADDRESS ACCESSES
	#-------------------------------------------------

	li  x25, 0x32435465
	sh  x25, 0(x29)   # SRAM  (offset 0 - aligned)

	li  x27, 0x25364758
	sh  x27, 2(x29)   # SRAM  (offset 2 - aligned)


	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------
    
end_of_test:
	nop
    j end_of_test   # infinite loop


