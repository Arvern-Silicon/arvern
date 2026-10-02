#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_mprv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP under mstatus.MPRV
#
#   With MPRV=1 the privilege used for a load or store is MPP, not the current
#   mode (Priv 3.1.6.3). PMP must follow that: an M-mode hart with MPP=U is
#   checked as U -- unlocked entries now apply, and no-match is denied -- while
#   instruction fetch keeps the current privilege, since MPRV never affects it.
#
#   One unlocked entry, read-only: NAPOT 16 B at 0x80000400. Nothing covers
#   0x80000500 or 0x80000600.
#
#     mode                  access             expect
#     -----------------------------------------------------------------
#     M, NMIE=0, MPRV=1/U   store  0x80000400  lands   (MPRV ignored, Smrnmi)
#     M, MPRV=1/U           store  0x80000400  MCAUSE 7 (U, W=0)
#     M, MPRV=1/U           load   0x80000400  lands   (U, R=1)
#     M, MPRV=1/U           store  0x80000500  MCAUSE 7 (U, no match)
#     M, MPRV=1/U           load   0x80000500  MCAUSE 5 (U, no match)
#     M, MPRV=1/M           store  0x80000400  lands   (M, entry unlocked)
#     M, MPRV=1/U           fetch  0x80000600  runs    (fetch is not MPRV-aware)
#
# Requires PMP_NR > 0 and SU_MODE_EN == 1.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ REGION,   0x80000400       # read-only, unlocked
.equ NOMATCH,  0x80000500       # no entry
.equ STUB,     0x80000600       # no entry; holds a `ret`

.equ MPRV_U,   0x00020000       # MPRV=1, MPP=U
.equ MPRV_M,   0x00021800       # MPRV=1, MPP=M

main:
    j _start

    .align 2
m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    lw   t0, 0x00(s1)           # trap count -> slot index
    slli t1, t0, 3
    addi t1, t1, 0x10
    add  t1, t1, s1
    csrr t2, mcause
    sw   t2, 0(t1)
    csrr t2, mtval
    sw   t2, 4(t1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    csrw mepc, s10              # resume at the armed recovery label

    lw   t2,  4(sp)
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

    li   s5, REGION
    li   s6, NOMATCH
    li   s7, STUB

    # Plant a `ret` at STUB while everything is still unprotected.
    li   t0, 0x00008067
    sw   t0, 0(s7)
    fence.i

    #-----------------------------------------------------------------
    # Entry 0: NAPOT 16 B at REGION, R only, NOT locked.
    #-----------------------------------------------------------------
    li   t0, REGION
    srli t0, t0, 2
    ori  t0, t0, 1
    csrw pmpaddr0, t0
    li   t0, 0x19               # A=NAPOT | R
    csrw pmpcfg0, t0

    #=================================================================
    # PHASE 0 -- NMIE is still 0 out of reset. Smrnmi says MPRV is
    # ignored then, so this store is checked as M and lands.
    #=================================================================
    li   t0, MPRV_U
    csrw mstatus, t0
    li   t1, 0xAAAA0000
    sw   t1, 0(s5)
    csrw mstatus, x0
    lw   a0, 0(s5)              # expect 0xAAAA0000

    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw  mstatush, x0          # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    #=================================================================
    # PHASE 1 -- MPRV=1/U: store refused (W=0), load allowed (R=1)
    #=================================================================
    la   s10, 1f
    li   t0, MPRV_U
    csrw mstatus, t0
    li   t1, 0xBBBB0000
    sw   t1, 0(s5)              # denied: MCAUSE 7, MTVAL REGION
1:  csrw mstatus, x0

    la   s10, 2f
    li   t0, MPRV_U
    csrw mstatus, t0
    lw   a1, 0(s5)              # permitted: still 0xAAAA0000
2:  csrw mstatus, x0
    addi t0, a1, 0              # consume the load

    li   x31, 0x11111111

    #=================================================================
    # PHASE 2 -- MPRV=1/U against an address no entry covers: denied
    #=================================================================
    la   s10, 3f
    li   t0, MPRV_U
    csrw mstatus, t0
    sw   t1, 0(s6)              # MCAUSE 7, MTVAL NOMATCH
3:  csrw mstatus, x0

    la   s10, 4f
    li   t0, MPRV_U
    csrw mstatus, t0
    lw   t2, 0(s6)              # MCAUSE 5, MTVAL NOMATCH
4:  csrw mstatus, x0

    #=================================================================
    # PHASE 3 -- MPRV=1/M: checked as M, the unlocked entry is ignored
    #=================================================================
    la   s10, 5f
    li   t0, MPRV_M
    csrw mstatus, t0
    li   t1, 0xCCCC0000
    sw   t1, 0(s5)              # lands
5:  csrw mstatus, x0
    lw   a2, 0(s5)              # expect 0xCCCC0000

    #=================================================================
    # PHASE 4 -- MPRV=1/U, then execute from an address no entry covers.
    # U would be refused; the fetch is checked as M and runs.
    #=================================================================
    la   s10, 6f
    li   t0, MPRV_U
    csrw mstatus, t0
    jalr ra, 0(s7)              # runs the `ret`, no trap
6:  csrw mstatus, x0

    lw   a4, 0x00(s1)           # trap count -- expect 3
    lw   a5, 0x10(s1)           # slot 0: MCAUSE 7
    lw   a6, 0x14(s1)           #         MTVAL REGION
    lw   a7, 0x18(s1)           # slot 1: MCAUSE 7
    lw   s2, 0x1C(s1)           #         MTVAL NOMATCH
    lw   s3, 0x20(s1)           # slot 2: MCAUSE 5
    lw   s4, 0x24(s1)           #         MTVAL NOMATCH
    addi t0, s4, 0              # consume the load

    li   x31, 0x22222222

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
9:  j    9b
