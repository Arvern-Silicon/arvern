#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_lw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: LW
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
 
	lw  x17,  -16(x29)   # 0x12345DDD  <--  SRAM_0
	lw  x4,    -4(x30)   # 0x99999CCB  <--  Periph0_IN11
	lw  x22,    0(x31)   # 0x89ABCbcd  <--  Periph1_IN12

	lw  x16,  -12(x29)   # 0xdeadbFFF  <--  SRAM_1
	lw  x8,    12(x30)   # 0x11223024  <--  Periph0_IN15
	lw  x23,    4(x31)   # 0xFEDCBbad  <--  Periph1_IN13

	lw  x15,   -8(x29)   # 0x10000112  <--  SRAM_2
	lw  x6,     4(x30)   # 0xDDDDD443  <--  Periph0_IN13
	lw  x25,   12(x31)   # 0x00FFEfff  <--  Periph1_IN15

	lw  x14,   -4(x29)   # 0xabcd1556  <--  SRAM_3
	lw  x1,   -16(x30)   # 0x33344FED  <--  Periph0_IN8
	lw  x19,  -12(x31)   # 0x99AAB234  <--  Periph1_IN9

	lw  x13,    0(x29)   # 0x0bad099A  <--  SRAM_4
	lw  x7,     8(x30)   # 0xFFF00135  <--  Periph0_IN14
	lw  x18,  -16(x31)   # 0x55667451  <--  Periph1_IN8

	lw  x12,    4(x29)   # 0x0000fDDE  <--  SRAM_5
	lw  x3,    -8(x30)   # 0x7778800F  <--  Periph0_IN10
	lw  x24,    8(x31)   # 0x76543012  <--  Periph1_IN14

	lw  x11,    8(x29)   # 0xffff0012  <--  SRAM_6
	lw  x5,     0(x30)   # 0xBBBCC887  <--  Periph0_IN12
	lw  x21,   -4(x31)   # 0x01234021  <--  Periph1_IN11

	lw  x10,   12(x29)   # 0x1111189A  <--  SRAM_7
	lw  x2,   -12(x30)   # 0x55555765  <--  Periph0_IN9
	lw  x20,   -8(x31)   # 0xDDEEFead  <--  Periph1_IN10


	#-------------------------------------------------
	# CHECK REGISTERS
	#-------------------------------------------------
	nop
	lw  x30, 0(x29)      # 0x0bad099A <--  SRAM_4
	sw  x30, 0(x29)
	nop

	#-------------------------------------------------
	# RE-INITIALIZE FOR MORE CHECKS
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
	li  x30, 0x10040010
	li  x31, 0x10041030

	# Store some data in the SRAM
	sw  x1,  -16(x29)   # 0x12345DDD  -->  SRAM_0
	sw  x2,  -12(x29)   # 0xdeadbFFF  -->  SRAM_1
	sw  x3,   -8(x29)   # 0x10000112  -->  SRAM_2
	sw  x4,   -4(x29)   # 0xabcd1556  -->  SRAM_3
	sw  x5,    0(x29)   # 0x0bad099A  -->  SRAM_4
	sw  x6,    4(x29)   # 0x0000fDDE  -->  SRAM_5
	sw  x7,    8(x29)   # 0xffff0012  -->  SRAM_6
	sw  x8,   12(x29)   # 0x1111189A  -->  SRAM_7

	nop
	nop

	#-------------------------------------------------
	# TRY TO TRICK THE PIPELINE
	#-------------------------------------------------

	# Do a load and immediately consume the result
	# (the design should then stall the pipeline until the load is complete)
 	lw  x10,   12(x29)      # 0x1111189A  <--  SRAM_7
    add x11, x10, x0 
	nop
	nop

	# Back to back load-store with dependency on RS2 (i.e. the data)
 	lw  x12,    4(x31)      # 0xFEDCBbad  <--  Periph1_IN13
	sw  x12,   12(x29)      # 0xFEDCBbad  -->  SRAM_7         <--- this store uses RS2 from earlier load
 	lw  x13,   12(x29)      # 0xFEDCBbad  <--  SRAM_7
	nop
	nop

	# Back to back load-store with dependency on RS1 (i.e. the address)
	sw  x30,    4(x29)      # 0x10040010  -->  SRAM_5          <--- we put the address of the Periph0 in SRAM
 	lw  x14,    4(x29)      # 0x10040010  <--  SRAM_5          <--- we retreive the address and put it in x14
	sw  x5,     0(x14)      # 0x0bad099A  -->  Periph0         <--- immediately use RS1 from earlier load
 	lw  x15,    0(x14)      # 0x0bad099A  <--  Periph0
	nop
	nop

	# Back to back load-load with dependency on RS1 (i.e. the address)
	sw  x30,    4(x29)      # 0x10040010  -->  SRAM_5          <--- we put the address of the Periph0 in SRAM
 	lw  x16,    4(x29)      # 0x10040010  <--  SRAM_5          <--- we retreive the address and put it in x14
 	lw  x17,    0(x16)      # 0x0bad099A  <--  Periph0         <--- immediately use RS1 from earlier load
	nop
	nop

	nop
	nop

	#-------------------------------------------------
	# TRY SOME ALIGNED ADDRESS ACCESSES
	#-------------------------------------------------

	lw  x9,  0(x29)   # 0x0bad099A  <--  SRAM_4

	lw  x30, 0(x29)   # 0x0bad099A  <--  SRAM_4 (sync with testbench)
	nop

	#-------------------------------------------------
	# WAW HAZARD TESTS
	#-------------------------------------------------
	# These test patterns create Write-After-Write conflicts
	# where an ALU/CSR instruction writes to the same register
	# as a pending load. Under random SRAM wait states the load
	# write-back can be delayed, so the hardware must suppress
	# the stale load result to keep the newer ALU value.
	#
	# Uses x18-x26 (callee-saved) to avoid conflicts with
	# earlier test phases that use x1-x17.

	# Store known data to SRAM using x28 as temp (x29 = 0x80000010)
	li  x28, 0xAAAAAAAA
	sw  x28, 0(x29)           # SRAM_4 = 0xAAAAAAAA
	li  x28, 0xBBBBBBBB
	sw  x28, 4(x29)           # SRAM_5 = 0xBBBBBBBB
	li  x28, 0xCCCCCCCC
	sw  x28, 8(x29)           # SRAM_6 = 0xCCCCCCCC
	nop
	nop

	# --- Test 1: LW then LI to same register (ALU WAW) ---
	# Load x18 from SRAM, then immediately overwrite with LI.
	# Without WAW protection, delayed load could overwrite the LI value.
	lw   x18, 0(x29)          # x18 <- 0xAAAAAAAA (may be delayed)
	li   x18, 0x11111111      # x18 <- 0x11111111 (must win)
	nop
	nop

	# --- Test 2: LW then ADD to same register (ALU WAW) ---
	li   x20, 0x22220000
	li   x21, 0x00002222
	lw   x19, 4(x29)          # x19 <- 0xBBBBBBBB (may be delayed)
	add  x19, x20, x21        # x19 <- 0x22222222 (must win)
	nop
	nop

	# --- Test 3: LW then CSRR to same register (CSR WAW) ---
	lw   x22, 8(x29)          # x22 <- 0xCCCCCCCC (may be delayed)
	csrr x22, mhartid         # x22 <- mhartid value (must win)
	nop
	nop

	# --- Test 4: Back-to-back WAW conflicts on different registers ---
	lw   x23, 0(x29)          # x23 <- 0xAAAAAAAA (may be delayed)
	li   x23, 0x33333333      # x23 <- 0x33333333 (must win)
	lw   x24, 4(x29)          # x24 <- 0xBBBBBBBB (may be delayed)
	li   x24, 0x44444444      # x24 <- 0x44444444 (must win)
	nop
	nop

	# --- Test 5: LW followed by two ALU ops to same register ---
	lw   x25, 0(x29)          # x25 <- 0xAAAAAAAA (may be delayed)
	li   x25, 0x55550000      # x25 <- 0x55550000 (newer write)
	addi x25, x25, 0x555      # x25 <- 0x55550555 (must be final value)
	nop
	nop

	# --- Test 6: LW with NO conflict (sanity check) ---
	lw   x26, 8(x29)          # x26 <- 0xCCCCCCCC
	nop
	nop
	nop

	# Signal WAW phase done
	li   x31, 0x0A0A0A0A

	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------

	lw  x30,  0(x29)   # 0xAAAAAAAA  <--  SRAM_4


end_of_test:
	nop
    j end_of_test   # infinite loop


