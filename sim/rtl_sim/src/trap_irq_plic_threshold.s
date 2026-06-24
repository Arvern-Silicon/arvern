#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_plic_threshold
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PLIC threshold-gating (M-mode context)
#   Per RISC-V PLIC 1.0 the threshold register on each context masks any
#   pending source whose priority is NOT STRICTLY GREATER than threshold.
#   Equality (priority == threshold) must NOT fire.
#
#   This test programs source 1 with priority 5 and walks the threshold
#   register through three values:
#     Phase 2: threshold = 5  -> priority == threshold -> NO trap
#     Phase 3: threshold = 7  -> priority <  threshold -> NO trap
#     Phase 4: threshold = 4  -> priority >  threshold -> trap fires
#
#   In Phases 2 & 3 the testbench keeps the source asserted for a generous
#   number of cycles to give a wrongly-fired IRQ plenty of time to be
#   observed; the firmware verifies trap_count has NOT incremented before
#   advancing.
#----------------------------------------------------------------------------

.section .text
.global main

# PLIC register addresses (M-mode context = ctx 0)
.equ PLIC_PRI_BASE,  0x0C000000
.equ PLIC_EN_M,      0x0C002000
.equ PLIC_TH_M,      0x0C200000
.equ PLIC_CLAIM_M,   0x0C200004

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x0C: last claimed source ID
#   0x80: TB drop-source signal
#=========================================================================

main:
    j _start

    .align 2
trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    sw   t0, 0x04(s1)

    # trap_count++
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    # Machine External only
    li   t3, 0x8000000B
    bne  t0, t3, handler_done

    # PLIC claim
    li   t3, PLIC_CLAIM_M
    lw   t4, 0(t3)
    sw   t4, 0x0C(s1)

    # Tell TB to drop the source line
    sw   t4, 0x80(s1)

    # Let TB drop the level
    li   t2, 100
plic_drop_wait:
    addi t2, t2, -1
    bnez t2, plic_drop_wait

    # Complete
    li   t3, PLIC_CLAIM_M
    sw   t4, 0(t3)

    sw   zero, 0x80(s1)

handler_done:
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
    mret


_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x80(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    #---------------------------------------------------------------
    # PHASE 1: configure PLIC
    #   priority[1] = 5, enable[ctx0][word0] = bit 1, threshold = 5
    #   (threshold = priority -> blocked)
    #---------------------------------------------------------------
    li   t0, 5
    li   t1, PLIC_PRI_BASE + 4*1
    sw   t0, 0(t1)

    li   t0, 0x00000002             # enable source 1
    li   t1, PLIC_EN_M
    sw   t0, 0(t1)

    li   t0, 5                      # threshold = priority -> must block
    li   t1, PLIC_TH_M
    sw   t0, 0(t1)

    # Enable MIE.MEIE + MSTATUS.MIE
    li   t0, 0x800
    csrs mie, t0
    li   t0, 0x8
    csrs mstatus, t0

    li   x31, 0x11111111            # signal: PLIC configured


    #---------------------------------------------------------------
    # PHASE 2: threshold == priority -> NO trap
    #   Wait for testbench to drive plic_irq_src[1] for ~600 cycles.
    #   When testbench advances x31, verify trap_count is still 0.
    #---------------------------------------------------------------
    li   x31, 0x21212121            # tell TB: assert src 1 now

phase2_settle:
    lw   t0, 0x00(s1)
    bnez t0, phase2_unexpected
    # Wait for TB to release us
    li   t2, 700
phase2_delay:
    addi t2, t2, -1
    bnez t2, phase2_delay

    lw   t0, 0x00(s1)
    bnez t0, phase2_unexpected

    li   x31, 0x22222222            # phase 2 done; trap_count is still 0
    j    phase3_setup

phase2_unexpected:
    li   x31, 0xBADBAD02            # unexpected trap during phase 2
    j    end_of_test


    #---------------------------------------------------------------
    # PHASE 3: threshold > priority -> NO trap
    #   threshold = 7 (still strictly greater than source priority 5).
    #---------------------------------------------------------------
phase3_setup:
    li   t0, 7
    li   t1, PLIC_TH_M
    sw   t0, 0(t1)

    li   x31, 0x31313131            # tell TB: assert src 1 again

    li   t2, 700
phase3_delay:
    addi t2, t2, -1
    bnez t2, phase3_delay

    lw   t0, 0x00(s1)
    bnez t0, phase3_unexpected

    li   x31, 0x33333333            # phase 3 done; trap_count still 0
    j    phase4_setup

phase3_unexpected:
    li   x31, 0xBADBAD03
    j    end_of_test


    #---------------------------------------------------------------
    # PHASE 4: threshold < priority -> trap fires
    #   threshold = 4 (priority 5 > 4 -> should fire). The PLIC gateway
    #   still has pending[1]=1 from phase 3 (gateway latch survives the
    #   level drop), so lowering the threshold immediately unmasks the
    #   pending source and the trap fires. The testbench does NOT need
    #   to re-assert plic_irq_src[1].
    #---------------------------------------------------------------
phase4_setup:
    li   t0, 4
    li   t1, PLIC_TH_M
    sw   t0, 0(t1)

    li   x31, 0x41414141            # signal: threshold lowered, expect trap

    # Wait until the handler bumps trap_count (>=1). Using beqz makes the
    # poll robust against any stray follow-up trap incrementing past 1.
phase4_wait:
    lw   t0, 0x00(s1)
    beqz t0, phase4_wait

    li   x31, 0x44444444


end_of_test:
    j    end_of_test
