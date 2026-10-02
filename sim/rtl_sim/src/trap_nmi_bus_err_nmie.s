#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_bus_err_nmie
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: a data-bus error with mnstatus.NMIE = 0 is HELD, not lost
#
#   NMIE resets to 0 and is software-set-only (Smrnmi), so the reset state is
#   the interesting one: firmware that faults before arming RNMIs must not
#   silently lose the error.
#
#   Phase A: fault with NMIE = 0 -- nothing delivered, but marv_estat.valid
#            must show the error was CAPTURED.
#   Phase B: set NMIE -- the held error is delivered, mncause = 3.
#
#   mtvec is a negative control throughout: causes 5/7 are RESERVED, so no
#   synchronous trap may ever be taken.
#
# Scratchpad (base 0x80000000):
#   0x00 nmi_handler addr   0x04 nmi_count   0x08 mncause
#   0x0C marv_estat while NMIE=0             0x10 trap_count (mtvec, must stay 0)
#----------------------------------------------------------------------------

.equ MNSTATUS,   0x744
.equ MNCAUSE,    0x742
.equ MARV_ESTAT, 0x7FE
.equ FAULT_ADDR, 0x00000000

.section .text
.global main

main:
    j _start

    .align 2
nmi_handler:
    li   s1, 0x80000000
    lw   t0, 0x04(s1)
    addi t0, t0, 1
    sw   t0, 0x04(s1)
    csrr t0, MNCAUSE
    sw   t0, 0x08(s1)
    lw   zero, 0x08(s1)
    .word 0x70200073               # mnret

    .align 2
trap_handler:                      # NEGATIVE CONTROL -- must never run
    addi sp, sp, -8
    sw   t0, 4(sp)
    sw   t1, 0(sp)
    lw   t0, 0x10(s1)
    addi t0, t0, 1
    sw   t0, 0x10(s1)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    lw   t1, 0(sp)
    lw   t0, 4(sp)
    addi sp, sp, 8
    mret

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x10(s1)

    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x00(s1)
    lw   zero, 0x00(s1)

    li   x31, 0x11111111           # tb programs nmi_vector; NMIE still 0

    li   t0, 20
wait_vec:
    addi t0, t0, -1
    bnez t0, wait_vec

    #---------------------------------------------------------------
    # PHASE A: fault while NMIE = 0
    #---------------------------------------------------------------
    li   t1, FAULT_ADDR
    li   t0, 0xDEAD
    sw   t0, 0(t1)                 # AHB ERROR -- must be HELD, not delivered

    li   t3, 40                    # t3: the RNMI handler clobbers t0 and s1
settleA:
    addi t3, t3, -1
    bnez t3, settleA

    csrr t0, MARV_ESTAT
    sw   t0, 0x0C(s1)              # captured even though nothing was delivered
    lw   zero, 0x0C(s1)

    li   x31, 0x22222222

    #---------------------------------------------------------------
    # PHASE B: arm NMIE -- the held error must now be delivered
    #---------------------------------------------------------------
    csrsi MNSTATUS, 8

    li   t3, 40                    # ditto -- an RNMI landing mid-loop would
settleB:                           # otherwise reload the counter from mncause
    addi t3, t3, -1
    bnez t3, settleB

    li   x31, 0x33333333

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
