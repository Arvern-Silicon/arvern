#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_csrrwi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSRRWI
#----------------------------------------------------------------------------

.section .text
.global main

# CSR address (custom)
.equ MYCSR0, 0x7C0
.equ MYCSR1, 0x7C1
.equ MYCSR2, 0x7C2
.equ MYCSR3, 0x7C3
.equ MYCSR4, 0x7C4
.equ MYCSR5, 0x7C5
.equ MYCSR6, 0x7C6
.equ MYCSR7, 0x7C7

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
	li  x10, 0x10042000
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

    csrrwi   x1,  MYCSR0,  3
    csrrwi   x2,  MYCSR1, 17
    csrrwi   x3,  MYCSR2, 31
    csrrwi   x4,  MYCSR3,  5
    csrrwi   x5,  MYCSR4, 12
    csrrwi   x6,  MYCSR5, 28
    csrrwi   x7,  MYCSR6,  1
    csrrwi   x8,  MYCSR7, 24

    csrrwi   x11, MYCSR0,  7
    csrrwi   x12, MYCSR1, 19
    csrrwi   x13, MYCSR2,  2
    csrrwi   x14, MYCSR3, 25
    csrrwi   x15, MYCSR4, 14
    csrrwi   x16, MYCSR5, 31
    csrrwi   x17, MYCSR6,  9
    csrrwi   x18, MYCSR7,  1

    csrr     x21, MYCSR0
    csrr     x22, MYCSR1
    csrr     x23, MYCSR2
    csrr     x24, MYCSR3
    csrr     x25, MYCSR4
    csrr     x26, MYCSR5
    csrr     x27, MYCSR6
    csrr     x28, MYCSR7

	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------

	lw  x9,    8(x10)   # Load something twice to make sure earlier SW transfer is done
	lw  x9,    8(x10)   #

 	li  x31,  0xdeadbeef

    csrrwi   x0, MYCSR0, 31   # Try writing old value to X0 to make sure the read is disabled (visual inspection only)

end_of_test:
	nop
    j end_of_test   # infinite loop


# -------------------------------------------
# Test patterns
patterns:
    .word 0xBADCAFFE
    .word 0x12345678
    .word 0xC0FFEBAD
    .word 0x9ABCDEF0
    .word 0x0000FFFF
    .word 0xFFFF0000
patterns_end:

# -------------------------------------------
# Results buffer (enough space)
    .section .bss
results:
    .space 12 * 6   # 6 patterns, each with 3 words (index, old, new)
