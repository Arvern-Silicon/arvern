#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_instret
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZICNTR INSTRET
#   Zicntr minstret/instreth CSR deep verification:
#   - minstret write/readback (preset >= written value)
#   - minstreth write/readback (exact match)
#   - mcountinhibit[2] (IR bit) freezes minstret: two reads identical
#   - instret (0xC02) shadow == minstret while inhibited (same window)
#   - Exact instruction count in inhibit-gated window (5 ADDIs -> 7 total)
#   - Hazard count: load-use stalls, branch loops, CSR hazards (-> 16 total)
#   - WFI counts as exactly 1 instruction in minstret (-> 3 total in window)
#   - 64-bit carry: minstret lo-to-hi carry propagation
#
#   No random IRQ injection (no_random_irq test).
#
#   Inhibit-gated window protocol:
#   ENTER: li t0,4; csrrs x0,MCOUNTINHIBIT,t0  <- counts (1,2)
#   csrw MINSTRET,x0  <- does NOT count (inhibit active)
#   li t0,4; csrrc x0,MCOUNTINHIBIT,t0  <- does NOT count
#   minstret=0, counting ON from next instruction
#   EXIT:  li t0,4           <- counts (n-1)
#   csrrs x0,MCOUNTINHIBIT,t0  <- counts (n); inhibit from next
#   csrr t0,MINSTRET   <- reads n (frozen, does NOT count)
#
#   Scratchpad layout (base 0x80000000):
#   0x00: phase1_preset_rb    — minstret readback after writing 0xBEEF0000
#   0x04: phase2_instreth_rb  — minstreth readback after writing 0xCAFE0000
#   0x08: phase3_inhibit_rd1  — minstret first read while IR inhibited
#   0x0C: phase3_inhibit_rd2  — minstret second read while IR inhibited
#   0x10: phase4_shadow       — instret (0xC02) read while IR inhibited
#   0x14: phase4_direct       — minstret (0xB02) read while IR inhibited
#   0x18: phase5_exact_count  — minstret after exact-count window (=7)
#   0x1C: phase6_hazard_count — minstret after hazard-count window (=16)
#   0x20: phase7_wfi_count    — minstret after WFI window (=3)
#   0x24: phase8_carry_lo     — minstret lo after carry (expect 0x0000000A)
#   0x28: phase8_carry_hi     — minstret hi after carry (expect 0xABCD5679)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MINSTRET,       0xB02
.equ MINSTRETH,      0xB82
.equ MCOUNTINHIBIT,  0x320
.equ INSTRET,        0xC02
.equ INSTRETH,       0xC82

main:
    li   sp, 0x80010000
    li   s1, 0x80000000          # Scratchpad base
    # DO NOT call _random_irq_init (no_random_irq test)

    # Zero the scratchpad (11 words)
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

    #=================================================================
    # PHASE 1: minstret write/readback
    # Write 0xBEEF0000, read back immediately.
    # Readback must be >= written value (counter keeps running).
    #=================================================================

    li   t0, 0xBEEF0000
    csrw MINSTRET, t0            # preset minstret

    csrr t0, MINSTRET            # read back immediately
    sw   t0, 0x00(s1)            # phase1_preset_rb
    lw   t3, 0x00(s1)            # AHB fence

    li   x31, 0x11111111         # Sync: phase 1 done


    #=================================================================
    # PHASE 2: minstreth write/readback
    # Write 0xCAFE0000 to minstreth, read back.
    # Readback must match exactly (high word does not self-increment
    # unless low word wraps, which will not happen in this window).
    #=================================================================

    li   t0, 0xCAFE0000
    csrw MINSTRETH, t0           # preset minstreth

    csrr t0, MINSTRETH           # read back
    sw   t0, 0x04(s1)            # phase2_instreth_rb
    lw   t3, 0x04(s1)            # AHB fence

    li   x31, 0x22222222         # Sync: phase 2 done


    #=================================================================
    # PHASE 3: mcountinhibit[2] (IR bit) freezes minstret
    # Set IR bit, read minstret twice; both reads must be identical.
    # Then clear IR bit.
    #=================================================================

    li   t0, 4
    csrrs x0, MCOUNTINHIBIT, t0  # set IR inhibit bit

    csrr t0, MINSTRET            # first read while inhibited
    sw   t0, 0x08(s1)            # phase3_inhibit_rd1

    csrr t0, MINSTRET            # second read while inhibited
    sw   t0, 0x0C(s1)            # phase3_inhibit_rd2
    lw   t3, 0x0C(s1)            # AHB fence

    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clear IR inhibit bit

    li   x31, 0x33333333         # Sync: phase 3 done


    #=================================================================
    # PHASE 4: instret shadow (0xC02) == minstret while IR inhibited
    # Set IR inhibit, read instret (shadow) and minstret (direct) in
    # the same inhibit window; both must be equal.
    # Then clear IR inhibit.
    #=================================================================

    li   t0, 4
    csrrs x0, MCOUNTINHIBIT, t0  # set IR inhibit bit

    csrr t0, INSTRET             # read instret shadow (0xC02)
    sw   t0, 0x10(s1)            # phase4_shadow

    csrr t0, MINSTRET            # read minstret direct (0xB02)
    sw   t0, 0x14(s1)            # phase4_direct
    lw   t3, 0x14(s1)            # AHB fence

    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clear IR inhibit bit

    li   x31, 0x44444444         # Sync: phase 4 done


    #=================================================================
    # PHASE 5: EXACT instruction count in inhibit-gated window
    #
    # ENTER inhibit window (preset minstret to 0):
    #   li t0,4         <- counts (external, not in window)
    #   csrrs           <- counts; inhibit activates from next
    #   csrw MINSTRET   <- does NOT count (inhibit active)
    #   li t0,4         <- does NOT count
    #   csrrc           <- does NOT count; clears inhibit
    # minstret=0, counting ON from next instruction
    #
    # WINDOW (7 instructions counted):
    #   addi t2,x0,1    <- count=1
    #   addi t2,t2,1    <- count=2
    #   addi t2,t2,1    <- count=3
    #   addi t2,t2,1    <- count=4
    #   addi t2,t2,1    <- count=5
    #   li t0,4         <- count=6
    #   csrrs           <- count=7; inhibit activates from next
    #
    # EXIT (inhibit now active; reads frozen minstret=7):
    #   csrr t0,MINSTRET <- reads 7 (does NOT count)
    #   sw + fence        <- does NOT count
    #   li t0,4           <- does NOT count
    #   csrrc             <- does NOT count; clears inhibit
    #
    # Expected: 0x18 = 7
    #=================================================================

    # ENTER inhibit window
    li   t0, 4
    csrrs x0, MCOUNTINHIBIT, t0  # counts; inhibit from next
    csrw MINSTRET, x0            # preset minstret to 0 (does NOT count)
    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clears inhibit (does NOT count)
    # minstret = 0, counting ON

    # WINDOW: 5 ADDI instructions (count 1..5)
    addi t2, x0,  1              # count=1
    addi t2, t2,  1              # count=2
    addi t2, t2,  1              # count=3
    addi t2, t2,  1              # count=4
    addi t2, t2,  1              # count=5

    # EXIT inhibit window
    li   t0, 4                   # count=6
    csrrs x0, MCOUNTINHIBIT, t0  # count=7; inhibit from next
    csrr t0, MINSTRET            # reads 7 (frozen, does NOT count)
    sw   t0, 0x18(s1)            # phase5_exact_count (does NOT count)
    lw   t3, 0x18(s1)            # AHB fence (does NOT count)
    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clears inhibit

    li   x31, 0x55555555         # Sync: phase 5 done


    #=================================================================
    # PHASE 6: HAZARD instruction count in inhibit-gated window
    #
    # minstret counts retired instructions regardless of stalls.
    # Load-use hazards, branch mispredictions, and CSR hazards each
    # still retire exactly one instruction.
    #
    # WINDOW (16 instructions counted):
    #
    #   Load-use hazard pair 1:
    #   sw   x0,0x00(s1)    <- count=1
    #   lw   t4,0x00(s1)    <- count=2
    #   add  t5,t4,t4       <- count=3  (uses t4 immediately: load-use stall)
    #
    #   Load-use hazard pair 2:
    #   lw   t4,0x00(s1)    <- count=4
    #   sub  t5,t4,t5       <- count=5  (uses t4 immediately: load-use stall)
    #
    #   Branch loop (li + 3 iterations of addi+bne):
    #   li   t4,3           <- count=6
    #   addi t4,t4,-1       <- count=7   (iter 1, t4=2)
    #   bne  t4,x0,loop     <- count=8   (taken)
    #   addi t4,t4,-1       <- count=9   (iter 2, t4=1)
    #   bne  t4,x0,loop     <- count=10  (taken)
    #   addi t4,t4,-1       <- count=11  (iter 3, t4=0)
    #   bne  t4,x0,loop     <- count=12  (not taken)
    #
    #   CSR-use hazard:
    #   csrr t4,MINSTRET    <- count=13  (reads current count=12)
    #   add  t5,t4,t4       <- count=14  (uses t4 immediately: CSR hazard)
    #
    #   EXIT:
    #   li   t0,4           <- count=15
    #   csrrs ...           <- count=16; inhibit from next
    #
    # Expected: 0x1C = 16
    #=================================================================

    # ENTER inhibit window
    li   t0, 4
    csrrs x0, MCOUNTINHIBIT, t0  # counts; inhibit from next
    csrw MINSTRET, x0            # preset minstret to 0 (does NOT count)
    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clears inhibit (does NOT count)
    # minstret = 0, counting ON

    # Load-use hazard pair 1
    sw   x0, 0x00(s1)            # count=1 (write 0 to scratchpad)
    lw   t4, 0x00(s1)            # count=2
    add  t5, t4, t4              # count=3 (load-use hazard: stall but still retires)

    # Load-use hazard pair 2
    lw   t4, 0x00(s1)            # count=4
    sub  t5, t4, t5              # count=5 (load-use hazard: stall but still retires)

    # Branch loop: 3 iterations (li + addi + bne * 3)
    li   t4, 3                   # count=6
phase6_bne_loop:
    addi t4, t4, -1              # count=7,9,11
    bne  t4, x0, phase6_bne_loop # count=8,10,12 (taken 2x, then not-taken)

    # CSR-use hazard
    csrr t4, MINSTRET            # count=13 (reads current value=12)
    add  t5, t4, t4              # count=14 (uses t4 immediately)

    # EXIT inhibit window
    li   t0, 4                   # count=15
    csrrs x0, MCOUNTINHIBIT, t0  # count=16; inhibit from next
    csrr t0, MINSTRET            # reads 16 (frozen, does NOT count)
    sw   t0, 0x1C(s1)            # phase6_hazard_count (does NOT count)
    lw   t3, 0x1C(s1)            # AHB fence (does NOT count)
    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clears inhibit

    li   x31, 0x66666666         # Sync: phase 6 done


    #=================================================================
    # PHASE 7: WFI counts as exactly 1 instruction
    #
    # mie.MTIE is set so WFI can wake on irq_m_timer (hardware requires
    # mip & mie != 0 for wakeup). mstatus.MIE remains 0, so no ISR
    # is taken — execution simply resumes after WFI.
    # Testbench asserts irq_m_timer after seeing sync 0x77777777 and
    # keeps it asserted until 0xdeadbeef.
    #
    # WINDOW (3 instructions counted):
    #   WFI (.word 0x10500073)   <- count=1 (wakes on irq_m_timer, MIE=0)
    #   li   t0,4                <- count=2
    #   csrrs ...                <- count=3; inhibit from next
    #
    # Expected: 0x20 = 3
    #=================================================================

    # Enable timer interrupt in mie so WFI can wake on irq_m_timer.
    # mstatus.MIE remains 0, so no ISR will actually be taken.
    li   t0, 0x80                # mie.MTIE bit
    csrrs x0, mie, t0            # set MTIE

    li   x31, 0x77777777         # Sync: testbench should assert irq_m_timer now

    # ENTER inhibit window
    li   t0, 4
    csrrs x0, MCOUNTINHIBIT, t0  # counts; inhibit from next
    csrw MINSTRET, x0            # preset minstret to 0 (does NOT count)
    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clears inhibit (does NOT count)
    # minstret = 0, counting ON

    # WINDOW: WFI (mie.MTIE=1, mstatus.MIE=0 — wakes on irq_m_timer but no ISR taken)
    .word 0x10500073             # WFI — count=1

    # EXIT inhibit window
    li   t0, 4                   # count=2
    csrrs x0, MCOUNTINHIBIT, t0  # count=3; inhibit from next
    csrr t0, MINSTRET            # reads 3 (frozen, does NOT count)
    sw   t0, 0x20(s1)            # phase7_wfi_count (does NOT count)
    lw   t3, 0x20(s1)            # AHB fence (does NOT count)
    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clears inhibit

    # Clear mie.MTIE
    li   t0, 0x80
    csrrc x0, mie, t0            # clear MTIE

    li   x31, 0x88888888         # Sync: phase 7 done


    #=================================================================
    # PHASE 8: 64-bit carry — minstret lo-to-hi carry propagation
    # Set IR inhibit, preset minstret_lo=0xFFFFFFFE, minstret_hi=0xABCD5678.
    # Clear inhibit: counting resumes. minstret_lo reaches 0 after 2 retirements,
    # carrying into minstret_hi (→ 0xABCD5679).
    # Run 10 ADDIs + 1 li + 1 csrrs = 13 total retirements; re-inhibit; read back.
    # Since this is a no_random_irq test with no random wait states on minstret,
    # the exact lo value is 0x0000000A (0xFFFFFFFE + 12 with overflow at +2).
    #=================================================================

    li   t0, 4
    csrrs x0, MCOUNTINHIBIT, t0  # set IR inhibit
    li   t0, 0xFFFFFFFE
    csrw MINSTRET, t0            # preset lo = 0xFFFFFFFE (2 retirements to carry)
    li   t0, 0xABCD5678
    csrw MINSTRETH, t0           # preset hi = 0xABCD5678
    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clear IR inhibit — counting resumes

    # Retire 10 ADDIs (only 2 retirements needed for carry; 13 total follow)
    addi t2, x0,  1              # retirement 1 → lo=0xFFFFFFFF
    addi t2, t2,  1              # retirement 2 → lo wraps to 0, hi=0xABCD5679
    addi t2, t2,  1              # retirement 3
    addi t2, t2,  1              # retirement 4
    addi t2, t2,  1              # retirement 5
    addi t2, t2,  1              # retirement 6
    addi t2, t2,  1              # retirement 7
    addi t2, t2,  1              # retirement 8
    addi t2, t2,  1              # retirement 9
    addi t2, t2,  1              # retirement 10

    li   t0, 4                   # retirement 11
    csrrs x0, MCOUNTINHIBIT, t0  # retirement 12 (last to count); inhibit from next
    csrr t0, MINSTRET            # reads frozen lo = 0xFFFFFFFE + 12 = 0x0000000A
    sw   t0, 0x24(s1)            # phase8_carry_lo
    csrr t0, MINSTRETH           # reads frozen hi = 0xABCD5679
    sw   t0, 0x28(s1)            # phase8_carry_hi
    lw   t3, 0x28(s1)            # AHB fence
    li   t0, 4
    csrrc x0, MCOUNTINHIBIT, t0  # clear inhibit

    li   x31, 0xdeadbeef         # Sync: all done

end_of_test:
    j    end_of_test
