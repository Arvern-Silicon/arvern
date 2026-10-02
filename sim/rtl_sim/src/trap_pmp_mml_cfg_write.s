#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_mml_cfg_write
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Smepmp MML write restriction on every UNLOCKED pmpcfg byte
#
#   Priv 6.2 Smepmp 4b: "Adding a rule with executable privileges that either
#   is M-mode-only or a locked Shared-Region is not possible and such pmpcfg
#   writes are ignored, leaving pmpcfg unchanged." Applied per entry
#   (spec_compliance_notes.md "Smepmp MML write restriction is applied per
#   PMP entry").
#
#   Only one rule is locked: the ROM rule (LRWX 1101, M read/execute, needed
#   to keep executing once MML withdraws M execute on a no-match), placed in
#   the LAST writable entry (PMP_NR-1 = byte 3 of the last pmpcfg word). Every
#   other entry is unlocked, so each byte lane of each pmpcfg word shows the
#   MML refusal itself (trap_pmp_mml cannot: its rows 8..15 are locked).
#
#   Per pmpcfg0..3, after MML=1 (RLB=0), write and read back:
#     0x9C9A9E9D  LRWX 1001/1010/1011/1101 -> every byte refused
#     0x19191919  L=0 NAPOT R              -> written
#     0x18181818  L=0 NAPOT, no permission -> written
#     0x9C199C19  mixed                    -> only the 0x19 bytes land
#     0x199C199C  mixed, other lanes (after a 0x18181818 reset) -> only the
#                 0x19 bytes land
#   pmpaddr of the rewritten entries is 0 (NAPOT [0,8), never accessed).
#   Words at or beyond PMP_NR read 0 (entries >= PMP_NR are read-only zero).
#   Read-backs at 0x80000100 + 0x20*N + 4*step; the bench derives the
#   expected values from PMP_NR.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MSECCFG,  0x747
.equ ROM_NAPOT, 0x08001FFF          # 0x2000_0000, 64 KB

.macro CFG_SEQ csr, res
    li   t0, 0x9C9A9E9D
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 0(\res)
    li   t0, 0x19191919
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 4(\res)
    li   t0, 0x18181818
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 8(\res)
    li   t0, 0x9C199C19
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 12(\res)
    li   t0, 0x18181818              # reset every lane first
    csrw \csr, t0
    li   t0, 0x199C199C
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 16(\res)
    addi \res, \res, 0x20
.endm

.section .text
.global main
main:
    j    _start

    .align 2
bad_handler:
    csrr t0, mcause
    li   x31, 0xBADBAD01
    j    bad_handler

_start:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw  mstatush, x0              # mstatus.MDT   = 0
    la    t0, bad_handler
    csrw  mtvec, t0

    csrw  pmpcfg0, x0
    csrw  pmpcfg1, x0
    csrw  pmpcfg2, x0
    csrw  pmpcfg3, x0
    csrw  pmpaddr0, x0
    csrw  pmpaddr1, x0
    csrw  pmpaddr2, x0
    csrw  pmpaddr3, x0
    csrw  pmpaddr4, x0
    csrw  pmpaddr5, x0
    csrw  pmpaddr6, x0
    csrw  pmpaddr7, x0
    csrw  pmpaddr8, x0
    csrw  pmpaddr9, x0
    csrw  pmpaddr10, x0
    csrw  pmpaddr11, x0
    csrw  pmpaddr12, x0
    csrw  pmpaddr13, x0
    csrw  pmpaddr14, x0
    csrw  pmpaddr15, x0

    # Locked M read/execute rule over the ROM in the last writable entry.
    li    t0, ROM_NAPOT
    li    t1, 0x9D000000
.if CFG_PMP_NR == 4
    csrw  pmpaddr3, t0
    csrw  pmpcfg0, t1
.elseif CFG_PMP_NR == 8
    csrw  pmpaddr7, t0
    csrw  pmpcfg1, t1
.else
    csrw  pmpaddr15, t0
    csrw  pmpcfg3, t1
.endif

    csrsi MSECCFG, 1                # MML = 1
    csrr  s8, MSECCFG               # expect bit 0 set, RLB (bit 2) clear

    li    x31, 0x11111111

    li    s7, 0x80000100
    CFG_SEQ pmpcfg0, s7
    CFG_SEQ pmpcfg1, s7
    CFG_SEQ pmpcfg2, s7
    CFG_SEQ pmpcfg3, s7
    lw    zero, -4(s7)

    li    x31, 0xdeadbeef
end_of_test:
    nop
    j     end_of_test
