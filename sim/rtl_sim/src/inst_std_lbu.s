#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_lbu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: LBU
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
 
	lbu x17,  -16(x29)   # 0xDD  -->  SRAM_0
	lbu x4,    -4(x30)   # 0xCB  -->  Periph0_IN11
	lbu x22,    0(x31)   # 0xcd  -->  Periph1_IN12

	lbu x16,  -12(x29)   # 0xFF  -->  SRAM_1
	lbu x8,    12(x30)   # 0x24  -->  Periph0_IN15
	lbu x23,    4(x31)   # 0xad  -->  Periph1_IN13

	lbu x15,   -8(x29)   # 0x12  -->  SRAM_2
	lbu x6,     4(x30)   # 0x43  -->  Periph0_IN13
	lbu x25,   12(x31)   # 0xff  -->  Periph1_IN15

	lbu x14,   -4(x29)   # 0x56  -->  SRAM_3
	lbu x1,   -16(x30)   # 0xED  -->  Periph0_IN8
	lbu x19,  -12(x31)   # 0x34  -->  Periph1_IN9

	lbu x13,    0(x29)   # 0x9A  -->  SRAM_4
	lbu x7,     8(x30)   # 0x35  -->  Periph0_IN14
	lbu x18,  -16(x31)   # 0x51  -->  Periph1_IN8

	lbu x12,    4(x29)   # 0xDE  -->  SRAM_5
	lbu x3,    -8(x30)   # 0x0F  -->  Periph0_IN10
	lbu x24,    8(x31)   # 0x12  -->  Periph1_IN14

	lbu x11,    8(x29)   # 0x12  -->  SRAM_6
	lbu x5,     0(x30)   # 0x87  -->  Periph0_IN12
	lbu x21,   -4(x31)   # 0x21  -->  Periph1_IN11

	lbu x10,   12(x29)   # 0x9A  -->  SRAM_7
	lbu x2,   -12(x30)   # 0x65  -->  Periph0_IN9
	lbu x20,   -8(x31)   # 0xad  -->  Periph1_IN10



	#-------------------------------------------------
	# LOAD BYTES FROM VARIOUS OFFSETS
	#-------------------------------------------------

	lbu x9,  0(x29)   # 0x9A  -->  SRAM_4
	lbu x26, 1(x29)   # 0x09  -->  SRAM_4
	lbu x27, 2(x29)   # 0xAD  -->  SRAM_4
	lbu x28, 3(x29)   # 0xBA  -->  SRAM_4

	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------

	lbu x30,  0(x29)   # 0x0bad099A  -->  SRAM_4


end_of_test:
	nop
    j end_of_test   # infinite loop


