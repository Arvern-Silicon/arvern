#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_bltu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BLTU
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
	li  x24, 0x00000000
	li  x25, 0x00000000
	li  x26, 0x00000000
	li  x27, 0x00000000
	li  x28, 0x00000000
	li  x29, 0x00000000
	li  x30, 0xFFFFFFFF
	li  x31, 0xFFFFFFFF


    #-------------------------------------------------------
    # Test 1: Unsigned 5 < 10 → taken
    #-------------------------------------------------------
    li   x2, 5
    li   x3, 10
    bltu x2, x3, L1
    addi x10, x10, 1      # skipped
L1: addi x11, x11, 1      # executed → 1

    #-------------------------------------------------------
    # Test 2: Unsigned 10 < 5 → not taken
    #-------------------------------------------------------
    li   x2, 10
    li   x3, 5
    bltu x2, x3, L2
    addi x12, x12, 1      # executed → 1
L2: addi x13, x13, 1      # executed → 1

    #-------------------------------------------------------
    # Test 3: Unsigned 0xFFFFFFFF < 5 → not taken
    #-------------------------------------------------------
    li   x2, -1           # 0xFFFFFFFF
    li   x3, 5
    bltu x2, x3, L3
    addi x14, x14, 1      # executed → 1
L3: addi x15, x15, 1      # executed → 1

    #-------------------------------------------------------
    # Test 4: Unsigned 5 < 0xFFFFFFFF → taken
    #-------------------------------------------------------
    li   x2, 5
    li   x3, -1           # 0xFFFFFFFF
    bltu x2, x3, L4
    addi x16, x16, 1      # skipped
L4: addi x17, x17, 1      # executed → 1

    #-------------------------------------------------------
    # Test 5: Equal values (5 < 5 → not taken)
    #-------------------------------------------------------
    li   x2, 5
    li   x3, 5
    bltu x2, x3, L5
    addi x18, x18, 1      # executed → 1
L5: addi x19, x19, 1      # executed → 1

    #-------------------------------------------------------
    # Test 6: Hazard – Branch right after ALU write
    # x4 = 29 + 5 = 34, x5 = 30 → (34>30 → not taken)
    #-------------------------------------------------------
    li   x4, 29
    li   x5, 30
    addi x4, x4, 5
    bltu x4, x5, L6
    addi x20, x20, 1      # executed → 1
L6: addi x21, x21, 1      # executed → 1

    #-------------------------------------------------------
    # Test 7: Hazard – Branch right after LOAD (different reg)
    # x6 = 0xFF, x7 = 0x100 → (0xFF<0x100 → taken)
    #-------------------------------------------------------
    li   x8,  0x80000000
    li   x7,  0x00000100
    li   x9,  0x000000FF
    sw   x9,  0(x8)
    lw   x6,  0(x8)
    bltu x6, x7, L7
    addi x22, x22, 1      # skipped
L7: addi x23, x23, 1      # executed → 1

    #-------------------------------------------------------
    # Test 8: Hazard – Branch right after LOAD (same reg)
    # x9 = 0xFF, x7 = 0xFF → equal → not taken
    #-------------------------------------------------------
    li   x7,  0x000000FF
    li   x9,  0
    sw   x7,  0(x8)
    lw   x9,  0(x8)
    bltu x9, x7, L8
    addi x24, x24, 1      # executed → 1
L8: addi x25, x25, 1      # executed → 1

    #-------------------------------------------------------
    # Test 9: Backward loop (unsigned count)
    #-------------------------------------------------------
    li   x1, 0
    li   x3, 5
Loop:
    addi x1, x1, 1
    bltu x1, x3, Loop     # loop while x1 < 5
    add  x26, x26, x1     # after loop → 5

    #-------------------------------------------------------
    # Test 10: Branch chain
    # x7 = 5, x8 = 5 → not taken
    # x7 = 5, x9 = 10 → taken
    #-------------------------------------------------------
    li   x7, 5
    li   x8, 5
    li   x9, 10
    bltu x7, x8, L9
    addi x27, x27, 1      # executed → 1
L9: bltu x7, x9, L10
    addi x28, x28, 1      # skipped
L10:addi x29, x29, 1      # executed → 1


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop
