#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_lui
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: LUI
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

	#-------------------------------------------------
	# WRITE SOME VALUES IN THE REGISTERS
	#-------------------------------------------------
 
	lui x0,  0x34512
	lui x1,  0x12345
 	lui x2,  0xdeadb
 	lui x3,  0x10000
 	lui x4,  0xabcd1
	lui x5,  0x0bad0
	lui x6,  0x0000f
	lui x7,  0xffff0
	lui x8,  0x11111
	lui x9,  0x33344
	lui x10, 0x55555
	lui x11, 0x77788
	lui x12, 0x99999
	lui x13, 0xBBBCC
	lui x14, 0xDDDDD
	lui x15, 0xFFF00
	lui x16, 0x11223
	lui x17, 0x55667
	lui x18, 0x99AAB
	lui x19, 0xDDEEF
	lui x20, 0x01234
	lui x21, 0x89ABC
	lui x22, 0xFEDCB
	lui x23, 0x76543
	lui x24, 0x00FFE
	lui x25, 0xCCBBA
	lui x26, 0x88776
	lui x27, 0x44332
	lui x28, 0x13579
	lui x29, 0x02468

	# Trigger check in the testbench
	li  x30, 0xABCDEF01
	li  x31, 0x10040000
	sw  x30, 0(x31)              # write 0x00FEBADC to Periph #0

	# Add a few NOPs to make sure the store instruction is done for the verilog stimuli check
	nop
	nop
	nop
	nop
	nop
	nop
	nop

	#-------------------------------------------------
	# WRITE A 1 IN EACH BIT OF THE IMMEDIATE FIELD
	#-------------------------------------------------
 
	lui x0,  0xA5A5A
 	lui x3,  0x00001
 	lui x4,  0x00002
	lui x5,  0x00004
	lui x6,  0x00008
	lui x7,  0x00010
	lui x8,  0x00020
	lui x9,  0x00040
	lui x10, 0x00080
	lui x11, 0x00100
	lui x12, 0x00200
	lui x13, 0x00400
	lui x14, 0x00800
	lui x15, 0x01000
	lui x16, 0x02000
	lui x17, 0x04000
	lui x18, 0x08000
	lui x19, 0x10000
	lui x20, 0x20000
	lui x21, 0x40000
	lui x22, 0x80000
	lui x23, 0x40000
	lui x24, 0x20000
	lui x25, 0x10000
	lui x26, 0x08000
	lui x27, 0x04000
	lui x28, 0x02000
	lui x29, 0x01000
	lui x30, 0x00800
	lui x31, 0x00400

	# Trigger check in the testbench
	li  x1,  0x23456789
	li  x2,  0x10040000
	sw  x1,  4(x2)              # write 0x00FEBADC to Periph #0

	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------
    
end_of_test:
	nop
    j end_of_test   # infinite loop


