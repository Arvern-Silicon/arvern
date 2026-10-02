#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_wfi_bus_error
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: a data-bus error around WFI must never strand the hart
#
#   A store to an unmapped address is posted, then WFI executes immediately.
#   The AHB error walks back around the moment the core tries to sleep.
#
#   Whether the core sleeps at all is timing: WFI only drops hclk_en once the
#   AHB masters have drained, so the error may resolve first. Either outcome
#   is acceptable -- what must NOT happen is the hart sleeping through the
#   error and never waking. So the assertion is progress: the RNMI is
#   delivered and execution continues past the WFI.
#
#   Deliberately ONE phase: with NMIE armed the error cannot still be pending
#   by the time a later WFI executes -- it is delivered first, leaving that WFI
#   with no wake source at all. The NMIE=0 case is a separate test.
#
#   BASE TIMING ONLY (no_variants). The whole point is that the error is STILL
#   IN FLIGHT when the WFI executes, and that ordering is a property of bus
#   latency: under -rwsrom the fetch is delayed enough that the error resolves
#   and the RNMI is delivered ~40 cycles BEFORE the WFI (measured: pending at
#   286, wfi_active at 326). The WFI then has no wake source and sleeps, which
#   is correct behaviour for a WFI with nothing pending -- the scenario simply
#   does not occur, so there is nothing to assert.
#
# Scratchpad (base 0x80000000):
#   0x00 nmi_handler addr   0x04 nmi_count   0x08 mncause
#   0x0C reached-after-WFI marker
#----------------------------------------------------------------------------

.equ MNSTATUS,   0x744
.equ MNCAUSE,    0x742
.equ FAULT_ADDR, 0x00000000        # unmapped in the tb AHB decoder

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

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x10(s1)

    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x00(s1)
    lw   zero, 0x00(s1)

    li   x31, 0x11111111           # tb programs nmi_vector

    li   t0, 20
wait_vec:
    addi t0, t0, -1
    bnez t0, wait_vec

    csrsi MNSTATUS, 8              # NMIE = 1

    li   x31, 0x22222222

    #---------------------------------------------------------------
    # PHASE 1: post a faulting store, then sleep immediately
    #---------------------------------------------------------------
    li   t1, FAULT_ADDR
    li   t0, 0xDEAD
    sw   t0, 0(t1)                 # posted; will AHB-ERROR
    wfi

    li   t0, 1
    sw   t0, 0x0C(s1)              # progress: we got past the WFI
    lw   zero, 0x0C(s1)

    li   x31, 0x33333333

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
