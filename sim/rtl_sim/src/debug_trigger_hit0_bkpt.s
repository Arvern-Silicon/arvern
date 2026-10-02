#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_hit0_bkpt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: mcontrol6.hit0 for action=0 (breakpoint exception) fires
#   Debug 1.0 mcontrol6 hit0: the TM sets it when the trigger fires, whatever
#   its action. An M-mode handler (tcontrol.MTE=1) reads tdata1 of the trigger
#   that raised the breakpoint:
#     phase 1: trigger 0, execute, action=0 on bp_target  -> mcause 3, hit0 = 1
#     phase 2: trigger 0, load,    action=0 on DATA_ADDR  -> mcause 3, hit0 = 1
#   Before each phase hit0 is cleared and read back as 0.
#
#   Scratchpad (base 0x80000000): 0x00 phase-1 tdata1 in handler, 0x04 mcause,
#   0x08 phase-2 tdata1 in handler, 0x0C mcause, 0x10 tdata1 read before phase 1
#----------------------------------------------------------------------------

.equ SBASE,          0x80000000
.equ DATA_ADDR,      0x80000400
.equ HIT0,           0x00400000

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j _start

    .align 2
m_handler:
    csrr t0, 0x7a1                 # tdata1 of tselect=0
    sw   t0, 0(s5)
    csrr t0, mcause
    sw   t0, 4(s5)
    csrw 0x7a1, x0                 # disarm
    lw   zero, 4(s5)
    csrw mepc, s6
    mret

_start:
    li   sp, 0x80010000
    li   s1, SBASE
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: NMIE=1 first...
    csrw mstatush, x0              # ...then MDT=0
    csrsi 0x7a5, 8                 # tcontrol.MTE
    csrw 0x7a0, x0                 # tselect = 0

    li   x31, 0x11111111           # Sync: configured

    # phase 1: execute breakpoint
    csrw 0x7a1, x0
    la   t0, bp_target
    csrw 0x7a2, t0
    li   t0, 0x60000044            # mcontrol6 | m | execute | action=0
    csrw 0x7a1, t0
    csrr t0, 0x7a1
    sw   t0, 0x10(s1)
    addi s5, s1, 0x00
    la   s6, p1_done
    nop
    nop
    nop
    nop
bp_target:
    nop
p1_done:

    # phase 2: load watchpoint
    csrw 0x7a1, x0
    li   t0, DATA_ADDR
    csrw 0x7a2, t0
    li   t0, 0x60000041            # mcontrol6 | m | load | action=0
    csrw 0x7a1, t0
    addi s5, s1, 0x08
    la   s6, p2_done
    li   t1, DATA_ADDR
    nop
    nop
    lw   t2, 0(t1)
p2_done:

    lw   zero, 0x0C(s1)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
