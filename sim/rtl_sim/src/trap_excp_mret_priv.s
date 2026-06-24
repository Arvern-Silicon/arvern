#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_mret_priv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MRET FROM LOWER PRIVILEGE -> ILLEGAL
#   RISC-V Privileged ISA: MRET (0x30200073) is only legal in M-mode.
#   Executing MRET when the current privilege is less than Machine (S-mode
#   or U-mode) MUST raise an illegal-instruction exception (mcause=2) and
#   MUST NOT perform a trap return / escalate privilege.
#
#   Test structure:
#   Phase 1: init, install M-mode trap handler, zero scratchpad.
#   Phase 2 (positive control + U-mode MRET illegal):
#   M-mode MRET legitimately descends to U-mode (MPP=00). U-mode
#   firmware records a "ran" marker (proves the M-mode MRET that
#   descended actually worked), then executes MRET. That U-mode
#   MRET must trap illegal (mcause=2) with MPP captured = 00. The
#   handler forces MPP=11 and MRETs back to M-mode (proving the
#   hart did NOT escape to M-mode via the U-mode MRET itself).
#   Phase 3 (positive control + S-mode MRET illegal):
#   M-mode MRET legitimately descends to S-mode (MPP=01). S-mode
#   firmware records a "ran" marker, then executes MRET. That
#   S-mode MRET must trap illegal (mcause=2) with MPP = 01.
#
#   Verdict (checked in .v):
#   trap_count == 2, unexpected_count == 0,
#   u_mret_mcause == 2, s_mret_mcause == 2,
#   u_trap_mpp[12:11] == 00, s_trap_mpp[12:11] == 01,
#   u_ran_marker != 0, s_ran_marker != 0.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
#   0x00: trap_count          (expect 2: U-mode MRET + S-mode MRET)
#   0x04: unexpected_count     (expect 0: any non-(mcause==2) entry)
#   0x08: last MCAUSE
#   0x0C: last MEPC
#
# Phase 2 (U-mode MRET illegal):
#   0x20: u_mret_mcause        (expect 2)
#   0x24: u_trap_mpp           (MSTATUS at trap entry; MPP[12:11] expect 00)
#   0x28: u_ran_marker         (expect 0xC0FFEE01: U-mode code executed)
#
# Phase 3 (S-mode MRET illegal):
#   0x30: s_mret_mcause        (expect 2)
#   0x34: s_trap_mpp           (MSTATUS at trap entry; MPP[12:11] expect 01)
#   0x38: s_ran_marker         (expect 0xC0FFEE02: S-mode code executed)
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    #
    # Classifies the trap:
    #   - interrupt (mcause[31]=1)   -> unexpected: count, recover
    #   - mcause[4:0] == 2 (illegal) -> EXPECTED:
    #         record mcause/mepc, advance MEPC by 4 (MRET is always a
    #         4-byte instruction, 0x30200073), force MPP=11 so the
    #         handler's own MRET resumes in M-mode (proving the faulting
    #         lower-priv MRET did NOT itself escape to M-mode), return.
    #   - any other cause            -> unexpected: count, advance MEPC
    #         by 4 + force MPP=11 to avoid livelock, return.
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mstatus

    # Increment global trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Save latest mcause / mepc (debug aid)
    sw   t0, 0x08(s1)
    sw   t1, 0x0C(s1)

    # Interrupt? (mcause[31] set) -> unexpected
    bltz t0, m_unexpected

    # Exception cause field
    andi t3, t0, 0x1F
    li   t4, 2
    bne  t3, t4, m_unexpected

    #---------------------------------------------------------------
    # EXPECTED: illegal-instruction (mcause == 2) from lower-priv MRET
    #---------------------------------------------------------------
    # Which lower-privilege MRET caused this?  MSTATUS.MPP captured the
    # privilege the hart was in *at trap entry*: 00 = U-mode, 01 = S-mode.
    srli t4, t2, 11
    andi t4, t4, 0x3            # t4 = MPP

    li   t3, 0x0                # MPP == 00 -> U-mode MRET
    beq  t4, t3, m_from_u
    li   t3, 0x1                # MPP == 01 -> S-mode MRET
    beq  t4, t3, m_from_s

    # mcause==2 but MPP not 00/01 (e.g. came from M-mode) -> unexpected
    j    m_unexpected

m_from_u:
    sw   t0, 0x20(s1)           # u_mret_mcause
    sw   t2, 0x24(s1)           # u_trap_mpp (MSTATUS snapshot)
    j    m_expected_resume

m_from_s:
    sw   t0, 0x30(s1)           # s_mret_mcause
    sw   t2, 0x34(s1)           # s_trap_mpp (MSTATUS snapshot)
    j    m_expected_resume

m_expected_resume:
    # MRET is always a 4-byte instruction (0x30200073): advance past it.
    addi t1, t1, 4
    csrw mepc, t1
    # Force MPP = 11 so the handler MRET resumes in M-mode.  This is the
    # proof the lower-priv MRET did NOT escape: only this handler-driven
    # MRET (a true M-mode MRET) returns control to M-mode.
    li   t4, 0x1800
    csrs mstatus, t4
    j    m_handler_done

m_unexpected:
    # Record an unexpected entry.
    lw   t3, 0x04(s1)
    addi t3, t3, 1
    sw   t3, 0x04(s1)
    # Recover: if it was an interrupt MEPC need not advance; for any
    # synchronous cause advance by 4 (all instructions here are 4-byte)
    # and force MPP=11 so we do not livelock back into lower privilege.
    bltz t0, m_unexpected_irq
    addi t1, t1, 4
    csrw mepc, t1
m_unexpected_irq:
    li   t4, 0x1800
    csrs mstatus, t4

m_handler_done:
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x8000F000          # safe SP inside 64KB SRAM
    li   s1, 0x80000000          # scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # NOTE: medeleg / medeleg[2] is left at its reset value (0).  An
    # illegal-instruction from S/U-mode therefore routes to the M-mode
    # handler at mtvec (no stvec handler is installed in this test).

    # Initialize callee-saved registers for preservation check
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111         # init done


    #=================================================================
    # PHASE 2: POSITIVE CONTROL (M-mode MRET) + U-mode MRET illegal
    #
    # A legitimate M-mode MRET descends to U-mode (MPP=00).  U-mode code
    # writes a "ran" marker (proving the M-mode MRET worked), then runs
    # MRET -> must trap illegal (mcause=2, MPP captured=00).  Handler
    # forces MPP=11 and MRETs back to M-mode.
    #=================================================================

    la   t0, u_mode_p2
    csrw mepc, t0

    # MPP = 00 (U-mode)
    li   t0, 0x1800
    csrc mstatus, t0
    # Clear MPIE so MIE stays 0 after MRET (no IRQs wanted)
    li   t0, 0x80
    csrc mstatus, t0

    mret                         # legitimate M-mode MRET -> U-mode

u_mode_p2:
    # Now in U-mode (reached only if the M-mode MRET worked: positive
    # control).  Record the "ran" marker.
    li   t0, 0xC0FFEE01
    sw   t0, 0x28(s1)
    lw   t1, 0x28(s1)            # force store completion before MRET

    # Illegal: MRET from U-mode.  Must trap (mcause=2), NOT return.
    mret

    # Control returns here only via the M-mode handler's MRET (MPP=11).
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: POSITIVE CONTROL (M-mode MRET) + S-mode MRET illegal
    #
    # A legitimate M-mode MRET descends to S-mode (MPP=01).  S-mode code
    # writes a "ran" marker, then runs MRET -> must trap illegal
    # (mcause=2, MPP captured=01).  Handler forces MPP=11, MRETs back.
    #=================================================================

    la   t0, s_mode_p3
    csrw mepc, t0

    # MPP = 01 (S-mode)
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0
    # Clear MPIE
    li   t0, 0x80
    csrc mstatus, t0

    mret                         # legitimate M-mode MRET -> S-mode

s_mode_p3:
    # Now in S-mode (positive control: the M-mode MRET worked).
    li   t0, 0xC0FFEE02
    sw   t0, 0x38(s1)
    lw   t1, 0x38(s1)            # force store completion before MRET

    # Illegal: MRET from S-mode.  Must trap (mcause=2), NOT return.
    mret

    # Control returns here only via the M-mode handler's MRET (MPP=11).
    li   x31, 0x33333333

    li   x31, 0xdeadbeef         # final sentinel: end of test


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
