#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_ebreak_priv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: dcsr.ebreakm / ebreaks / ebreaku per privilege (Debug 1.0)
#   Debug 1.0 dcsr: "ebreakm 0 (exception): ebreak instructions in M-mode
#   behave as described in the Privileged Spec. 1 (debug mode): ebreak
#   instructions in M-mode enter Debug Mode." (same wording for ebreaks /
#   S-mode and ebreaku / U-mode). Table 9: for cause ebreak, dpc = "Address
#   of the ebreak instruction".
#
#   An ebreak (32-bit, pinned with .word) is executed in M, S and U mode in
#   three passes; S/U only when CFG_SU_MODE_EN:
#     pass 1: dcsr ebreak bits all 0 (reset)   -> M, S, U: breakpoint exception
#     pass 2: debugger sets ebreakm=1, ebreaku=1 -> M: Debug, S: exception, U: Debug
#     pass 3: debugger sets ebreaks=1 only      -> M: exception, S: Debug, U: exception
#     pass 4: debugger clears all three again   -> M, S, U: breakpoint exception
#   On a breakpoint exception the M handler records mcause, mepc, mstatus
#   into the slot s5 points at and returns past the ebreak (same mode). On a
#   Debug-Mode entry the debugger checks cause=1, prv, dpc = s6 and resumes
#   at dpc+4; the slot keeps mcause=0, proving no trap was taken.
#   Each S/U ebreak is followed by an ecall that returns to M.
#
#   Scratchpad (base 0x80000000), one 16-byte slot per ebreak:
#     +0 mcause  +4 mepc  +8 mstatus  +C address of the ebreak
#     pass1 M 0x00 S 0x10 U 0x20 | pass2 M 0x30 S 0x40 U 0x50
#     pass3 M 0x60 S 0x70 U 0x80 | pass4 M 0x90 S 0xA0 U 0xB0
#     0x100 breakpoint-exception count
#   Registers: s1 scratch base, s5 slot pointer, s6 current ebreak address,
#   x29 release flag written by the debugger, x31 sync (11111111 = end of
#   pass 1, 22222222 = end of pass 2, 33333333 = end of pass 3,
#   deadbeef = done).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ SBASE, 0x80000000

.section .text
.global main

.option norvc

# ebreak in M-mode, result slot at s1+\slot
.macro EBREAK_M slot
    addi s5, s1, \slot
    la   s6, 1f
    sw   s6, 12(s5)
1:  .word 0x00100073               # ebreak (32-bit)
.endm

# ebreak in the privilege selected by \mpp (0x800 = S, 0 = U), then ecall back
.macro EBREAK_LOW slot, mpp
    addi s5, s1, \slot
    la   s6, 2f
    sw   s6, 12(s5)
    la   t0, 1f
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, \mpp
    csrs mstatus, t0
    mret
1:  nop
2:  .word 0x00100073               # ebreak (32-bit)
    ecall                          # back to M
.endm

main:
    j    _start

    .align 2
m_handler:
    csrr t0, mcause
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    li   t2, 3
    bne  t0, t2, m_not_bkpt
    sw   t0, 0(s5)
    addi t1, t1, -4
    sw   t1, 4(s5)
    csrr t2, mstatus
    sw   t2, 8(s5)
    lw   t2, 0x100(s1)
    addi t2, t2, 1
    sw   t2, 0x100(s1)
    mret                           # same privilege, past the ebreak
m_not_bkpt:
    li   t2, 0x1800
    csrs mstatus, t2               # ecall: return to M past the ecall
    mret

_start:
    li   sp, 0x8000F000
    li   s1, SBASE
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0
.if CFG_SU_MODE_EN
    PMP_ALLOW_ALL
.endif
    li   x29, 0
    mv   t0, s1
    addi t1, s1, 0x104
clr:
    sw   zero, 0(t0)
    addi t0, t0, 4
    bne  t0, t1, clr

    # pass 1
    EBREAK_M 0x00
.if CFG_SU_MODE_EN
    EBREAK_LOW 0x10, 0x800
    EBREAK_LOW 0x20, 0x000
.endif
    li   x31, 0x11111111
wait1:
    beq  x29, x0, wait1
    li   x29, 0

    # pass 2
    EBREAK_M 0x30
.if CFG_SU_MODE_EN
    EBREAK_LOW 0x40, 0x800
    EBREAK_LOW 0x50, 0x000
.endif
    li   x31, 0x22222222
wait2:
    beq  x29, x0, wait2

    # pass 3
    EBREAK_M 0x60
.if CFG_SU_MODE_EN
    EBREAK_LOW 0x70, 0x800
    EBREAK_LOW 0x80, 0x000
.endif
    li   x29, 0
    li   x31, 0x33333333
wait3:
    beq  x29, x0, wait3

    # pass 4
    EBREAK_M 0x90
.if CFG_SU_MODE_EN
    EBREAK_LOW 0xA0, 0x800
    EBREAK_LOW 0xB0, 0x000
.endif
    lw   zero, 0x100(s1)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
