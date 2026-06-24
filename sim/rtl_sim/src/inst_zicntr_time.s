#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_time
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZICNTR TIME
#   Zicntr time/timeh CSR verification:
#   - time (0xC01) and timeh (0xC81) are non-zero (random mtime_init)
#   - time is strictly increasing between two reads
#   - 64-bit coherence guard: double-read of timeh brackets time read
#   - time != cycle (distinct values due to random mtime_init offset)
#
#   No random IRQ injection (no_random_irq test).
#   The testbench sets tb_arvern.mtime_init = {$random, $random} before
#   reset, so mtime starts from a large random value clearly distinguishable
#   from cycle (which starts near 0).
#
#   Scratchpad layout (base 0x80000000):
#   0x00: phase1_time_lo    — first read of time  (0xC01)
#   0x04: phase1_time_hi    — first read of timeh (0xC81)
#   0x08: phase2_time2_lo   — second read of time (must be > first)
#   0x0C: phase3_coh_hi1    — timeh before time read (coherence guard)
#   0x10: phase3_coh_lo     — time between the two timeh reads
#   0x14: phase3_coh_hi2    — timeh after time read (must == hi1 or hi1+1)
#   0x18: phase4_time_lo    — time readback for time != cycle check
#   0x1C: phase4_cycle_lo   — cycle readback for time != cycle check
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ TIME,     0xC01
.equ TIMEH,    0xC81
.equ CYCLE,    0xC00

main:
    li   sp, 0x80010000
    li   s1, 0x80000000          # Scratchpad base
    # DO NOT call _random_irq_init (no_random_irq test)

    # Zero the scratchpad (8 words)
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)

    #=================================================================
    # PHASE 1: time and timeh are non-zero (random mtime_init)
    # The testbench sets mtime_init to a large random 64-bit value,
    # so time_lo and {time_hi, time_lo} should both be non-zero.
    #=================================================================

    csrr t0, TIME                # read time low word
    sw   t0, 0x00(s1)            # phase1_time_lo

    csrr t0, TIMEH               # read time high word
    sw   t0, 0x04(s1)            # phase1_time_hi
    lw   t3, 0x04(s1)            # AHB fence

    li   x31, 0x11111111         # Sync: phase 1 done


    #=================================================================
    # PHASE 2: time is strictly increasing
    # Read time again; it must be greater than the first read.
    # Several firmware instructions have elapsed between phase 1 and
    # here, so time must have advanced.
    #=================================================================

    csrr t0, TIME                # second read of time
    sw   t0, 0x08(s1)            # phase2_time2_lo
    lw   t3, 0x08(s1)            # AHB fence

    li   x31, 0x22222222         # Sync: phase 2 done


    #=================================================================
    # PHASE 3: 64-bit coherence guard (double-read of timeh)
    # Read timeh, then time, then timeh again.
    # The second timeh must equal the first or be exactly one more
    # (if a carry propagated during the time read).
    #=================================================================

    csrr t0, TIMEH               # read high half first
    sw   t0, 0x0C(s1)            # phase3_coh_hi1

    csrr t1, TIME                # read low half
    sw   t1, 0x10(s1)            # phase3_coh_lo

    csrr t0, TIMEH               # read high half again
    sw   t0, 0x14(s1)            # phase3_coh_hi2
    lw   t3, 0x14(s1)            # AHB fence

    li   x31, 0x33333333         # Sync: phase 3 done


    #=================================================================
    # PHASE 4: time != cycle
    # Read both time and cycle; they must differ.
    # Due to random mtime_init, time starts from a large random value
    # while cycle starts from 0, so they should clearly differ.
    #=================================================================

    csrr t0, TIME                # read time
    sw   t0, 0x18(s1)            # phase4_time_lo

    csrr t0, CYCLE               # read cycle
    sw   t0, 0x1C(s1)            # phase4_cycle_lo
    lw   t3, 0x1C(s1)            # AHB fence

    li   x31, 0xdeadbeef         # Sync: all done

end_of_test:
    j    end_of_test
