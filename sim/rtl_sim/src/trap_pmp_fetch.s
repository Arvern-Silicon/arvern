#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_fetch
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP fetch checker
#   Machine mode throughout:
#     - a LOCKED rule without X denies instruction fetch: MCAUSE=1, and both
#       MEPC and MTVAL name the address that could not be fetched
#     - the fetch is SUPPRESSED, not performed and reported, so the protected
#       region needs no valid code in it -- nothing is ever read from there
#     - the same rule still grants R: a load from the address whose fetch was
#       refused succeeds, which separates "no execute" from "no access"
#
#   The handler cannot resume with MEPC+4: the faulting PC is an address whose
#   instruction was never fetched. It restores MEPC from s10 instead, which each
#   phase points at its own recovery label.
#
# Requires PMP_NR > 0 (pmpcfg/pmpaddr raise illegal-instruction otherwise).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#   0x000: trap count
#   0x004: last MCAUSE
#   0x008: last MEPC
#   0x00C: last MTVAL
#
#   0x300: the protected region -- a fetch target, never a data target
#=========================================================================

.equ TARGET, 0x80000300

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mtval

    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Resume at the recovery label this phase armed.
    csrw mepc, s10

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

#=========================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    la   t0, m_trap_handler
    csrw mtvec, t0

    # Arm NMIE first, then clear MDT. Either one left unset makes every M-mode
    # trap "unexpected", which diverts it away from mtvec.
    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw mstatush, x0           # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    li   s4, TARGET

    li   t0, 0xC0DE0000         # seed, while the region is still unprotected
    sw   t0, 0(s4)

    #=================================================================
    # PHASE 1 -- a LOCKED rule without X denies the fetch
    #
    # Entry 0 covers the target with R=1, W=0, X=0 and L=1. Reads are
    # permitted; executing from it is not.
    #=================================================================
    srli t0, s4, 2
    ori  t0, t0, 1              # NAPOT, 16 bytes
    csrw pmpaddr0, t0
    li   t0, 0x99               # L | A=NAPOT | R
    csrw pmpcfg0, t0

    la   s10, p1_recover        # where the handler resumes
    jalr x0, s4, 0              # denied -- nothing is fetched from TARGET

p1_recover:
    lw   a0, 0x04(s1)           # MCAUSE -- expect 1
    lw   a1, 0x08(s1)           # MEPC   -- expect TARGET
    lw   a2, 0x0C(s1)           # MTVAL  -- expect TARGET
    addi t0, a2, 0              # consume the load: hold the sync until it retires

    li   x31, 0x11111111

    #=================================================================
    # PHASE 2 -- the region is still READABLE
    #
    # The rule grants R, so a load from the very address whose fetch was
    # refused must succeed. This separates "no execute" from "no access".
    #=================================================================
    la   s10, p2_recover        # armed BEFORE the faulting access
    li   t0, 0x5A5A0000
    sw   t0, 0(s4)              # denied -- entry 0 grants R only
p2_recover:
    lw   a3, 0x04(s1)           # MCAUSE -- expect 7 (store access fault)
    lw   a4, 0(s4)              # allowed by R -- expect the seed, not 0x5A5A0000

    lw   a5, 0x00(s1)           # trap count -- expect 2
    addi t0, a5, 0              # consume the load: hold the sync until it retires

    li   x31, 0x22222222

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
1:  j    1b
