#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_csrrc
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSRRC
#----------------------------------------------------------------------------

.section .text
.global main

# CSR address (custom)
.equ MYCSR, 0x7C0

main:

	#-------------------------------------------------
	# WRITE SOME VALUES IN THE REGISTERS
	#-------------------------------------------------
 
	li  x1,  0x00000000
 	li  x2,  0x00000000
 	li  x3,  0x00000000
 	li  x4,  0x00000000
	li  x5,  0x00000000
	li  x6,  0x00000000
	li  x7,  0x00000000
	li  x8,  0x00000000
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
	li  x29, 0x00000000
	li  x30, 0x00000000
	li  x31, 0xFFFFFFFF

	#-------------------------------------------------
	# INITIALIZE CSR REGISTERS TO 0xFFFFFFFF
	#-------------------------------------------------

    csrrw   x0, MYCSR, x31

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
    csrrc   x11, MYCSR, x10

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

    csrrc   x10, MYCSR, x0   # Try writing reading set value from X0, the write is disabled (visual inspection only)

end_of_test:
	nop
    j end_of_test   # infinite loop


# -------------------------------------------
# Test patterns
patterns:
    .word 0x800A5001    # 0x7FF5AFFE
    .word 0x10052008    # 0x6FF08FF6
    .word 0x02400930    # 0x6DB086C6
    .word 0x28138481    # 0x45A00246
    .word 0x00834000    # 0x45200246
    .word 0x45200246    # 0x00000000
patterns_end:

# -------------------------------------------
# Results buffer (enough space)
    .section .bss
results:
    .space 12 * 6   # 6 patterns, each with 3 words (index, old, new)
