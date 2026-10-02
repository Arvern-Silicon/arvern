#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ldst_older_ifetch
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: an OLDER faulting load/store vs a YOUNGER instruction-fetch fault
#   PMP_NR > 0. Machine mode, entry 0 = LOCKED NAPOT (32 bytes) R=W=1 X=0 over
#   block D, so fetching D faults (cause 1) in M-mode.
#
#   The last instruction before D is a load/store whose address comes from the
#   load right before it (load-use hazard: its fault status resolves late) and
#   which faults (misaligned). The older exception must be the one reported:
#   mcause 4/6, mepc = &faulting access, mtval = its address -- never cause 1
#   at &D. The handler resumes at the round's recovery label.
#
#   Rounds: 0 lw misaligned, 1 sw misaligned, 2 lw with one NOP before the
#   boundary is NOT a hazard (control: same result).
#
#   Scratchpad (base 0x80000000):
#     0x00 word holding the misaligned address   0x10 trap count
#     0x100 + id*16 : w0 mcause, w1 mepc, w2 mtval, w3 trap count
#     0x200 + id*4  : &faulting access of round id
#----------------------------------------------------------------------------

.equ SBASE,          0x80000000
.equ MISALIGNED,     0x80000101

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j _start

    .align 2
m_handler:
    csrr t0, mcause
    sw   t0, 0(s11)
    csrr t0, mepc
    sw   t0, 4(s11)
    csrr t0, mtval
    sw   t0, 8(s11)
    lw   t0, 12(s11)
    addi t0, t0, 1
    sw   t0, 12(s11)
    lw   zero, 12(s11)
    csrw mepc, s10
    mret

_start:
    li   sp, 0x80010000
    li   s1, SBASE
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8              # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0          # ...then MDT=0
    csrci mstatus, 8

    li   t0, MISALIGNED
    sw   t0, 0x00(s1)
    li   t0, 0
    sw   t0, 0x10C(s1)
    sw   t0, 0x11C(s1)
    sw   t0, 0x12C(s1)
    lw   zero, 0x12C(s1)

    la   t1, D0
    srli t1, t1, 2
    ori  t1, t1, 3              # NAPOT, 32 bytes
    csrw pmpaddr0, t1
    la   t1, D1
    srli t1, t1, 2
    ori  t1, t1, 3
    csrw pmpaddr1, t1
    la   t1, D2
    srli t1, t1, 2
    ori  t1, t1, 3
    csrw pmpaddr2, t1
    li   t0, 0x9B9B9B           # entries 0..2: L | NAPOT | R | W, X=0
    csrw pmpcfg0, t0

    li   x31, 0x11111111        # Sync: configured

    #--- round 0: lw a4,0(a0) with a0 from the previous lw ---
    la   s10, rec0
    addi s11, s1, 0x100
    la   t0, acc0
    sw   t0, 0x200(s1)
    .balign 32
    nop
    nop
    nop
    nop
    nop
    nop
    lw   a0, 0(s1)              # a0 = misaligned address (load-use below)
acc0:
    lw   a4, 0(a0)              # older fault: load address misaligned
D0:
    .rept 8
    nop                         # X=0: fetching here faults
    .endr
rec0:

    #--- round 1: sw a4,0(a0) with a0 from the previous lw ---
    la   s10, rec1
    addi s11, s1, 0x110
    la   t0, acc1
    sw   t0, 0x204(s1)
    .balign 32
    nop
    nop
    nop
    nop
    nop
    nop
    lw   a0, 0(s1)
acc1:
    sw   a4, 0(a0)              # older fault: store address misaligned
D1:
    .rept 8
    nop
    .endr
rec1:

    #--- round 2: control, no load-use hazard ---
    la   s10, rec2
    addi s11, s1, 0x120
    la   t0, acc2
    sw   t0, 0x208(s1)
    .balign 32
    nop
    nop
    nop
    nop
    nop
    lw   a0, 0(s1)
    nop
acc2:
    lw   a4, 0(a0)
D2:
    .rept 8
    nop
    .endr
rec2:

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
