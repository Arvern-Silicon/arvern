#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_plic_seip
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PLIC -> S-mode external IRQ (delegated SEI via PLIC ctx 1)
#   Verifies the PLIC's per-hart S-context drives irq_s_external_o and that
#   a delegated SEI is taken in S-mode with the correct SCAUSE, claim ID,
#   and complete behaviour.
#
#   PLIC contexts under NUM_HARTS=1, SU_MODE_EN=1:
#     ctx 0 = hart0/M  (enable @ 0x0C002000, threshold/claim @ 0x0C200000)
#     ctx 1 = hart0/S  (enable @ 0x0C002080, threshold/claim @ 0x0C201000)
#
#   Flow:
#     - M-mode: install S-mode handler via stvec, program PLIC ctx 1,
#       delegate SEI to S-mode (mideleg bit 9), enable SIE.SEIE and
#       SSTATUS.SIE, drop to S-mode via mret.
#     - S-mode: signal TB ready; TB asserts plic_irq_src[1].
#     - PLIC ctx 1 raises irq_s_external_o -> SEIP -> delegated SEI ->
#       S-mode trap.
#     - S-handler reads ctx 1 claim register, asks TB to drop the source,
#       writes complete, sret.
#     - S-mode mainline reports completion via x31.
#----------------------------------------------------------------------------

.section .text
.global main

# PLIC S-context (ctx 1)
.equ PLIC_PRI_BASE,  0x0C000000
.equ PLIC_EN_S,      0x0C002080
.equ PLIC_TH_S,      0x0C201000
.equ PLIC_CLAIM_S,   0x0C201004

#=========================================================================
# Scratchpad (base 0x80000000)
#   0x00: s_trap_count
#   0x04: last SCAUSE
#   0x08: last SEPC
#   0x0C: last claimed source ID
#   0x80: TB drop-source signal (handler writes claimed ID; TB drops it)
#=========================================================================

main:
    j _start

    #---------------------------------------------------------------
    # S-MODE TRAP HANDLER
    #---------------------------------------------------------------
    .align 2
s_trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, scause
    csrr t1, sepc

    # s_trap_count++
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    sw   t0, 0x04(s1)             # SCAUSE
    sw   t1, 0x08(s1)             # SEPC

    # Only handle Supervisor External Interrupt (cause 9 + MSB)
    li   t3, 0x80000009
    bne  t0, t3, s_handler_done

    # PLIC claim from S-context
    li   t3, PLIC_CLAIM_S
    lw   t4, 0(t3)
    sw   t4, 0x0C(s1)

    # Tell TB to drop the source
    sw   t4, 0x80(s1)

    # Busy-loop ~100 cycles to let TB drop the level
    li   t2, 100
plic_drop_wait:
    addi t2, t2, -1
    bnez t2, plic_drop_wait

    # PLIC complete
    li   t3, PLIC_CLAIM_S
    sw   t4, 0(t3)

    sw   zero, 0x80(s1)

s_handler_done:
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
    sret


    #---------------------------------------------------------------
    # M-MODE TRAP HANDLER (catches any spurious M-mode trap)
    #---------------------------------------------------------------
    .align 2
m_trap_handler:
    # Should not be invoked under this test (SEI is delegated). If it is,
    # advance MEPC by 4 and return so the test can finish gracefully.
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret


    #---------------------------------------------------------------
    # MAIN
    #---------------------------------------------------------------
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x80(s1)

    # Install handlers
    la   t0, m_trap_handler
    csrw mtvec, t0
    la   t0, s_trap_handler
    csrw stvec, t0

    # Configure PLIC ctx 1 (S-context)
    #   priority[1] = 5
    #   enable[ctx1][word0] = bit 1
    #   threshold[ctx1] = 0
    li   t0, 5
    li   t1, PLIC_PRI_BASE + 4*1
    sw   t0, 0(t1)

    li   t0, 0x00000002             # enable source 1 in ctx 1
    li   t1, PLIC_EN_S
    sw   t0, 0(t1)

    li   t0, 0
    li   t1, PLIC_TH_S
    sw   t0, 0(t1)

    # Delegate Supervisor External Interrupt (cause 9) to S-mode
    li   t0, 0x200                  # mideleg bit 9
    csrs mideleg, t0

    # Enable SIE.SEIE (bit 9)
    li   t0, 0x200
    csrs sie, t0

    # Enable SSTATUS.SIE (bit 1) so S-mode honors IRQs at its own level
    li   t0, 0x2
    csrs sstatus, t0

    # Disable MSTATUS.MIE so an M-mode trap is not preempted before we
    # transition to S-mode (matches trap_irq_seip pattern).
    li   t0, 0x8
    csrc mstatus, t0

    # Set up mstatus to return to S-mode: MPP = 01, MPIE = 1
    li   t0, 0x1800                 # MPP[12:11]
    csrc mstatus, t0
    li   t0, 0x0800                 # MPP = 01 (S-mode)
    csrs mstatus, t0
    li   t0, 0x80                   # MPIE = 1
    csrs mstatus, t0

    # mret to S-mode entry
    la   t0, s_mode_entry
    csrw mepc, t0
    li   x31, 0x11111111            # signal: PLIC configured, dropping to S
    mret


    .align 2
s_mode_entry:
    # Now in S-mode with SIE=1.
    li   x31, 0x21212121            # tell TB: in S-mode, assert src 1 now

    # Wait for the S-handler to bump trap_count
s_wait:
    lw   t0, 0x00(s1)
    beqz t0, s_wait

    # All done from S-mode (no ecall back needed; the testbench just
    # observes x31 from probes_cpu regardless of current privilege).
    li   x31, 0x44444444

end_of_test:
    j    end_of_test
