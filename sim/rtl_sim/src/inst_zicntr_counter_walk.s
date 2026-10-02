#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_counter_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Counter data-path walk (mcycle, minstret, mhpmcounterN) and
#              two minstret carry/borrow boundaries
#
#   PART A -- walking ones and walking zeros (64 patterns) through each half of
#   every implemented counter, with all counters frozen:
#     Priv 3.1.10: "When XLEN=32, reads of the mcycle, minstret, mhpmcountern
#     [...] CSRs return bits 31-0 of the corresponding register, and writes
#     change only bits 31-0; reads of the mcycleh, minstreth, mhpmcounternh
#     [...] return bits 63-32 [...] and writes change only bits 63-32."
#     Priv 3.1.11: "The cycle, instret, and hpmcountern CSRs are read-only
#     shadows of mcycle, minstret, and mhpmcounter n, respectively."
#     Priv 3.1.12: "When the CY, IR, or HPM_n_ bit is set, the corresponding
#     counter does not increment."
#   Per pattern: the written half reads back exactly, its user shadow reads the
#   same, and the other half still holds the sentinel written before the walk.
#   With ZIHPM_NR > 0 the unprovided mhpmcounter(N)(h), N = 3+ZIHPM_NR..10,
#   are written with every pattern and must read 0, shadows included
#   (doc/arvern_instructions.md, Zihpm: "the unprovided counters [...] are
#   read-only zero, not absent").
#
#   PART B -- minstret boundaries (IR running):
#     B1  minstreth = 0x123, minstret = 0xFFFFFFFF, then ECALL.
#         Priv 3.3.1: "As ECALL and EBREAK cause synchronous exceptions, they
#         are not considered to retire, and should not increment the minstret
#         CSR." aRVern "counts at
#         dispatch and un-retires the instruction at trap entry"
#         (doc/traps_and_interrupts.md) -- the ECALL's increment carries into
#         the high half, so the un-retire must borrow it back.
#         The handler's first instruction reads minstret (the count before it:
#         expect 0xFFFFFFFF), the second reads minstreth (that read has now
#         retired and carried: expect 0x124; a missed borrow reads 0x125).
#     B2  minstret = 0xFFFFFFFE, then csrw minstreth, 0x456, then NOPs, then
#         IR frozen. Priv 3.1.10: "Any CSR write takes effect after the writing
#         instruction has otherwise completed." The low half wraps AFTER the
#         high-half write (FE -> FF happens at most at the writer), so the
#         carry must land in the written value: minstreth = 0x457. The low
#         half is checked only as a window (see the .v).
#
#   Result registers:
#     s5 (x21) checks performed      s6 (x22) failures     s7 (x23) first code
#     s4 (x20) pattern of the first failure
#     s8 (x24) mcountinhibit after writing all ones
#     a6/a7 (x16/x17)  B1 minstret / minstreth read in the handler
#     s9 (x25)         B1 mcause (expect 11)
#     a2/a3 (x12/x13)  B2 minstret / minstreth
#
# Requires ZICNTR_EN == 1.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.option norvc

.equ MCYCLE,    0xB00
.equ MINSTRET,  0xB02
.equ MCYCLEH,   0xB80
.equ MINSTRETH, 0xB82
.equ CYCLE,     0xC00
.equ INSTRET,   0xC02
.equ CYCLEH,    0xC80
.equ INSTRETH,  0xC82
.equ MCOUNTINHIBIT, 0x320

main:
    j _start

    #=================================================================
    # Only the B1 ECALL reaches this handler. The minstret read must be
    # its FIRST instruction, the minstreth read its second.
    #=================================================================
    .align 2
m_handler:
    csrr a6, MINSTRET
    csrr a7, MINSTRETH
    csrr s9, mcause
    csrr a0, mepc
    addi a0, a0, 4
    csrw mepc, a0
    mret

# One check: \reg == 0 passes.
.macro CHK reg, code
    addi s5, s5, 1
    beqz \reg, .Lchk_ok\@
    addi s6, s6, 1
    bnez s7, .Lchk_ok\@
    li   s7, \code
    mv   s4, a2
.Lchk_ok\@:
.endm

# Walk one half: \w written, \sh its shadow, \o the other half (sentinel).
.macro WALK w, sh, o, code
    li   a3, 0x5A5AA5A5 ^ (\code)
    csrw \o, a3
    li   a4, 0                      # 0 = walking ones, 1 = walking zeros
.Lwalk_phase\@:
    li   a1, 1
.Lwalk_loop\@:
    mv   a2, a1
    beqz a4, .Lwalk_pat\@
    not  a2, a1
.Lwalk_pat\@:
    csrw \w, a2
    csrr t0, \w
    xor  t0, t0, a2
    CHK  t0, ((\code) << 4) | 1
    csrr t0, \sh
    xor  t0, t0, a2
    CHK  t0, ((\code) << 4) | 2
    csrr t0, \o
    xor  t0, t0, a3
    CHK  t0, ((\code) << 4) | 3
    slli a1, a1, 1
    bnez a1, .Lwalk_loop\@
    bnez a4, .Lwalk_done\@
    li   a4, 1
    j    .Lwalk_phase\@
.Lwalk_done\@:
.endm

# Unprovided HPM counter N: every pattern written to both halves reads 0.
.macro RAZ n, code
    li   a4, 0
.Lraz_phase\@:
    li   a1, 1
.Lraz_loop\@:
    mv   a2, a1
    beqz a4, .Lraz_pat\@
    not  a2, a1
.Lraz_pat\@:
    csrw 0xB00 + (\n), a2
    csrw 0xB80 + (\n), a2
    csrr t0, 0xB00 + (\n)
    CHK  t0, ((\code) << 4) | 1
    csrr t0, 0xB80 + (\n)
    CHK  t0, ((\code) << 4) | 2
    csrr t0, 0xC00 + (\n)
    CHK  t0, ((\code) << 4) | 3
    csrr t0, 0xC80 + (\n)
    CHK  t0, ((\code) << 4) | 4
    slli a1, a1, 1
    bnez a1, .Lraz_loop\@
    bnez a4, .Lraz_done\@
    li   a4, 1
    j    .Lraz_phase\@
.Lraz_done\@:
.endm

.macro HPM_ONE n
.if (\n) < (3 + CFG_ZIHPM_NR)
    WALK 0xB00 + (\n), 0xC00 + (\n), 0xB80 + (\n), 0x100 + ((\n) << 1)
    WALK 0xB80 + (\n), 0xC80 + (\n), 0xB00 + (\n), 0x101 + ((\n) << 1)
.else
    RAZ  \n, 0x200 + (\n)
.endif
.endm

_start:
    li   sp, 0x80010000
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw mstatush, x0               # mstatus.MDT = 0
    csrci mstatus, 8                # MIE = 0

    li   s4, 0
    li   s5, 0
    li   s6, 0
    li   s7, 0

    li   t0, -1
    csrw MCOUNTINHIBIT, t0          # freeze every counter
    csrr s8, MCOUNTINHIBIT

    li   x31, 0x11111111            # Sync: start of the walk

    #=================================================================
    # PART A
    #=================================================================
    WALK MCYCLE,    CYCLE,    MCYCLEH,   0x10
    WALK MCYCLEH,   CYCLEH,   MCYCLE,    0x11
    WALK MINSTRET,  INSTRET,  MINSTRETH, 0x12
    WALK MINSTRETH, INSTRETH, MINSTRET,  0x13

.if CFG_ZIHPM_NR > 0
    HPM_ONE 3
    HPM_ONE 4
    HPM_ONE 5
    HPM_ONE 6
    HPM_ONE 7
    HPM_ONE 8
    HPM_ONE 9
    HPM_ONE 10
.endif

    li   x31, 0x22222222            # Sync: walk done

    #=================================================================
    # PART B1 -- ECALL at minstret = 0xFFFFFFFF
    #=================================================================
    li   a6, 0
    li   a7, 0
    li   s9, 0
    li   t0, 4
    csrc MCOUNTINHIBIT, t0          # IR counts from here on
    li   t1, 0x123
    li   t2, 0xFFFFFFFF
    csrw MINSTRETH, t1
    csrw MINSTRET, t2
    ecall

    #=================================================================
    # PART B2 -- csrw minstreth while minstret = 0xFFFFFFFE
    #=================================================================
    li   t0, 4
    li   t1, 0x456
    li   t2, 0xFFFFFFFE
    csrw MINSTRET, t2
    csrw MINSTRETH, t1
    nop
    nop
    nop
    nop
    csrs MCOUNTINHIBIT, t0          # freeze IR again
    csrr a2, MINSTRET
    csrr a3, MINSTRETH

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
