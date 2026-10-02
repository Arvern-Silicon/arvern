#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_zcmt_jt_fault
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.JT/JALT LOAD ACCESS-FAULT TRAP
#   Requires C_EXTENSION>=4 (Zcmt). Points the JVT CSR at unmapped memory
#   (0x00000000) and issues CM.JT and CM.JALT. The JVT load must take a
#   load access-fault (MCAUSE=5) and the trap must DELIVER — pre-fix the
#   JT FSM hangs in JT_DPH waiting for wb_ldst_wr_i (which never fires when
#   the load errors), causing the core to livelock.
#
#   The handler advances MEPC by 2 (compressed instruction) and returns to a
#   known recovery target stored in scratchpad so the test can continue.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x0C: recovery address (overwritten before each cm.jt/jalt)
#
#   Phase 2 (cm.jt 0):  trap_count, MCAUSE, MEPC captured
#   Phase 3 (cm.jalt N=32): trap_count, MCAUSE, MEPC captured
#=========================================================================

.equ MNSTATUS,       0x744
.equ MNCAUSE,        0x742

main:
    j _start

    #=================================================================
    # RNMI HANDLER -- the JVT load access fault is reported here now.
    #=================================================================
    .align 2
nmi_handler:
    li   s1, 0x80000000
    lw   t0, 0x24(s1)
    addi t0, t0, 1
    sw   t0, 0x24(s1)
    csrr t0, MNCAUSE
    sw   t0, 0x28(s1)
    csrr t0, 0x741              # mnepc -- where does mnret resume?
    sw   t0, 0x2C(s1)
    csrr t0, 0x7FE              # marv_estat
    sw   t0, 0x30(s1)
    csrr t0, 0xFFC              # marv_epc -- WHAT faulted
    sw   t0, 0x34(s1)
    li   t0, 0x5
    csrw 0x7FE, t0              # W1C valid|overrun so the next phase reads its own

    # mnepc points AT the cm.jt, and a JT table read is NOT restartable: a plain
    # mnret would re-execute it into the same hard bus error forever. A real
    # handler must decide where to go. This one skips to the recovery address --
    # the documented opt-in idiom, just in the other direction.
    lw   t0, 0x0C(s1)
    csrw 0x741, t0              # mnepc = recovery
    lw   zero, 0x28(s1)
    .word 0x70200073            # mnret

    .align 2
trap_handler:
    # Reach the handler with the JT FSM half-way through JT_DPH after a fault.
    # We need the handler to:
    #   1) record MCAUSE / MEPC
    #   2) redirect MEPC to a known recovery address so the JT branch doesn't
    #      try to use a poisoned jt_branch_target.
    addi sp, sp, -16
    sw   s10,12(sp)
    sw   s11, 8(sp)

    csrr s10, mcause
    csrr s11, mepc

    # Increment trap_count
    lw   s10, 0x00(s1)
    addi s10, s10, 1
    sw   s10, 0x00(s1)

    csrr s10, mcause
    sw   s10, 0x04(s1)
    csrr s10, mepc
    sw   s10, 0x08(s1)

    # Redirect to recovery address (stashed by main at 0x0C)
    lw   s11, 0x0C(s1)
    csrw mepc, s11

    lw   s11, 8(sp)
    lw   s10,12(sp)
    addi sp, sp, 16
    mret


 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)

    # Install handler -- NEGATIVE CONTROL, must never be entered
    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x20(s1)
    sw   zero, 0x24(s1)
    sw   zero, 0x28(s1)
    lw   zero, 0x20(s1)

    li   x31, 0x11111111        # tb now programs nmi_vector

    li   t0, 20
wait_vec:
    addi t0, t0, -1
    bnez t0, wait_vec

    csrsi MNSTATUS, 8           # mnstatus.NMIE = 1 -- REQUIRED for delivery


    #=================================================================
    # PHASE 2: cm.jt 0 with JVT base = 0x00000000 (unmapped)
    #          The JVT load from address 0 must fault.
    #          Without the fix, JT_DPH hangs and the trap never delivers.
    #=================================================================

    # JVT base = 0x00000000
    li   t0, 0
    csrw 0x017, t0

    # Recovery address: continue at phase3_start after the trap
    la   t0, phase3_start
    sw   t0, 0x0C(s1)

    la   t0, jt_pc
    sw   t0, 0x38(s1)           # publish the cm.jt PC for the testbench
    lw   zero, 0x38(s1)

    li   x31, 0x12121212        # marker: about to enter cm.jt
jt_pc:
    cm.jt 0                     # JVT[0] -> load from 0x00000000 -> fault
    # The RNMI aborts the table jump; mnret resumes at the resume point,
    # so control falls through here rather than taking the poisoned target.

phase3_start:
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: cm.jalt 32 with JVT base = 0x00000000
    #          Same fault, but on the cm.jalt path which also touches
    #          the ALU phase (PC+2 link) — must not leak into JT_ALU.
    #=================================================================

    la   t0, phase4_start
    sw   t0, 0x0C(s1)

    la   t0, jalt_pc
    sw   t0, 0x38(s1)           # publish the cm.jalt PC
    lw   zero, 0x38(s1)

    li   x31, 0x32323232
jalt_pc:
    cm.jalt 32                  # JVT[32] at address 128 -> load fault

phase4_start:
    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test
