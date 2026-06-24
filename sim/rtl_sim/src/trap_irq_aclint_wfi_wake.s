#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_aclint_wfi_wake
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ACLINT MTIMER -> WFI -> LF wake -> MTI trap
#   Exercises the always-on wake path that is the whole point of an
#   ACLINT:
#     1. Firmware programs MTIMECMP slightly ahead of MTIME.
#     2. Firmware enters WFI -> dut hclk_en drops -> hclk gates.
#     3. LF MTIME ticks on the always-on clk_lf. When mtime >= mtimecmp,
#        irq_m_timer_lf rises in the LF domain.
#     4. The aclint_mtimer_wake_lf signal -- driven by irq_m_timer_lf --
#        is OR'd into dut_hclk_en at the testbench top, so hclk un-gates
#        even though the CPU's own hclk_en_o is still low.
#     5. The hclk_aon-clocked 2-FF MTIP synchronizer propagates the LF
#        MTIP into irq_m_timer_o. The CPU sees MIP.MTIP and wakes from
#        WFI, taking the MTI trap.
#     6. Handler: on first fire it re-arms mtimecmp = mtime + 0x100; on
#        second fire it parks mtimecmp at all-ones. The re-arm tolerates
#        the early-MTI race under heavy wait states (sample-to-write
#        latency can eat the initial margin), so trap_count is 1 (no
#        race) or 2 (race observed and recovered) -- both pass.
#----------------------------------------------------------------------------

.section .text
.global main

.equ ACLINT_MTIMECMP_LO,  0x02004000
.equ ACLINT_MTIMECMP_HI,  0x02004004
.equ ACLINT_MTIME_LO,     0x02004008
.equ ACLINT_MTIME_HI,     0x0200400C

#=========================================================================
# SRAM scratchpad
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: mtime_snapshot_lo
#   0x0C: mtime_snapshot_hi
#=========================================================================

main:
    j _start

    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  12(sp)
    sw   t1,   8(sp)
    sw   t2,   4(sp)
    sw   t3,   0(sp)

    csrr t0, mcause

    lw   t1, 0x00(s1)
    addi t1, t1, 1
    sw   t1, 0x00(s1)
    sw   t0, 0x04(s1)

    # Only handle Machine Timer Interrupt (cause 0x80000007)
    li   t2, 0x80000007
    bne  t0, t2, handler_done

    # First fire (trap_count==1) -> rearm; later fires -> park at all-ones.
    li   t2, 1
    bne  t1, t2, mti_park

    # Race recovery: MTI fired before WFI could commit. Re-arm
    # mtimecmp = current_mtime + 0x10000 LF ticks (~1.3 ms at LF=50MHz)
    # so the timer fires again well after WFI commits, even with heavy
    # wait states stretching the handler+MRET path. Safe write order per
    # ACLINT spec: HI<-0xFFFFFFFF, LO<-new_lo, HI<-new_hi.
    li   t0, ACLINT_MTIMECMP_HI
    li   t1, 0xFFFFFFFF
    sw   t1, 0(t0)

    li   t0, ACLINT_MTIME_LO
    lw   t1, 0(t0)
    li   t0, ACLINT_MTIME_HI
    lw   t2, 0(t0)

    li   t3, 0x10000
    add  t3, t1, t3
    sltu t0, t3, t1
    add  t2, t2, t0

    li   t0, ACLINT_MTIMECMP_LO
    sw   t3, 0(t0)
    li   t0, ACLINT_MTIMECMP_HI
    sw   t2, 0(t0)
    j    handler_done

mti_park:
    # Final fire (post-WFI): park MTIMECMP at all-ones to drop MTIP.
    li   t0, ACLINT_MTIMECMP_HI
    li   t1, 0xFFFFFFFF
    sw   t1, 0(t0)
    li   t0, ACLINT_MTIMECMP_LO
    sw   t1, 0(t0)

handler_done:
    lw   t3,   0(sp)
    lw   t2,   4(sp)
    lw   t1,   8(sp)
    lw   t0,  12(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)

    la   t0, trap_handler
    csrw mtvec, t0

    # Sample MTIME (LO then HI)
    li   t0, ACLINT_MTIME_LO
    lw   t1, 0(t0)
    li   t0, ACLINT_MTIME_HI
    lw   t2, 0(t0)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    # MTIMECMP = mtime + 0x1000 LF ticks (~82 us at LF=50MHz). Sized to
    # cover WFI commit + advisory drain through the generic AHB
    # interconnect under heavy wait states, so the main osc has time to
    # gate before MTI fires. Heavier wait-state combos may still cause an
    # early-MTI race; the trap handler re-arms with a larger margin to
    # recover -- both paths exercise the wake correctly.
    li   t3, 0x1000
    add  t3, t1, t3
    sltu t4, t3, t1
    add  t4, t2, t4

    li   t0, ACLINT_MTIMECMP_LO
    sw   t3, 0(t0)
    li   t0, ACLINT_MTIMECMP_HI
    sw   t4, 0(t0)

    # Enable MIE.MTIE + MSTATUS.MIE
    li   t0, 0x080
    csrs mie, t0
    li   t0, 0x008
    csrs mstatus, t0

    li   x31, 0x11111111            # signal: programmed, about to WFI

    # Enter WFI sleep. The CPU's hclk_en_o drops; hclk gates at the SoC
    # ICG. mtime keeps ticking on the LF clock. When the LF comparator
    # fires, the wake aggregator un-gates hclk, the MTIP sync chain
    # propagates, and we take the trap below.
    wfi

    # If we got here, WFI returned (post-MRET in the handler).
    li   x31, 0x22222222            # signal: WFI returned

    # Confirm the trap was actually taken (handler bumped trap_count).
    # 1 = no race; 2 = race observed and recovered (see handler comment).
    lw   t4, 0x00(s1)
    li   t5, 1
    bltu t4, t5, fail
    li   t5, 3
    bgeu t4, t5, fail

    li   x31, 0xdeadbeef
    j end_of_test

fail:
    li   x31, 0xbadbad00
    j end_of_test

end_of_test:
    nop
    j end_of_test
