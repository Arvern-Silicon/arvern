#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_tor
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP top-of-range (TOR) matching
#   A TOR entry spans [pmpaddr[g-1], pmpaddr[g]). Both edges are checked, since
#   the lower bound is the part an implementation can quietly get wrong:
#
#     0x800003FC   BELOW the range -- no match, machine mode proceeds
#     0x80000400   first byte IN  -- locked read-only: load ok, store faults
#     0x80000410   first byte OUT -- no match, machine mode proceeds
#
#   Entry 4 supplies the lower bound with A=OFF, which is legal: TOR reads the
#   neighbouring pmpaddr register regardless of that neighbour's own A field.
#
# Requires PMP_NR > 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ LO,   0x80000400           # first byte inside the range
.equ HI,   0x80000410           # first byte past the range

main:
    j _start

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
    sw   t2, 0x0C(s1)

    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    addi t1, t1, 4              # every fault here is a 32-bit store
    csrw mepc, t1

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

    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw mstatush, x0
    csrci mstatus, 8            # MIE=0

    li   s4, LO - 4             # 0x800003FC -- below the range
    li   s5, LO                 # inside
    li   s6, HI                 # first past the range

    # Seed all three while unprotected.
    li   t0, 0xAA000000
    sw   t0, 0(s4)
    li   t0, 0xBB000000
    sw   t0, 0(s5)
    li   t0, 0xCC000000
    sw   t0, 0(s6)

    #=================================================================
    # Install the TOR rule: entry 1 covers [pmpaddr0, pmpaddr1),
    # locked, read-only. Entry 0 is OFF and only supplies the bound.
    # Entries 0/1 exist in every PMP_NR>0 build (the smallest is 4).
    #=================================================================
    li   t0, LO
    srli t0, t0, 2
    csrw pmpaddr0, t0           # lower bound
    li   t0, HI
    srli t0, t0, 2
    csrw pmpaddr1, t0           # upper bound

    li   t0, 0x00008900         # byte1 = 0x89 (L | A=TOR | R), byte0 = 0x00 (OFF)
    csrw pmpcfg0, t0

    #=================================================================
    # PHASE 1 -- inside the range: load permitted, store refused
    #=================================================================
    lw   a0, 0(s5)              # expect 0xBB000000

    li   t0, 0x11110000
    sw   t0, 0(s5)              # denied

    lw   a1, 0x04(s1)           # MCAUSE -- expect 7
    lw   a2, 0x0C(s1)           # MTVAL  -- expect LO
    addi t0, a2, 0              # consume the load: hold the sync until it retires

    li   x31, 0x11111111

    #=================================================================
    # PHASE 2 -- one word BELOW the lower bound: outside, so allowed
    #
    # This is the edge the shared-bound logic decides. If the lower
    # bound were dropped, the range would start at zero and this store
    # would fault.
    #=================================================================
    li   t0, 0x22220000
    sw   t0, 0(s4)
    lw   a3, 0(s4)              # expect 0x22220000 -- the store landed

    #=================================================================
    # PHASE 3 -- at the upper bound: TOR is exclusive there, so allowed
    #=================================================================
    li   t0, 0x33330000
    sw   t0, 0(s6)
    lw   a4, 0(s6)              # expect 0x33330000 -- the store landed

    lw   a5, 0x00(s1)           # trap count -- expect exactly 1
    addi t0, a5, 0              # consume the load: hold the sync until it retires

    li   x31, 0x22222222

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
1:  j    1b
