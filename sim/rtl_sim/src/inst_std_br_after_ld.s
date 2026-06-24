#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_br_after_ld
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: BRANCH/JAL/JALR AFTER LOAD/STORE
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

	# SRAM base address
	li  x29, 0x80000000

	#-------------------------------------------------------------------
	# SECTION 1: JAL immediately after SW (no data hazard on JAL)
	#-------------------------------------------------------------------
	# SW fires a data-bus transaction. JAL immediately after must wait
	# for ex_ldst_busy to clear before id_branch_detect_o fires.
	li  x1, 0x11223344
	sw  x1, 0(x29)              # SW -> data bus transaction
	jal x10, sec1_target        # JAL must fire exactly once
sec1_fallthrough:
	jal x0, test_fail           # MUST NOT reach here
sec1_target:
	la  x28, sec1_fallthrough
	li  x30, 0x00000101
	bne x10, x28, test_fail     # x10 must equal return address
	li  x31, 0x11111111         # Sync point 1


	#-------------------------------------------------------------------
	# SECTION 2: JAL immediately after LW (load to x2, JAL uses no regs)
	#-------------------------------------------------------------------
	lw  x2, 0(x29)              # LW to x2 (no dep with JAL operands)
	jal x11, sec2_target        # JAL immediately after LW, no dep on x2
sec2_fallthrough:
	jal x0, test_fail
sec2_target:
	la  x28, sec2_fallthrough
	li  x30, 0x00000201
	bne x11, x28, test_fail     # x11 must equal return address
	li  x31, 0x22222222         # Sync point 2


	#-------------------------------------------------------------------
	# SECTION 3: BNE immediately after LW (load to x4, BNE uses x3/x5)
	#-------------------------------------------------------------------
	li  x3, 0xAAAAAAAA
	li  x5, 0xBBBBBBBB
	sw  x3, 4(x29)              # Write 0xAAAAAAAA to SRAM[1]
	lw  x4, 4(x29)              # LW to x4 (= 0xAAAAAAAA), x3/x5 unaffected
	bne x3, x5, sec3_taken      # BNE immediately after LW, no dep on x4, must be taken
	jal x0, test_fail
sec3_taken:
	li  x31, 0x33333333         # Sync point 3


	#-------------------------------------------------------------------
	# SECTION 4: JALR immediately after LW (load to x8, JALR uses x6)
	#-------------------------------------------------------------------
	la  x6, sec4_target         # x6 = JALR target address (no dep with LW)
	li  x7, 0xCCCCCCCC
	sw  x7, 8(x29)              # Write 0xCCCCCCCC to SRAM[2]
	lw  x8, 8(x29)              # LW to x8 (= 0xCCCCCCCC), x6 unaffected
	jalr x12, x6, 0             # JALR immediately after LW, uses x6 (not x8), must jump
sec4_fallthrough:
	jal x0, test_fail
sec4_target:
	la  x28, sec4_fallthrough
	li  x30, 0x00000401
	bne x12, x28, test_fail     # x12 must equal return address
	li  x31, 0x44444444         # Sync point 4


	#-------------------------------------------------------------------
	# SECTION 5: BEQ immediately after SW (no data hazard on BEQ)
	#-------------------------------------------------------------------
	li  x13, 0x55556666
	sw  x13, 12(x29)            # SW -> data bus transaction
	beq x13, x13, sec5_taken    # BEQ immediately after SW, trivially taken
	jal x0, test_fail
sec5_taken:
	li  x31, 0x55555555         # Sync point 5


	#-------------------------------------------------------------------
	# SECTION 6: Back-to-back: LW then BNE then SW then JAL (no deps)
	#-------------------------------------------------------------------
	# Chain: LW -> BNE -> (taken) -> SW -> JAL to check all in one shot
	li  x14, 0xDEAD0000
	sw  x14, 16(x29)            # Pre-store for LW below
	li  x15, 0x0000DEAD
	lw  x16, 16(x29)            # LW to x16 (= 0xDEAD0000)
	bne x14, x15, sec6_bne_ok   # BNE immediately after LW, uses x14/x15 != x16
	jal x0, test_fail
sec6_bne_ok:
	sw  x14, 20(x29)            # SW
	jal x17, sec6_jal_ok        # JAL immediately after SW
sec6_jal_fallthrough:
	jal x0, test_fail
sec6_jal_ok:
	la  x28, sec6_jal_fallthrough
	li  x30, 0x00000601
	bne x17, x28, test_fail
	li  x31, 0x66666666         # Sync point 6


	#-------------------------------------------------------------------
	# SECTION 7: BNE immediately after LW, RS1 = load dest (data hazard)
	#-------------------------------------------------------------------
	# Pipeline must insert a stall bubble until the load completes,
	# then BNE evaluates the freshly loaded value in RS1.
	li  x1, 0x11111111
	sw  x1, 24(x29)             # SRAM[6] = 0x11111111
	li  x3, 0x22222222
	lw  x2, 24(x29)             # x2 = 0x11111111  (load-use hazard: BNE RS1=x2)
	bne x2, x3, sec7_taken      # RS1=x2 hazard, must be taken (0x11111111 != 0x22222222)
	jal x0, test_fail
sec7_taken:
	li  x30, 0x00000701
	bne x2, x1, test_fail       # x2 must equal the loaded value 0x11111111
	li  x31, 0x77777777         # Sync point 7


	#-------------------------------------------------------------------
	# SECTION 8: BNE immediately after LW, RS2 = load dest (data hazard)
	#-------------------------------------------------------------------
	li  x4, 0x33333333
	sw  x4, 28(x29)             # SRAM[7] = 0x33333333
	li  x6, 0x44444444
	lw  x5, 28(x29)             # x5 = 0x33333333  (load-use hazard: BNE RS2=x5)
	bne x6, x5, sec8_taken      # RS2=x5 hazard, must be taken (0x44444444 != 0x33333333)
	jal x0, test_fail
sec8_taken:
	li  x30, 0x00000801
	bne x5, x4, test_fail       # x5 must equal the loaded value 0x33333333
	li  x31, 0x88888888         # Sync point 8


	#-------------------------------------------------------------------
	# SECTION 9: JALR immediately after LW, RS1 = load dest (data hazard)
	#-------------------------------------------------------------------
	# Load the JALR target address from SRAM, then JALR using that register.
	la  x7, sec9_target         # x7 = target address
	sw  x7, 32(x29)             # SRAM[8] = target address
	lw  x8, 32(x29)             # x8 = target address  (load-use hazard: JALR RS1=x8)
	jalr x9, x8, 0              # RS1=x8 hazard, must jump to sec9_target
sec9_fallthrough:
	jal x0, test_fail
sec9_target:
	la  x28, sec9_fallthrough
	li  x30, 0x00000901
	bne x9, x28, test_fail      # x9 must equal return address
	li  x31, 0x99999999         # Sync point 9


	#-------------------------------------------------------------------
	# SECTION 10: BEQ immediately after LW, RS1 = load dest (data hazard)
	#-------------------------------------------------------------------
	li  x10, 0x55555555
	sw  x10, 36(x29)            # SRAM[9] = 0x55555555
	lw  x11, 36(x29)            # x11 = 0x55555555  (load-use hazard: BEQ RS1=x11)
	beq x11, x10, sec10_taken   # RS1=x11 hazard, must be taken (both == 0x55555555)
	jal x0, test_fail
sec10_taken:
	li  x30, 0x00000A01
	bne x11, x10, test_fail     # x11 must equal the loaded value 0x55555555
	li  x31, 0xA0A0A0A0         # Sync point 10


	#-------------------------------------------------------------------
	# END OF TEST
	#-------------------------------------------------------------------
	li  x31, 0xdeadbeef         # Final sync: all tests passed

end_of_test:
	nop
	j end_of_test


test_fail:
	# x30 already holds the error code
	li  x31, 0xBADC0DE0
	j end_of_test
