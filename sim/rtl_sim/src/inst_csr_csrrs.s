#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_csrrs
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSRRS
#----------------------------------------------------------------------------

.section .text
.global main

# CSR address (custom)
.equ MYCSR, 0x7C0

main:

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

	#-------------------------------------------------
	# TEST CSR INSTRUCTION
	#-------------------------------------------------

    la      x1,  results                  # x1 points to memory where we log results
    la      x20, results                  #

    la      x2,  patterns_end
    la      x3,  patterns
    sub     x4,  x2, x3
    srli    x4,  x4, 2                    # number of patterns / 4 bytes
 
    li      x5,  0                        # pattern index
loop_patterns:
    # Load test pattern
    lw      x10, 0(x3)                    # load pattern
    addi    x3,  x3, 4

    # CSRRW: write x10 to MYCSR, old value -> x11
    csrrs   x11, MYCSR, x10

    # Read CSR back
    csrr    x12, MYCSR

    # Save results: reference pattern, old_value, new_read
    sw      x10, 0(x1)
    sw      x11, 4(x1)
    sw      x12, 8(x1)
    addi    x1,  x1, 12

    # Decrement pattern index
    addi    x4, x4, -1
    bne     x4, x0, loop_patterns


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

	lw  x23,    8(x1)   # Load something to make sure earlier SW transfer is done

 	li  x31,  0xdeadbeef

    csrrs   x10, MYCSR, x0   # Try writing reading set value from X0, the write is disabled (visual inspection only)

end_of_test:
	nop
    j end_of_test   # infinite loop


# -------------------------------------------
# Test patterns
patterns:
    .word 0x800A5001    # 800A5001
    .word 0x10052008    # 900F7009
    .word 0x02400930    # 924F7939  
    .word 0x28138481    # BA5FFDB9
    .word 0x00834000    # BADFFDB9
    .word 0x45200246    # FFFFFFFF
patterns_end:

# -------------------------------------------
# Results buffer (enough space)
    .section .bss
results:
    .space 12 * 6   # 6 patterns, each with 3 words (index, old, new)
