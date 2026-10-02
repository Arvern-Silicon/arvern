#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_prefetch_flush
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: a pmpcfg write applies to the very next fetch, prefetch included
#   PMP checks apply to every instruction fetch. A write to pmpcfg*/pmpaddr*
#   therefore takes effect for the instruction right behind the csrw -- even
#   when the fetch unit had already prefetched that instruction under the
#   old configuration. No fence.i is required.
#
#   Machine mode throughout, MML=0: a LOCKED entry binds M-mode.
#
#   Each phase is a straight-line block B of eight 32-bit `addi sN, sN, 1`
#   (`.option norvc`, 32 bytes, NAPOT-aligned) that FOLLOWS the csrw pmpcfg0
#   with no branch in between, so B's first parcels sit in the prefetch
#   buffer when the csrw executes. sN counts how many of B's instructions
#   ran.
#
#     PHASE 1  entry 0, L|NAPOT, R=W=X=0, csrw immediately before B1.
#              Expect: cause 1 at B1 exactly (mepc = mtval = &B1), s3 == 0.
#     PHASE 2  entry 1, same, but a fence.i between the csrw and B2.
#              Control: must fault at &B2 too (the construction is right).
#     PHASE 3  entry 2, L|NAPOT, X=1. Negative: B3 runs, s5 == 8, no trap.
#
#   The handler cannot resume with MEPC+4 (the faulting word was never
#   fetched): it restores MEPC from s10, which each phase points at its own
#   continuation label outside the region.
#
#   Scratchpad (base 0x80000000), one 16-byte slot per phase (s11 = slot):
#     +0 mcause  +4 mepc  +8 mtval  +C trap count
#     phase 1: 0x00   phase 2: 0x10   phase 3: 0x20
#     0x30 &B1   0x34 &B2
#
#   Bug signature: phase 1 runs some of B1's prefetched parcels before the
#   fault (s3 > 0, mepc > &B1) or never faults at all (count 0).
#
# Requires PMP_NR > 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main
.option norvc

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
    csrr t0, mcause
    sw   t0, 0(s11)
    csrr t0, mepc
    sw   t0, 4(s11)
    csrr t0, mtval
    sw   t0, 8(s11)
    lw   t0, 12(s11)
    addi t0, t0, 1
    sw   t0, 12(s11)
    csrw mepc, s10             # resume at this phase's continuation label
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
    csrw  mstatush, x0          # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

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
    sw   t0, 0x2C(s1)
    li   s3, 0
    li   s4, 0
    li   s5, 0

    la   t0, B1
    sw   t0, 0x30(s1)
    la   t0, B2
    sw   t0, 0x34(s1)

    #=================================================================
    # PHASE 1 -- csrw pmpcfg0 immediately followed by B1, no fence
    #=================================================================
    la   t1, B1
    srli t1, t1, 2
    ori  t1, t1, 3              # NAPOT, 32 bytes
    csrw pmpaddr0, t1           # entry 0 address, still A=OFF
    li   t0, 0x98               # entry 0: L | A=NAPOT | R=W=X=0
    la   s10, p1_cont
    li   s11, 0x80000000
    .balign 32
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    csrw pmpcfg0, t0            # at B1-4: locks entry 0, B1 already prefetched
B1:
    addi s3, s3, 1              # must NOT run: cause 1 here, mepc = &B1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
p1_cont:
    lw   a0, 0x0C(s1)           # phase-1 trap count -- expect 1
    addi t0, a0, 0              # consume the load: hold the sync until it retires
    li   x31, 0x11111111

    #=================================================================
    # PHASE 2 -- control: same, with a fence.i between csrw and B2
    #=================================================================
    la   t1, B2
    srli t1, t1, 2
    ori  t1, t1, 3
    csrw pmpaddr1, t1
    li   t0, 0x9898             # entry 1: L | NAPOT | none (entry 0 locked, unchanged)
    la   s10, p2_cont
    li   s11, 0x80000010
    .balign 32
    nop
    nop
    nop
    nop
    nop
    nop
    csrw pmpcfg0, t0
    fence.i                     # explicit flush: B2 refetched under the new rule
B2:
    addi s4, s4, 1              # cause 1 here, mepc = &B2
    addi s4, s4, 1
    addi s4, s4, 1
    addi s4, s4, 1
    addi s4, s4, 1
    addi s4, s4, 1
    addi s4, s4, 1
    addi s4, s4, 1
p2_cont:
    lw   a1, 0x1C(s1)           # phase-2 trap count -- expect 1
    addi t0, a1, 0
    li   x31, 0x22222222

    #=================================================================
    # PHASE 3 -- negative: entry 2 grants X, B3 executes normally
    #=================================================================
    la   t1, B3
    srli t1, t1, 2
    ori  t1, t1, 3
    csrw pmpaddr2, t1
    li   t0, 0x9C9898           # entry 2: L | NAPOT | X ; entries 0/1 locked, unchanged
    la   s10, p3_cont
    li   s11, 0x80000020
    .balign 32
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    csrw pmpcfg0, t0
B3:
    addi s5, s5, 1              # all eight run: s5 == 8
    addi s5, s5, 1
    addi s5, s5, 1
    addi s5, s5, 1
    addi s5, s5, 1
    addi s5, s5, 1
    addi s5, s5, 1
    addi s5, s5, 1
p3_cont:
    lw   a2, 0x2C(s1)           # phase-3 trap count -- expect 0
    addi t0, a2, 0
    li   x31, 0x33333333

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
1:  j    1b
