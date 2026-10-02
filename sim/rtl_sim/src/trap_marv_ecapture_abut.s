#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_marv_ecapture_abut
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: marv_estat.restartable across ABUTTING uop sequences
#   COMP-only: cm.push / cm.mva01s cannot assemble in an RV32I march.
#
#   The one interleaving a level check on ex_uop_enable cannot get right.
#
#   cm.push's LAST store is posted and the sequence retires; its error is still
#   outstanding when the NEXT uop sequence begins. If that next sequence is
#   REGISTER-ONLY (cm.mva01s needs no bus, so nothing delays its start), the two
#   sequences ABUT: ex_uop_enable never returns low between them. A predicate
#   that asks "is a uop sequence running?" then answers yes -- about the WRONG
#   sequence -- and reports the retired push's store as restartable. Replaying it
#   would run cm.push a second time and decrement sp twice.
#
#   The design instead clears its liveness flag on the sequence BOUNDARY
#   (ex_uop_ready), which fires even when enable never falls.
#
#   BASE TIMING ONLY (no_variants). Whether an error arrives before or after its
#   sequence retires is set by bus and ALU latency, so wait states / ALU stalls
#   move this fault mid-sequence, where restartable=1 is the TRUTHFUL answer and
#   the premise of the test no longer holds. That is timing, not a defect.
#
#   Scratchpad (base 0x80000000). The push straddles the SRAM base, so its
#   surviving stores land in the low words -- results live at 0x40+.
#   Two rounds at DIFFERENT pinned latencies -- the testbench raises the SRAM wait
#   states between them (s_sram_x_number_ws), so the boundary clear is checked at
#   two deterministic alignments without inviting random variants.
#
#   0x00 nmi_handler_addr  0x4C nmi_count
#   round 1: 0x40 estat  0x44 marv_epc  0x48 push PC
#   round 2: 0x50 estat  0x54 marv_epc  0x58 push PC
#----------------------------------------------------------------------------

.equ MARV_ESTAT,     0x7FE
.equ MARV_EPC,       0xFFC
.equ MNSTATUS,       0x744

.equ EDGE_SP,        0x8000000C      # sp-16 = 0x7FFFFFFC, just below SRAM base

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    .align 2
nmi_handler:
    li   s1, 0x80000000
    lw   t0, 0x4C(s1)
    addi t0, t0, 1
    sw   t0, 0x4C(s1)
    lw   zero, 0x4C(s1)
    .word 0x70200073                # mnret

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   zero, 0x40(s1)
    sw   zero, 0x44(s1)
    sw   zero, 0x48(s1)
    sw   zero, 0x4C(s1)
    sw   zero, 0x50(s1)
    sw   zero, 0x54(s1)
    sw   zero, 0x58(s1)

    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x00(s1)
    lw   zero, 0x00(s1)

    li   x31, 0x11111111            # Sync: handler address published

    li   t0, 20                     # let the testbench program nmi_vector
wait_vec:
    addi t0, t0, -1
    bnez t0, wait_vec

    csrsi MNSTATUS, 8               # mnstatus.NMIE = 1 -- REQUIRED for delivery

    li   ra, 0xAAAAAAAA
    li   s0, 0xBBBBBBBB
    li   s2, 0xDDDDDDDD

    li   x31, 0x22222222            # Sync: NMIE armed

    #---------------------------------------------------------------
    # The push's last store faults after the macro-op retires; the
    # register-only sequences that follow abut it, holding
    # ex_uop_enable high across the boundary.
    #---------------------------------------------------------------
    li   sp, EDGE_SP
abut_push:
    cm.push {ra, s0-s2}, -16
    cm.mva01s s0, s1                # register-only: no bus, starts immediately
    cm.mva01s s0, s1

    li   sp, 0x80010000
    li   t0, 40
settle:
    addi t0, t0, -1
    bnez t0, settle

    li   s1, 0x80000000
    csrr t3, MARV_ESTAT
    sw   t3, 0x40(s1)
    csrr t3, MARV_EPC
    sw   t3, 0x44(s1)
    la   t3, abut_push
    sw   t3, 0x48(s1)
    lw   zero, 0x48(s1)

    li   t0, 0x5
    csrw MARV_ESTAT, t0             # W1C: first-fault-wins must not carry over

    li   x31, 0x33333333            # Sync: round 1 recorded; tb now pins wait states

    li   t0, 200                    # give the testbench time to apply them
wait_ws:
    addi t0, t0, -1
    bnez t0, wait_ws

    #---------------------------------------------------------------
    # Round 2 -- same shape, different bus latency
    #---------------------------------------------------------------
    li   ra, 0xAAAAAAAA
    li   s0, 0xBBBBBBBB
    li   s2, 0xDDDDDDDD

    li   sp, EDGE_SP
abut_push2:
    cm.push {ra, s0-s2}, -16
    cm.mva01s s0, s1
    cm.mva01s s0, s1

    li   sp, 0x80010000
    li   t0, 40
settle2:
    addi t0, t0, -1
    bnez t0, settle2

    li   s1, 0x80000000
    csrr t3, MARV_ESTAT
    sw   t3, 0x50(s1)
    csrr t3, MARV_EPC
    sw   t3, 0x54(s1)
    la   t3, abut_push2
    sw   t3, 0x58(s1)
    lw   zero, 0x58(s1)

    li   x31, 0x44444444            # Sync: round 2 recorded

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
