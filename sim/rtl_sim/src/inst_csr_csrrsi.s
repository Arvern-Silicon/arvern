#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_csrrsi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSRRSI
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

    csrrsi   x1,  MYCSR0, 0x03
    csrrsi   x2,  MYCSR1, 0x17
    csrrsi   x3,  MYCSR2, 0x0C
    csrrsi   x4,  MYCSR3, 0x06
    csrrsi   x5,  MYCSR4, 0x12
    csrrsi   x6,  MYCSR5, 0x18
    csrrsi   x7,  MYCSR6, 0x01
    csrrsi   x8,  MYCSR7, 0x14

    csrrsi   x11, MYCSR0, 0x08     # 0x0B
    csrrsi   x12, MYCSR1, 0x19     # 0x1F
    csrrsi   x13, MYCSR2, 0x12     # 0x1E
    csrrsi   x14, MYCSR3, 0x15     # 0x17
    csrrsi   x15, MYCSR4, 0x14     # 0x16
    csrrsi   x16, MYCSR5, 0x01     # 0x19
    csrrsi   x17, MYCSR6, 0x09     # 0x09
    csrrsi   x18, MYCSR7, 0x01     # 0x15

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

    csrrsi   x9, MYCSR0, 0   # Try writing immediate 0 to make sure the write is disabled (visual inspection only)

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
