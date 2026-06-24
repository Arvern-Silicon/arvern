#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_lsu_waw_kill
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: LSU WAW vs EX-stage trap (P2 C1 probe)
#   Targets the LSU WAW-vs-trap_kill_ex hazard described in P2 C1 of the RTL
#   review (arv_load_store.v:297). Builds a precisely aligned 2-instruction
#   window in which an EX-stage write enable could spuriously cause the WAW
#   detector to suppress the in-flight load:
#
#   LW   t0, <slow-SRAM>      <- enters DPH, dph_ongoing=1
#   csrrw t0, mvendorid, x0   <- illegal (RO CSR), same rd
#
#   Expected (spec-correct) behavior:
#   - The illegal CSR access raises an illegal-instruction trap.
#   - It does NOT write rd (ex_csr_reg_dest_wr_o gated by
#   ~ex_excp_illegal_inst).
#   - waw_conflict_detected stays 0 because the EX writer is gated.
#   - The load result reaches rd normally when DPH completes.
#
#   Buggy behavior (pre-fix #14): ex_csr_reg_dest_wr_o pulses high, the WAW
#   detector latches, the load is suppressed AND rd is overwritten with 0
#   (csr read mux output for the illegal access). Either way rd is wrong.
#
#   Each phase uses a different value loaded from SRAM and a different rd to
#   avoid stale-value coincidences.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#
# Phase 2: LW t0 + csrrw t0 mvendorid x0
#   0x100: pre-seeded data word loaded by LW            -> 0xCAFEBABE
#   0x20:  t0 captured AFTER illegal CSR                -> must equal 0xCAFEBABE
#
# Phase 3: LW t1 + csrrs t1 mvendorid t6
#   0x104: pre-seeded data word                         -> 0xDEADBEEF
#   0x30:  t1 captured                                  -> must equal 0xDEADBEEF
#
# Phase 4: LW t2 + csrrwi t2 mvendorid 1
#   0x108: pre-seeded data word                         -> 0x1234ABCD
#   0x40:  t2 captured                                  -> must equal 0x1234ABCD
#=========================================================================

main:
    j _start

    .align 2
trap_handler:
    addi sp, sp, -16
    sw   s10,12(sp)
    sw   s11, 8(sp)

    csrr s10, mcause
    csrr s11, mepc

    lw   s10, 0x00(s1)
    addi s10, s10, 1
    sw   s10, 0x00(s1)

    csrr s10, mcause
    sw   s10, 0x04(s1)

    addi s11, s11, 4
    csrw mepc, s11

    lw   s11, 8(sp)
    lw   s10,12(sp)
    addi sp, sp, 16
    mret


 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero handler scratchpad and result slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x40(s1)

    # Pre-seed the load source words.
    li   t0, 0xCAFEBABE
    sw   t0, 0x100(s1)
    li   t0, 0xDEADBEEF
    sw   t0, 0x104(s1)
    li   t0, 0x1234ABCD
    sw   t0, 0x108(s1)

    la   t0, trap_handler
    csrw mtvec, t0

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2 — LW t0 followed by illegal csrrw t0, mvendorid, x0
    #          The two instructions must be back-to-back so csrrw enters
    #          EX while LW is in WB DPH (especially under -rwsram).
    #=================================================================

    # Set t0 to a sentinel different from both the expected load value
    # and the buggy-write value (0). If WAW spuriously suppresses the
    # load AND ~the illegal-CSR rd-write~ are both gated, the load result
    # never lands -> rd retains 0xBAADF00D and the check fails.
    li    t0, 0xBAADF00D

    # Back-to-back LW + csrrw. The bug would be exposed here.
    lw    t0, 0x100(s1)             # load 0xCAFEBABE into t0
    csrrw t0, 0xF11, x0             # illegal -> trap, must not write t0

    # Capture t0 immediately after the trap returns.
    sw    t0, 0x20(s1)
    lw    t0, 0x20(s1)              # drain SW under wait states

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3 — LW t1 followed by csrrs t1, mvendorid, t6 (rs1!=x0)
    #=================================================================

    li    t1, 0xBAADCAFE
    li    t6, 0xFFFFFFFF
    lw    t1, 0x104(s1)
    csrrs t1, 0xF11, t6

    sw    t1, 0x30(s1)
    lw    t1, 0x30(s1)

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4 — LW t2 followed by csrrwi t2, mvendorid, 1
    #=================================================================

    li     t2, 0xFEEDFACE
    lw     t2, 0x108(s1)
    csrrwi t2, 0xF11, 1

    sw     t2, 0x40(s1)
    lw     t2, 0x40(s1)

    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test
