#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_bne
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BNE
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
	li  x24, 0xFFFFFFFF
	li  x25, 0xFFFFFFFF
	li  x26, 0xFFFFFFFF
	li  x27, 0xFFFFFFFF
	li  x28, 0xFFFFFFFF
	li  x29, 0xFFFFFFFF
	li  x30, 0xFFFFFFFF
	li  x31, 0xFFFFFFFF


#-------------------------------------------------------
# Test 1: Branch not taken (x2 == x3)
#-------------------------------------------------------
    li   x2,  5
    li   x3,  5
    bne  x2,  x3,  L1
    addi x10, x10, 1      # executed → 1
L1: addi x11, x11, 1      # executed → 1

#-------------------------------------------------------
# Test 2: Branch taken (x2 != x4)
#-------------------------------------------------------
    li   x2,   5
    li   x4,  10
    bne  x2,  x4,  L2
    addi x12, x12, 1      # should be skipped
L2: addi x13, x13, 1      # executed → 1

#-------------------------------------------------------
# Test 3: Negative offset branch (jumping back)
#-------------------------------------------------------
    li   x1,  0           # loop counter
    li   x3,  5
Loop:
    addi x1,  x1,  1      # loop counter++
    bne  x1,  x3,  Loop   # loop while x1 != x3
L3: add  x14, x14, x1     # after loop → 5

#-------------------------------------------------------
# Test 4: Hazard – Branch right after ALU write
# (x5=20, x6=25 so x5!=x6 → branch taken)
#-------------------------------------------------------
    li   x5,  20
    li   x6,  20
    addi x6,  x6,  5      # ALU operation writing x6
    bne  x5,  x6,  L4     # branch uses just written x6 (taken)
    addi x15, x15, 1      # should be skipped
L4: addi x16, x16, 1      # executed → 1

#---------------------------------------------------------------------
# Test 5: Hazard – Branch right after LOAD write different registers
# (x9=0, x8=0xFF → not equal → branch taken)
#---------------------------------------------------------------------
    li   x6,  0x80000000
    li   x7,  0x000000FF
    sw   x7,  0(x6)       # 0x000000FF  -->  SRAM_0

    li   x8,  0x000000FF
    li   x9,  0x00000000

    lw   x5,  0(x6)       # LOAD value into x5 (different register)
    bne  x9,  x8,  L5     # branch uses x9,x8 (taken)
    addi x17, x17, 1      # should be skipped
L5: addi x18, x18, 1      # executed → 1

#---------------------------------------------------------------
# Test 6: Hazard – Branch right after LOAD write same register
# (x9 loaded = 0xFF, x8 = 0xFF → equal → branch not taken)
#---------------------------------------------------------------
    li   x6,  0x80000000
    li   x7,  0x000000FF
    sw   x7,  0(x6)

    li   x8,  0x000000FF
    li   x9,  0x00000000

    lw   x9,  0(x6)       # LOAD value into x9
    bne  x9,  x8,  L6     # branch not taken
    addi x19, x19, 1      # executed → 1
L6: addi x20, x20, 1      # executed → 1

#-------------------------------------------------------
# Test 7: Chain of branches (mix taken/not taken)
# (x7=7, x8=7 → equal → branch not taken)
# (x7=7, x9=9 → not equal → branch taken)
#-------------------------------------------------------
    li   x7,  7
    li   x8,  7
    li   x9,  9

    bne  x7,  x8,  L7
    addi x21, x21, 1      # executed (branch not taken) → 1
L7: bne  x7,  x9,  L8
    addi x22, x22, 1      # should be skipped (branch taken)
L8: addi x23, x23, 1      # executed → 1


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop
