#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_fetch_wrongpath
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP fetch faults on the wrong path and on a redirect target
#
#   A PMP violation is trapped precisely (Priv 3.7): only an instruction that
#   is actually executed may fault. The fetch unit prefetches sequentially, so
#   a no-execute region placed right after a taken branch is fetched and must
#   be discarded; but the same region reached AS a branch target must fault.
#
#   D = NAPOT 16 B at 0x80000410, locked, read-only: M-mode may not execute
#   there. 0x80000400..0x8000040F is uncovered and holds the stubs.
#
#     probe  stub at 0x8000040C   entry                   expect
#     -------------------------------------------------------------------
#     1      nop nop nop ret     jalr 0x80000400         no trap
#     2      ret                 jalr 0x8000040C         no trap
#     3      ecall               jalr 0x8000040C         cause 11 only
#     4      --                  jalr 0x80000410 (D)     cause 1, mtval D
#     5      --                  mret to 0x80000410 (D)  cause 1, mtval D
#
#   1, 2: sequential prefetch into D behind a taken ret -- discarded.
#   3:    the same, behind a trap redirect instead of a branch.
#   4, 5: D is the target of a fast branch and of a slow one -- reported.
#   D holds an ECALL so a fault wrongly suppressed shows up as cause 11.
#
# Requires PMP_NR > 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ SLOTS,  0x80000100
.equ STUB,   0x80000400
.equ D,      0x80000410

main:
    j _start

    .align 2
m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    csrr t0, mcause
    sw   t0, 0(s11)
    csrr t0, mtval
    sw   t0, 4(s11)
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)           # total trap count
    li   t1, 0x1800
    csrs mstatus, t1            # back to M whatever MPP says
    csrw mepc, s10
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

#=========================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000
    sw   x0, 0x00(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw  mstatush, x0          # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    li   t0, SLOTS
    .rept 10
    sw   x0, 0(t0)
    addi t0, t0, 4
    .endr

    li   s5, STUB
    li   s6, D

    # Stubs, while everything is still unprotected.
    li   t0, 0x00000013         # nop
    sw   t0, 0x0(s5)
    sw   t0, 0x4(s5)
    sw   t0, 0x8(s5)
    li   t0, 0x00008067         # ret
    sw   t0, 0xC(s5)
    li   t0, 0x00000073         # ecall
    sw   t0, 0x0(s6)            # inside D: must never run
    sw   t0, 0x4(s6)
    fence.i

    # D: locked, read-only, no execute -- binds M-mode.
    li   t0, D
    srli t0, t0, 2
    ori  t0, t0, 1
    csrw pmpaddr0, t0
    li   t0, 0x99               # L | NAPOT | R
    csrw pmpcfg0, t0

    #=================================================================
    # PROBE 1 -- flow through three nops into a ret; prefetch enters D
    #=================================================================
    la   s10, 1f
    li   s11, SLOTS+0x00
    jalr ra, 0(s5)
1:
    #=================================================================
    # PROBE 2 -- land directly on the ret; prefetch enters D at once
    #=================================================================
    la   s10, 2f
    li   s11, SLOTS+0x08
    addi t0, s5, 0xC
    jalr ra, 0(t0)
2:
    #=================================================================
    # PROBE 3 -- same slot holds an ecall: a trap redirect, not a branch
    #=================================================================
    li   t0, 0x00000073
    sw   t0, 0xC(s5)
    fence.i
    la   s10, 3f
    li   s11, SLOTS+0x10
    addi t0, s5, 0xC
    jalr ra, 0(t0)              # cause 11, and nothing else
3:
    #=================================================================
    # PROBE 4 -- D as a fast-branch target
    #=================================================================
    la   s10, 4f
    li   s11, SLOTS+0x18
    jalr ra, 0(s6)              # cause 1
4:
    #=================================================================
    # PROBE 5 -- D as a slow-branch target (mret)
    #=================================================================
    la   s10, 5f
    li   s11, SLOTS+0x20
    li   t0, 0x1800
    csrs mstatus, t0            # MPP=M
    csrw mepc, s6
    mret                        # cause 1
5:
    lw   a0, 0x00(s1)           # total traps -- expect 3
    addi t0, a0, 0

    li   x31, 0x11111111

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
9:  j    9b
