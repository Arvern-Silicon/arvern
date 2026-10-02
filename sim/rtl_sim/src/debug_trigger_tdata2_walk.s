#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_tdata2_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: tdata2 bit walk and NAPOT size sweep on every trigger
#
#   doc/debug_interface.md 8: tselect "Only the low 3 bits of the written value
#   are considered; a 3-bit value beyond DM_TRIGGER_NR-1 clamps to
#   DM_TRIGGER_NR-1"; tdata1 "type[31:28] WARL, always reads 6"; tdata2
#   "32-bit match value"; "Match types: match=0 (exact) and match=1 (NAPOT
#   range), for both execute and load/store"; load/store action=0 ->
#   "mcause=3, mepc = the load/store PC, mtval = the data address"; "store
#   does not modify memory; load does not update its destination"; hit0 is
#   set "when that trigger fires, whatever its action"; "A software-written
#   (csrw) trigger takes effect only after the write retires".
#   Debug 1.0 mcontrol6.match: "1 (napot): Matches when the top M bits of any
#   compare value match the top M bits of tdata2. M is XLEN-1 minus the index
#   of the least-significant bit containing 0 in tdata2. [...] Legal values
#   for tdata2 require M + maskmax6 >= XLEN and M > 0."
#   Debug 1.0 5.7.x (maskmax6 discovery): "Write tdata1=0 [...] Write tdata2=0
#   [...] Write tdata1 with type=mcontrol6 and match=1. Read match. [...]
#   Write all ones to tdata2. Read tdata2. The value of maskmax6 is the index
#   of the most significant 0 bit plus 1."
#
#   Global: tselect <- 7 reads NR-1; tselect <- 8 reads 0.
#   PART A, per trigger t (tdata1 = 0, disarmed): tselect reads t, tdata1
#     reads 0x60000000; tdata2 <- 0xFFFFFFFF, 0, walking one and walking zero
#     over bits 0..31, each read back exactly.
#   PART B, per trigger t: maskmax6 discovery (match reads 1; kmax = min(30,
#     index of the most significant 0 of the all-ones read-back, 31 if none);
#     every trigger must report the same kmax). Then for k = 0..kmax, with
#     k trailing ones the range is 2^(k+1) bytes:
#       k 0..23  B = 0x81000000        k 24..30 B = 0x80000000
#       tdata2 = B | (2^k - 1); tdata1 = mcontrol6 | match=1 | m | store | load
#       (action=0, size=any) = 0x600000C3; both read back exactly.
#       M-mode LB+SB at B and at B+size-1: both fire (mcause 3, mepc = the
#       LB/SB, mtval = the address, hit0 set, LB rd unchanged);
#       LB+SB at B-1 and at B+size (not for k = 30): no fire.
#       tdata1 <- 0.
#   Non-firing accesses outside the bench memories reach the executable SRAM
#   through the bench alias (armed by the .v); an RNMI is counted as an
#   error. The handlers touch no memory.
#
#   Every check writes x31 = 0x5 << 28 | phase << 24 | t << 16 | k << 8 | idx.
#   Result registers:
#     s5 (x21) checks performed      s6 (x22) failures (0)
#     s7 (x23) first failing x31 code (0)
#     s10 (x26) handler mismatches: mtval/hit0 +1, unexpected cause/mepc
#               +0x10000
#     s11 (x27) kmax                 a1 (x11) all-ones tdata2 read-back (match=1)
#     a3 (x13) load fires            a4 (x14) store fires
#     a7 (x17) RNMIs (0)
#   Handler-only registers: t5, gp, tp.
#
# Requires DEBUG_EN == 1 and DM_TRIGGER_NR > 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.option norvc

.equ MARV_NMVEC,   0x7FD
.equ MARV_ESTAT,   0x7FE
.equ TSELECT,      0x7A0
.equ TDATA1,       0x7A1
.equ TDATA2,       0x7A2
.equ TCONTROL,     0x7A5
.equ T1_OFF,       0x60000000               # type 6, disarmed
.equ T1_NAPOT,     0x60000080               # type 6, match=1, disarmed
.equ T1_ARM,       0x600000C3               # type 6, match=1, m, store, load
.equ LD_POISON,    0x0BAD0BAD
.equ CTX_BASE,     0x50000000
.equ NT,           CFG_DM_TRIGGER_NR

main:
    j _start

    #=================================================================
    # M trap handler (no memory access)
    #=================================================================
    .align 2
m_handler:
    csrr t5, mcause
    li   gp, 3
    bne  t5, gp, h_unexp
    csrr t5, mepc
    la   gp, probe_ld
    bne  t5, gp, 1f
    ori  s9, s9, 1
    addi a3, a3, 1
    j    h_chk
1:  la   gp, probe_st
    bne  t5, gp, h_unexp
    ori  s9, s9, 2
    addi a4, a4, 1
h_chk:
    csrr t5, mtval
    beq  t5, a0, 2f
    addi s10, s10, 1
2:  csrr t5, TDATA1
    srli t5, t5, 22
    andi t5, t5, 1
    bnez t5, h_skip
    addi s10, s10, 1
    j    h_skip
h_unexp:
    li   gp, 0x10000
    add  s10, s10, gp
h_skip:
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret

    #=================================================================
    # RNMI handler: a non-firing access got a bus error. Count it.
    #=================================================================
    .align 2
nmi_handler:
    csrw 0x740, t5                  # mnscratch
    li   t5, 5
    csrw MARV_ESTAT, t5             # W1C valid|overrun
    addi a7, a7, 1
    csrr t5, 0x740
    .word 0x70200073                # mnret

    #=================================================================
    # Probe: LB then SB at a0.
    #=================================================================
    .align 2
probe:
    li   s9, 0
    li   t3, LD_POISON
    li   t4, 0x5A
probe_ld:
    lb   t3, 0(a0)
probe_st:
    sb   t4, 0(a0)
    jalr x0, 0(ra)

#=========================================================================
# Macros
#=========================================================================
.macro CHK reg, code
    li   t2, \code
    or   t2, t2, s4
    mv   x31, t2
    addi s5, s5, 1
    beqz \reg, .Lchk_ok\@
    addi s6, s6, 1
    bnez s7, .Lchk_ok\@
    mv   s7, t2
.Lchk_ok\@:
.endm

.macro CTX
    slli s4, s0, 16
    slli t0, s1, 8
    or   s4, s4, t0
    li   t0, CTX_BASE
    or   s4, s4, t0
.endm

# a2 = expected fire mask (0 or 3): mask check, then rd check.
.macro PROBE_CHECK code
    jal  ra, probe
    xor  t0, s9, a2
    CHK  t0, \code
    li   t0, 0
    beqz a2, .Lpc\@
    li   t1, LD_POISON
    xor  t0, t3, t1
.Lpc\@:
    CHK  t0, (\code)+1
.endm

#=========================================================================
_start:
    li   sp, 0x80010000
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, nmi_handler
    csrw MARV_NMVEC, t0
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw mstatush, x0               # mstatus.MDT = 0
    csrci mstatus, 8                # MIE = 0
    csrsi TCONTROL, 8               # tcontrol.MTE = 1

    li   s0, 0
    li   s1, 0
    li   s4, CTX_BASE
    li   s5, 0
    li   s6, 0
    li   s7, 0
    li   s9, 0
    li   s10, 0
    li   s11, 0
    li   a1, 0
    li   a3, 0
    li   a4, 0
    li   a5, 0
    li   a7, 0

    li   t0, 0                      # disarm every trigger
1:  csrw TSELECT, t0
    csrw TDATA1, x0
    csrw TDATA2, x0
    addi t0, t0, 1
    li   t1, NT
    blt  t0, t1, 1b

    li   x31, 0x11111111            # Sync: PART A

    li   t0, 7
    csrw TSELECT, t0
    csrr t0, TSELECT
    xori t0, t0, NT - 1
    CHK  t0, 0x0F000000
    li   t0, 8
    csrw TSELECT, t0
    csrr t0, TSELECT
    CHK  t0, 0x0F000001

    #=================================================================
    # PART A: tdata2 bit walk, trigger disarmed
    #=================================================================
    li   s0, 0
a_trig:
    li   s1, 0
    CTX
    csrw TSELECT, s0
    csrr t0, TSELECT
    xor  t0, t0, s0
    CHK  t0, 0x01000000
    csrw TDATA1, x0
    csrr t0, TDATA1
    li   t1, T1_OFF
    xor  t0, t0, t1
    CHK  t0, 0x01000001
    li   a0, -1
    csrw TDATA2, a0
    csrr t0, TDATA2
    xor  t0, t0, a0
    CHK  t0, 0x01000002
    csrw TDATA2, x0
    csrr t0, TDATA2
    CHK  t0, 0x01000003
a_ones:
    CTX
    li   t0, 1
    sll  a0, t0, s1
    csrw TDATA2, a0
    csrr t0, TDATA2
    xor  t0, t0, a0
    CHK  t0, 0x01000004
    addi s1, s1, 1
    li   t0, 32
    blt  s1, t0, a_ones
    li   s1, 0
a_zeros:
    CTX
    li   t0, 1
    sll  a0, t0, s1
    not  a0, a0
    csrw TDATA2, a0
    csrr t0, TDATA2
    xor  t0, t0, a0
    CHK  t0, 0x01000005
    addi s1, s1, 1
    li   t0, 32
    blt  s1, t0, a_zeros
    csrw TDATA2, x0
    addi s0, s0, 1
    li   t0, NT
    blt  s0, t0, a_trig

    li   x31, 0x22222222            # Sync: PART B

    #=================================================================
    # PART B: NAPOT size sweep
    #=================================================================
    li   s0, 0
b_trig:
    li   s1, 0
    CTX
    csrw TSELECT, s0
    csrw TDATA1, x0
    csrw TDATA2, x0
    li   t0, T1_NAPOT
    csrw TDATA1, t0
    csrr t0, TDATA1
    srli t0, t0, 7
    andi t0, t0, 0xF
    xori t0, t0, 1
    CHK  t0, 0x02000000
    li   t0, -1
    csrw TDATA2, t0
    csrr a1, TDATA2
    not  t1, a1
    li   s11, 31
    beqz t1, 2f
1:  bltz t1, 2f
    slli t1, t1, 1
    addi s11, s11, -1
    j    1b
2:  li   t0, 30
    ble  s11, t0, 3f
    li   s11, 30
3:  bnez s0, 4f
    mv   a5, s11
4:  xor  t0, s11, a5
    CHK  t0, 0x02000001
    csrw TDATA1, x0
    csrw TDATA2, x0

b_size:
    CTX
    li   t0, 2
    sll  s3, t0, s1                 # size = 2 << k
    li   s2, 0x81000000
    li   t0, 23
    ble  s1, t0, 1f
    li   s2, 0x80000000
1:  li   t0, 1
    sll  t0, t0, s1
    addi t0, t0, -1
    or   s8, s2, t0                 # tdata2
    csrw TDATA1, x0
    csrw TDATA2, s8
    li   t0, T1_ARM
    csrw TDATA1, t0
    csrr t0, TDATA2
    xor  t0, t0, s8
    CHK  t0, 0x02000002
    csrr t0, TDATA1
    li   t1, T1_ARM
    xor  t0, t0, t1
    CHK  t0, 0x02000003

    li   a2, 3
    mv   a0, s2
    PROBE_CHECK 0x02000010
    add  a0, s2, s3
    addi a0, a0, -1
    PROBE_CHECK 0x02000012
    li   a2, 0
    addi a0, s2, -1
    PROBE_CHECK 0x02000014
    li   t0, 30
    beq  s1, t0, 5f
    add  a0, s2, s3
    PROBE_CHECK 0x02000016
5:  csrw TDATA1, x0

    addi s1, s1, 1
    ble  s1, s11, b_size
    csrw TDATA2, x0
    addi s0, s0, 1
    li   t0, NT
    blt  s0, t0, b_trig

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
