#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_multi_dmode
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: debugger-armed mcontrol6 triggers (action=1): trigger 1 firing
#   alone, all triggers firing on one instruction, and action=1 + action=0
#   on the same instruction
#   Debug 1.0 5.3: "When multiple triggers in the same priority fire at once,
#   hit (if implemented) is set for all of them. ... If this is not
#   implemented, then the hart must enter Debug Mode and ignore the
#   breakpoint exception. In the latter case, hit of the trigger whose action
#   is 0 must still be set, giving a debugger an opportunity to handle this
#   case."
#
#   The debugger (the .v) halts the hart at `wait`, arms the triggers over
#   abstract access, releases x29 and resumes; each target then enters Debug
#   Mode and the debugger re-arms for the next one.
#     A: trigger 1 on tgtA, trigger 0 on tgtB   -> halt at tgtA, hit0 on 1 only
#     B: every trigger on tgtB                  -> halt at tgtB, hit0 on all
#     C: trigger 0 action=0, trigger 1 action=1, both on tgtC
#        -> Debug Mode (cause 2), hit0 on 0 and 1
#   The M handler counts breakpoint exceptions in x27 and returns to mepc
#   (reached only if the core also takes the action=0 breakpoint in C).
#
#   Registers: x5/x6/x7 &tgtA/&tgtB/&tgtC, x8 &m_handler, x21/x22/x23 target
#   side effects, x27 breakpoint count, x29 release flag, x31 sync
#   (11111111 = waiting for the debugger, deadbeef = done).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j    _start

    .align 2
m_handler:
    addi x27, x27, 1
    mret

_start:
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0
    csrsi 0x7a5, 8                 # tcontrol.MTE (action=0 trigger in phase C)

    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x27, 0
    li   x29, 0
    la   x5, tgtA
    la   x6, tgtB
    la   x7, tgtC
    la   x8, m_handler
    li   x31, 0x11111111
wait:
    beq  x29, x0, wait
    nop
    nop
tgtA:
    addi x21, x0, 0xA1
    nop
    nop
tgtB:
    addi x22, x0, 0xB2
    nop
    nop
tgtC:
    addi x23, x0, 0xC3
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
