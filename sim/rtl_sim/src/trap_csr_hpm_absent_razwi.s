#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_csr_hpm_absent_razwi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: HPM ABSENT/RAZWI - Zihpm two-case existence rule (M-mode)
#   Runs on every configuration and adapts with .if CFG_ZIHPM_NR.
#
#   ZIHPM_NR == 0: Zihpm is absent. Priv §2.1: accesses to non-existent CSRs
#     raise illegal-instruction; spec_compliance_notes.md "RAZ/WI in known
#     banks": "at ZIHPM_NR == 0 the extension is absent and
#     mhpmcounter3-31/mhpmevent3-31 raise illegal-instruction". Probed:
#     mhpmcounter3/mhpmevent3 read and write, mhpmcounterh3, hpmcounter3,
#     mhpmcounter31, mhpmevent31.
#   ZIHPM_NR > 0: implemented counters are 3..ZIHPM_NR+2 (at most 3..10), so
#     index 11 and 31 are always unprovided. Priv §3.1.10: "a legal
#     implementation is to make both the counter and its corresponding event
#     selector be read-only 0"; the same note: "at ZIHPM_NR > 0 the whole
#     set exists and the registers this build does not provide are
#     read-only zero, not absent". Probed: mhpmcounter11, mhpmevent11,
#     mhpmcounterh31, mhpmevent31, mhpmcounter31 (all-ones write, no trap,
#     read 0), hpmcounter31 / hpmcounterh11 (read 0). Control: mhpmevent3
#     (implemented) reads back a written event code.
#   Both cases: a write to hpmcounter3 (0xC03, csr[11:10]=11) traps. Priv
#     §2.1: "attempts to write a read-only register raise illegal-instruction".
#
#   Probe mechanism: s2 = index, s3 = &probe, a0 = sentinel 0x5A5A5A5A.
#   Slot 0x100 + 32*index: +0 mcause, +4 mtval, +8 mepc-s3, +12 MPP, +16 rd;
#   pre-filled 0xEEEEEEEE.
#
#   Scratchpad (base 0x80000000):
#   0x00: illegal-instruction trap count (expect 9 at ZIHPM_NR=0, 1 otherwise)
#   0x04: unexpected (non-illegal) mcause (0 if none)
#   0x100+: probe slots
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ SPAD,       0x80000000
.equ SLOT_BASE,  0x80000100
.equ SENT,       0x5A5A5A5A
.equ NSLOTS,     16

.macro PROBE idx, insn:vararg
    li   s2, \idx
    li   a0, SENT
    la   s3, 991f
991:
    \insn
    li   t0, SLOT_BASE + (\idx * 32)
    sw   a0, 16(t0)
.endm

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE HANDLER (direct). Uses t3-t6 only.
    #=================================================================
    .align 2
m_handler:
    csrr t3, mcause
    li   t4, 2
    beq  t3, t4, m_illegal
    sw   t3, 0x04(s1)
    li   x31, 0x0BADBADB
m_fail_loop:
    j    m_fail_loop

m_illegal:
    slli t4, s2, 5
    add  t4, t4, s1
    sw   t3, 0x100(t4)
    csrr t5, mtval
    sw   t5, 0x104(t4)
    csrr t5, mepc
    sub  t6, t5, s3
    sw   t6, 0x108(t4)
    csrr t6, mstatus
    srli t6, t6, 11
    andi t6, t6, 3
    sw   t6, 0x10C(t4)
    lw   t6, 0x00(s1)
    addi t6, t6, 1
    sw   t6, 0x00(s1)
    addi t5, t5, 4
    li   t6, 0x7EEDBEEF
    csrw mtval, t6              # marker: the next trap must write mtval
    csrw mepc, t5
    mret

    #=================================================================
    # MAIN
    #=================================================================
    .align 2
_start:
    csrsi 0x744, 8              # mnstatus.NMIE = 1 (first)
    csrw  mstatush, x0          # mstatus.MDT = 0 (second)

    li   s1, SPAD
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    li   t0, SLOT_BASE
    li   t1, SLOT_BASE + (NSLOTS * 32)
    li   t2, 0xEEEEEEEE
fill_loop:
    sw   t2, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, fill_loop

    la   t0, m_handler
    csrw mtvec, t0
    li   t0, 0x7EEDBEEF
    csrw mtval, t0              # marker: the first trap must write mtval

    li   x31, 0x11111111
    li   a1, 0xFFFFFFFF

.if CFG_ZIHPM_NR == 0
    # ---- Zihpm absent: every access traps ----
    PROBE  0, csrr  a0, 0xB03       # mhpmcounter3
    PROBE  1, csrw  0xB03, a1
    PROBE  2, csrr  a0, 0x323       # mhpmevent3
    PROBE  3, csrw  0x323, a1
    PROBE  4, csrr  a0, 0xB83       # mhpmcounterh3
    PROBE  5, csrr  a0, 0xC03       # hpmcounter3
    PROBE  6, csrr  a0, 0xB1F       # mhpmcounter31
    PROBE  7, csrr  a0, 0x33F       # mhpmevent31
    PROBE  8, csrw  0xC03, a1       # write to a read-only CSR
.else
    # ---- Zihpm present: implemented control ----
    li   a2, 7
    PROBE  0, csrw  0x323, a2       # mhpmevent3 = 7 (load event)
    PROBE  1, csrr  a0, 0x323       # rd = 7
    # ---- unprovided indices: read-only zero, no trap ----
    PROBE  2, csrw  0xB0B, a1       # mhpmcounter11
    PROBE  3, csrr  a0, 0xB0B
    PROBE  4, csrw  0x32B, a1       # mhpmevent11
    PROBE  5, csrr  a0, 0x32B
    PROBE  6, csrw  0xB9F, a1       # mhpmcounterh31
    PROBE  7, csrr  a0, 0xB9F
    PROBE  8, csrw  0x33F, a1       # mhpmevent31
    PROBE  9, csrr  a0, 0x33F
    PROBE 10, csrw  0xB1F, a1       # mhpmcounter31
    PROBE 11, csrr  a0, 0xB1F
    PROBE 12, csrr  a0, 0xC1F       # hpmcounter31
    PROBE 13, csrr  a0, 0xC8B       # hpmcounterh11
    PROBE 14, csrw  0xC03, a1       # write to a read-only CSR -> traps
    csrw 0x323, zero                # mhpmevent3 back to "no event"
.endif

    lw   t0, 0x00(s1)           # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
