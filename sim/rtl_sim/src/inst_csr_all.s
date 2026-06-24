#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_all
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSR MSCRATCH
#----------------------------------------------------------------------------

.section .text
.global main

# Standard CSR addresses (no custom CSR required)
.equ MSCRATCH,  0x340       # Machine Scratch Register

main:

	#-------------------------------------------------
	# INITIAL REGISTER SETUP
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
	# TEST CSRRW - CSR Read/Write
	#-------------------------------------------------

    li      x10, 0x12345678
    csrrw   x11, MSCRATCH, x10      # Write 0x12345678, read old value -> x11
    csrr    x12, MSCRATCH           # Read back -> x12

    li      x10, 0xAABBCCDD
    csrrw   x13, MSCRATCH, x10      # Write 0xAABBCCDD, old (0x12345678) -> x13
    csrr    x14, MSCRATCH           # Read back -> x14

	#-------------------------------------------------
	# TEST CSRRS - CSR Read and Set Bits
	#-------------------------------------------------

    li      x15, 0x0F0F0F0F
    csrrw   x16, MSCRATCH, x0       # Clear MSCRATCH
    csrrs   x17, MSCRATCH, x15      # Set bits 0x0F0F0F0F, old (0) -> x17
    csrr    x18, MSCRATCH           # Read back (should be 0x0F0F0F0F)

    li      x15, 0xF0F0F0F0
    csrrs   x19, MSCRATCH, x15      # Set more bits, old (0x0F0F0F0F) -> x19
    csrr    x20, MSCRATCH           # Read back (should be 0xFFFFFFFF)

	#-------------------------------------------------
	# TEST CSRRC - CSR Read and Clear Bits
	#-------------------------------------------------

    li      x21, 0x0000FFFF
    csrrc   x22, MSCRATCH, x21      # Clear lower 16 bits, old (0xFFFFFFFF) -> x22
    csrr    x23, MSCRATCH           # Read back (should be 0xFFFF0000)

    li      x21, 0xFFFF0000
    csrrc   x24, MSCRATCH, x21      # Clear upper 16 bits, old (0xFFFF0000) -> x24
    csrr    x25, MSCRATCH           # Read back (should be 0x00000000)

	#-------------------------------------------------
	# TEST CSRRWI - CSR Read/Write Immediate
	#-------------------------------------------------

    csrrwi  x1, MSCRATCH, 15        # Write immediate 15, old (0) -> x1
    csrr    x2, MSCRATCH            # Read back (should be 15)

    csrrwi  x3, MSCRATCH, 31        # Write immediate 31, old (15) -> x3
    csrr    x4, MSCRATCH            # Read back (should be 31)

	#-------------------------------------------------
	# TEST CSRRSI - CSR Read and Set Bits Immediate
	#-------------------------------------------------

    csrrwi  x5, MSCRATCH, 0         # Clear MSCRATCH
    csrrsi  x6, MSCRATCH, 0x0F      # Set bits 0x0F, old (0) -> x6
    csrr    x7, MSCRATCH            # Read back (should be 0x0F)

    csrrsi  x8, MSCRATCH, 0x10      # Set bit 4, old (0x0F) -> x8
    csrr    x9, MSCRATCH            # Read back (should be 0x1F)

	#-------------------------------------------------
	# TEST CSRRCI - CSR Read and Clear Bits Immediate
	#-------------------------------------------------

    csrrwi  x10, MSCRATCH, 31       # Write 0x1F to MSCRATCH
    csrrci  x26, MSCRATCH, 0x0F     # Clear lower 4 bits, old (0x1F) -> x26
    csrr    x27, MSCRATCH           # Read back (should be 0x10)

    csrrci  x28, MSCRATCH, 0x10     # Clear bit 4, old (0x10) -> x28
    csrr    x29, MSCRATCH           # Read back (should be 0x00)

	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------

	li  x31, 0xdeadbeef

end_of_test:
	nop
    j end_of_test   # infinite loop

