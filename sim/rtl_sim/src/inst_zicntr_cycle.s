#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_cycle
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZICNTR CYCLE
#   Zicntr mcycle/cycleh CSR deep verification:
#   - mcycle write/readback (preset >= written value)
#   - mcycleh write/readback (exact match)
#   - mcountinhibit[0] (CY bit) freezes mcycle: two reads identical
#   - cycle (0xC00) shadow == mcycle while inhibited (same window)
#   - WFI: cycle counter advances while processor waits for interrupt
#   - 64-bit carry: mcycle lo-to-hi carry propagation
#
#   No random IRQ injection (no_random_irq test).
#
#   Scratchpad layout (base 0x80000000):
#   0x00: phase1_preset_rb     — mcycle readback after writing 0xDEAD1000
#   0x04: phase2_cycleh_rb     — mcycleh readback after writing 0xABCD0000
#   0x08: phase3_inhibit_rd1   — mcycle first read while CY inhibited
#   0x0C: phase3_inhibit_rd2   — mcycle second read while CY inhibited
#   0x10: phase4_cycle_shadow  — cycle (0xC00) read while CY inhibited
#   0x14: phase4_mcycle_direct — mcycle (0xB00) read while CY inhibited
#   0x18: phase5_cycle_before  — mcycle before WFI
#   0x1C: phase5_cycle_after   — mcycle after WFI returns
#   0x20: phase6_carry_lo      — mcycle lo after carry (expect wrapped < 0xFFFFFFFE)
#   0x24: phase6_carry_hi      — mcycle hi after carry (expect 0x12345679)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCYCLE,         0xB00
.equ MCYCLEH,        0xB80
.equ MCOUNTINHIBIT,  0x320
.equ CYCLE,          0xC00
.equ CYCLEH,         0xC80
.equ MTVEC,          0x305
.equ MIE,            0x304
.equ MSTATUS,        0x300

main:
    j    _start

    .align 2
wfi_irq_handler:
    mret

_start:
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
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)

    #=================================================================
    # PHASE 1: mcycle write/readback
    # Write 0xDEAD1000 to mcycle, then read it back immediately.
    # The readback may be >= the written value (counter keeps running).
    #=================================================================

    li   t0, 0xDEAD1000
    csrw MCYCLE, t0              # preset mcycle

    csrr t0, MCYCLE              # read back immediately
    sw   t0, 0x00(s1)            # phase1_preset_rb
    lw   t3, 0x00(s1)            # AHB fence

    li   x31, 0x11111111         # Sync: phase 1 done


    #=================================================================
    # PHASE 2: mcycleh write/readback
    # Write 0xABCD0000 to mcycleh, then read it back.
    # Readback must match exactly (high word does not self-increment
    # unless low word wraps, which will not happen in this window).
    #=================================================================

    li   t0, 0xABCD0000
    csrw MCYCLEH, t0             # preset mcycleh

    csrr t0, MCYCLEH             # read back
    sw   t0, 0x04(s1)            # phase2_cycleh_rb
    lw   t3, 0x04(s1)            # AHB fence

    li   x31, 0x22222222         # Sync: phase 2 done


    #=================================================================
    # PHASE 3: mcountinhibit[0] (CY bit) freezes mcycle
    # Set CY bit, read mcycle twice; both reads must be identical.
    # Then clear CY bit.
    #=================================================================

    li   t0, 1
    csrrs x0, MCOUNTINHIBIT, t0  # set CY inhibit bit

    csrr t0, MCYCLE              # first read while inhibited
    sw   t0, 0x08(s1)            # phase3_inhibit_rd1

    csrr t0, MCYCLE              # second read while inhibited
    sw   t0, 0x0C(s1)            # phase3_inhibit_rd2
    lw   t3, 0x0C(s1)            # AHB fence

    li   t0, 1
    csrrc x0, MCOUNTINHIBIT, t0  # clear CY inhibit bit

    li   x31, 0x33333333         # Sync: phase 3 done


    #=================================================================
    # PHASE 4: cycle shadow (0xC00) == mcycle while CY inhibited
    # Set CY inhibit, read cycle (shadow) and mcycle (direct) in the
    # same inhibit window; both must be equal.
    # Then clear CY inhibit.
    #=================================================================

    li   t0, 1
    csrrs x0, MCOUNTINHIBIT, t0  # set CY inhibit bit

    csrr t0, CYCLE               # read cycle shadow (0xC00)
    sw   t0, 0x10(s1)            # phase4_cycle_shadow

    csrr t0, MCYCLE              # read mcycle direct (0xB00)
    sw   t0, 0x14(s1)            # phase4_mcycle_direct
    lw   t3, 0x14(s1)            # AHB fence

    li   t0, 1
    csrrc x0, MCOUNTINHIBIT, t0  # clear CY inhibit bit

    li   x31, 0x44444444         # Sync: phase 4 done


    #=================================================================
    # PHASE 5: WFI — cycle counter advances while processor waits
    # Install a minimal IRQ handler (just mret), enable timer IRQ,
    # enable global interrupts, sample mcycle, execute WFI, sample
    # mcycle again after returning from handler.
    # The testbench asserts irq_m_timer after seeing sync 0x55555555.
    #=================================================================

    # Install WFI IRQ handler
    la   t0, wfi_irq_handler
    csrw MTVEC, t0

    # Enable timer IRQ (MTIE = bit 7 of mie)
    li   t0, 0x80
    csrw MIE, t0

    # Enable global interrupts (MIE = bit 3 of mstatus)
    li   t0, 8
    csrs MSTATUS, t0

    # Sample mcycle before WFI
    csrr t0, MCYCLE
    sw   t0, 0x18(s1)            # phase5_cycle_before
    lw   t3, 0x18(s1)            # AHB fence

    li   x31, 0x55555555         # Sync: about to execute WFI

    .word 0x10500073             # WFI instruction

    # After WFI returns (timer IRQ fired, handler ran mret):
    # Disable global interrupts
    li   t0, 8
    csrc MSTATUS, t0

    # Sample mcycle after WFI
    csrr t0, MCYCLE
    sw   t0, 0x1C(s1)            # phase5_cycle_after
    lw   t3, 0x1C(s1)            # AHB fence

    li   x31, 0x66666666         # Sync: phase 5 done


    #=================================================================
    # PHASE 6: 64-bit carry — mcycle lo-to-hi carry propagation
    # Set CY inhibit, preset lo=0xFFFFFFFE and hi=0x12345678.
    # Clear inhibit: counter resumes from 0xFFFFFFFE.
    # After 2 cycles mcycle_lo wraps and mcycle_hi increments once.
    # Run 10 ADDIs (well above the 2-cycle threshold) then re-inhibit.
    # Expected: carry_hi == 0x12345679 (exactly one carry into hi).
    #=================================================================

    li   t0, 1
    csrrs x0, MCOUNTINHIBIT, t0  # set CY inhibit
    li   t0, 0xFFFFFFFE
    csrw MCYCLE, t0              # preset lo = 0xFFFFFFFE
    li   t0, 0x12345678
    csrw MCYCLEH, t0             # preset hi = 0x12345678
    li   t0, 1
    csrrc x0, MCOUNTINHIBIT, t0  # clear CY inhibit — counter resumes from 0xFFFFFFFE

    # Run 10 ADDIs to ensure overflow (only 2 cycles needed for carry)
    addi t2, x0,  1
    addi t2, t2,  1
    addi t2, t2,  1
    addi t2, t2,  1
    addi t2, t2,  1
    addi t2, t2,  1
    addi t2, t2,  1
    addi t2, t2,  1
    addi t2, t2,  1
    addi t2, t2,  1

    li   t0, 1
    csrrs x0, MCOUNTINHIBIT, t0  # set CY inhibit — freeze counter
    csrr t0, MCYCLE              # read lo (confirm overflow: lo < 0xFFFFFFFE)
    sw   t0, 0x20(s1)            # phase6_carry_lo
    csrr t0, MCYCLEH             # read hi (expect exactly 0x12345679)
    sw   t0, 0x24(s1)            # phase6_carry_hi
    lw   t3, 0x24(s1)            # AHB fence
    li   t0, 1
    csrrc x0, MCOUNTINHIBIT, t0  # clear inhibit

    li   x31, 0xdeadbeef         # Sync: all done

end_of_test:
    j    end_of_test
