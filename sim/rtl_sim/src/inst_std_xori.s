#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_xori
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: XORI
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
    # 1. XOR with 0 (should return original value)
    #------------------------------------------------
    li    x1, 0x12345678
    xori  x2, x1, 0        # expect x2 = 0x12345678

    #------------------------------------------------
    # 2. XOR with all 1s (-1) (bitwise NOT)
    #------------------------------------------------
    li    x1, 0x12345678
    xori  x3, x1, -1       # expect x3 = ~0x12345678 = 0xEDCBA987

    #------------------------------------------------
    # 3. XOR with some mask (0xFF)
    #------------------------------------------------
    li    x1, 0x12345600
    xori  x4, x1, 0xFF     # expect x4 = 0x123456FF

    #------------------------------------------------
    # 4. XOR with itself (should be zero)
    #------------------------------------------------

    li    x6, 0xABCD1234
    xori  x7, x6, 0          # check original. expect x7 = 0xABCD1234
    xori  x8, x6, -1         # just another pattern test.   expect x8 = 0x5432EDCB

    #------------------------------------------------
    # 5. Negative value XOR with small immediate
    #------------------------------------------------
    li    x1, -1             # 0xFFFFFFFF
    xori  x9, x1, 1          # expect 0xFFFFFFFE

    #------------------------------------------------
    # 6. Zero value XOR with non-zero immediate
    #------------------------------------------------
    li    x1, 0xFEDCBA98
    xori  x10, x1, -1366     # 0xFEDCBA98 ^ 0xFFFFFAAA; expect x10 = 0x01234032


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


