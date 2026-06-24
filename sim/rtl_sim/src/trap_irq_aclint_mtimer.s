#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_aclint_mtimer
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ACLINT MTIMER end-to-end (MTIP via MTIMECMP)
#   - Firmware reads MTIME (LO-then-HI atomic-snapshot contract)
#   - Firmware programs MTIMECMP = mtime + delta
#   - LF comparator fires when mtime >= mtimecmp
#   - irq_m_timer_o propagates through hclk_aon synchronizer
#   - Core takes MTI trap (mcause = 0x80000007)
#   - Handler parks MTIMECMP at all-ones to clear MTIP and MRETs
#
#   ACLINT address map (SiFive CLINT-compatible base = 0x02000000):
#     MTIMECMP_LO[0] = 0x02004000
#     MTIMECMP_HI[0] = 0x02004004
#     MTIME_LO       = 0x02004008
#     MTIME_HI       = 0x0200400C
#
#   AHB-read protocol: firmware MUST read MTIME_LO first (triggers the
#   atomic snapshot), then MTIME_HI (returns the buffered upper half).
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
#   0x08: mtime_snapshot_lo (taken in main, used to compute MTIMECMP)
#   0x0C: mtime_snapshot_hi
#=========================================================================

main:
    j _start

    #=====================================================================
    # TRAP HANDLER (M-mode MTI path)
    #=====================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  12(sp)
    sw   t1,   8(sp)
    sw   t2,   4(sp)

    csrr t0, mcause
    csrr t1, mepc

    # trap_count++
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    sw   t0, 0x04(s1)               # last MCAUSE

    # Only handle Machine Timer Interrupt (cause 0x80000007)
    li   t2, 0x80000007
    bne  t0, t2, handler_done

    # Park MTIMECMP at all-ones to drop MTIP. Per the spec, writing
    # MTIMECMP_HI = 0xFFFFFFFF first guards against a transient match
    # while crossing the 32-bit boundary.
    li   t0, ACLINT_MTIMECMP_HI
    li   t1, 0xFFFFFFFF
    sw   t1, 0(t0)
    li   t0, ACLINT_MTIMECMP_LO
    sw   t1, 0(t0)

handler_done:
    lw   t2,   4(sp)
    lw   t1,   8(sp)
    lw   t0,  12(sp)
    addi sp, sp, 16
    mret


    #=====================================================================
    # MAIN
    #=====================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Read current MTIME (LO first, then HI — atomic-snapshot contract)
    li   t0, ACLINT_MTIME_LO
    lw   t1, 0(t0)                  # mtime_lo (also triggers snapshot)
    li   t0, ACLINT_MTIME_HI
    lw   t2, 0(t0)                  # mtime_hi (from buffered shadow)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    # MTIMECMP = mtime + 0x80 (128 LF ticks ahead)
    addi t3, t1, 0x80
    sltu t4, t3, t1                 # carry out of LO
    add  t4, t2, t4                 # mtimecmp_hi = mtime_hi + carry

    # Write MTIMECMP: spec convention says HI=all-ones first, then LO,
    # then HI to final value (to avoid a transient match while
    # crossing the 32-bit boundary). For our small delta the HI half
    # doesn't change, so write LO then HI in order.
    li   t0, ACLINT_MTIMECMP_LO
    sw   t3, 0(t0)
    li   t0, ACLINT_MTIMECMP_HI
    sw   t4, 0(t0)

    # Enable MIE.MTIE (bit 7) + MSTATUS.MIE
    li   t0, 0x080
    csrs mie, t0
    li   t0, 0x008
    csrs mstatus, t0

    li   x31, 0x11111111            # signal: ACLINT MTIMER configured

    # Spin until handler bumps trap_count
wait_mti:
    lw   t4, 0x00(s1)
    beqz t4, wait_mti

    li   x31, 0xdeadbeef
    j end_of_test

end_of_test:
    nop
    j end_of_test
