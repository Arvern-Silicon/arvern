#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_irq_masked
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DEBUG HALTREQ vs interrupts (Sdext)
#   A halted hart is frozen: an interrupt that becomes pending WHILE in Debug
#   Mode must NOT be taken (no vector to mtvec) — but it must NOT be lost either;
#   it stays pending and is delivered after resume. This exercises the
#   `trap_pending_set & ~dbg_mode` suppression that every other debug test (all
#   no_random_irq) leaves dark.
#
#   Firmware: enable mie.MEIE + mstatus.MIE, install a handler that sets x20 =
#   0xBEEF and masks MEIE, then spin until x20 is set. The testbench raises the
#   external IRQ only while the hart is halted, checks x20 stays 0 (not taken),
#   then resumes and checks x20 becomes 0xBEEF (delivered after resume).
#
#   Registers:
#     x20 : IRQ-taken flag, set by handler  (expect 0x0000BEEF after resume)
#     x21 : spin progress counter           (advances only while running)
#     x7  : sentinel marker                 (expect 0xA5A5A5A5)
#     x31 : sync (11111111=spinning/ready, 22222222=IRQ handled, deadbeef=done)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main
main:
    li   x7,  0xA5A5A5A5        # sentinel marker, must survive untouched (x5=t0 is used below)
    li   x20, 0                 # IRQ-taken flag (handler sets 0xBEEF)
    li   x21, 0                 # spin progress counter

    la   t0, irq_handler        # mtvec = handler, direct mode (mode bits 0)
    csrw mtvec, t0

    # Smrnmi (ratified): "When NMIE=0, all interrupts are disabled" and NMIE
    # resets to 0, so boot code must set mnstatus.NMIE=1 before any
    # ordinary interrupt can be delivered. Smrnmi is unconditional.
    csrsi 0x744, 8              # mnstatus.NMIE = 1

    li   t0, 0x800              # mie.MEIE (bit 11) = machine external IRQ enable
    csrw mie, t0
    li   t0, 0x8               # mstatus.MIE (bit 3) = global IRQ enable
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0

    li   x31, 0x11111111        # sync: spinning, ready to be halted
wait_irq:
    addi x21, x21, 1           # progress: proves the hart is actually running
    beq  x20, x0, wait_irq      # spin until the handler marks the IRQ taken

    li   x31, 0x22222222        # IRQ was taken (only possible after resume)
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)

    .align 2
irq_handler:
    li   x20, 0x0000BEEF        # mark the IRQ as taken
    li   t0,  0x800            # clear mie.MEIE so the level IRQ won't re-fire
    csrc mie, t0
    mret
