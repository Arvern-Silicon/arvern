#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_fence_characterize
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: FENCE characterization -- what each encoding actually holds
#
#   Measures, per trial, when the instruction AFTER the fence becomes visible
#   relative to the completion of a store that precedes it on the data bus.
#   A MEASUREMENT, not a conformance check: it records behaviour rather than
#   asserting an ordering, so it documents the implementation instead of
#   encoding an assumption about it.
#
#   The first SRAM_X transfer is a deliberate throwaway: the wait-state model
#   applies the count latched at the PREVIOUS transfer, so without it trial 0
#   would measure a 1-cycle data phase against everyone else's 7.
#
#   THE GAP MATTERS. With the store immediately before the fence, the store is
#   still in EX and the LSU's own ready signal stalls every instruction anyway,
#   so a fence can add nothing and all encodings look identical for reasons
#   that have nothing to do with fences. To see a fence act, the store must
#   have LEFT EX and be in its data phase -- which needs filler instructions
#   between the store and the fence. Part A sweeps that gap; part B compares
#   encodings at a gap where the store is genuinely in flight.
#
#   Each trial:
#       li   x31, ARM+k        <- testbench arms on this
#       <settle>
#       sw   t1, 0(s3)         <- reference store (SRAM_X, wait states pinned)
#       <G filler nops>        <- lets the store leave EX and enter its data phase
#       <fence encoding, or nothing>
#       addi x31, x0, MARK+k   <- first instruction after the fence
#
#   Encodings (verified against the assembler):
#     iorw,iorw 0x0ff0000f   rw,rw 0x0330000f   r,r 0x0220000f   w,w 0x0110000f
#     i,i       0x0880000f   o,o   0x0440000f   tso 0x8330000f   pause 0x0100000f
#
# Scratchpad: store target 0x80000100 (away from the result area)
#----------------------------------------------------------------------------

.equ TARGET, 0x80000100
.equ ARM,    0x00000300
.equ MARK,   0x00000400

.section .text
.global main

main:
	j    _start

_start:
	li   sp, 0x80010000

	# IRQs off: a trap between the store and the marker would corrupt the
	# measurement by inserting handler instructions into the window.
	csrw mstatush, x0           # Smdbltrp: MDT resets to 1 and blocks MIE
	csrci mstatus, 8            # MIE=0

	li   s3, TARGET

	# WARM-UP -- absorbs the wait-state model's one-transfer lag.
	#
	# ahb_waitstate_inserter samples number_ws_i one transfer AHEAD: the count
	# applied to a transfer is the value latched at the PREVIOUS address phase,
	# or at reset for the first one. The stimulus pins the latency after reset,
	# so the first-ever SRAM_X transfer still runs at the reset value of 0 and
	# reports a 1-cycle data phase instead of 7. Trial 0 used to be that
	# transfer, which made the calibration baseline unusable.
	#
	# This throwaway access takes the stale count so every measured transfer
	# sees the pinned latency. It must precede the first ARM, or the bus
	# observer would attribute it to trial 0.
	li   t0, TARGET + 0x40
	sw   x0, 0(t0)
	lw   zero, 0(t0)

.macro SETTLE
	li   t2, 60
1:	addi t2, t2, -1
	bnez t2, 1b
.endm

.macro TRIAL_HEAD k
	li   x31, ARM + \k
	SETTLE
	li   t1, 0xA5A50000 + \k
.endm

.macro TRIAL_TAIL k
	addi x31, x0, MARK + \k
	SETTLE
.endm

# G filler instructions: independent of the store, touch no memory and no
# register the store or the marker uses.
.macro FILL n
	.rept \n
	nop
	.endr
.endm

	#===============================================================
	# PART A -- gap sweep. Even trials have NO fence, odd trials have
	# `fence iorw,iorw`, at the same gap. Each pair is directly
	# comparable: the difference is the fence and nothing else.
	#===============================================================

	TRIAL_HEAD 0                # gap 0, no fence
	sw   t1, 0(s3)
	FILL 0
	TRIAL_TAIL 0

	TRIAL_HEAD 1                # gap 0, fence
	sw   t1, 0(s3)
	FILL 0
	fence iorw,iorw
	TRIAL_TAIL 1

	TRIAL_HEAD 2                # gap 2, no fence
	sw   t1, 0(s3)
	FILL 2
	TRIAL_TAIL 2

	TRIAL_HEAD 3                # gap 2, fence
	sw   t1, 0(s3)
	FILL 2
	fence iorw,iorw
	TRIAL_TAIL 3

	TRIAL_HEAD 4                # gap 4, no fence
	sw   t1, 0(s3)
	FILL 4
	TRIAL_TAIL 4

	TRIAL_HEAD 5                # gap 4, fence
	sw   t1, 0(s3)
	FILL 4
	fence iorw,iorw
	TRIAL_TAIL 5

	TRIAL_HEAD 6                # gap 8, no fence
	sw   t1, 0(s3)
	FILL 8
	TRIAL_TAIL 6

	TRIAL_HEAD 7                # gap 8, fence
	sw   t1, 0(s3)
	FILL 8
	fence iorw,iorw
	TRIAL_TAIL 7

	#===============================================================
	# PART B -- encoding sweep at gap 2, where the store is in flight
	# rather than blocking in EX. Trial 2 (gap 2, no fence) is the
	# control for this whole part.
	#===============================================================

	TRIAL_HEAD 8
	sw   t1, 0(s3)
	FILL 2
	fence rw,rw
	TRIAL_TAIL 8

	TRIAL_HEAD 9
	sw   t1, 0(s3)
	FILL 2
	fence r,r
	TRIAL_TAIL 9

	TRIAL_HEAD 10
	sw   t1, 0(s3)
	FILL 2
	fence w,w
	TRIAL_TAIL 10

	TRIAL_HEAD 11
	sw   t1, 0(s3)
	FILL 2
	fence i,i
	TRIAL_TAIL 11

	TRIAL_HEAD 12
	sw   t1, 0(s3)
	FILL 2
	fence o,o
	TRIAL_TAIL 12

	TRIAL_HEAD 13
	sw   t1, 0(s3)
	FILL 2
	.word 0x8330000f            # fence.tso
	TRIAL_TAIL 13

	TRIAL_HEAD 14
	sw   t1, 0(s3)
	FILL 2
	.word 0x0100000f            # pause (fence w,0 -- Zihintpause)
	TRIAL_TAIL 14

	TRIAL_HEAD 15               # late no-fence control: guards against drift
	sw   t1, 0(s3)
	FILL 2
	TRIAL_TAIL 15

	#===============================================================
	# PART C -- the preceding access is a LOAD, not a store.
	#
	# The fence term carries wb_load_busy_i (= dph_is_load) alongside
	# ~wb_ldst_ready_i. The ready term drops when hready rises, i.e. on the
	# data phase's completing cycle; dph_is_load is only cleared at the END of
	# that cycle. So a fence after a LOAD should be held one cycle longer than
	# a fence after a STORE. Trials 16/17 measure that against 2/3.
	#===============================================================

	TRIAL_HEAD 16               # gap 2, load, no fence
	lw   t4, 0(s3)
	FILL 2
	TRIAL_TAIL 16

	TRIAL_HEAD 17               # gap 2, load, fence
	lw   t4, 0(s3)
	FILL 2
	fence iorw,iorw
	TRIAL_TAIL 17

	#-------------------------------------------------
	# END OF TEST
	#-------------------------------------------------
	li   x31, 0xdeadbeef
1:	j    1b
