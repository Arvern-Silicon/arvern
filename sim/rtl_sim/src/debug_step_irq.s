#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_step_irq
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DEBUG single-step vs a pending interrupt (Sdext, dcsr.stepie=0)
#   REPRODUCER for the "interrupt commits during Debug-Mode entry" race
#   (Pass-2 functional finding F-1). Combines the single-step walk with a
#   pending, enabled machine external IRQ:
#
#     firmware enables mie.MEIE + mstatus.MIE and spins on a self-jalr.
#     The testbench halts it, sets dcsr.step (stepie stays 0 -> IRQs are
#     masked for the span of the step), raises the external IRQ WHILE halted,
#     then single-steps ONE instruction. At the step boundary the step
#     IRQ-mask drops one cycle before Debug Mode re-latches; a correct core
#     keeps the IRQ pending (dcsr.cause=4, mstatus.MIE untouched, mcause=0),
#     a buggy core lets the IRQ commit during entry (mstatus.MIE cleared,
#     mcause=0x8000000b, mepc written) -- which the testbench reads back via
#     abstract CSR access.
#
#   Registers:
#     x5,x6,x7 : step-run targets (pre-init 0; the redirect lands on step_start)
#     x10      : scratch for CSR setup / handler (NOT a step target)
#     x12      : jalr spin base (&spin_self; TB rewrites to &step_start)
#     x13      : &step_start (TB reads this to learn the redirect target)
#     x18      : sentinel marker, must survive untouched (0xA5A5A5A5)
#     x20      : IRQ-taken flag, set by handler (0x0000BEEF after full resume)
#     x31      : sync (11111111=spinning/halt-me, deadbeef=done)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x20, 0                 # IRQ-taken flag (handler sets 0xBEEF)

    # pre-init the step-run targets to 0 (clean baseline for the TB)
    li   x5,  0
    li   x6,  0
    li   x7,  0

    la   x10, irq_handler       # mtvec = handler, direct mode
    csrw mtvec, x10

    # Smrnmi (ratified): "When NMIE=0, all interrupts are disabled" and NMIE
    # resets to 0, so boot code must set mnstatus.NMIE=1 before any
    # ordinary interrupt can be delivered. Smrnmi is unconditional.
    csrsi 0x744, 8              # mnstatus.NMIE = 1

    li   x10, 0x800             # mie.MEIE (bit 11) = machine external IRQ enable
    csrw mie, x10
    li   x10, 0x8               # mstatus.MIE (bit 3) = global IRQ enable
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, x10

    la   x13, step_start        # redirect target (testbench abstract-reads this)
    la   x12, spin_self         # jalr base = self -> infinite self-jump (spin)

    li   x31, 0x11111111        # sync: spinning (testbench halts us at spin_self)
spin_self:
    jalr x0, 0(x12)             # spin in place; TB rewrites x12 to &step_start

    #=============================================================
    # STEP RUN: straight-line, distinct 32-bit instructions (+4 each).
    # Reached only after the TB redirects x12 and single-steps the jalr.
    #=============================================================
.option push
.option norvc
step_start:
    addi x5,  x0, 0x11
    addi x6,  x0, 0x22
    addi x7,  x0, 0x33
.option pop

    #=============================================================
    # After the TB clears dcsr.step and free-runs, the still-pending IRQ
    # must be delivered EXACTLY here (post-resume), not during the step.
    #=============================================================
wait_irq:
    beq  x20, x0, wait_irq      # spin until the handler marks the IRQ taken
    li   x31, 0xdeadbeef        # final sync: test done (IRQ delivered cleanly)
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)

    .align 2
irq_handler:
    li   x20, 0x0000BEEF        # mark the IRQ as taken
    li   x10, 0x800            # clear mie.MEIE so the level IRQ won't re-fire
    csrc mie, x10
    mret
