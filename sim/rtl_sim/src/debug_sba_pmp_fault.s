#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_sba_pmp_fault
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP-denied loads/stores while the debugger runs SBA traffic
#   DEBUG_EN, PMP_NR > 0. Entry 0 = LOCKED NAPOT (32 bytes) R=W=X=0 over DENY:
#   every access there faults in M-mode (cause 5 / 7). The firmware executes
#   N denied accesses in a loop (alternating lw / sw, with 0..3 NOPs of
#   spacing) while the testbench keeps the SBA master busy on the shared data
#   port. Each denied access must raise exactly ONE access fault: trap count
#   == N, no RNMI (a second trap on the same access would be an Smdbltrp
#   unexpected trap), no lockup.
#
#   Scratchpad (base 0x80000000):
#     0x10 trap count  0x14 rnmi count  0x18 wrong-cause count
#----------------------------------------------------------------------------

.equ SBASE,          0x80000000
.equ DENY,           0x80003000
.equ N_LOOPS,        64

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j _start

    .align 2
m_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    csrr t1, mcause
    addi t1, t1, -5
    beqz t1, 1f
    addi t1, t1, -2
    beqz t1, 1f
    lw   t1, 0x18(t0)               # neither 5 nor 7
    addi t1, t1, 1
    sw   t1, 0x18(t0)
1:
    lw   t1, 0x10(t0)
    addi t1, t1, 1
    sw   t1, 0x10(t0)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    lw   t1, 0x00(t0)
    csrr t0, mscratch
    mret

    .align 2
nmi_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    lw   t1, 0x14(t0)
    addi t1, t1, 1
    sw   t1, 0x14(t0)
    csrw mstatush, x0               # a double trap left MDT=1: clear it to keep going
    lw   t1, 0x00(t0)
    csrr t0, mscratch
    .word 0x70200073                # mnret

_start:
    li   sp, 0x80010000
    li   s1, SBASE
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, nmi_handler
    csrw 0x7FD, t0                  # marv_nmvec
    csrsi 0x744, 8                  # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0              # ...then MDT=0
    csrci mstatus, 8

    sw   zero, 0x10(s1)
    sw   zero, 0x14(s1)
    sw   zero, 0x18(s1)
    lw   zero, 0x18(s1)

    li   t0, (DENY >> 2) | 3        # NAPOT, 32 bytes
    csrw pmpaddr0, t0
    li   t0, 0x98                   # entry 0: L | NAPOT | R=W=X=0
    csrw pmpcfg0, t0

    li   a1, DENY
    li   s2, N_LOOPS

    li   x31, 0x11111111            # Sync: start the SBA traffic

    li   x31, 0x22222222            # Sync: denied-access loop running
loop:
    lw   a0, 0(a1)
    sw   a0, 4(a1)
    nop
    lw   a0, 8(a1)
    nop
    nop
    sw   a0, 12(a1)
    nop
    nop
    nop
    addi s2, s2, -1
    bnez s2, loop

    li   x31, 0x33333333            # Sync: loop done
    lw   zero, 0x18(s1)
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
