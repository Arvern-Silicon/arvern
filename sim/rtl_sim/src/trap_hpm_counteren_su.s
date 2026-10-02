#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_hpm_counteren_su
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: hpmcounter3..10 / hpmcounterh3..10 from S and U under
#              mcounteren x scounteren combinations
#
#   Priv §3.1.11: "When the CY, TM, IR, or HPMn bit in the mcounteren register
#   is clear, attempts to read the cycle, time, instret, or hpmcountern
#   register while executing in S-mode or U-mode will cause an
#   illegal-instruction exception. When one of these bits is set, access to
#   the corresponding register is permitted in the next implemented privilege
#   mode (S-mode if implemented, otherwise U-mode)."
#   Priv §12.1.4 (scounteren): "When the CY, TM, IR, or HPMn bit in the
#   scounteren register is clear, attempts to read the cycle, time, instret,
#   or hpmcountern register while executing in U-mode will cause an
#   illegal-instruction exception. When one of these bits is set, access to
#   the corresponding register is permitted in U-mode."
#   software_guide.md §11: "U-mode access ... requires the corresponding bit
#   set in both mcounteren and scounteren ... S-mode's own counter access is
#   gated by mcounteren alone."
#   spec_compliance_notes.md: at ZIHPM_NR > 0 "the registers this build does
#   not provide are read-only zero, not absent".
#
#   The HPM counters are frozen (mcountinhibit[10:3]) and preloaded with
#   lo = 0xC0DE0000|N, hi = 0xB1C00000|N. For each phase the enables are
#   written and read back; S and U then read all 16 shadows. A read that
#   traps leaves the marker 0xBADC0DE0 in its result word.
#
#   Phase  mcounteren[10:3]  scounteren[10:3]
#     0        0x000              0x000
#     1        0x000              0x7F8
#     2        0x7F8              0x000
#     3        0x7F8              0x7F8
#     4        0x2A8              0x198   (every (m,s) pair across the bits)
#
#   0x80000100 + 16*p: +0 mcounteren read back, +4 scounteren read back
#   0x80000200 + 64*(2p+m) (m 0 = S, 1 = U): 8 x hpmcounterN, 8 x hpmcounterhN
#   0x80000000: cause-2 traps   0x80000004: unexpected traps
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSTATUS,  0x744
.equ MSTATUSH,  0x310
.equ MCOUNTINHIBIT, 0x320
.equ MARK,      0xBADC0DE0
.equ HDR,       0x80000100
.equ RES,       0x80000200

.section .text
.global main

main:
    j    _start

#=========================================================================
# M handler: cause 2 skipped; ECALL from U/S returns to M at s10
#=========================================================================
    .align 2
m_handler:
    csrr t0, mcause
    li   t1, 8
    beq  t0, t1, m_to_m
    li   t1, 9
    beq  t0, t1, m_to_m
    li   t1, 2
    beq  t0, t1, 1f
    lw   t1, 4(s1)
    addi t1, t1, 1
    sw   t1, 4(s1)
    j    2f
1:  lw   t1, 0(s1)
    addi t1, t1, 1
    sw   t1, 0(s1)
2:  csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    mret
m_to_m:
    li   t1, 0x1800
    csrs mstatus, t1
    csrw mepc, s10
    mret

#=========================================================================
# Read all 16 HPM shadows into a1[0..15] (run in S or U)
#=========================================================================
.macro RDC csr, off
    mv   a0, a6
    csrr a0, \csr
    sw   a0, \off(a1)
.endm

    .align 2
read_shadows:
    RDC 0xC03, 0
    RDC 0xC04, 4
    RDC 0xC05, 8
    RDC 0xC06, 12
    RDC 0xC07, 16
    RDC 0xC08, 20
    RDC 0xC09, 24
    RDC 0xC0A, 28
    RDC 0xC83, 32
    RDC 0xC84, 36
    RDC 0xC85, 40
    RDC 0xC86, 44
    RDC 0xC87, 48
    RDC 0xC88, 52
    RDC 0xC89, 56
    RDC 0xC8A, 60
    ecall                           # back to M at s10

# a0 = 0 (U) / 1 (S)
    .align 2
enter_lower:
    li   t0, 0x1800
    csrc mstatus, t0
    slli t0, a0, 11
    csrs mstatus, t0
    la   t0, read_shadows
    csrw mepc, t0
    mret

#-------------------------------------------------------------------------
# One phase: write the enables, read them back, run S then U
#-------------------------------------------------------------------------
.macro PHASE p, mcen, scen
    li   t0, \mcen
    csrw mcounteren, t0
    li   t0, \scen
    csrw scounteren, t0
    li   t2, HDR + 16*\p
    csrr t0, mcounteren
    sw   t0, 0(t2)
    csrr t0, scounteren
    sw   t0, 4(t2)
    li   a1, RES + 64*(2*\p)
    li   a0, 1
    la   s10, 91f
    j    enter_lower
91: li   a1, RES + 64*(2*\p + 1)
    li   a0, 0
    la   s10, 92f
    j    enter_lower
92:
.endm

.macro PRELOAD n
    li   t0, 0xC0DE0000 | \n
    csrw 0xB00 + \n, t0
    li   t0, 0xB1C00000 | \n
    csrw 0xB80 + \n, t0
.endm

#=========================================================================
_start:
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE = 1 first
    csrw MSTATUSH, x0               # then MDT = 0

    li   sp, 0x80010000
    li   s1, 0x80000000
    li   a6, MARK
    PMP_ALLOW_ALL
    mv   t0, s1
    li   t1, 0x80000600
1:  sw   x0, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b

    la   t0, m_handler
    csrw mtvec, t0
    csrw medeleg, x0

    li   t0, 0x7F8
    csrs MCOUNTINHIBIT, t0          # freeze mhpmcounter3..10
    csrw 0x323, x0                  # mhpmevent3..10 = no event
    csrw 0x324, x0
    csrw 0x325, x0
    csrw 0x326, x0
    csrw 0x327, x0
    csrw 0x328, x0
    csrw 0x329, x0
    csrw 0x32A, x0
    PRELOAD 3
    PRELOAD 4
    PRELOAD 5
    PRELOAD 6
    PRELOAD 7
    PRELOAD 8
    PRELOAD 9
    PRELOAD 10

    li   x31, 0x11111111            # sync: init done

    PHASE 0, 0x000, 0x000
    PHASE 1, 0x000, 0x7F8
    PHASE 2, 0x7F8, 0x000
    PHASE 3, 0x7F8, 0x7F8
    PHASE 4, 0x2A8, 0x198

    csrw mcounteren, x0
    csrw scounteren, x0

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
