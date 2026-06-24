#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_andi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ANDI
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
	li  x10, 0xFFFFFFFF
	li  x11, 0xFFFFFFFF
	li  x12, 0xFFFFFFFF
	li  x13, 0xFFFFFFFF
	li  x14, 0xFFFFFFFF
	li  x15, 0xFFFFFFFF
	li  x16, 0xFFFFFFFF
	li  x17, 0xFFFFFFFF
	li  x18, 0xFFFFFFFF
	li  x19, 0xFFFFFFFF
	li  x20, 0xFFFFFFFF
	li  x21, 0xFFFFFFFF
	li  x22, 0xFFFFFFFF
	li  x23, 0xFFFFFFFF
	li  x24, 0xFFFFFFFF
	li  x25, 0xFFFFFFFF
	li  x26, 0xFFFFFFFF
	li  x27, 0xFFFFFFFF
	li  x28, 0xFFFFFFFF
	li  x29, 0xFFFFFFFF
	li  x30, 0xFFFFFFFF
	li  x31, 0xFFFFFFFF

    #------------------------------------------------
    # 1. AND with 0 (result always 0)
    #------------------------------------------------
    li    x1, 0x12345678
    andi  x2, x1, 0          # expect 0x00000000

    #------------------------------------------------
    # 2. AND with -1 (all bits unchanged)
    # (-1 is encoded as imm = 0xFFF)
    #------------------------------------------------
    li    x1, 0x12345678
    andi  x3, x1, -1         # expect 0x12345678

    #------------------------------------------------
    # 3. AND with small positive mask (0x7F)
    #------------------------------------------------
    li    x1, 0x12345678
    andi  x4, x1, 0x7F       # expect 0x00000078

    #------------------------------------------------
    # 4. AND with negative small immediate (-1366 = 0xFFFFFAAA)
    #------------------------------------------------
    li    x1, 0x00000FFF
    andi  x5, x1, -1366      # expect 0x00000AAA (0x0FFF & 0xFFFFFAAA)

    #------------------------------------------------
    # 5. Zero register AND with any immediate (always 0)
    #------------------------------------------------
    li    x1, 0
    andi  x6, x1, 0x123      # expect 0x00000000


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


