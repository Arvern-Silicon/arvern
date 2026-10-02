#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_bus_err_uop_victim
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: data-bus error on a PLAIN access followed by a Zcmp/Zcmt macro-op
#   COMP-only: cm.push / cm.mva01s / cm.jt need Zcmp + Zcmt.
#
#   A plain sw/lw to the unmapped address 0 takes an AHB ERROR response. That is
#   a resumable RNMI reported against the plain access; the macro-op that follows
#   is a separate, younger instruction and must execute exactly once:
#     cm.push   -- sp moves by -16 once, ra/s0 land on the stack
#     cm.mva01s -- both a0 and a1 are written
#     cm.jt     -- the jump lands on its table target, one RNMI (no replay loop)
#
#   Each round records its architectural result; the testbench compares.
#   An RNMI storm in a round is broken by the handler (mnepc <- escape label).
#
#   Scratchpad (base 0x80000000):
#     0x10 nmi_count   0x14 escape address   0x18 mtvec_count   0x1C round-start count
#     0x100 + id*16 : result words w0..w3 (see the .v)
#     0x400 jvt table (64-byte aligned)   0x2000 stack top SP0
#----------------------------------------------------------------------------

.equ MNSTATUS,       0x744
.equ MNEPC,          0x741
.equ MARV_ESTAT,     0x7FE
.equ MARV_NMVEC,     0x7FD
.equ JVT,            0x017

.equ SBASE,          0x80000000
.equ OFF_NMI_CNT,    0x010
.equ OFF_ESCAPE,     0x014
.equ OFF_MTVEC_CNT,  0x018
.equ OFF_START_CNT,  0x01C
.equ OFF_RES,        0x100
.equ OFF_JVT,        0x400
.equ SP0,            0x80002000

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    .align 2
nmi_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    sw   t2, 0x04(t0)
    sw   t3, 0x08(t0)
    lw   t1, OFF_NMI_CNT(t0)
    addi t1, t1, 1
    sw   t1, OFF_NMI_CNT(t0)
    lw   t2, OFF_START_CNT(t0)
    sub  t2, t1, t2
    li   t3, 4
    blt  t2, t3, 1f
    lw   t3, OFF_ESCAPE(t0)         # RNMI storm in this round: leave it
    csrw MNEPC, t3
1:
    lw   zero, OFF_NMI_CNT(t0)
    li   t1, 0x5
    csrw MARV_ESTAT, t1             # W1C valid|overrun
    lw   t1, 0x00(t0)
    lw   t2, 0x04(t0)
    lw   t3, 0x08(t0)
    csrr t0, mscratch
    .word 0x70200073                # mnret

    .align 4
mtvec_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    lw   t1, OFF_MTVEC_CNT(t0)
    addi t1, t1, 1
    sw   t1, OFF_MTVEC_CNT(t0)
    lw   zero, OFF_MTVEC_CNT(t0)
    lw   t1, OFF_ESCAPE(t0)         # unexpected synchronous trap: abandon the round
    csrw mepc, t1
    lw   t1, 0x00(t0)
    csrr t0, mscratch
    mret

# Round prologue: escape label, round-start RNMI count
.macro BEGIN_ROUND esc
    li   s1, SBASE
    la   t0, \esc
    sw   t0, OFF_ESCAPE(s1)
    lw   t0, OFF_NMI_CNT(s1)
    sw   t0, OFF_START_CNT(s1)
    lw   zero, OFF_START_CNT(s1)
.endm

.macro FAULT kind
    .if \kind == 0
    sw   zero, 0(zero)              # AHB ERROR, posted store
    .else
    lw   t4, 0(zero)                # AHB ERROR, load
    .endif
.endm

.macro SETTLE
    li   t0, 40
99:
    addi t0, t0, -1
    bnez t0, 99b
.endm

# w3 = RNMIs taken in this round
.macro RECORD_DELTA id
    li   s1, SBASE
    lw   t0, OFF_NMI_CNT(s1)
    lw   t1, OFF_START_CNT(s1)
    sub  t0, t0, t1
    sw   t0, OFF_RES + \id*16 + 12(s1)
.endm

# PUSH round (Zcmp stores s0 at sp-4, ra at sp-8): w0 = sp after, w1 = [SP0-4] (s0), w2 = [SP0-8] (ra)
.macro PUSH_ROUND id, nops, kind
    li   t0, SP0
    sw   zero, -4(t0)
    sw   zero, -8(t0)
    lw   zero, -8(t0)
    BEGIN_ROUND push_esc_\id
    li   ra, 0x1A000000 + \id
    li   s0, 0x50000000 + \id
    li   sp, SP0
    FAULT \kind
    .rept \nops
    nop
    .endr
    cm.push {ra, s0}, -16
    SETTLE
push_esc_\id:
    mv   t2, sp
    li   sp, SP0
    li   s1, SBASE
    sw   t2, OFF_RES + \id*16 + 0(s1)
    lw   t2, -4(sp)
    sw   t2, OFF_RES + \id*16 + 4(s1)
    lw   t2, -8(sp)
    sw   t2, OFF_RES + \id*16 + 8(s1)
    RECORD_DELTA \id
.endm

# MVA round: w0 = a0, w1 = a1, w2 = 0
.macro MVA_ROUND id, nops, kind
    BEGIN_ROUND mva_esc_\id
    li   a0, 0xDEAD0A00
    li   a1, 0xDEAD0A01
    li   s2, 0x22000000 + \id
    li   s3, 0x33000000 + \id
    FAULT \kind
    .rept \nops
    nop
    .endr
    cm.mva01s s2, s3
    SETTLE
mva_esc_\id:
    li   s1, SBASE
    sw   a0, OFF_RES + \id*16 + 0(s1)
    sw   a1, OFF_RES + \id*16 + 4(s1)
    sw   zero, OFF_RES + \id*16 + 8(s1)
    RECORD_DELTA \id
.endm

# JT round: w0 = t5 (1 = landed on target, 0xFA11 = fell through, 0xE5C = escaped)
.macro JT_ROUND id, nops, kind
    li   s1, SBASE
    la   t0, jt_tgt_\id
    sw   t0, OFF_JVT(s1)
    lw   zero, OFF_JVT(s1)
    BEGIN_ROUND jt_esc_\id
    li   t5, 0
    FAULT \kind
    .rept \nops
    nop
    .endr
    cm.jt 0
    li   t5, 0xFA11
    j    jt_chk_\id
jt_esc_\id:
    li   t5, 0xE5C
    j    jt_chk_\id
jt_tgt_\id:
    li   t5, 1
jt_chk_\id:
    SETTLE
    li   s1, SBASE
    sw   t5, OFF_RES + \id*16 + 0(s1)
    sw   zero, OFF_RES + \id*16 + 4(s1)
    sw   zero, OFF_RES + \id*16 + 8(s1)
    RECORD_DELTA \id
.endm

_start:
    li   sp, SP0
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0              # ...then MDT=0

    la   t0, nmi_handler
    csrw MARV_NMVEC, t0
    la   t0, mtvec_handler
    csrw mtvec, t0

    li   s1, SBASE
    sw   zero, OFF_NMI_CNT(s1)
    sw   zero, OFF_MTVEC_CNT(s1)
    li   t0, SBASE + OFF_JVT
    csrw JVT, t0
    nop
    nop

    li   x31, 0x11111111            # Sync: set up

    PUSH_ROUND 0, 0, 0
    PUSH_ROUND 1, 1, 0
    PUSH_ROUND 2, 2, 0
    PUSH_ROUND 3, 0, 1
    PUSH_ROUND 4, 1, 1
    MVA_ROUND  5, 0, 0
    MVA_ROUND  6, 1, 0
    MVA_ROUND  7, 0, 1
    JT_ROUND   8, 0, 1
    JT_ROUND   9, 1, 1
    JT_ROUND  10, 0, 0
    JT_ROUND  11, 1, 0

    li   s1, SBASE
    lw   zero, OFF_MTVEC_CNT(s1)
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
