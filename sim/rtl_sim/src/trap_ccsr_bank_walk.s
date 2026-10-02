#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_ccsr_bank_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: every custom-CSR bank and offset, from M, S and U
#
#   integration_guide.md §7 bank table: 0 0x800, 1 0x840, 2 0x880, 3 0x8C0
#   (U RW); 4 0xCC0 (U RO); 5 0x5C0, 6 0x9C0 (S RW); 7 0xDC0 (S RO); 8 0x7C0,
#   9 0xBC0 (M RW); 10 0xFC0 (M RO).
#   integration_guide.md §7: "Privilege (csr[9:8]), read-only windows
#   (csr[11:10] = 11) and illegal accesses are checked before any select is
#   asserted: a failing access raises an illegal-instruction exception".
#   Priv §2.1: "Attempts to access a CSR without appropriate privilege level
#   raise illegal-instruction exceptions ... attempts to write a read-only
#   register raise illegal-instruction exceptions."
#   integration_guide.md §7: "With SU_MODE_EN = 0 the S-mode windows (banks
#   5, 6, 7) remain accessible from M-mode".
#   The seven core-owned addresses 0x7FD-0x7FF and 0xFFC-0xFFF are left out
#   (bank 8 walks 61 offsets, bank 10 walks 60).
#
#   Bench peripheral (arv_custom_csr, tb_arvern.v): U RW registers at
#   0x800/0x801, S RW at 0x5C0/0x5C1, M RW at 0x7C0-0x7C7, RO at 0xCC0,
#   0xDC0, 0xFC0, 0xFC1 (driven by this test's .v); every other offset reads
#   0 and ignores writes.
#
#   Pass per mode (M, then S and U when SU_MODE_EN), tag t = 3 / 1 / 0:
#     W: old = csrrw(addr, 0xA5000000 | t<<16 | addr); rb = csrr(addr)
#     R: rr = csrr(addr), after every write of the pass (catches aliasing)
#   A trapping access leaves the marker 0xDEADC0DE in its result.
#   Record (index i in bank-table order): 0x80001000 + 0x3000*pass + 16*i:
#     +0 old  +4 rb  +8 rr
#   0x80000000: illegal-instruction traps   0x80000004: other traps
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSTATUS,  0x744
.equ MSTATUSH,  0x310
.equ MARK,      0xDEADC0DE
.equ REC,       0x80001000

.section .text
.global main

main:
    j    _start

#=========================================================================
# M handler: cause 2 skipped; ECALL (8/9/11) ends the pass -> M at s10
#=========================================================================
    .align 2
m_handler:
    csrr t0, mcause
    li   t1, 2
    beq  t0, t1, m_ill
    li   t1, 8
    beq  t0, t1, m_to_m
    li   t1, 9
    beq  t0, t1, m_to_m
    li   t1, 11
    beq  t0, t1, m_to_m
    lw   t1, 4(s1)
    addi t1, t1, 1
    sw   t1, 4(s1)
    j    1f
m_ill:
    lw   t1, 0(s1)
    addi t1, t1, 1
    sw   t1, 0(s1)
1:  csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    mret
m_to_m:
    li   t1, 0x1800
    csrs mstatus, t1
    csrw mepc, s10
    mret

#=========================================================================
# Access macros
#=========================================================================
.macro W1 a
    mv    a0, s6
    addi  a2, s7, (\a) - 0x800
    csrrw a0, \a, a2
    mv    a3, s6
    csrrs a3, \a, x0
    sw    a0, 0(a1)
    sw    a3, 4(a1)
    addi  a1, a1, 16
.endm

.macro R1 a
    mv    a4, s6
    csrrs a4, \a, x0
    sw    a4, 8(a1)
    addi  a1, a1, 16
.endm

.macro WBANK base, cnt
    .set  wofs, 0
    .rept \cnt
    W1    (\base + wofs)
    .set  wofs, wofs + 1
    .endr
.endm

.macro RBANK base, cnt
    .set  rofs, 0
    .rept \cnt
    R1    (\base + rofs)
    .set  rofs, rofs + 1
    .endr
.endm

.macro ALLBANKS m
    \m 0x800, 64
    \m 0x840, 64
    \m 0x880, 64
    \m 0x8C0, 64
    \m 0xCC0, 64
    \m 0x5C0, 64
    \m 0x9C0, 64
    \m 0xDC0, 64
    \m 0x7C0, 61
    \m 0xBC0, 64
    \m 0xFC0, 60
.endm

#=========================================================================
# One pass (runs in M, S or U): s5 = record base, s7 = pattern base
#=========================================================================
    .align 2
ccsr_pass:
    mv    a1, s5
    ALLBANKS WBANK
    mv    a1, s5
    ALLBANKS RBANK
    ecall                           # -> M at s10

# a0 = privilege (0 U / 1 S / 3 M)
    .align 2
enter_mode:
    li   t0, 0x1800
    csrc mstatus, t0
    slli t0, a0, 11
    csrs mstatus, t0
    la   t0, ccsr_pass
    csrw mepc, t0
    mret

#=========================================================================
_start:
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE = 1 first
    csrw MSTATUSH, x0               # then MDT = 0

    li   sp, 0x80010000
    li   s1, 0x80000000
    li   s6, MARK
    PMP_ALLOW_ALL
    sw   x0, 0(s1)
    sw   x0, 4(s1)

    la   t0, m_handler
    csrw mtvec, t0
.if CFG_SU_MODE_EN
    csrw medeleg, x0
.endif

    li   x31, 0x11111111            # sync: init done

    # M pass
    li   s5, REC
    li   s7, 0xA5030800
    li   a0, 3
    la   s10, 1f
    j    enter_mode
1:  li   x31, 0x22222222

.if CFG_SU_MODE_EN
    # S pass
    li   s5, REC + 0x3000
    li   s7, 0xA5010800
    li   a0, 1
    la   s10, 1f
    j    enter_mode
1:  li   x31, 0x33333333

    # U pass
    li   s5, REC + 0x6000
    li   s7, 0xA5000800
    li   a0, 0
    la   s10, 1f
    j    enter_mode
1:  li   x31, 0x44444444
.endif

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
