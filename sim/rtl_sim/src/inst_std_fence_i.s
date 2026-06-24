#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_fence_i
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: FENCE.I
#   Tests three scenarios:
#   Phase 1: FENCE.I smoke test (no pending ops, back-to-back)
#   Phase 2: FENCE.I after stores (verifies store-drain stall)
#   Phase 3: Self-modifying code (verifies instruction-buffer flush via
#   SRAM_X which is accessible from both instruction and data AHB)
#
#   Scratch areas use hardcoded SRAM_X addresses (li, not la) because the
#   .text section lives in ROM at 0x20000000 and BSS at 0x80000000 is
#   unreachable via AUIPC (1.5 GB gap exceeds 20-bit PC-relative range).
#   Writes: ADDI x10,x0,0x555 (0x55500513) + JALR x0,x1,0 (0x00008067).
#   Without buffer flush the processor would execute stale zeros in the
#   instruction buffer; with flush it returns x10=0x555.
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal  t0, _random_irq_init
	li   t0, 0

	#-------------------------------------------------
	# INIT: set all registers to known value
	#-------------------------------------------------
	li   x1,  0xFFFFFFFF
	li   x2,  0xFFFFFFFF
	li   x3,  0xFFFFFFFF
	li   x4,  0xFFFFFFFF
	li   x5,  0xFFFFFFFF
	li   x6,  0xFFFFFFFF
	li   x7,  0xFFFFFFFF
	li   x8,  0xFFFFFFFF
	li   x9,  0xFFFFFFFF
	li   x10, 0xFFFFFFFF
	li   x11, 0xFFFFFFFF
	li   x12, 0xFFFFFFFF
	li   x13, 0xFFFFFFFF
	li   x14, 0xFFFFFFFF
	li   x15, 0xFFFFFFFF
	li   x16, 0xFFFFFFFF
	li   x17, 0xFFFFFFFF
	li   x18, 0xFFFFFFFF
	li   x19, 0xFFFFFFFF
	li   x20, 0xFFFFFFFF
	li   x21, 0xFFFFFFFF
	li   x22, 0xFFFFFFFF
	li   x23, 0xFFFFFFFF
	li   x24, 0xFFFFFFFF
	li   x25, 0xFFFFFFFF
	li   x26, 0xFFFFFFFF
	li   x27, 0xFFFFFFFF
	li   x28, 0xFFFFFFFF
	li   x29, 0xFFFFFFFF
	li   x30, 0xFFFFFFFF
	li   x31, 0xFFFFFFFF        # SYNC 0xFFFFFFFF: init done

	#-------------------------------------------------
	# PHASE 1: FENCE.I smoke test
	#   - FENCE.I with nothing pending
	#   - Back-to-back FENCE.I
	#   - FENCE.I sandwiched between register writes
	#-------------------------------------------------
	li   x1, 0xA1A1A1A1
	fence.i                     # FENCE.I: nothing pending (no stall expected)
	li   x2, 0xB2B2B2B2
	fence.i                     # back-to-back
	fence.i
	li   x3, 0xC3C3C3C3
	fence.i
	li   x4, 0xD4D4D4D4

	li   x31, 0x11111111        # SYNC 0x11111111: phase 1 done

	#-------------------------------------------------
	# PHASE 2: FENCE.I after stores (stall test)
	#   Store two words to SRAM_X scratch, then FENCE.I.
	#   FENCE.I must stall until ex/wb LSU is idle.
	#   Load the values back and verify.
	#   Use x28 (not t0/x5) as base: lw x5 would clobber t0.
	#-------------------------------------------------
	li   x28, 0x80001000        # SRAM_X scratch area for phase-2 (x28, not t0/x5)
	li   t1, 0xABCD1234
	sw   t1, 0(x28)
	li   t2, 0x5678EF01
	sw   t2, 4(x28)
	fence.i                     # must drain both stores before continuing
	lw   x5, 0(x28)             # 0xABCD1234
	lw   x6, 4(x28)             # 0x5678EF01
	addi x31, x6, 0             # RAW dependency: stall until lw x6 data phase completes

	li   x31, 0x22222222        # SYNC 0x22222222: phase 2 done

	#-------------------------------------------------
	# PHASE 3: Self-modifying code via SRAM_X
	#
	#   patch_buf at 0x80001010 in SRAM_X.
	#   Accessible by both instruction-fetch AHB and data AHB.
	#
	#   We write two instructions:
	#     [0]  ADDI x10, x0, 0x555   => 0x55500513
	#     [4]  JALR x0,  x1, 0       => 0x00008067  (RET)
	#
	#   Without FENCE.I buffer flush, the instruction buffer may hold
	#   stale zeros => executing there hits an illegal-instruction trap.
	#   With the flush, x10 == 0x555.
	#
	#   IRQs are disabled for this section (RISC-V convention for self-
	#   modifying code): an IRQ handler re-entering the code before stores
	#   are visible via I-fetch causes a nested trap in the generic handler.
	#-------------------------------------------------
	csrci mstatus, 8            # disable global interrupts (MIE=0) for critical section

	li   x10, 0xDEAD0000        # sentinel: wrong value if patch not executed

	li   t0, 0x80001010         # SRAM_X patch area (hardcoded; see Phase 2 comment)
	li   t1, 0x55500513         # ADDI x10, x0, 0x555
	sw   t1, 0(t0)
	li   t1, 0x00008067         # JALR x0, x1, 0  (standard RET)
	sw   t1, 4(t0)

	fence.i                     # flush: ensure stores are visible to I-fetch

	la   x1, patch_return       # return address (in ROM, reachable by AUIPC)
	li   t0, 0x80001010
	jalr x0, t0, 0              # jump into self-modified code

patch_return:
	csrsi mstatus, 8            # re-enable global interrupts (MIE=1)
	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------
	li   x31, 0xdeadbeef        # SYNC 0xdeadbeef: end of test

end_of_test:
	nop
	j    end_of_test            # infinite loop


