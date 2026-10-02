#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_lock_rlb_mmwp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP lock semantics, mseccfg.RLB, and the two no-match policies
#
#   Locks (Priv 3.7.1): a locked entry ignores writes to its pmpcfg and
#   pmpaddr; a locked TOR entry also locks the pmpaddr below it, but not that
#   neighbour's own pmpcfg.
#
#   RLB (Smepmp 6.2): set while no rule is locked, it lets locked rules be
#   edited; once cleared with a locked rule present it cannot be set again.
#
#   No-match policy for M-mode: allowed by default; with MML set, execute is
#   refused (data still allowed); with MMWP set, everything is refused. MMWP
#   is sticky. A matching rule is unaffected by MMWP.
#
#   Entries:  0    NAPOT 16 B @ 0x80002000, locked, R -- the RLB subject
#             1    address only, its cfg stays OFF -- locked via entry 2's TOR
#             2    TOR up to 0x80002020, locked, R
#             4    NAPOT 256 MB over the ROM, locked, RX -- the test itself
#             5    NAPOT 4 KB @ 0x80000000, locked, RW -- stack and slots
#   No-match probes use 0x80008000, which nothing covers.
#
# Requires PMP_NR >= 8 and SU_MODE_EN == 1.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ SLOTS,    0x80000100
.equ NOMATCH,  0x80008000
.equ SCRATCH,  0x80000000

main:
    j _start

    .align 2
m_trap_handler:
    addi sp, sp, -8
    sw   t0, 4(sp)
    csrr t0, mcause
    sw   t0, 0(s11)
    csrw mepc, s10
    lw   t0, 4(sp)
    addi sp, sp, 8
    mret

.macro PROBE_LOAD addr, slot
    la   s10, 1f
    li   s11, \slot
    lw   t0, 0(\addr)
1:
.endm
.macro PROBE_STORE addr, slot
    la   s10, 1f
    li   s11, \slot
    sw   t1, 8(\addr)
1:
.endm
.macro PROBE_EXEC addr, slot
    la   s10, 1f
    li   s11, \slot
    jalr ra, 0(\addr)
1:
.endm

#=========================================================================
_start:
    li   sp, SCRATCH + 0x1000   # stack lives inside entry 5's window
    li   s1, SCRATCH

    la   t0, m_trap_handler
    csrw mtvec, t0

    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw  mstatush, x0          # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    li   t0, SLOTS
    .rept 8
    sw   x0, 0(t0)
    addi t0, t0, 4
    .endr

    li   s7, NOMATCH
    li   t0, 0x00000073         # ECALL, in case a refused fetch is wrongly allowed
    sw   t0, 0(s7)
    fence.i
    li   t1, 0x5A5A5A5A

    #=================================================================
    # PART A -- RLB and lock semantics, before any policy bit is set
    #=================================================================
    csrsi 0x747, 4              # RLB: allowed, nothing is locked yet
    csrr  a0, 0x747             # expect 0x4

    li   t0, 0x20000801         # NAPOT 16 B @ 0x80002000
    csrw pmpaddr0, t0
    li   t0, 0x99               # L | NAPOT | R
    csrw pmpcfg0, t0
    csrr a1, pmpcfg0            # expect 0x00000099

    # RLB is set, so the locked entry is still editable.
    li   t0, 0x9B               # L | NAPOT | R | W
    csrw pmpcfg0, t0
    csrr a2, pmpcfg0            # expect 0x0000009B
    li   t0, 0x20000805         # NAPOT 16 B @ 0x80002010
    csrw pmpaddr0, t0
    csrr a3, pmpaddr0           # expect 0x20000805

    csrci 0x747, 4              # clear RLB
    csrr  a4, 0x747             # expect 0x0
    csrsi 0x747, 4              # a locked rule exists: RLB cannot come back
    csrr  a5, 0x747             # expect 0x0

    # Now the lock holds.
    li   t0, 0x9F
    csrw pmpcfg0, t0            # ignored
    csrr a6, pmpcfg0            # expect 0x0000009B
    li   t0, 0x20000809
    csrw pmpaddr0, t0           # ignored
    csrr a7, pmpaddr0           # expect 0x20000805

    # A locked TOR entry locks the address below it, not that entry's cfg.
    li   t0, 0x20000804         # pmpaddr1 = 0x80002010 >> 2
    csrw pmpaddr1, t0
    li   t0, 0x20000808         # pmpaddr2 = 0x80002020 >> 2
    csrw pmpaddr2, t0
    li   t0, 0x00890000         # entry 2 = L | TOR | R
    csrw pmpcfg0, t0            # entry 0 byte is 0 here but locked: ignored
    li   t0, 0x20000806
    csrw pmpaddr1, t0           # ignored: entry 2 is locked TOR
    csrr s2, pmpaddr1           # expect 0x20000804
    li   t0, 0x00890100         # entry 1 cfg = R (A stays OFF): its cfg is free
    csrw pmpcfg0, t0
    csrr s3, pmpcfg0            # expect 0x0089019B

    #=================================================================
    # Cover the test itself before either policy bit can bite.
    #=================================================================
    li   t0, 0x09FFFFFF         # ROM
    csrw pmpaddr4, t0
    li   t0, 0x200001FF         # 4 KB @ 0x80000000
    csrw pmpaddr5, t0
    li   t0, 0x00009B9D         # entry 4 = L RX, entry 5 = L RW
    csrw pmpcfg1, t0

    #=================================================================
    # PART B -- MML alone: M-mode no-match execute refused, data allowed
    #=================================================================
    csrsi 0x747, 1
    PROBE_LOAD  s7, SLOTS+0x00  # expect 0
    PROBE_STORE s7, SLOTS+0x04  # expect 0
    PROBE_EXEC  s7, SLOTS+0x08  # expect 1

    #=================================================================
    # PART C -- MMWP: M-mode no-match refused outright, sticky, and a
    # matching rule is unaffected
    #=================================================================
    csrsi 0x747, 2
    csrr  s4, 0x747             # expect 0x3
    PROBE_LOAD  s7, SLOTS+0x0C  # expect 5
    PROBE_STORE s7, SLOTS+0x10  # expect 7
    PROBE_EXEC  s7, SLOTS+0x14  # expect 1
    PROBE_LOAD  s1, SLOTS+0x18  # scratch, covered by entry 5: expect 0
    csrci 0x747, 2
    csrr  s5, 0x747             # expect 0x3

    lw   s6, 0x18(s1)           # last slot, consumed so the sync waits for it
    addi t0, s6, 0

    li   x31, 0x11111111

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
9:  j    9b
