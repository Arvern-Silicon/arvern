#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_sra
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SRA
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

    #---------------------------------------------------
    # 1. SRA by 0 (no change)
    #---------------------------------------------------
    li    x1,  0x12345678
    li    x2,  0
    sra   x3,  x1, x2        # expect 0x12345678

    #---------------------------------------------------
    # 2. Positive value SRA by 4 (same as SRL)
    #---------------------------------------------------
    li    x4,  0x12345678
    li    x5,  4
    sra   x6,  x4, x5        # expect 0x01234567

    #---------------------------------------------------
    # 3. Negative number (-1) SRA by 1 (sign extend)
    #---------------------------------------------------
    li    x7,  -1            # 0xFFFFFFFF
    li    x8,  1
    sra   x9,  x7, x8        # expect 0xFFFFFFFF

    #---------------------------------------------------
    # 4. Negative number (-2) SRA by 1
    #---------------------------------------------------
    li    x10, -2            # 0xFFFFFFFE
    li    x11, 1
    sra   x12, x10, x11      # expect 0xFFFFFFFF (arithmetic fill)

    #---------------------------------------------------
    # 5. Negative number (-8) SRA by 2
    #---------------------------------------------------
    li    x13, -8            # 0xFFFFFFF8
    li    x14, 2
    sra   x15, x13, x14      # expect 0xFFFFFFFE (rounds toward -1)

    #---------------------------------------------------
    # 6. 0x80000000 (most negative) SRA by 1
    #---------------------------------------------------
    li    x16, 0x80000000
    li    x17, 1
    sra   x18, x16, x17      # expect 0xC0000000 (sign extend)

    #---------------------------------------------------
    # 7. 0x80000000 SRA by 31 (edge)
    #---------------------------------------------------
    li    x19, 0x80000000
    li    x20, 31
    sra   x21, x19, x20      # expect 0xFFFFFFFF (all bits 1)

    #---------------------------------------------------
    # 8. Positive random value shift by 12
    #---------------------------------------------------
    li    x22, 0x12345678
    li    x23, 12
    sra   x24, x22, x23      # expect 0x00012345

    #---------------------------------------------------
    # 9. Negative random value shift by 12
    #---------------------------------------------------
    li    x25, -305419896    # -0x12345678 = 0xEDCBA988
    li    x26, 12
    sra   x27, x25, x26      # expect 0xFFFEDCBA (sign extended)

	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


