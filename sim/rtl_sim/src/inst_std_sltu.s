#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_sltu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SLTU
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
    # 1. Equal numbers (unsigned) → 0
    #---------------------------------------------------
    li    x1, 5
    li    x2, 5
    sltu  x3, x1, x2         # expect 0

    #---------------------------------------------------
    # 2. Small < large (unsigned) → 1
    #---------------------------------------------------
    li    x4, 1
    li    x5, 2
    sltu  x6, x4, x5         # expect 1

    #---------------------------------------------------
    # 3. Large > small (unsigned) → 0
    #---------------------------------------------------
    li    x7, 10
    li    x8, 3
    sltu  x9, x7, x8         # expect 0

    #---------------------------------------------------
    # 4. Negative vs positive (unsigned: 0xFFFFFFFF > 1)
    #---------------------------------------------------
    li    x10, -1            # 0xFFFFFFFF
    li    x11, 1
    sltu  x12, x10, x11      # expect 0 (FFFFFFFF > 1)

    #---------------------------------------------------
    # 5. Positive vs negative (unsigned: 1 < 0xFFFFFFFF)
    #---------------------------------------------------
    li    x13, 1
    li    x14, -1            # 0xFFFFFFFF
    sltu  x15, x13, x14      # expect 1

    #---------------------------------------------------
    # 6. Edge: 0 < 0x80000000 (unsigned) → 1
    #---------------------------------------------------
    li    x16, 0
    li    x17, 0x80000000
    sltu  x18, x16, x17      # expect 1

    #---------------------------------------------------
    # 7. Edge: 0x80000000 < 0xFFFFFFFF (unsigned) → 1
    #---------------------------------------------------
    li    x19, 0x80000000
    li    x20, 0xFFFFFFFF
    sltu  x21, x19, x20      # expect 1

    #---------------------------------------------------
    # 8. Edge: 0xFFFFFFFF < 0x80000000? (unsigned) → 0
    #---------------------------------------------------
    li    x22, 0xFFFFFFFF
    li    x23, 0x80000000
    sltu  x24, x22, x23      # expect 0

    #---------------------------------------------------
    # 9. Equal big numbers (0xFFFFFFFF vs 0xFFFFFFFF) → 0
    #---------------------------------------------------
    li    x25, 0xFFFFFFFF
    li    x26, 0xFFFFFFFF
    sltu  x27, x25, x26      # expect 0

    #---------------------------------------------------
    # 10. Small vs small (2 < 3) → 1
    #---------------------------------------------------
    li    x28, 2
    li    x29, 3
    sltu  x30, x28, x29      # expect 1

    #---------------------------------------------------
    # 11. Big vs small (0xFFFFFFFF < 3?) → 0
    #---------------------------------------------------
    li    x31, 0xFFFFFFFF
    li    x1,  3
    sltu  x2,  x31, x1       # expect 0

    #---------------------------------------------------
    # 12. Small vs big (3 < 0xFFFFFFFF) → 1
    #---------------------------------------------------
    li    x3, 3
    li    x4, 0xFFFFFFFF
    sltu  x5, x3, x4         # expect 1


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


