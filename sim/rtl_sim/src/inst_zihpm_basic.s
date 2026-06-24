#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_basic
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM BASIC
#   Zihpm HPM counter CSR verification across all ZIHPM_NR counters:
#   Phase 1 — mhpmeventN  write/read: event selector 5 (branch-taken)
#   Phase 2 — mhpmcounterN increments on branch-taken events
#   Phase 3 — mcountinhibit bit[N] freezes mhpmcounterN
#   Phase 4 — hpmcounterN (shadow) == mhpmcounterN when inhibited
#
#   ZIHPM_NR is discovered at runtime from mimpid[23:20].  The test loops
#   over counters 3..2+ZIHPM_NR; if ZIHPM_NR==0 the body is skipped.
#
#   Saved registers used (safe across random IRQs):
#   s1 = scratchpad base (0x80000000)
#   s2 = current counter block pointer (advances by 0x18 per counter)
#   s3 = ZIHPM_NR (0-8)
#
#   Scratchpad layout (base 0x80000000):
#   0x00: mimpid readback  — bits[23:20] = ZIHPM_NR
#   Per counter i (i=0 => counter3, i=7 => counter10):
#   base = 0x04 + i*0x18
#   +0x00: phase1_event_rb    — mhpmevent(3+i) readback
#   +0x04: phase2_count       — mhpmcounter(3+i) after branch loop
#   +0x08: phase3_rd1         — mhpmcounter(3+i) first read, inhibited
#   +0x0C: phase3_rd2         — mhpmcounter(3+i) second read, inhibited
#   +0x10: phase4_machine     — mhpmcounter(3+i) read, inhibited
#   +0x14: phase4_shadow      — hpmcounter(3+i)  read, inhibited
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MIMPID,        0xF13

# Per-counter scratchpad block size (6 words × 4 bytes)
.equ CTR_BLOCK_SZ,  0x18


#=======================================================================
# MACRO: COUNTER_TEST
# Runs all 4 phases for one HPM counter and writes results to the
# current scratchpad block (s2), then advances s2 by CTR_BLOCK_SZ.
#
# Arguments:
#   \mhpmevent   — CSR address of mhpmeventN
#   \mhpmcounter — CSR address of mhpmcounterN
#   \hpmcounter  — CSR address of hpmcounterN  (U-mode shadow)
#   \inhibit_bit — mcountinhibit bitmask for this counter (1 << N)
#=======================================================================
.macro COUNTER_TEST mhpmevent, mhpmcounter, hpmcounter, inhibit_bit

    # ---- Phase 1: event selector write and read back ----
    li   t0, 5                       # selector = branch-taken (event 5)
    csrw \mhpmevent, t0
    csrr t0, \mhpmevent
    sw   t0, 0x00(s2)                # phase1_event_rb
    lw   t3, 0x00(s2)                # AHB fence

    # ---- Phase 2: counter increments on branch-taken events ----
    li   t0, 0
    csrw \mhpmcounter, t0            # preset counter to zero
    li   t0, 8                       # loop count
1:  addi t0, t0, -1
    bne  t0, x0, 1b                  # 7 taken branches
    csrr t0, \mhpmcounter
    sw   t0, 0x04(s2)                # phase2_count
    lw   t3, 0x04(s2)                # AHB fence

    # ---- Phase 3: mcountinhibit stops counter ----
    li   t0, \inhibit_bit
    csrrs x0, MCOUNTINHIBIT, t0      # set inhibit bit for this counter
    csrr t0, \mhpmcounter
    sw   t0, 0x08(s2)                # phase3_rd1
    li   t4, 4                       # inner loop count
2:  addi t4, t4, -1
    bne  t4, x0, 2b                  # branches while inhibited (must not count)
    csrr t0, \mhpmcounter
    sw   t0, 0x0C(s2)                # phase3_rd2
    lw   t3, 0x0C(s2)                # AHB fence
    li   t0, \inhibit_bit
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit bit

    # ---- Phase 4: hpmcounterN shadow == mhpmcounterN when inhibited ----
    li   t0, \inhibit_bit
    csrrs x0, MCOUNTINHIBIT, t0      # inhibit counter (freeze both views)
    csrr t0, \mhpmcounter
    sw   t0, 0x10(s2)                # phase4_machine
    csrr t0, \hpmcounter
    sw   t0, 0x14(s2)                # phase4_shadow
    lw   t3, 0x14(s2)                # AHB fence
    li   t0, \inhibit_bit
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit bit

    # ---- Advance scratchpad pointer to next counter block ----
    addi s2, s2, CTR_BLOCK_SZ

.endm


main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base
    li   s2, 0x80000000              # s2 = zero-fill pointer

    # Zero 52 words of scratchpad (4 bytes mimpid + 8 counters × 24 bytes)
    li   t0, 0
    li   t2, 52
zero_loop:
    sw   t0, 0(s2)
    addi s2, s2, 4
    addi t2, t2, -1
    bnez t2, zero_loop

    li   s2, 0x80000004              # s2 = start of counter data blocks

    # Read mimpid; extract ZIHPM_NR from bits[23:20] into s3
    csrr t0, MIMPID
    sw   t0, 0x00(s1)                # mimpid readback at scratchpad[0]
    lw   t3, 0x00(s1)                # AHB fence
    srli s3, t0, 20
    andi s3, s3, 0xF                 # s3 = ZIHPM_NR (0-8)

    li   x31, 0x11111111             # Sync: mimpid written to scratchpad
    beqz s3, skip_to_done            # no HPM counters — skip test body


    #=================================================================
    # Counter 3  (present when ZIHPM_NR >= 1, guaranteed here)
    #=================================================================
    COUNTER_TEST 0x323, 0xB03, 0xC03, 0x8

    #=================================================================
    # Counter 4  (present when ZIHPM_NR >= 2)
    #=================================================================
    li   t0, 2
    blt  s3, t0, sync_done
    COUNTER_TEST 0x324, 0xB04, 0xC04, 0x10

    #=================================================================
    # Counter 5  (present when ZIHPM_NR >= 3)
    #=================================================================
    li   t0, 3
    blt  s3, t0, sync_done
    COUNTER_TEST 0x325, 0xB05, 0xC05, 0x20

    #=================================================================
    # Counter 6  (present when ZIHPM_NR >= 4)
    #=================================================================
    li   t0, 4
    blt  s3, t0, sync_done
    COUNTER_TEST 0x326, 0xB06, 0xC06, 0x40

    #=================================================================
    # Counter 7  (present when ZIHPM_NR >= 5)
    #=================================================================
    li   t0, 5
    blt  s3, t0, sync_done
    COUNTER_TEST 0x327, 0xB07, 0xC07, 0x80

    #=================================================================
    # Counter 8  (present when ZIHPM_NR >= 6)
    #=================================================================
    li   t0, 6
    blt  s3, t0, sync_done
    COUNTER_TEST 0x328, 0xB08, 0xC08, 0x100

    #=================================================================
    # Counter 9  (present when ZIHPM_NR >= 7)
    #=================================================================
    li   t0, 7
    blt  s3, t0, sync_done
    COUNTER_TEST 0x329, 0xB09, 0xC09, 0x200

    #=================================================================
    # Counter 10  (present when ZIHPM_NR >= 8)
    #=================================================================
    li   t0, 8
    blt  s3, t0, sync_done
    COUNTER_TEST 0x32A, 0xB0A, 0xC0A, 0x400

sync_done:
    li   x31, 0xAAAAAAAA             # Sync: all counter tests done

skip_to_done:
    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
