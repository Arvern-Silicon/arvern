#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_lhu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: LHU
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
	li  x9,  0x00000000
	li  x10, 0x00000000
	li  x11, 0x00000000
	li  x12, 0x00000000
	li  x13, 0x00000000
	li  x14, 0x00000000
	li  x15, 0x00000000
	li  x16, 0x00000000
	li  x17, 0x00000000
	li  x18, 0x00000000
	li  x19, 0x00000000
	li  x20, 0x00000000
	li  x21, 0x00000000
	li  x22, 0x00000000
	li  x23, 0x00000000
	li  x24, 0x00000000
	li  x25, 0x00000000
	li  x26, 0x00000000
	li  x27, 0x00000000
	li  x28, 0x00000000

	# Prepare target pointers to SRAM, Periph #0 and Periph #1
	li  x29, 0x80000010
	li  x30, 0x10040030
	li  x31, 0x10041030

	#-------------------------------------------------
	# STORE SOME DATA IN THE SRAM
	#-------------------------------------------------
 
	sw  x1,  -16(x29)   # 0x12345DDD  -->  SRAM_0
	sw  x2,  -12(x29)   # 0xdeadbFFF  -->  SRAM_1
	sw  x3,   -8(x29)   # 0x10000112  -->  SRAM_2
	sw  x4,   -4(x29)   # 0xabcd1556  -->  SRAM_3
	sw  x5,    0(x29)   # 0x0bad099A  -->  SRAM_4
	sw  x6,    4(x29)   # 0x0000fDDE  -->  SRAM_5
	sw  x7,    8(x29)   # 0xffff0012  -->  SRAM_6
	sw  x8,   12(x29)   # 0x1111189A  -->  SRAM_7

	#-------------------------------------------------
	# LOAD SOME DATA 
	#-------------------------------------------------
 
	lhu x17,  -16(x29)   # 0x5DDD  -->  SRAM_0
	lhu x4,    -4(x30)   # 0x9CCB  -->  Periph0_IN11
	lhu x22,    0(x31)   # 0xCbcd  -->  Periph1_IN12

	lhu x16,  -12(x29)   # 0xbFFF  -->  SRAM_1
	lhu x8,    12(x30)   # 0x3024  -->  Periph0_IN15
	lhu x23,    4(x31)   # 0xBbad  -->  Periph1_IN13

	lhu x15,   -8(x29)   # 0x0112  -->  SRAM_2
	lhu x6,     4(x30)   # 0xD443  -->  Periph0_IN13
	lhu x25,   12(x31)   # 0xEfff  -->  Periph1_IN15

	lhu x14,   -4(x29)   # 0x1556  -->  SRAM_3
	lhu x1,   -16(x30)   # 0x4FED  -->  Periph0_IN8
	lhu x19,  -12(x31)   # 0xB234  -->  Periph1_IN9

	lhu x13,    0(x29)   # 0x099A  -->  SRAM_4
	lhu x7,     8(x30)   # 0x0135  -->  Periph0_IN14
	lhu x18,  -16(x31)   # 0x7451  -->  Periph1_IN8

	lhu x12,    4(x29)   # 0xfDDE  -->  SRAM_5
	lhu x3,    -8(x30)   # 0x800F  -->  Periph0_IN10
	lhu x24,    8(x31)   # 0x3012  -->  Periph1_IN14

	lhu x11,    8(x29)   # 0x0012  -->  SRAM_6
	lhu x5,     0(x30)   # 0xC887  -->  Periph0_IN12
	lhu x21,   -4(x31)   # 0x4021  -->  Periph1_IN11

	lhu x10,   12(x29)   # 0x189A  -->  SRAM_7
	lhu x2,   -12(x30)   # 0x5765  -->  Periph0_IN9
	lhu x20,   -8(x31)   # 0xFead  -->  Periph1_IN10



	#-------------------------------------------------
	# TRY SOME MISALINGED ADDRESS ACCESSES
	#-------------------------------------------------

	lhu x9,  0(x29)   # 0x099A  -->  SRAM_4  -->  pass
	lhu x27, 2(x29)   # 0x0bad  -->  SRAM_4  -->  pass

	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------

	lhu x30,  0(x29)   # 0x0bad099A  -->  SRAM_4


end_of_test:
	nop
    j end_of_test   # infinite loop


