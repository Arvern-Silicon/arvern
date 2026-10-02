#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_fetch_postfault
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: nothing past a PMP fetch fault may execute
#
#   The fetch unit runs ahead of the decoder. When the word it is fetching is
#   refused, the words it has already asked for behind it keep arriving. None
#   of them may reach the decoder: the fault is reported at the refused
#   instruction and execution resumes wherever the handler says, so anything
#   younger that ran would be an instruction the program never reached.
#
#   D = NAPOT 16 B at 0x80000410, locked, read-only. Its LAST word, 0x8000041C,
#   is the target; the two words after it are outside D, executable, and each
#   leaves a mark:
#
#       0x8000041C   (in D)      the refused fetch
#       0x80000420   li a3, ...  runs only if the word behind the fault leaks
#       0x80000424   li a4, ...  runs only if the one behind that leaks
#       0x80000428   ret
#
#   Two entries: a jump straight to 0x8000041C, and a flow through nops from
#   0x80000400 that crosses into D at 0x80000410 (there the leaked words would
#   be D's own, refused too, so only the count can tell) -- run under the wait
#   state variants, which move the data phases relative to the fault.
#
# Requires PMP_NR > 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ SLOTS,  0x80000100
.equ PRE,    0x80000400
.equ D,      0x80000410
.equ LAST,   0x8000041C
.equ AFTER,  0x80000420

main:
    j _start

    .align 2
m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    csrr t0, mcause
    sw   t0, 0(s11)
    csrr t0, mepc
    sw   t0, 4(s11)
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)
    csrw mepc, s10
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

#=========================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000
    sw   x0, 0x00(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw  mstatush, x0          # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    li   t0, SLOTS
    .rept 4
    sw   x0, 0(t0)
    addi t0, t0, 4
    .endr

    li   s5, PRE
    li   s6, LAST
    li   s7, AFTER

    # PRE: four nops flowing into D.
    li   t0, 0x00000013
    sw   t0, 0x0(s5)
    sw   t0, 0x4(s5)
    sw   t0, 0x8(s5)
    sw   t0, 0xC(s5)
    # D: ecalls, so a fetch wrongly permitted is visible as cause 11.
    li   t0, 0x00000073
    li   t1, D
    sw   t0, 0x0(t1)
    sw   t0, 0x4(t1)
    sw   t0, 0x8(t1)
    sw   t0, 0xC(t1)
    # AFTER: the two canaries and a ret.
    li   t0, 0x7AD00693         # addi a3, x0, 0x7AD
    sw   t0, 0x0(s7)
    li   t0, 0x7AE00713         # addi a4, x0, 0x7AE
    sw   t0, 0x4(s7)
    li   t0, 0x00008067         # ret
    sw   t0, 0x8(s7)
    fence.i

    li   a3, 0x600D
    li   a4, 0x600D

    # D: locked, read-only, no execute.
    li   t0, D
    srli t0, t0, 2
    ori  t0, t0, 1
    csrw pmpaddr0, t0
    li   t0, 0x99
    csrw pmpcfg0, t0

    #=================================================================
    # PROBE 1 -- straight onto the last word of D
    #=================================================================
    la   s10, 1f
    li   s11, SLOTS+0x00
    jalr ra, 0(s6)              # cause 1 at LAST; a3/a4 untouched
1:
    #=================================================================
    # PROBE 2 -- flow through PRE and cross into D
    #=================================================================
    la   s10, 2f
    li   s11, SLOTS+0x08
    jalr ra, 0(s5)              # cause 1 at D+0
2:
    lw   a0, 0x00(s1)           # total traps -- expect 2
    addi t0, a0, 0

    li   x31, 0x11111111

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
9:  j    9b
