#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_sltiu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SLTIU
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    .section .text
    .globl  _start
_start:

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
    # 1. Positive < Positive  (expect 1)
    #------------------------------------------------
    li    x1, 5
    sltiu x2, x1, 10       # 5 < 10 (unsigned) -> x2 = 1

    #------------------------------------------------
    # 2. Positive == Positive (expect 0)
    #------------------------------------------------
    li    x1, 5
    sltiu x3, x1, 5        # 5 < 5 (unsigned) -> x3 = 0

    #------------------------------------------------
    # 3. Positive > Positive  (expect 0)
    #------------------------------------------------
    li    x1, 10
    sltiu x4, x1, 5        # 10 < 5 (unsigned) -> x4 = 0

    #------------------------------------------------
    # 4. Negative value vs positive immediate
    #------------------------------------------------
    # In unsigned comparison, negative values are very big (e.g., 0xFFFFFFFF)
    # So 0xFFFFFFFF < 10 (unsigned)? -> false
    li    x1, -1           # 0xFFFFFFFF
    sltiu x5, x1, 10       # expect 0

    #------------------------------------------------
    # 5. Positive value vs 0 immediate
    #------------------------------------------------
    li    x1, 1
    sltiu x6, x1, 0        # 1 < 0 (unsigned)? -> false (x6 = 0)

    #------------------------------------------------
    # 6. Zero vs positive immediate (expect 1)
    #------------------------------------------------
    li    x1, 0
    sltiu x7, x1, 5        # 0 < 5 -> x7 = 1

    #------------------------------------------------
    # 7. Edge immediate 2047 (max immediate) with small value
    #------------------------------------------------
    li    x1, 1000
    sltiu x8, x1, 2047     # 1000 < 2047 -> x8 = 1

    #------------------------------------------------
    # 8. Edge immediate 0 with negative register value (huge unsigned)
    #------------------------------------------------
    li    x1, -1           # 0xFFFFFFFF
    sltiu x9, x1, 0        # 0xFFFFFFFF < 0 -> false -> x9 = 0

    #------------------------------------------------
    # 9. Edge immediate 0 with zero register value (expect 0)
    #------------------------------------------------
    li    x1, 0
    sltiu x10, x1, 0       # 0 < 0 -> x10 = 0


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef


end_of_test:
	nop
    j end_of_test   # infinite loop


