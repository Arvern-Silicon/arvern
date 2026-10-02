#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_ldst_all
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: debugger-armed load watchpoint (action=1) on every trigger index
#   The debugger (the .v) halts the hart at `wait`, writes the iteration
#   count x28 = DM_TRIGGER_NR, arms trigger 0 on D_0 and releases x29. The
#   firmware then runs x28 iterations of one `lw` at lw_site; iteration t
#   loads D_t = 0x80001000 + 4*t, which trigger t watches. Each lw enters
#   Debug Mode before it is performed; the debugger checks the halt,
#   disarms trigger t, arms trigger t+1 on D_(t+1) and resumes, and the lw
#   then completes and its value is stored to the result slot.
#
#   Data:    D_t    0x80001000 + 4*t = 0x0D0D0D00 + t   (t = 0..7)
#   Results: R_t    0x80001100 + 4*t (loaded value, expect D_t)
#   Registers: x5 lw destination (PRE 0xBEEF0000 before every lw),
#   x6 &lw_site, x20 iteration index, x27 trap count (0), x28 iteration
#   count, x29 release flag, x31 sync (11111111 = waiting, deadbeef = done).
#----------------------------------------------------------------------------

.section .text
.global main

.option norvc

main:
    j    _start

    .align 2
m_handler:
    addi x27, x27, 1               # must never run
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

_start:
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0

    li   s1, 0x80001000
    li   t0, 0
    li   t1, 0x0D0D0D00
init:
    slli t2, t0, 2
    add  t2, t2, s1
    add  t3, t1, t0
    sw   t3, 0x000(t2)             # D_t
    sw   x0, 0x100(t2)             # R_t
    addi t0, t0, 1
    li   t3, 8
    blt  t0, t3, init

    li   x20, 0
    li   x27, 0
    li   x28, 0
    li   x29, 0
    la   x6, lw_site
    li   x31, 0x11111111
wait:
    beq  x29, x0, wait

loop:
    bgeu x20, x28, done
    slli t1, x20, 2
    add  a3, s1, t1
    li   x5, 0xBEEF0000
lw_site:
    lw   x5, 0(a3)                 # watched by trigger x20
    sw   x5, 0x100(a3)
    addi x20, x20, 1
    j    loop

done:
    lw   t2, 0x100(s1)
    addi t2, t2, 0
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
