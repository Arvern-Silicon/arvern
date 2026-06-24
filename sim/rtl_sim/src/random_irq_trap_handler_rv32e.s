#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      random_irq_trap_handler_rv32e
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: RV32E-only IRQ trap handler (uses only x0-x15) for random_irq tests.
#----------------------------------------------------------------------------

    .section .text

    .align 2
    .global _random_irq_init
_random_irq_init:

    # Save return address (t0) to MSCRATCH temporarily
    csrw mscratch, t0

    # Set MTVEC to point to trap handler
    la   t0, _random_irq_trap_handler
    csrw mtvec, t0

    # Zero the trap counter (near handler stack, above stack growth)
    li   t0, 0x8000FFF0
    sw   zero, 0x00(t0)

    # Enable all standard interrupt sources in MIE
    #   bit  3: MSIE (software)
    #   bit  7: MTIE (timer)
    #   bit 11: MEIE (external)
    li   t0, 0x888
    csrw mie, t0

    # Set MSCRATCH to handler stack BEFORE enabling interrupts
    # (avoids race: if IRQ fires after MSTATUS.MIE but before
    #  MSCRATCH is set, handler would swap SP with stale value)
    csrr t1, mscratch       # t1 = saved return address
    li   t0, 0x8000FF00
    csrw mscratch, t0

    # Enable global interrupts: set MSTATUS.MIE (bit 3)
    # MSCRATCH is already set, so IRQs are safe from this point
    li   t0, 0x8
    csrs mstatus, t0

    # Clear t0 and restore return address to t0
    mv   t0, t1
    li   t1, 0

    # Return via t0 (not ra, to avoid clobbering x1)
    jalr x0, t0, 0


    #=================================================================
    # TRAP HANDLER
    #=================================================================

    .align 2
_random_irq_trap_handler:

    # ---- Swap SP with MSCRATCH (handler stack) ----
    csrrw  sp, mscratch, sp

    # ---- Save context on handler stack (RV32E: only t0-t2 exist as temps) ----
    addi sp, sp, -16
    sw   t0,  12(sp)
    sw   t1,   8(sp)
    sw   t2,   4(sp)

    # ---- Increment trap count (near handler stack) ----
    li   t0, 0x8000FFF0
    lw   t1, 0x00(t0)
    addi t1, t1, 1
    sw   t1, 0x00(t0)

    # ---- Check trap type ----
    csrr t0, mcause

    # If MSB=1, this is an interrupt -> just return
    bltz t0, _random_irq_handler_done

    # ---- Exception path: advance MEPC past faulting instruction ----
    csrr t1, mepc
    lhu  t2, 0(t1)          # read first halfword of faulting instruction
    andi t2, t2, 0x3         # check bits [1:0]
    li   t0, 0x3             # (RV32I handler uses t3 here; x28 absent in RV32E)
    beq  t2, t0, _random_irq_advance_4
    addi t1, t1, 2           # compressed instruction (16-bit)
    j    _random_irq_exc_done
_random_irq_advance_4:
    addi t1, t1, 4           # standard instruction (32-bit)
_random_irq_exc_done:
    csrw mepc, t1

_random_irq_handler_done:
    # ---- Restore context ----
    lw   t2,   4(sp)
    lw   t1,   8(sp)
    lw   t0,  12(sp)
    addi sp, sp, 16

    # ---- Restore original SP ----
    csrrw  sp, mscratch, sp

    mret
