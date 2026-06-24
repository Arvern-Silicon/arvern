#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_csrrci
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSRRCI
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

	li  x1,  0x00000000
 	li  x2,  0x00000000
 	li  x3,  0x00000000
 	li  x4,  0x00000000
	li  x5,  0x00000000
	li  x6,  0x00000000
	li  x7,  0x00000000
	li  x8,  0x00000000
	li  x9,  0x00000000
	li  x10, 0x10042000
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

    csrrw   x0, MYCSR0, x31
    csrrw   x0, MYCSR1, x31
    csrrw   x0, MYCSR2, x31
    csrrw   x0, MYCSR3, x31
    csrrw   x0, MYCSR4, x31
    csrrw   x0, MYCSR5, x31
    csrrw   x0, MYCSR6, x31
    csrrw   x0, MYCSR7, x31


	#-------------------------------------------------
	# TEST CSR INSTRUCTION
	#-------------------------------------------------

    csrrci   x1,  MYCSR0, 0x03     # 0xFC
    csrrci   x2,  MYCSR1, 0x17     # 0xE8
    csrrci   x3,  MYCSR2, 0x0C     # 0xF3
    csrrci   x4,  MYCSR3, 0x06     # 0xF9
    csrrci   x5,  MYCSR4, 0x12     # 0xED
    csrrci   x6,  MYCSR5, 0x18     # 0xE7
    csrrci   x7,  MYCSR6, 0x01     # 0xFE
    csrrci   x8,  MYCSR7, 0x14     # 0xEB

    csrrci   x11, MYCSR0, 0x08     # 0xF4
    csrrci   x12, MYCSR1, 0x19     # 0xE0
    csrrci   x13, MYCSR2, 0x12     # 0xE1
    csrrci   x14, MYCSR3, 0x15     # 0xE8
    csrrci   x15, MYCSR4, 0x14     # 0xE9
    csrrci   x16, MYCSR5, 0x01     # 0xE6
    csrrci   x17, MYCSR6, 0x09     # 0xF6
    csrrci   x18, MYCSR7, 0x01     # 0xEA

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

	lw  x9,    8(x10)   # Load something to make sure earlier SW transfer is done

 	li  x31,  0xdeadbeef

    csrrci   x9, MYCSR0, 0   # Try writing immediate 0 to make sure the write is disabled (visual inspection only)

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
