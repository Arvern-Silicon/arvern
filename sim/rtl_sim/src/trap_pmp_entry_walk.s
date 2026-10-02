#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_entry_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP entry walk -- every writable entry, every permission pattern,
#              M and U, unlocked and locked, then lock and read back
#
#   Priv 3.7.1: "The R, W, and X bits, when set, indicate that the PMP entry
#   permits read, write, and instruction execution, respectively. When one of
#   these bits is clear, the corresponding access type is denied. The R, W,
#   and X fields form a collective WARL field for which the combinations with
#   R=0 and W=1 are reserved."
#   Priv 3.7.1.2: "When the L bit is set, these permissions are enforced for
#   all privilege modes. When the L bit is clear, any M-mode access matching
#   the PMP entry will succeed". "If PMP entry i is locked, writes to pmpicfg
#   and pmpaddri are ignored."
#   Smepmp (Priv, mseccfg.RLB): "When mseccfg.RLB is 1 locked PMP rules may be
#   removed/modified and locked PMP entries may be edited."
#   doc/traps_and_interrupts.md: mtval for causes 1, 5, 7 is "The faulting
#   (access-faulting) address".
#
#   Entries walked: 0..15 when PMP_NR >= 16, 0..7 when PMP_NR >= 8, else 0..3.
#
#   PART A (mseccfg.RLB = 1, so a locked entry can be rewritten):
#     for each entry e, e is the only entry matching region R (16-byte NAPOT
#     at 0x80003000, holding a `jalr x0, 0(ra)` word); the only other active
#     entry is a helper -- entry 1 for e = 0, else entry 0 -- granting R+X
#     over the ROM so U-mode code can run. For each pattern R, W, X, RW, RX,
#     RWX:
#       1 cfg = NAPOT|perm (L=0), read back
#       2 U-mode probe            -> outcome follows the read-back perm
#       3 M-mode probe            -> everything allowed
#       4 cfg = L|NAPOT|perm, read back
#       5 M-mode probe            -> outcome follows the read-back perm
#       6 U-mode probe            -> outcome follows the read-back perm
#     A probe is: LW from R, SW to R+4, JALR to R (executes the return word),
#     ECALL. The handler ORs 1/2/4 into s9 for cause 5/7/1 and checks mtval
#     (and mepc for cause 1). Steps 2 and 6 need S/U (CFG_SU_MODE_EN).
#     W alone (R=0, W=1) is a reserved WARL encoding the documentation does
#     not map: its read-back is checked only for the L and A fields, and the
#     store outcome is not asserted while the read-back still holds R=0, W=1.
#
#   PART B (RLB cleared with no entry locked): each entry e is locked on its
#     own 16-byte NAPOT region at 0x80004000 + 16e with a varying permission;
#     then writes of 0 to pmpaddr_e and pmpcfg_(e/4), and a write flipping
#     entry e's cfg byte, must all be ignored. Finally every pmpcfg word is
#     read back (entries at or above PMP_NR read 0) and RLB cannot be set.
#
#   Result registers:
#     s5 (x21) checks performed   s6 (x22) failures (expect 0)
#     s7 (x23) first failure: (entry << 8) | (step << 4) | perm
#     s10 (x26) handler mismatches: mtval/mepc (+1 each), unexpected cause
#               (+0x10000 each) -- expect 0
#   Scratchpad: 0x80000100 handler save area, 0x80000200 + 4w final pmpcfgw.
#
# Requires PMP_NR > 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.option norvc

.equ SAVE,         0x80000100
.equ CFG_OUT,      0x80000200
.equ REGION,       0x80003000
.equ REGION_NAPOT, (REGION >> 2) | 1
.equ ROM_NAPOT,    (0x20000000 >> 2) | 0x1FFF      # 64 KB
.equ LOCK_BASE,    0x80004000
.equ MSECCFG,      0x747
.equ RET_WORD,     0x00008067                      # jalr x0, 0(ra)
.equ LD_POISON,    0x0BAD0BAD

.if CFG_PMP_NR >= 16
.equ NE, 16
.elseif CFG_PMP_NR >= 8
.equ NE, 8
.else
.equ NE, 4
.endif

main:
    j _start

    #=================================================================
    # M trap handler
    #=================================================================
    .align 2
m_handler:
    csrw mscratch, t0
    li   t0, SAVE
    sw   t1, 0(t0)
    sw   t2, 4(t0)
    csrr t1, mcause
    li   t2, 5
    beq  t1, t2, h_load
    li   t2, 7
    beq  t1, t2, h_store
    li   t2, 1
    beq  t1, t2, h_fetch
    li   t2, 8
    beq  t1, t2, h_ecall
    li   t2, 11
    beq  t1, t2, h_ecall
    li   t2, 0x10000                # unexpected: abandon the probe
    add  s10, s10, t2
    sw   t1, 8(t0)
    j    h_ecall
h_load:
    ori  s9, s9, 1
    csrr t1, mtval
    beq  t1, s11, h_skip
    addi s10, s10, 1
    j    h_skip
h_store:
    ori  s9, s9, 2
    csrr t1, mtval
    addi t2, s11, 4
    beq  t1, t2, h_skip
    addi s10, s10, 1
    j    h_skip
h_fetch:
    ori  s9, s9, 4
    csrr t1, mtval
    beq  t1, s11, 1f
    addi s10, s10, 1
1:  csrr t1, mepc
    beq  t1, s11, 2f
    addi s10, s10, 1
2:  csrw mepc, ra                   # the JALR linked the ECALL's address
    j    h_out
h_skip:
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    j    h_out
h_ecall:
    csrw mepc, s8
    li   t1, 0x1800
    csrs mstatus, t1                # MPP = M
h_out:
    lw   t2, 4(t0)
    lw   t1, 0(t0)
    csrr t0, mscratch
    mret

    #=================================================================
    # Probe (runs in M or U). s11 = R.
    #=================================================================
    .align 2
probe:
    li   s9, 0
    li   t3, LD_POISON
    li   t4, 0x00000013
    lw   t3, 0(s11)
    sw   t4, 4(s11)
    jalr ra, 0(s11)
    ecall

#=========================================================================
# Macros
#=========================================================================
.macro CHK reg, code
    addi s5, s5, 1
    beqz \reg, .Lchk_ok\@
    addi s6, s6, 1
    bnez s7, .Lchk_ok\@
    li   s7, \code
    or   s7, s7, s3
.Lchk_ok\@:
.endm

# cfg byte of entry \e <- a0
.macro SETCFG e
    csrr t0, 0x3A0 + ((\e) >> 2)
    li   t1, (~(0xFF << (((\e) & 3) * 8))) & 0xFFFFFFFF
    and  t0, t0, t1
    slli t1, a0, ((\e) & 3) * 8
    or   t0, t0, t1
    csrw 0x3A0 + ((\e) >> 2), t0
.endm

# s4 <- cfg byte of entry \e
.macro GETCFG e
    csrr s4, 0x3A0 + ((\e) >> 2)
    srli s4, s4, ((\e) & 3) * 8
    andi s4, s4, 0xFF
.endm

.macro CLEAR_ALL
    csrw pmpcfg0, zero
    csrw pmpcfg1, zero
    csrw pmpcfg2, zero
    csrw pmpcfg3, zero
.endm

# Read-back of the byte just written (a0): exact, except for the reserved
# R=0,W=1 pattern where only L and A are compared.
.macro RB_CHECK code
    li   t1, 0xFF
    andi t0, a0, 3
    li   t2, 2
    bne  t0, t2, .Lrb\@
    li   t1, 0x98
.Lrb\@:
    xor  t0, s4, a0
    and  t0, t0, t1
    CHK  t0, \code
.endm

# a1 <- expected fault mask from the read-back perm in s4 (denied = ~perm),
# a2 <- mask of outcomes that are asserted.
.macro EXPECT_FROM_S4
    andi t0, s4, 7
    xori a1, t0, 7
    li   a2, 7
    andi t1, t0, 3
    li   t2, 2
    bne  t1, t2, .Lexp\@
    li   a2, 5
.Lexp\@:
.endm

# Two checks per probe: the fault mask, and the load's destination.
.macro CHECK_PROBE code
    xor  t0, s9, a1
    and  t0, t0, a2
    CHK  t0, \code
    li   t1, RET_WORD
    andi t0, a1, 1
    beqz t0, .Lcp\@
    li   t1, LD_POISON
.Lcp\@:
    xor  t0, t3, t1
    CHK  t0, \code
.endm

.macro PROBE_M
    la   s8, .Lpm\@
    j    probe
.Lpm\@:
.endm

.macro PROBE_U
    la   s8, .Lpu\@
    la   t0, probe
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0                # MPP = U
    mret
.Lpu\@:
.endm

.macro EWALK e
    CLEAR_ALL
.if (\e) == 0
    li   t0, ROM_NAPOT
    csrw pmpaddr1, t0
    li   a0, 0x1D                   # helper: NAPOT | X | R
    SETCFG 1
.else
    li   t0, ROM_NAPOT
    csrw pmpaddr0, t0
    li   a0, 0x1D
    SETCFG 0
.endif
    li   t0, REGION_NAPOT
    csrw 0x3B0 + (\e), t0
    li   s2, 0x753421               # patterns, low nibble first: R, W, X, RW, RX, RWX
.Lpat\@:
    andi s3, s2, 0xF

    ori  a0, s3, 0x18               # NAPOT | perm, unlocked
    SETCFG \e
    GETCFG \e
    RB_CHECK ((\e) << 8) | 0x10
    EXPECT_FROM_S4
.if CFG_SU_MODE_EN
    PROBE_U
    CHECK_PROBE ((\e) << 8) | 0x20
.endif
    li   a1, 0
    li   a2, 7
    PROBE_M
    CHECK_PROBE ((\e) << 8) | 0x30

    ori  a0, s3, 0x98               # L | NAPOT | perm
    SETCFG \e
    GETCFG \e
    RB_CHECK ((\e) << 8) | 0x40
    EXPECT_FROM_S4
    PROBE_M
    CHECK_PROBE ((\e) << 8) | 0x50
.if CFG_SU_MODE_EN
    PROBE_U
    CHECK_PROBE ((\e) << 8) | 0x60
.endif

    srli s2, s2, 4
    bnez s2, .Lpat\@
    li   a0, 0
    SETCFG \e                       # unlock (RLB = 1)
.endm

# PART B: lock entry \e and prove its registers ignore writes.
.macro ELOCK e
.if ((\e) % 6) == 0
    .set LK_CFG, 0x99
.elseif ((\e) % 6) == 1
    .set LK_CFG, 0x9C
.elseif ((\e) % 6) == 2
    .set LK_CFG, 0x9B
.elseif ((\e) % 6) == 3
    .set LK_CFG, 0x9D
.elseif ((\e) % 6) == 4
    .set LK_CFG, 0x9F
.else
    .set LK_CFG, 0x98
.endif
.if ((\e) & 3) == 0
    .set EXPW, 0
.endif
    .set EXPW, EXPW | (LK_CFG << (((\e) & 3) * 8))
    .set LK_ADDR, ((LOCK_BASE + 16 * (\e)) >> 2) | 1

    li   s3, 0
    li   t0, LK_ADDR
    csrw 0x3B0 + (\e), t0
    li   a0, LK_CFG
    SETCFG \e

    csrw 0x3B0 + (\e), zero
    csrr t0, 0x3B0 + (\e)
    li   t1, LK_ADDR
    xor  t0, t0, t1
    CHK  t0, ((\e) << 8) | 0x70

    csrw 0x3A0 + ((\e) >> 2), zero
    csrr t0, 0x3A0 + ((\e) >> 2)
    li   t1, EXPW
    xor  t0, t0, t1
    CHK  t0, ((\e) << 8) | 0x80

    li   t0, EXPW ^ ((LK_CFG ^ 0x1F) << (((\e) & 3) * 8))
    csrw 0x3A0 + ((\e) >> 2), t0
    csrr t0, 0x3A0 + ((\e) >> 2)
    li   t1, EXPW
    xor  t0, t0, t1
    CHK  t0, ((\e) << 8) | 0x90

.if ((\e) >> 2) == 0
    .set EXPW0, EXPW
.elseif ((\e) >> 2) == 1
    .set EXPW1, EXPW
.elseif ((\e) >> 2) == 2
    .set EXPW2, EXPW
.else
    .set EXPW3, EXPW
.endif
.endm

.macro FINAL_CFG w, expw
    csrr t0, 0x3A0 + (\w)
    sw   t0, (\w) * 4(s1)
    li   t1, \expw
    xor  t0, t0, t1
    CHK  t0, 0xF00 | ((\w) << 4)
.endm

#=========================================================================
_start:
    li   sp, 0x80010000
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw mstatush, x0               # mstatus.MDT = 0
    csrci mstatus, 8                # MIE = 0
    li   t0, 0x20000                # MPRV = 0
    csrc mstatus, t0

    li   s3, 0
    li   s5, 0
    li   s6, 0
    li   s7, 0
    li   s10, 0
    li   s11, REGION
    li   s1, CFG_OUT

    li   t0, RET_WORD
    sw   t0, 0(s11)
    sw   zero, 4(s11)
    fence.i

    # RLB must be settable while nothing is locked; everything below needs it.
    csrsi MSECCFG, 4
    csrr t0, MSECCFG
    andi t0, t0, 4
    xori t0, t0, 4
    CHK  t0, 0x001

    li   x31, 0x11111111            # Sync: PART A

    .set EXPW0, 0
    .set EXPW1, 0
    .set EXPW2, 0
    .set EXPW3, 0

    EWALK 0
    EWALK 1
    EWALK 2
    EWALK 3
.if NE >= 8
    EWALK 4
    EWALK 5
    EWALK 6
    EWALK 7
.endif
.if NE >= 16
    EWALK 8
    EWALK 9
    EWALK 10
    EWALK 11
    EWALK 12
    EWALK 13
    EWALK 14
    EWALK 15
.endif

    li   x31, 0x22222222            # Sync: PART B

    CLEAR_ALL                       # no L bit left anywhere
    csrci MSECCFG, 4                # RLB = 0

    ELOCK 0
    ELOCK 1
    ELOCK 2
    ELOCK 3
.if NE >= 8
    ELOCK 4
    ELOCK 5
    ELOCK 6
    ELOCK 7
.endif
.if NE >= 16
    ELOCK 8
    ELOCK 9
    ELOCK 10
    ELOCK 11
    ELOCK 12
    ELOCK 13
    ELOCK 14
    ELOCK 15
.endif

    li   s3, 0
    FINAL_CFG 0, EXPW0
    FINAL_CFG 1, EXPW1
    FINAL_CFG 2, EXPW2
    FINAL_CFG 3, EXPW3

    # A locked rule exists: RLB cannot be set again.
    csrsi MSECCFG, 4
    csrr t0, MSECCFG
    andi t0, t0, 4
    CHK  t0, 0x002

    lw   zero, 12(s1)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
