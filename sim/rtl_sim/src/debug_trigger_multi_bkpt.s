#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_multi_bkpt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: several mcontrol6 triggers firing together, and trigger index
#   >= 1 firing alone, with action=0 (breakpoint exception)
#   Debug 1.0 5.3: "When multiple triggers in the same priority fire at once,
#   hit (if implemented) is set for all of them." mcontrol6.hit0: "The TM
#   updates this field when the trigger fires." / "0 (false): The trigger did
#   not fire." Table 13 puts the execute-address breakpoint above the
#   load/store-address breakpoint.
#
#   The M handler (tcontrol.MTE=1) records mcause, mepc, mtval, a per-phase
#   trap count and tdata1 of every trigger (0..CFG_DM_TRIGGER_NR-1), disarms
#   them all and returns to s6.
#     P1: trigger 1 execute on tgt1, trigger 0 execute on never_exec
#         -> one trap, hit0 on trigger 1 only
#     P2: trigger 1 load on DATA, trigger 0 load on DATA+0x10
#         -> one trap, mtval = DATA, hit0 on trigger 1 only
#     P3: every trigger execute on tgt3  -> one trap, hit0 on all
#     P4: every trigger load on DATA     -> one trap, hit0 on all
#     P5: trigger 0 execute on the lw at tgt5, trigger 1 load on its address
#         -> execute breakpoint (higher priority) is taken before the load
#         executes: hit0 on trigger 0 only
#
#   Scratchpad (base 0x80000000), slot per phase at 0x40*(n-1):
#     +0x00 mcause  +0x04 mepc  +0x08 mtval  +0x0C trap count in the phase
#     +0x10..+0x2C tdata1[0..7] at handler entry  +0x30 expected mepc
#   0x200: total trap count (5 expected).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ SBASE,    0x80000000
.equ DATA,     0x80000800

.section .text
.global main

.option norvc

# Arm trigger \idx with tdata2 = a0 and tdata1 = \t1val
.macro ARM idx, t1val
    li   t0, \idx
    csrw 0x7a0, t0
    csrw 0x7a1, x0
    csrw 0x7a2, a0
    li   t0, \t1val
    csrw 0x7a1, t0
.endm

# Arm every implemented trigger with tdata2 = a0 and tdata1 = \t1val
.macro ARM_ALL t1val
    li   t1, 0
1:  csrw 0x7a0, t1
    csrw 0x7a1, x0
    csrw 0x7a2, a0
    li   t0, \t1val
    csrw 0x7a1, t0
    addi t1, t1, 1
    li   t0, CFG_DM_TRIGGER_NR
    bne  t1, t0, 1b
.endm

.equ EXEC_M, 0x60000044            # mcontrol6 | m | execute, action=0
.equ LOAD_M, 0x60000041            # mcontrol6 | m | load,    action=0

main:
    j    _start

    .align 2
m_handler:
    csrr t0, mcause
    sw   t0, 0x00(s5)
    csrr t0, mepc
    sw   t0, 0x04(s5)
    csrr t0, mtval
    sw   t0, 0x08(s5)
    lw   t0, 0x0C(s5)
    addi t0, t0, 1
    sw   t0, 0x0C(s5)
    lw   t0, 0x200(s1)
    addi t0, t0, 1
    sw   t0, 0x200(s1)
    li   t1, 0
    addi t2, s5, 0x10
h_loop:
    csrw 0x7a0, t1
    csrr t0, 0x7a1
    sw   t0, 0(t2)
    csrw 0x7a1, x0                 # disarm (clears hit0)
    addi t1, t1, 1
    addi t2, t2, 4
    li   t0, CFG_DM_TRIGGER_NR
    bne  t1, t0, h_loop
    csrw mepc, s6
    mret

_start:
    li   sp, 0x8000F000
    li   s1, SBASE
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0
    csrsi 0x7a5, 8                 # tcontrol.MTE

    mv   t0, s1
    addi t1, s1, 0x204
clr:
    sw   zero, 0(t0)
    addi t0, t0, 4
    bne  t0, t1, clr
    li   t0, DATA
    li   t1, 0x5A5A5A5A
    sw   t1, 0(t0)

    li   x31, 0x11111111

    #--------------------------------------------------------------
    # P1: trigger 1 alone fires (execute)
    #--------------------------------------------------------------
    addi s5, s1, 0x00
    la   s6, p1_done
    la   a0, tgt1
    sw   a0, 0x30(s5)
    ARM  1, EXEC_M
    la   a0, never_exec
    ARM  0, EXEC_M
    nop
    nop
    nop
    nop
tgt1:
    addi a1, zero, 0x11
p1_done:

    #--------------------------------------------------------------
    # P2: trigger 1 alone fires (load)
    #--------------------------------------------------------------
    addi s5, s1, 0x40
    la   s6, p2_done
    la   a0, tgt2
    sw   a0, 0x30(s5)
    li   a0, DATA
    ARM  1, LOAD_M
    li   a0, DATA + 0x10
    ARM  0, LOAD_M
    li   a2, DATA
    nop
    nop
    nop
    nop
tgt2:
    lw   a1, 0(a2)
p2_done:

    #--------------------------------------------------------------
    # P3: every trigger fires on the same instruction (execute)
    #--------------------------------------------------------------
    addi s5, s1, 0x80
    la   s6, p3_done
    la   a0, tgt3
    sw   a0, 0x30(s5)
    ARM_ALL EXEC_M
    nop
    nop
    nop
    nop
tgt3:
    addi a1, zero, 0x33
p3_done:

    #--------------------------------------------------------------
    # P4: every trigger fires on the same access (load)
    #--------------------------------------------------------------
    addi s5, s1, 0xC0
    la   s6, p4_done
    la   a0, tgt4
    sw   a0, 0x30(s5)
    li   a0, DATA
    ARM_ALL LOAD_M
    li   a2, DATA
    nop
    nop
    nop
    nop
tgt4:
    lw   a1, 0(a2)
p4_done:

    #--------------------------------------------------------------
    # P5: execute (trigger 0) and load (trigger 1) on the same lw
    #--------------------------------------------------------------
    addi s5, s1, 0x100
    la   s6, p5_done
    la   a0, tgt5
    sw   a0, 0x30(s5)
    ARM  0, EXEC_M
    li   a0, DATA
    ARM  1, LOAD_M
    li   a2, DATA
    nop
    nop
    nop
    nop
tgt5:
    lw   a1, 0(a2)
p5_done:

    lw   zero, 0x200(s1)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test

never_exec:
    nop
    j    end_of_test
