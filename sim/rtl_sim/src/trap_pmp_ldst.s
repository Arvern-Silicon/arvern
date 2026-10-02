#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_ldst
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP load/store checker
#   Machine mode throughout, so the subject is the rule itself rather than the
#   privilege drop:
#     - an UNLOCKED rule does not bind M-mode, even with no permissions
#     - a LOCKED rule does bind M-mode: store -> MCAUSE=7, load -> MCAUSE=5
#     - MTVAL carries the faulting data address
#     - a denied store leaves memory UNCHANGED, i.e. the access is suppressed
#       rather than performed and reported
#     - a locked read-only rule permits the load and refuses the store
#
#   Entries are installed lowest-last so no locked rule is ever rewritten: once
#   pmpcfg.L is set it is read-only until reset while mseccfg.RLB is clear.
#
#   The faulting accesses use t0 with s4/s5/s6 as base. Neither register is in
#   x8-x15, so the assembler cannot emit a compressed form and the handler's
#   uniform MEPC+4 skip is exact.
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
# Protected regions, 16-byte NAPOT each, clear of the handler area and stack:
#   0x200: region A -- unlocked, no permissions
#   0x210: region B -- locked,   no permissions
#   0x220: region C -- locked,   read-only
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -16
    sw   t1, 12(sp)
    sw   t2,  8(sp)
    sw   t3,  4(sp)
    sw   t0,  0(sp)             # preserved: a denied load's destination is inspected

    csrr t1, mcause
    csrr t2, mepc
    csrr t3, mtval

    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    sw   t1, 0x04(s1)
    sw   t2, 0x08(s1)
    sw   t3, 0x0C(s1)

    # Every fault here is a 32-bit load or store: resume past it.
    addi t2, t2, 4
    csrw mepc, t2

    lw   t0,  0(sp)
    lw   t3,  4(sp)
    lw   t2,  8(sp)
    lw   t1, 12(sp)
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
    csrci mstatus, 8            # MIE=0 -- no IRQ may perturb the trap records

    li   s4, 0x80000200         # region A
    li   s5, 0x80000210         # region B
    li   s6, 0x80000220         # region C

    # Seed the regions while they are still unprotected.
    li   t0, 0xAAAA0000
    sw   t0, 0(s4)
    li   t0, 0xBBBB0000
    sw   t0, 0(s5)
    li   t0, 0xCCCC0000
    sw   t0, 0(s6)

    #=================================================================
    # PHASE 1 -- an UNLOCKED rule does not bind M-mode
    #
    # Entry 0 covers region A with no R/W/X and L=0. Machine mode ignores
    # it, so the store must land.
    #=================================================================
    srli t0, s4, 2
    ori  t0, t0, 1              # NAPOT, 16 bytes
    csrw pmpaddr0, t0
    li   t0, 0x18               # A=NAPOT, L=0, no permissions
    csrw pmpcfg0, t0

    li   t0, 0x11110000
    sw   t0, 0(s4)
    lw   a1, 0(s4)              # expect 0x11110000 -- the store was allowed

    lw   a0, 0x00(s1)           # trap count so far -- expect 0
    addi t0, a0, 0              # consume the load: hold the sync until it retires

    li   x31, 0x11111111

    #=================================================================
    # PHASE 2 -- a LOCKED rule binds M-mode: store -> MCAUSE 7
    #
    # Entry 1 covers region B with no R/W/X and L=1.
    #=================================================================
    srli t0, s5, 2
    ori  t0, t0, 1
    csrw pmpaddr1, t0
    li   t0, 0x9818             # byte1 = 0x98 (L|NAPOT, no perms), byte0 unchanged
    csrw pmpcfg0, t0

    li   t0, 0xDEADBEEF
    sw   t0, 0(s5)              # denied

    lw   a2, 0x04(s1)           # MCAUSE -- expect 7
    lw   a3, 0x0C(s1)           # MTVAL  -- expect region B
    addi t0, a3, 0              # consume the load: hold the sync until it retires

    li   x31, 0x22222222

    #=================================================================
    # PHASE 3 -- the load faults too, and the denied store never landed
    #=================================================================
    li   t0, 0xEE110000
    lw   t0, 0(s5)              # denied -- t0 keeps its value
    mv   a4, t0                 # expect 0xEE110000, i.e. no load occurred

    lw   a5, 0x04(s1)           # MCAUSE -- expect 5
    lw   a6, 0x0C(s1)           # MTVAL  -- expect region B

    # Region B must still hold its seed. Entry 1 is locked and cannot be
    # relaxed, so entry 0 -- lower-numbered, hence higher priority, and
    # still unlocked -- is retargeted over B to grant the read. That the
    # read now succeeds is itself the priority check: the permissive
    # entry 0 must win over the denying entry 1.
    srli t0, s5, 2
    ori  t0, t0, 1
    csrw pmpaddr0, t0
    li   t0, 0x9819             # byte0 = 0x19 (NAPOT|R, L=0)
    csrw pmpcfg0, t0

    lw   s8, 0(s5)              # expect 0xBBBB0000 -- the seed, not 0xDEADBEEF
    addi t0, s8, 0              # consume the load: hold the sync until it retires

    li   x31, 0x33333333

    #=================================================================
    # PHASE 4 -- a locked read-only rule permits the load, refuses the store
    #
    # Entry 2 covers region C with R=1, W=0, X=0 and L=1.
    #=================================================================
    srli t0, s6, 2
    ori  t0, t0, 1
    csrw pmpaddr2, t0
    li   t0, 0x00999819         # byte2 = 0x99 (L|NAPOT|R)
    csrw pmpcfg0, t0

    lw   a7, 0(s6)              # allowed -- expect 0xCCCC0000

    li   t0, 0x44440000
    sw   t0, 0(s6)              # denied

    lw   s2, 0x04(s1)           # MCAUSE -- expect 7
    lw   s3, 0x0C(s1)           # MTVAL  -- expect region C

    lw   s7, 0x00(s1)           # total trap count -- expect 3
    addi t0, s7, 0              # consume the load: hold the sync until it retires

    li   x31, 0x44444444

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
1:  j    1b
