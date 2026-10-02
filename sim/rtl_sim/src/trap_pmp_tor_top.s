#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_tor_top
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP regions at the top of the 32-bit address space
#
#   The physical address space is 32 bits, so pmpaddr[31:30] (address bits
#   33:32) read 0: writing 0xFFFFFFFF reads back 0x3FFFFFFF. Priv 3.7.1: "the
#   entry matches any address y such that pmpaddr[i-1] <= y < pmpaddr[i]" --
#   a TOR entry's exclusive top is then at most 0xFFFFFFFC, so the last word
#   0xFFFFFFFC..0xFFFFFFFF is NOT covered by TOR, while a NAPOT entry ending at
#   2^32 (or covering 2^33) covers it (doc/arvern_instructions.md, pmpaddr row).
#
#   All accesses are made from U-mode: "If no PMP entry matches an S-mode or
#   U-mode access, but at least one PMP entry is implemented, the access fails."
#   Entries are unlocked, so M-mode (handlers) is never restricted.
#
#   0xFFFFFFxx is unmapped on the bench. An access PMP ALLOWS reaches the bus,
#   gets an AHB ERROR and is reported as the resumable RNMI (mncause
#   0x80000003, marv_eaddr = address). An access PMP DENIES is a synchronous
#   mcause 5/7 with mtval = address and never reaches the bus (no RNMI).
#
#   Entries: 0 NAPOT 0x20000000/256 MB R+X (U code in ROM)
#            1 OFF, pmpaddr1 = 0x3FFFFFC0 (lower bound 0xFFFFFF00)
#            2 under test
#
#   Phase A  entry 2 TOR RW, pmpaddr2 written 0xFFFFFFFF (reads 0x3FFFFFFF)
#            -> covers [0xFFFFFF00, 0xFFFFFFFC)
#     0 lw  0xFFFFFF00  RNMI         1 lw  0xFFFFFFF8  RNMI
#     2 lbu 0xFFFFFFFB  RNMI         3 lw  0xFFFFFFFC  mcause 5
#     4 lbu 0xFFFFFFFF  mcause 5     5 sw  0xFFFFFFFC  mcause 7
#     6 sw  0xFFFFFFF8  RNMI         7 lw  0xFFFFFEFC  mcause 5 (below)
#   Phase B  entry 2 NAPOT RW, pmpaddr2 = 0x3FFFFFDF (0xFFFFFF00, 256 B)
#     8 lw  0xFFFFFFFC  RNMI         9 lbu 0xFFFFFFFF  RNMI
#    10 sw  0xFFFFFFFC  RNMI        11 lw  0xFFFFFEFC  mcause 5 (below)
#   Phase C  entry 2 NAPOT R, pmpaddr2 written 0xFFFFFFFF (reads 0x3FFFFFFF)
#    12 lw  0xFFFFFFFC  RNMI        13 lw  0x81000000  loads 0x13579BDF
#    14 sw  0xFFFFFFFC  mcause 7 (R only)
#   Phase D  entry 2 NAPOT R, pmpaddr2 = 0x1FFFFFFF (exactly 2^32 bytes)
#    15 lw  0xFFFFFFFC  RNMI        16 lw  0x81000000  loads 0x13579BDF
#
#   Scratchpad (SBASE = 0x80000000):
#     0x00/0x04  M handler save (t1,t2)     0x10/0x14 RNMI handler save
#     0x40 total RNMIs   0x44 total mcause 5/7-class traps
#     0x80 pmpaddr2 (A)  0x84 pmpaddr1 (A)  0x88 pmpaddr2 (B)
#     0x8C pmpaddr2 (C)  0x90 pmpcfg0 (A)   0x94 pmpcfg0 (C)  0x98 pmpaddr2 (D)
#     0x100 + id*64  round record:
#       +0 trap count   +4 mcause   +8 mtval    +12 mepc
#       +16 RNMI count  +20 mncause +24 marv_eaddr +28 marv_epc
#       +32 marv_estat  +36 mnstatus.MNPP (read inside the RNMI handler)
#       +40 t3 at the ecall (load rd; preset 0xBAD30000+id)
#       +44 ecall count +48 PC of the access
#
# Requires PMP_NR > 0 and SU_MODE_EN == 1.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ SBASE,       0x80000000
.equ NXWORD,      0x81000000
.equ MNSCRATCH,   0x740
.equ MNEPC,       0x741
.equ MNCAUSE,     0x742
.equ MNSTATUS,    0x744
.equ MARV_NMVEC,  0x7FD
.equ MARV_ESTAT,  0x7FE
.equ MARV_EPC,    0xFFC
.equ MARV_EADDR,  0xFFD

.equ OP_LW,  0
.equ OP_LBU, 1
.equ OP_SW,  2

main:
    j _start

    #=================================================================
    # M trap handler. ecall from U (mcause 8): record t3, return to the
    # M-mode continuation in s10. Any other trap: record it and resume
    # after the (32-bit) faulting instruction; a runaway round (4 traps)
    # is aborted to s10.
    #=================================================================
    .align 2
m_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    sw   t2, 0x04(t0)
    slli t1, s9, 6
    add  t1, t1, t0
    addi t1, t1, 0x100              # &record[s9]

    csrr t2, mcause
    addi t2, t2, -8
    bnez t2, 1f
    sw   t3, 40(t1)                 # ecall from U
    lw   t2, 44(t1)
    addi t2, t2, 1
    sw   t2, 44(t1)
    j    2f

1:  lw   t2, 0(t1)
    addi t2, t2, 1
    sw   t2, 0(t1)
    csrr t2, mcause
    sw   t2, 4(t1)
    csrr t2, mtval
    sw   t2, 8(t1)
    csrr t2, mepc
    sw   t2, 12(t1)
    lw   t2, 0x44(t0)
    addi t2, t2, 1
    sw   t2, 0x44(t0)
    lw   t2, 0(t1)
    addi t2, t2, -4
    bgez t2, 2f                     # runaway guard
    csrr t2, mepc
    addi t2, t2, 4
    csrw mepc, t2
    j    3f

2:  csrw mepc, s10
    li   t2, 0x1800
    csrs mstatus, t2                # MPP = M
3:  lw   t2, 0x04(t0)
    lw   t1, 0x00(t0)
    csrr t0, mscratch
    mret

    #=================================================================
    # RNMI handler: record the evidence in record[s9], clear
    # marv_estat, mnret (resumes after the faulting access).
    #=================================================================
    .align 2
nmi_handler:
    csrw MNSCRATCH, t0
    li   t0, SBASE
    sw   t1, 0x10(t0)
    sw   t2, 0x14(t0)
    slli t1, s9, 6
    add  t1, t1, t0
    addi t1, t1, 0x100              # &record[s9]

    lw   t2, 16(t1)
    addi t2, t2, 1
    sw   t2, 16(t1)
    csrr t2, MNCAUSE
    sw   t2, 20(t1)
    csrr t2, MARV_EADDR
    sw   t2, 24(t1)
    csrr t2, MARV_EPC
    sw   t2, 28(t1)
    csrr t2, MARV_ESTAT
    sw   t2, 32(t1)
    csrr t2, MNSTATUS
    srli t2, t2, 11
    andi t2, t2, 3
    sw   t2, 36(t1)                 # MNPP = privilege at RNMI entry
    li   t2, 5
    csrw MARV_ESTAT, t2             # W1C valid|overrun
    lw   t2, 0x40(t0)
    addi t2, t2, 1
    sw   t2, 0x40(t0)

    lw   t2, 0x14(t0)
    lw   t1, 0x10(t0)
    csrr t0, MNSCRATCH
    .word 0x70200073                # mnret

    #=================================================================
    # ROUND: from M, drop to U at u_<id>, do one access at \addr, spin,
    # ecall back to M at done_<id>, spin again (a late RNMI still lands
    # in record[id]).
    #=================================================================
.macro ROUND id, addr, op
    li   s9, \id
    li   t0, 5
    csrw MARV_ESTAT, t0
    la   t0, acc_\id
    sw   t0, 0x100 + (\id)*64 + 48(s0)
    la   s10, done_\id
    la   t0, u_\id
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0                # MPP = U
    li   a0, \addr
    li   t3, 0xBAD30000 + (\id)
    li   t2, 0x5A5A5A5A
    mret
u_\id:
    .option push
    .option norvc
acc_\id:
    .if \op == OP_LW
    lw   t3, 0(a0)
    .elseif \op == OP_LBU
    lbu  t3, 0(a0)
    .else
    sw   t2, 0(a0)
    .endif
    .option pop
    li   a4, 40
98: addi a4, a4, -1
    bnez a4, 98b
    ecall
done_\id:
    li   a4, 40
99: addi a4, a4, -1
    bnez a4, 99b
.endm

#=========================================================================
_start:
    li   sp, 0x80010000
    li   s0, SBASE

    li   t0, SBASE
    li   t1, SBASE + 0x600
1:  sw   zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b

    la   t0, m_handler
    csrw mtvec, t0
    la   t0, nmi_handler
    csrw MARV_NMVEC, t0

    csrsi MNSTATUS, 8               # mnstatus.NMIE = 1
    csrw  mstatush, x0              # Smdbltrp: MDT resets to 1
    csrci mstatus, 8                # MIE = 0

    li   t0, NXWORD
    li   t1, 0x13579BDF
    sw   t1, 0(t0)
    lw   zero, 0(t0)

    #=================================================================
    # Phase A -- TOR [0xFFFFFF00, 0x3FFFFFFF<<2)
    #=================================================================
    li   t0, 0x09FFFFFF             # NAPOT 0x20000000, 256 MB
    csrw pmpaddr0, t0
    li   t0, 0x3FFFFFC0             # 0xFFFFFF00 >> 2
    csrw pmpaddr1, t0
    li   t0, 0xFFFFFFFF
    csrw pmpaddr2, t0
    csrr t0, pmpaddr2
    sw   t0, 0x80(s0)               # expect 0x3FFFFFFF
    csrr t0, pmpaddr1
    sw   t0, 0x84(s0)               # expect 0x3FFFFFC0
    li   t0, 0x000B001D             # e2 TOR|W|R, e1 OFF, e0 NAPOT|X|R
    csrw pmpcfg0, t0
    csrr t0, pmpcfg0
    sw   t0, 0x90(s0)

    li   x31, 0x11111111

    ROUND 0,  0xFFFFFF00, OP_LW
    ROUND 1,  0xFFFFFFF8, OP_LW
    ROUND 2,  0xFFFFFFFB, OP_LBU
    ROUND 3,  0xFFFFFFFC, OP_LW
    ROUND 4,  0xFFFFFFFF, OP_LBU
    ROUND 5,  0xFFFFFFFC, OP_SW
    ROUND 6,  0xFFFFFFF8, OP_SW
    ROUND 7,  0xFFFFFEFC, OP_LW

    #=================================================================
    # Phase B -- NAPOT 256 B at 0xFFFFFF00
    #=================================================================
    li   t0, 0x3FFFFFDF
    csrw pmpaddr2, t0
    csrr t0, pmpaddr2
    sw   t0, 0x88(s0)               # expect 0x3FFFFFDF
    li   t0, 0x001B001D             # e2 NAPOT|W|R
    csrw pmpcfg0, t0

    li   x31, 0x22222222

    ROUND 8,  0xFFFFFFFC, OP_LW
    ROUND 9,  0xFFFFFFFF, OP_LBU
    ROUND 10, 0xFFFFFFFC, OP_SW
    ROUND 11, 0xFFFFFEFC, OP_LW

    #=================================================================
    # Phase C -- NAPOT, pmpaddr2 written 0xFFFFFFFF (reads 0x3FFFFFFF)
    #=================================================================
    li   t0, 0xFFFFFFFF
    csrw pmpaddr2, t0
    csrr t0, pmpaddr2
    sw   t0, 0x8C(s0)               # expect 0x3FFFFFFF
    li   t0, 0x0019001D             # e2 NAPOT|R
    csrw pmpcfg0, t0
    csrr t0, pmpcfg0
    sw   t0, 0x94(s0)

    li   x31, 0x33333333

    ROUND 12, 0xFFFFFFFC, OP_LW
    ROUND 13, NXWORD,     OP_LW
    ROUND 14, 0xFFFFFFFC, OP_SW

    #=================================================================
    # Phase D -- NAPOT, pmpaddr2 = 0x1FFFFFFF (2^32 bytes from 0)
    #=================================================================
    li   t0, 0x1FFFFFFF
    csrw pmpaddr2, t0
    csrr t0, pmpaddr2
    sw   t0, 0x98(s0)               # expect 0x1FFFFFFF

    li   x31, 0x44444444

    ROUND 15, 0xFFFFFFFC, OP_LW
    ROUND 16, NXWORD,     OP_LW

    lw   zero, 0x40(s0)             # drain the last record stores
    li   x31, 0xdeadbeef
9:  j    9b
