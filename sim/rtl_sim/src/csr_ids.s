#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      csr_ids
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSR IDs
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MVENDORID,  0xF11       # Vendor ID.
.equ MARCHID,    0xF12       # Architecture ID.
.equ MIMPID,     0xF13       # Implementation ID.
.equ MHARTID,    0xF14       # Hardware thread ID.
.equ MCONFIGPTR, 0xF15       # Pointer to configuration data structure.

.equ MISA,       0x301       # ISA and extensions.


main:
    j _start            # Reset Vector
    j default_handler   # Default machine handler
    j default_handler   # Default supervisor handler

	#-------------------------------------------------
	# WRITE SOME VALUES IN THE REGISTERS
	#-------------------------------------------------
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

	#-------------------------------------------------
	# READ ALL ID REGISTERS DEFAULT VALUES
	#-------------------------------------------------

    csrr    x1,  MVENDORID
    csrr    x2,  MARCHID
    csrr    x3,  MIMPID
    csrr    x4,  MHARTID
    csrr    x5,  MCONFIGPTR
    csrr    x6,  MISA

 	li      x29, 0xdeadbeef
	nop
	nop
	nop


	#-------------------------------------------------
	# READ ALL ID REGISTERS FORCED OVERWRITEN VALUES
	#-------------------------------------------------

    csrr    x11, MVENDORID
    csrr    x12, MARCHID
    csrr    x13, MIMPID
    csrr    x14, MHARTID
    csrr    x15, MCONFIGPTR
    csrr    x16, MISA

	li      x30, 0xDEADBEEF
	nop
	nop
	nop

	#-------------------------------------------------
	# CHECK WRITING TO ID REGISTERS
	#-------------------------------------------------

	# Writing to MISA is allowed but has no impact
    csrrw   x21, MISA, x30
    csrr    x22, MISA

	# Writing to any other ID should generate a trap
    csrrw   x23, MVENDORID, x30
    csrr    x24, MVENDORID

	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------
trap_exit:
 	#li  x31,  0xdeadbeef
 	li  x31,  0xdeadbeef    # Fix later


end_of_test:
	nop
    j end_of_test   # infinite loop


default_handler:
    # Advance MEPC past the faulting 32-bit instruction and return
    csrr  t0, mepc
    addi  t0, t0, 4
    csrw  mepc, t0
    mret
