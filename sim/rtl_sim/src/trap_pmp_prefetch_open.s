#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_prefetch_open
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: a pmpcfg write that OPENS the very next instruction's region
#   The opening direction of trap_pmp_prefetch_flush. PMP checks use the
#   settings in force when the fetch is architecturally performed, so an
#   instruction prefetched while its region was denied must execute once a
#   csrw right before it grants X -- no fence.i required.
#
#   Machine mode with mseccfg.MMWP=1: an M-mode access that matches no entry
#   is denied. Entries (MML=0, unlocked entries grant M-mode full access):
#     0  TOR  [0, B)          RWX   code before the block, ROM, peripherals
#     1  NAPOT [B, B+32)      OFF -> RWX by the csrw right before B
#     2  TOR  [B+12, top)     RWX   (bottom = pmpaddr1 read as a TOR bound)
#   So B's first three words are unreachable until the csrw.
#
#   B = eight 32-bit `addi s3, s3, 1` (.option norvc, 32-byte aligned).
#   Expect: s3 == 8, no trap. Bug signature: cause 1 at &B (s3 == 0).
#
#   Scratchpad (base 0x80000000): +0 mcause +4 mepc +8 mtval +C trap count
#
# Requires PMP_NR > 0 (entries 0..2).
#----------------------------------------------------------------------------

.equ MSECCFG,  0x747

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j _start

    .align 2
m_trap_handler:
    csrr t0, mcause
    sw   t0, 0x00(s1)
    csrr t0, mepc
    sw   t0, 0x04(s1)
    csrr t0, mtval
    sw   t0, 0x08(s1)
    lw   t0, 0x0C(s1)
    addi t0, t0, 1
    sw   t0, 0x0C(s1)
    csrw mepc, s10
    mret

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000
    la   t0, m_trap_handler
    csrw mtvec, t0
    csrsi 0x744, 8              # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0          # ...then MDT=0
    csrci mstatus, 8

    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
    li   s3, 0
    la   s10, p_cont

    la   t1, B
    srli t2, t1, 2
    csrw pmpaddr0, t2           # entry 0 TOR top = B
    ori  t2, t2, 3
    csrw pmpaddr1, t2           # entry 1 NAPOT 32 bytes at B (bottom of entry 2 = B+12)
    li   t2, 0xFFFFFFFF
    csrw pmpaddr2, t2           # entry 2 TOR top
    li   t0, 0x000F000F         # e0 TOR|RWX, e1 OFF, e2 TOR|RWX
    csrw pmpcfg0, t0
    csrsi MSECCFG, 2            # MMWP: unmatched M-mode accesses are denied
    li   t0, 0x000F1F0F         # e1 NAPOT|RWX: opens B

    li   x31, 0x11111111        # Sync: configured

    .balign 32
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    csrw pmpcfg0, t0            # at B-4: B was prefetched while denied
B:
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
    addi s3, s3, 1
p_cont:
    lw   a0, 0x0C(s1)
    addi t0, a0, 0
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
