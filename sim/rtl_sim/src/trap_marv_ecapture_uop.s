#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_marv_ecapture_uop
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: bus error DURING a Zcmp sequence -- delivery + classification
#   COMP-only: cm.push cannot assemble in an RV32I march.
#
#   Two things this must cover, and the pre-S4 version covered neither properly:
#     1. DELIVERY. A bus error raised by a UOP micro-op must actually be TAKEN as
#        an RNMI (mncause=3). The earlier version never armed mnstatus.NMIE, so the
#        error was captured and classified but held pending forever -- it validated
#        capture, not delivery.
#     2. CLASSIFICATION, marv_estat[4:3]:
#          case 1  UOP access, sequence STILL IN FLIGHT -> uop=1 restart=1
#          case 2  UOP access, sequence ALREADY RETIRED -> uop=1 restart=0
#          case 3  BACK-TO-BACK cm.push: case-2's late error arriving near the
#                  start of a second push -> still uop=1 restart=0. Only reachable
#                  now that reporting is asynchronous.
#
#   The sharper interleaving -- two uop sequences ABUTTING, where ex_uop_enable
#   never falls between them -- lives in trap_marv_ecapture_abut. That one needs a
#   register-only cm.mva01s to close the gap, and it is the case a level check on
#   ex_uop_enable actually gets wrong.
#
#   BASE TIMING ONLY (no_variants). All three cases are built out of default bus
#   and ALU latency: wait states or ALU stalls move the fault mid-sequence, where
#   restartable=1 is the TRUTHFUL answer and the premise no longer holds. Verified
#   variant-fragile with the OLD predicate too, so this is not new.
#
#   Constructed by placing sp so the push straddles the bottom of SRAM:
#     case 1: sp wholly unmapped        -> the FIRST store faults, mid-sequence
#     case 2: sp just above the SRAM base -> the LAST store falls below it
#
#   Scratchpad (base 0x80000000) -- results at 0x40+, because case 2's surviving
#   stores land in the low words:
#   0x00 nmi_handler_addr  0x40 estat case1  0x44 estat case2  0x48 sp after case2
#   0x4C estat case3  0x50 nmi_count  0x54 mncause of the last RNMI
#   0x60 estat case4  0x64 eaddr case4  0x68 case-4 lw PC  0x6C epc case4
#   0x70 mncause case4
#
#   CASE 4 (not a UOP): a plain `lw` from address 0 (unmapped) after the Zcmp
#   cases -> RNMI 0x80000003, marv_estat = valid only (0x01: store, overrun,
#   restartable, uop_sourced all 0), marv_eaddr = 0, marv_epc = the lw.
#----------------------------------------------------------------------------

.equ MARV_ESTAT,     0x7FE
.equ MARV_EPC,       0xFFC
.equ MARV_EADDR,     0xFFD
.equ MNSTATUS,       0x744
.equ MNCAUSE,        0x742

.equ FAULT_SP_BASE,  0xA0000000      # wholly unmapped -> first store faults
.equ EDGE_SP,        0x8000000C      # sp-16 = 0x7FFFFFFC, just below SRAM base

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # RNMI handler -- counts deliveries, records mncause, resumes.
    #=================================================================
    .align 2
nmi_handler:
    li   s1, 0x80000000
    lw   t0, 0x50(s1)
    addi t0, t0, 1
    sw   t0, 0x50(s1)
    csrr t0, MNCAUSE
    sw   t0, 0x54(s1)
    lw   zero, 0x54(s1)
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
    # CASE 1: first store faults -- sequence still in flight
    #         expect valid|store|restart|uop = 0x1B, and an RNMI delivered
    #---------------------------------------------------------------
    li   sp, FAULT_SP_BASE
    cm.push {ra, s0-s2}, -16

    li   sp, 0x80010000
    li   t0, 40
settle1:
    addi t0, t0, -1
    bnez t0, settle1

    li   s1, 0x80000000
    csrr t3, MARV_ESTAT
    sw   t3, 0x40(s1)
    lw   zero, 0x40(s1)
    li   t0, 0x5
    csrw MARV_ESTAT, t0             # W1C before the next case

    li   x31, 0x33333333            # Sync: case 1 done

    #---------------------------------------------------------------
    # CASE 2: LAST store faults -- sequence has already retired
    #         expect valid|store|uop = 0x13 (restart = 0)
    #---------------------------------------------------------------
    li   sp, EDGE_SP
    cm.push {ra, s0-s2}, -16

    mv   t4, sp                     # sp as the push left it
    li   sp, 0x80010000
    li   t0, 40
settle2:
    addi t0, t0, -1
    bnez t0, settle2

    li   s1, 0x80000000
    csrr t3, MARV_ESTAT
    sw   t3, 0x44(s1)
    sw   t4, 0x48(s1)
    lw   zero, 0x48(s1)
    li   t0, 0x5
    csrw MARV_ESTAT, t0

    li   x31, 0x44444444            # Sync: case 2 done

    #---------------------------------------------------------------
    # CASE 3: back-to-back. Case-2's late error lands while a DIFFERENT
    #         cm.push is still in flight. restart must stay 0 -- the
    #         sequence that ISSUED the faulting store had retired.
    #---------------------------------------------------------------
    li   sp, EDGE_SP
case3_push:
    cm.push {ra, s0-s2}, -16        # late fault, sequence retires
    li   sp, 0x80010000
    cm.push {ra, s0-s2}, -16        # push #2 -- may be in flight when #1 lands

    li   sp, 0x80010000
    li   t0, 40
settle3:
    addi t0, t0, -1
    bnez t0, settle3

    li   s1, 0x80000000
    csrr t3, MARV_ESTAT
    sw   t3, 0x4C(s1)
    csrr t3, MARV_EPC                # WHICH fault populated estat?
    sw   t3, 0x58(s1)
    la   t3, case3_push
    sw   t3, 0x5C(s1)                # ...must be push #1 of case 3
    lw   zero, 0x5C(s1)

    li   x31, 0x55555555            # Sync: case 3 recorded

    #---------------------------------------------------------------
    # CASE 4: plain load bus error -- not UOP-sourced, not a store
    #---------------------------------------------------------------
    li   t0, 0x5
    csrw MARV_ESTAT, t0             # W1C case-3 evidence
    li   t0, 40
settle4:
    addi t0, t0, -1
    bnez t0, settle4
    li   t0, 0x5
    csrw MARV_ESTAT, t0             # and anything that landed meanwhile

    li   s1, 0x80000000
    la   t3, case4_lw
    sw   t3, 0x68(s1)
    lw   t6, 0x50(s1)               # RNMI count before the load
case4_lw:
    lw   t5, 0(zero)                # address 0: unmapped -> bus error
    li   t4, 10000
wait4:
    lw   t0, 0x50(s1)
    bne  t0, t6, got4
    addi t4, t4, -1
    bnez t4, wait4
got4:
    li   s1, 0x80000000
    csrr t3, MARV_ESTAT
    sw   t3, 0x60(s1)
    csrr t3, MARV_EADDR
    sw   t3, 0x64(s1)
    csrr t3, MARV_EPC
    sw   t3, 0x6C(s1)
    lw   t3, 0x54(s1)
    sw   t3, 0x70(s1)
    lw   zero, 0x70(s1)
    li   t0, 0x5
    csrw MARV_ESTAT, t0

    li   x31, 0x66666666            # Sync: case 4 recorded

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
