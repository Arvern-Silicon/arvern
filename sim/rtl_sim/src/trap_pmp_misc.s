#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_misc
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP -- NA4, execute-only, and misaligned-access priority
#
#   Three points the other PMP tests do not assert, all in M-mode with
#   mseccfg clear:
#
#   NA4 (A=2) is exactly four bytes: entry 0 locks 0x80000400 read-only, and
#   the words on either side are untouched by it.
#
#   Execute-only (L|X, no R) is a legal rule: M-mode runs the `ret` planted
#   at 0x80000500 yet a load from the same address faults.
#
#   A misaligned access into a region that would also refuse it reports the
#   PMP denial (cause 5/7), not the misalignment (4/6): the checker evaluates
#   the address whether or not the access is going to be issued, and its fault
#   outranks the misalignment. Priv 3.1.15 leaves the relative priority of the
#   two to the implementation. mtval names the faulting address either way.
#
#     entry 0   NA4    @ 0x80000400   L R
#     entry 1   NAPOT  @ 0x80000500   L X
#     entry 2   NAPOT  @ 0x80000600   L, no permissions
#
# Requires PMP_NR > 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ SLOTS,  0x80000100
.equ NA4R,   0x80000400
.equ XONLY,  0x80000500
.equ NONE,   0x80000600

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
    sw   t0, 0x00(s1)
    csrw mepc, s10
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

.macro PROBE_LW addr, off, slot
    la   s10, 1f
    li   s11, \slot
    lw   t0, \off(\addr)
1:
.endm
.macro PROBE_SW addr, off, slot
    la   s10, 1f
    li   s11, \slot
    sw   t1, \off(\addr)
1:
.endm

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
    .rept 24
    sw   x0, 0(t0)
    addi t0, t0, 4
    .endr

    li   s5, NA4R
    li   s6, XONLY
    li   s7, NONE
    li   t1, 0x5A5A5A5A

    # Seed the NA4 neighbourhood and plant the execute-only stub.
    li   t0, 0x11110000
    sw   t0, -4(s5)
    li   t0, 0x22220000
    sw   t0,  0(s5)
    li   t0, 0x33330000
    sw   t0,  4(s5)
    li   t0, 0x00008067         # ret
    sw   t0,  0(s6)
    fence.i

    li   t0, 0x20000100         # NA4: pmpaddr = addr >> 2, no size bits
    csrw pmpaddr0, t0
    li   t0, 0x20000141         # NAPOT 16 B @ 0x80000500
    csrw pmpaddr1, t0
    li   t0, 0x20000181         # NAPOT 16 B @ 0x80000600
    csrw pmpaddr2, t0
    li   t0, 0x00989C91         # entry 2 = L,  entry 1 = L X,  entry 0 = L NA4 R
    csrw pmpcfg0, t0

    #=================================================================
    # NA4 -- exactly four bytes
    #=================================================================
    PROBE_SW s5,  0, SLOTS+0x00 # inside: cause 7, mtval 0x80000400
    PROBE_SW s5, -4, SLOTS+0x08 # below:  lands
    PROBE_SW s5,  4, SLOTS+0x10 # above:  lands
    lw   a0, -4(s5)             # expect 0x5A5A5A5A
    lw   a1,  0(s5)             # expect 0x22220000 (the denied store)
    lw   a2,  4(s5)             # expect 0x5A5A5A5A

    #=================================================================
    # Execute-only -- runs, but cannot be read
    #=================================================================
    la   s10, 2f
    li   s11, SLOTS+0x18
    jalr ra, 0(s6)              # runs the ret: no trap
2:  PROBE_LW s6,  0, SLOTS+0x20 # cause 5, mtval 0x80000500

    #=================================================================
    # Misaligned into a region with no permissions
    #=================================================================
    PROBE_LW s7,  0, SLOTS+0x28 # aligned:    cause 5
    PROBE_LW s7,  2, SLOTS+0x30 # misaligned: still cause 5, mtval 0x80000602
    PROBE_SW s7,  0, SLOTS+0x38 # aligned:    cause 7
    PROBE_SW s7,  2, SLOTS+0x40 # misaligned: still cause 7, mtval 0x80000602

    lw   a3, 0x00(s1)           # total traps -- expect 6
    addi t0, a3, 0

    li   x31, 0x11111111

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
9:  j    9b
