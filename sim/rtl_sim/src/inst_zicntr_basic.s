#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_basic
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZICNTR BASIC
#   Zicntr counter CSR verification:
#   - mcycle / mcycleh   (0xB00 / 0xB80): R/W, increments each cycle
#   - minstret / minstreth (0xB02 / 0xB82): R/W, increments per retired
#   - mcountinhibit (0x320): bits[2:0] stop counting when set
#   - time / timeh (0xC01 / 0xC81): read-only, external mtime
#   - cycle / cycleh / instret / instreth: read-only shadows
#   - mcounteren (0x306): write/readback of bits [2:0]
#
#   Scratchpad layout (base 0x80000000):
#   0x00: phase1_cycle_before  — mcycle before delay loop
#   0x04: phase1_cycle_after   — mcycle after delay loop
#   0x08: phase2_instret_init  — minstret before 5-ADDI sequence
#   0x0C: phase2_instret_final — minstret after 5-ADDI sequence
#   0x10: phase3_mcycle_preset — mcycle readback after writing preset value
#   0x14: phase3_inhibit_cycle — mcycle sampled while CY inhibited (before)
#   0x18: phase3_inhibit_cycle2— mcycle sampled while CY inhibited (after)
#   0x1C: phase4_time_lo       — time CSR 0xC01 readback
#   0x20: phase4_time_hi       — timeh CSR 0xC81 readback
#   0x24: phase5_cycle_lo      — cycle CSR 0xC00 shadow readback
#   0x28: phase5_instret_lo    — instret CSR 0xC02 shadow readback
#   0x2C: phase5_cycleh_lo     — cycleh CSR 0xC80 shadow readback
#   0x30: phase5_instreth_lo   — instreth CSR 0xC82 shadow readback
#   0x34: phase6_mcounteren_7  — mcounteren readback after writing 0x7
#   0x38: phase6_mcounteren_0  — mcounteren readback after writing 0x0
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCYCLE,         0xB00
.equ MCYCLEH,        0xB80
.equ MINSTRET,       0xB02
.equ MINSTRETH,      0xB82
.equ MCOUNTEREN,     0x306
.equ MCOUNTINHIBIT,  0x320
.equ CYCLE,          0xC00
.equ TIME,           0xC01
.equ INSTRET,        0xC02
.equ CYCLEH,         0xC80
.equ TIMEH,          0xC81
.equ INSTRETH,       0xC82

main:
    jal  t0, _random_irq_init    # Enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000          # Scratchpad base

    # Zero the scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)
    sw   t0, 0x3C(s1)
    sw   t0, 0x40(s1)

    #=================================================================
    # PHASE 1: mcycle increments across a delay loop
    # Read mcycle, spin a few iterations, read mcycle again.
    # Both values stored to scratchpad; testbench checks after > before.
    #=================================================================

    csrr t0, MCYCLE              # sample cycle counter before loop
    sw   t0, 0x00(s1)            # phase1_cycle_before

    # Small delay loop (8 iterations)
    li   t1, 8
phase1_delay:
    addi t1, t1, -1
    bne  t1, x0, phase1_delay

    csrr t0, MCYCLE              # sample cycle counter after loop
    sw   t0, 0x04(s1)            # phase1_cycle_after
    lw   t3, 0x04(s1)            # fence: ensure SW AHB data phase completes

    li   x31, 0x11111111         # Sync: phase 1 done


    #=================================================================
    # PHASE 2: minstret counts retired instructions
    # Read minstret, execute exactly 5 ADDI instructions, read again.
    # Delta must be >= 5 (plus overhead instructions in between).
    #=================================================================

    csrr t0, MINSTRET            # sample instret before sequence
    sw   t0, 0x08(s1)            # phase2_instret_init

    # Exactly 5 ADDI instructions (the counted sequence)
    addi t2, x0, 1
    addi t2, t2, 1
    addi t2, t2, 1
    addi t2, t2, 1
    addi t2, t2, 1

    csrr t0, MINSTRET            # sample instret after sequence
    sw   t0, 0x0C(s1)            # phase2_instret_final
    lw   t3, 0x0C(s1)            # fence: ensure SW AHB data phase completes

    li   x31, 0x22222222         # Sync: phase 2 done


    #=================================================================
    # PHASE 3: mcountinhibit stops cycle and instret counting
    #
    # 3a. Write a preset value to mcycle, read it back.
    # 3b. Set mcountinhibit[0] (CY bit) — inhibit cycle counting.
    #     Read mcycle twice; the two reads must be identical (no advance).
    #     Clear the inhibit.
    # 3c. Set mcountinhibit[2] (IR bit) — inhibit instret counting.
    #     Execute 5 ADDIs, sample minstret twice; delta must be 0.
    #     Clear the inhibit.
    #=================================================================

    # 3a: write preset value to mcycle
    li   t0, 0x12345600
    csrw MCYCLE, t0              # preset mcycle to known value

    csrr t0, MCYCLE              # read back immediately
    sw   t0, 0x10(s1)            # phase3_mcycle_preset
    lw   t3, 0x10(s1)            # fence: ensure SW AHB data phase completes

    # 3b: inhibit cycle counting — set bit[0] of mcountinhibit
    li   t0, 0x1
    csrrs x0, MCOUNTINHIBIT, t0  # set CY inhibit bit

    csrr t0, MCYCLE              # first read while inhibited
    sw   t0, 0x14(s1)            # phase3_inhibit_cycle (before)

    csrr t0, MCYCLE              # second read while inhibited
    sw   t0, 0x18(s1)            # phase3_inhibit_cycle2 (after)
    lw   t3, 0x18(s1)            # fence

    # clear CY inhibit
    li   t0, 0x1
    csrrc x0, MCOUNTINHIBIT, t0

    # 3c: inhibit instret counting — set bit[2] of mcountinhibit
    li   t0, 0x4
    csrrs x0, MCOUNTINHIBIT, t0  # set IR inhibit bit

    csrr t4, MINSTRET            # sample instret before (while inhibited)

    # 5 ADDI instructions (these must NOT be counted while inhibited)
    addi t2, x0, 1
    addi t2, t2, 1
    addi t2, t2, 1
    addi t2, t2, 1
    addi t2, t2, 1

    csrr t5, MINSTRET            # sample instret after (still inhibited)

    # clear IR inhibit
    li   t0, 0x4
    csrrc x0, MCOUNTINHIBIT, t0

    # Note: t4 and t5 are kept in registers; testbench checks via x29/x30
    # Store them to scratchpad for the check (reuse fields 0x14/0x18 for simplicity)
    # The testbench checks 0x14 == 0x18 (both reads equal while cycle inhibited),
    # and for instret inhibit the testbench uses register probes (t4=x28, t5=x29).

    li   x31, 0x33333333         # Sync: phase 3 done


    #=================================================================
    # PHASE 4: time and timeh read-only CSRs
    # Read time (0xC01) and timeh (0xC81), store to scratchpad.
    # The testbench drives a free-running mtime counter; by the time
    # phase 4 is reached many cycles have elapsed so time_lo != 0.
    #=================================================================

    csrr t0, TIME                # read time low word
    sw   t0, 0x1C(s1)            # phase4_time_lo

    csrr t0, TIMEH               # read time high word
    sw   t0, 0x20(s1)            # phase4_time_hi
    lw   t3, 0x20(s1)            # fence: ensure SW AHB data phase completes

    li   x31, 0x44444444         # Sync: phase 4 done


    #=================================================================
    # PHASE 5: cycle and instret read-only shadow CSRs
    # Read cycle (0xC00) and instret (0xC02), store to scratchpad.
    # These are read-only aliases of mcycle/minstret.
    #=================================================================

    csrr t0, CYCLE               # read cycle shadow
    sw   t0, 0x24(s1)            # phase5_cycle_lo

    csrr t0, INSTRET             # read instret shadow
    sw   t0, 0x28(s1)            # phase5_instret_lo

    csrr t0, CYCLEH              # read cycleh shadow (0xC80)
    sw   t0, 0x2C(s1)            # phase5_cycleh_lo

    csrr t0, INSTRETH            # read instreth shadow (0xC82)
    sw   t0, 0x30(s1)            # phase5_instreth_lo
    lw   t3, 0x30(s1)            # fence: ensure SW AHB data phase completes

    li   x31, 0x55555555         # Sync: phase 5 done


    #=================================================================
    # PHASE 6: mcounteren write/readback
    # mcounteren (0x306) controls U/S-mode access to cycle, time, instret.
    # Bits [2:0] = {IR, TM, CY}: 0x7 enables all three, 0x0 disables all.
    # Test: write 0x7, read back (expect 0x7); write 0x0, read back (expect 0x0).
    # Restore 0x7 at the end.
    #=================================================================

    li   t0, 0x7
    csrw MCOUNTEREN, t0              # write all 3 bits set
    csrr t0, MCOUNTEREN              # read back
    sw   t0, 0x34(s1)                # phase6_mcounteren_7
    lw   t3, 0x34(s1)                # AHB fence

    li   t0, 0x0
    csrw MCOUNTEREN, t0              # clear all bits
    csrr t0, MCOUNTEREN              # read back
    sw   t0, 0x38(s1)                # phase6_mcounteren_0
    lw   t3, 0x38(s1)                # AHB fence

    li   t0, 0x7
    csrw MCOUNTEREN, t0              # restore all bits

    li   x31, 0x66666666             # Sync: phase 6 done


    #=================================================================
    # PHASE 7: mcountinhibit[1] (TM bit) WARL — must always read 0
    # Write 0x7 (all three bits set) to mcountinhibit.
    # Readback must be 0x5 (bit 1 hardwired to 0 per spec).
    #=================================================================

    li   t0, 0x7
    csrw MCOUNTINHIBIT, t0           # attempt to set all 3 bits
    csrr t0, MCOUNTINHIBIT           # read back: TM (bit1) must be 0
    sw   t0, 0x3C(s1)                # phase7_mcountinhibit_warl (expect 0x5)
    lw   t3, 0x3C(s1)                # AHB fence

    li   t0, 0x0
    csrw MCOUNTINHIBIT, t0           # restore: clear all inhibit bits

    li   x31, 0x77777777             # Sync: phase 7 done


    #=================================================================
    # PHASE 8: mcounteren upper bits WARL — bits[31:11] must read 0
    # Write 0xFFFFFFFF to mcounteren; readback bits[31:11] must be 0
    # (unimplemented HPM counters above 10 are WARL hardwired to 0).
    #=================================================================

    li   t0, -1                      # 0xFFFFFFFF
    csrw MCOUNTEREN, t0              # attempt to set all 32 bits
    csrr t0, MCOUNTEREN              # read back: only bits [2:0] implemented
    sw   t0, 0x40(s1)                # phase8_mcounteren_warl (expect 0x7)
    lw   t3, 0x40(s1)                # AHB fence

    li   t0, 0x7
    csrw MCOUNTEREN, t0              # restore to 0x7

    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test
