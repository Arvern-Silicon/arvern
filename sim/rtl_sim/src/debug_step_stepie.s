#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_step_stepie
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: single-step with dcsr.stepie=0 vs stepie=1 (Debug 1.0 Sdext)
#   Debug 1.0 dcsr.stepie: "0 (interrupts disabled): Interrupts (including
#   NMI) are disabled during single stepping with step set." / "1 (interrupts
#   enabled): Interrupts (including NMI) are enabled during single stepping
#   with step set."
#   Debug 1.0 4.5.1: "If control is transferred to a trap handler while
#   executing the instruction, then Debug Mode is re-entered immediately after
#   the PC is changed to the trap handler, and the appropriate tval and cause
#   registers are updated. In this case none of the trap handler is executed,
#   and if the cause was a pending interrupt no instructions might be executed
#   at all."
#
#   The hart is halted on a self-jump (jalr x0, 0(x12) with x12 = its own
#   address), so the saved epc is the spin PC whether the interrupt is taken
#   before or after the stepped instruction executes.
#
#   Phase A/B (spin1, machine external IRQ, mie.MEIE + mstatus.MIE set):
#     A: stepie=0, IRQ pending -> dpc = spin1, cause 4, no trap taken.
#     B: stepie=1, IRQ pending -> dpc = irq_handler, cause 4, mcause
#        0x8000000b, mepc = spin1, handler body not executed (x20 still 0).
#     After free-run the handler sets x20, moves x12 to phase2 and mrets.
#   Phase C/D (spin2, nmi_i pin, mnstatus.NMIE=1):
#     C: stepie=0, NMI pending -> dpc = spin2, cause 4, no RNMI taken.
#     D: stepie=1, NMI pending -> dpc = nmi_handler, cause 4, mncause
#        0x80000002, mnepc = spin2, handler body not executed (x21 still 0).
#     After free-run the handler sets x21, moves x12 to phase_end, mnrets.
#
#   Registers (read by the debugger): x12 spin base, x13 &irq_handler,
#   x14 &nmi_handler, x15 current spin PC, x20/x21 handler flags,
#   x31 sync (11111111 = at spin1, 22222222 = at spin2, deadbeef = done).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

main:
    j    _start

    .align 2
irq_handler:
    li   x20, 0x0000BEEF
    li   x10, 0x800
    csrc mie, x10                  # level IRQ: mask it before mret
    la   x12, phase2               # mepc = spin1 -> its jalr leaves the spin
    mret

    .align 2
nmi_handler:
    li   x21, 0x0000BEEF
    la   x12, phase_end
    .word 0x70200073               # mnret

_start:
    li   x20, 0
    li   x21, 0
    la   x10, irq_handler
    csrw mtvec, x10                # direct mode
    la   x10, nmi_handler
    csrw 0x7FD, x10                # marv_nmvec
    csrsi 0x744, 8                 # Smdbltrp boot: mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0
    li   x10, 0x800
    csrw mie, x10                  # mie.MEIE
    csrsi mstatus, 8               # mstatus.MIE

    la   x13, irq_handler
    la   x14, nmi_handler
    la   x12, spin1
    la   x15, spin1
    li   x31, 0x11111111
spin1:
    jalr x0, 0(x12)

phase2:
    la   x12, spin2
    la   x15, spin2
    li   x31, 0x22222222
spin2:
    jalr x0, 0(x12)

phase_end:
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
