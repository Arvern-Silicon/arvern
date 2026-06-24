#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_aclint_setssip
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ACLINT SSWI SETSSIP end-to-end (S-mode self-IPI)
#   Requires SU_MODE_EN=1.
#   - M-mode delegates SSI (cause 1) to S-mode via mideleg
#   - M-mode enables SIE.SSIE + SSTATUS.SIE, installs an S-mode handler,
#     and MRETs to S-mode
#   - S-mode firmware writes SETSSIP[0]=1 at the ACLINT (write-only edge
#     register; LSB always reads 0 per spec)
#   - aclint_sswi raises irq_s_software_o for 1 hclk cycle; the core
#     latches it into MIP.SSIP
#   - Because mideleg.SSI=1, the SSI is taken in S-mode (scause = 0x80000001)
#   - Handler clears MIP.SSIP via CSRC and SRETs
#
#   ACLINT SSWI window: SETSSIP[hart=0] = 0x0200C000
#----------------------------------------------------------------------------

.section .text
.global main

.equ ACLINT_SETSSIP0,  0x0200C000

#=========================================================================
# SRAM scratchpad
#   0x00: s_trap_count
#   0x04: last SCAUSE
#   0x10: m_trap_count    (should stay 0 -- M-mode handler is the trap;
#                          its firing means delegation failed)
#   0x14: last MCAUSE     (diagnostic if m-mode trap fires)
#   0x18: last MEPC       (diagnostic)
#=========================================================================

main:
    j _start

    #=====================================================================
    # S-MODE TRAP HANDLER (SSI path)
    #=====================================================================
    .align 2
s_trap_handler:
    addi sp, sp, -16
    sw   t0,  12(sp)
    sw   t1,   8(sp)
    sw   t2,   4(sp)

    csrr t0, scause

    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)
    sw   t0, 0x04(s1)

    # Clear SIP.SSIP (S-mode delegated view of MIP.SSIP). Writing MIP
    # directly from S-mode would raise an illegal-instruction trap; SIP
    # is the proper S-mode-accessible CSR (0x144) and -- because SSI is
    # delegated -- writes to SIP.SSIP propagate to MIP.SSIP.
    li   t1, 0x2
    csrc sip, t1

    lw   t2,   4(sp)
    lw   t1,   8(sp)
    lw   t0,  12(sp)
    addi sp, sp, 16
    sret


    #=====================================================================
    # M-MODE TRAP HANDLER (must NOT fire under this test -- delegation
    # should send SSI to S-mode. If it does fire, log mcause/mepc so the
    # TB can diagnose, then mask MIE.SSIE so we don't livelock, advance
    # MEPC, and return.)
    #=====================================================================
    .align 2
m_trap_handler:
    addi sp, sp, -16
    sw   t0,  12(sp)
    sw   t1,   8(sp)
    sw   t2,   4(sp)

    csrr t0, mcause
    csrr t1, mepc

    lw   t2, 0x10(s1)
    addi t2, t2, 1
    sw   t2, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t1, 0x18(s1)

    # Mask MIE.SSIE so we don't re-trap forever
    li   t2, 0x2
    csrc mie, t2

    # Advance MEPC past the offending instruction so MRET makes forward
    # progress (for diagnostic completion only)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,   4(sp)
    lw   t1,   8(sp)
    lw   t0,  12(sp)
    addi sp, sp, 16
    mret


    #=====================================================================
    # MAIN
    #=====================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x10(s1)
    sw   zero, 0x14(s1)
    sw   zero, 0x18(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0
    la   t0, s_trap_handler
    csrw stvec, t0

    # Delegate SSI (cause 1) to S-mode
    li   t0, 0x2
    csrs mideleg, t0

    # Mirror what trap_irq_ssip_hw phase 4 does: write SIE.SSIE.
    # SIE is a delegated view of MIE -- writing SIE.SSIE updates MIE.SSIE
    # provided mideleg.SSI=1 (which we just set).
    li   t0, 0x2
    csrs sie, t0

    # Enable SSTATUS.SIE (bit 1) so S-mode honours IRQs at its own level
    li   t0, 0x2
    csrs sstatus, t0

    # Disable MSTATUS.MIE so an M-mode trap can't preempt us before we
    # transition to S-mode (matches trap_irq_ssip_hw pattern).
    li   t0, 0x8
    csrc mstatus, t0

    # MPP = 01 (S), MPIE = 1
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0880                 # MPP=01 + MPIE=1
    csrs mstatus, t0

    la   t0, s_mode_entry
    csrw mepc, t0
    li   x31, 0x11111111            # signal: configured, dropping to S
    mret


    .align 2
s_mode_entry:
    # In S-mode with SIE=1 and mideleg.SSI=1 -- SSI should be delegated.

    # Trigger SSI via ACLINT SSWI
    li   t0, ACLINT_SETSSIP0
    li   t1, 1
    sw   t1, 0(t0)

s_wait:
    lw   t0, 0x00(s1)
    beqz t0, s_wait

    li   x31, 0xdeadbeef
    j end_of_test

end_of_test:
    nop
    j end_of_test
