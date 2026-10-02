#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_instret_ifetch_fault
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: minstret across an INSTRUCTION ACCESS FAULT (cause 1)
#   csrr s2, minstret ; jalr to an unfetchable address. The csrr and the jalr
#   retire; the instruction at the target never executes. The handler's first
#   instruction reads minstret again: delta = instructions retired since the csrr, csrr included.
#
#   Probe 0: target 0x00000000 (unmapped: instruction-bus ERROR)
#   Probe 1: same, jalr preceded by a NOP (delta 3)
#   Probe 2: same, reached through a jal then the jalr (delta 3)
#   Probe 3: (DEBUG_EN, DM_TRIGGER_NR>0) csrr + nop, then an Sdtrig action=0
#            execute breakpoint on the next instruction (delta 2)
#
#   Scratchpad (base 0x80000000): 0x00 + 4*n = delta of probe n, 0x40 mcause
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j _start

    .align 2
m_trap_handler:
    csrr s3, minstret              # <-- must stay first
    sub  s4, s3, s2
    sw   s4, 0(s5)
    csrr t0, mcause
    sw   t0, 0x40(s1)
    lw   zero, 0x40(s1)
    csrw mepc, s6                  # resume at the probe's return label
    mret

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000
    la   t0, m_trap_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: NMIE=1 first...
    csrw mstatush, x0              # ...then MDT=0
    li   t1, 0x00000000

    li   x31, 0x11111111           # Sync: configured

    addi s5, s1, 0x00
    la   s6, ret0
    csrr s2, minstret
    jalr x0, 0(t1)
ret0:

    addi s5, s1, 0x04
    la   s6, ret1
    csrr s2, minstret
    nop
    jalr x0, 0(t1)
ret1:

    addi s5, s1, 0x08
    la   s6, ret2
    csrr s2, minstret
    jal  x0, hop2
ret2:
    j    probes_done
hop2:
    jalr x0, 0(t1)

probes_done:
.if CFG_DEBUG_EN && (CFG_DM_TRIGGER_NR > 0)
    # Probe 3: Sdtrig action=0 execute breakpoint on bp_target (never dispatched)
    csrsi 0x7a5, 8                 # tcontrol.MTE: M-mode action=0 triggers may fire
    li   t0, 0
    csrw 0x7a0, t0                 # tselect = 0
    csrw 0x7a1, x0
    la   t0, bp_target
    csrw 0x7a2, t0                 # tdata2 = &bp_target
    li   t0, 0x60000044            # mcontrol6 | m | execute | match=0 | action=0
    csrw 0x7a1, t0
    addi s5, s1, 0x0C
    la   s6, ret3
    nop
    nop
    nop
    nop
    csrr s2, minstret
    nop
bp_target:
    nop
ret3:
    csrw 0x7a1, x0                 # disarm
.endif
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
