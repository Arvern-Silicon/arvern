#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_sb
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SB
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
	
	li  x19, 0xDDEEFeda
	li  x20, 0x01234021
	li  x21, 0x89ABCbcd
	
	li  x22, 0xFEDCBbad
	li  x23, 0x76543012
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
	sb  x1,  -16(x29)   #                     0xDD    -->  SRAM
	sb  x2,    0(x30)   #                     0xFF    -->  Periph #0
	sb  x3,   16(x31)   #   0x12                      -->  Periph #1  --> not writable

	sb  x4,  -15(x29)   #               0x56          -->  SRAM
	sb  x5,    1(x30)   #               0x9A          -->  Periph #0
	sb  x6,   15(x31)   #   0xDE                      -->  Periph #1

	sb  x7,  -14(x29)   #         0x12                -->  SRAM
	sb  x8,   -1(x30)   #         0x9A                -->  Periph #0
	sb  x9,   14(x31)   #         0xED                -->  Periph #1

	sb  x10, -13(x29)   #   0x65                      -->  SRAM
	sb  x11,   2(x30)   #         0x0F                -->  Periph #0
	sb  x12,  13(x31)   #               0xCB          -->  Periph #1

	sb  x13, -12(x29)   #                     0x87    -->  SRAM
	sb  x14,  -2(x30)   #               0x43          -->  Periph #0
	sb  x15,  12(x31)   #                     0x35    -->  Periph #1

	sb  x16, -11(x29)   #               0x24          -->  SRAM
	sb  x17,   3(x30)   #   0x51                      -->  Periph #0
	sb  x18,  11(x31)   #   0x34                      -->  Periph #1

	sb  x19, -10(x29)   #         0xda                -->  SRAM
	sb  x20,  -3(x30)   #                     0x21    -->  Periph #0
	sb  x21,  10(x31)   #         0xcd                -->  Periph #1

	sb  x22,  -9(x29)   #   0xad                      -->  SRAM
	sb  x23,   4(x30)   #   0x12                      -->  Periph #0
	sb  x24,   9(x31)   #               0xff          -->  Periph #1

	sb  x25,  -8(x29)   #   0x11                      -->  SRAM
	sb  x26,  -4(x30)   #                     0x34    -->  Periph #0
	sb  x27,   8(x31)   #                     0x55    -->  Periph #1

	lw   x0,   0(x31)

	#--------------------------------------------------------------
	# TRY SOME MISALINGED ADDRESS ACCESSES (NOT POSSIBLE WITH SB)
	#--------------------------------------------------------------

	li  x25, 0x32435465
	sb  x25, 0(x29)   # SRAM

	li  x26, 0x75645342
	sb  x26, 1(x29)   # SRAM

	li  x27, 0x25364758
	sb  x27, 2(x29)   # SRAM

	li  x28, 0x95847362
	sb  x28, 3(x29)   # SRAM


	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------
    
end_of_test:
	nop
    j end_of_test   # infinite loop


