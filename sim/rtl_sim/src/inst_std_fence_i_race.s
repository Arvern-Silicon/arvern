#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_fence_i_race
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: FENCE.I store-to-ifetch race -- minimum-distance self-modifying code
#
#   inst_std_fence_i also patches code and jumps to it, but leaves four
#   instructions between the FENCE.I and the jump, so the store has ~23 cycles
#   of slack before the patched address is fetched. This test removes that
#   slack: the store, the FENCE.I and the jump into the patched word are
#   adjacent, with every operand preloaded.
#
#   FENCE.I orders prior data writes against subsequent instruction fetches.
#   Those use SEPARATE AHB buses, so unlike FENCE there is no in-order LSU
#   relationship to fall back on -- the only thing holding the fetch is the
#   FENCE.I dispatch stall.
#
#   Each iteration patches ADDI x10,x0,K with a DIFFERENT K and checks that the
#   patched word executed. A stale fetch yields the previous iteration's K (or
#   0 on the first), so a miss is detected rather than silently tolerated.
#
#   The measured margin is 3 cycles: store address phase at 914, patch fetch at
#   917 (base config, -gahb). To attack it the stimulus pins ROM and SRAM_X wait
#   states itself, one pair per round, rather than relying on random variants --
#   ROM latency delays the store's bus grant without delaying the patch fetch's
#   arrival at the SRAM slave.
#
# Scratchpad (SRAM_X):
#   0x80000000 mismatch count   0x80000004 first bad K   0x80000008 observed x10
#   0x8000000C round of first failure
#   0x80001010 patch buffer: [0] ADDI x10,x0,K   [4] JALR x0,x1,0 (ret)
#----------------------------------------------------------------------------

.equ PATCH,  0x80001010
.equ RESULT, 0x80000000
.equ ITERS,  20
.equ ROUNDS, 6

.section .text
.global main

main:
	j    _start

_start:
	li   sp, 0x80010000

	# IRQs off for the whole test: an IRQ landing between the store and the
	# jump would re-enter through the handler and hide the window. This is
	# also the RISC-V convention for self-modifying code.
	csrw mstatush, x0           # Smdbltrp: MDT resets to 1 and blocks MIE
	csrci mstatus, 8            # MIE=0

	li   s2, RESULT
	sw   x0, 0x00(s2)           # mismatch count
	sw   x0, 0x04(s2)           # first bad K
	sw   x0, 0x08(s2)           # observed x10
	sw   x0, 0x0C(s2)           # round of first failure
	lw   zero, 0x0C(s2)         # fence: drain the init stores

	li   s3, PATCH
	la   x1, patch_ret          # return address used by the patched RET
	li   t2, 0x00008067         # JALR x0, x1, 0  == RET
	sw   t2, 4(s3)              # [4] = RET, written once
	fence.i

	li   s4, 0                  # mismatch count
	li   s5, 0                  # round

	#-------------------------------------------------
	# Round loop. Each round announces itself on x31 and then burns a fixed
	# delay, giving the testbench time to pin this round's wait states before
	# the timing-critical loop starts.
	#-------------------------------------------------
round:
	li   t3, 0x100
	add  x31, t3, s5            # x31 = 0x100 + round: testbench pins wait states
	li   t3, 150
ws_settle:
	addi t3, t3, -1
	bnez t3, ws_settle

	li   s0, 1                  # K
	li   s1, ITERS + 1

	#-------------------------------------------------
	# The window under test.
	#
	# Nothing separates the store from the jump except the FENCE.I itself:
	# t1 (the instruction word) and s3 (the address) are both ready before
	# the store issues, so the store is the only thing that can still be in
	# flight when the fetch of PATCH goes out on the instruction bus.
	#-------------------------------------------------
loop:
	slli t1, s0, 20             # K << 20
	ori  t1, t1, 0x513          # | ADDI x10, x0, _  ->  0x_____513
	li   x10, 0xDEAD0000        # sentinel: survives if the patch never ran

	sw   t1, 0(s3)              # patch [0]
	fence.i                     # must order this store against the fetch below
	jalr x0, s3, 0              # jump straight into the patched word

patch_ret:
	beq  x10, s0, ok            # patched ADDI must have produced K

	# Mismatch: record the first one only.
	addi s4, s4, 1
	lw   t3, 0x00(s2)
	bnez t3, count_only
	sw   s0, 0x04(s2)           # first bad K
	sw   x10, 0x08(s2)          # what was actually executed
	sw   s5, 0x0C(s2)           # which round
count_only:
	sw   s4, 0x00(s2)

ok:
	addi s0, s0, 1
	blt  s0, s1, loop

	addi s5, s5, 1
	li   t3, ROUNDS
	blt  s5, t3, round

	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------
	sw   s4, 0x00(s2)           # final mismatch count
	lw   zero, 0x00(s2)         # fence: drain before the sync sentinel

	li   x31, 0xdeadbeef
1:	j    1b
