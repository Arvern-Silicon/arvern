#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_wfi_stip_hang
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: WFI wake on software-set supervisor-timer pending (STIP).
#
#   Reproducer for a suspected WFI liveness gap. Per the RISC-V Privileged
#   spec, WFI must wake on ANY enabled+pending interrupt (mie bit set, mip
#   bit set) REGARDLESS of the global mstatus.MIE. STIP (mip[5]) has no
#   input pin in this core -- it is purely software-set via an M-mode write
#   to mip. The combinational live-wakeup that ungates hclk during sleep is
#   reconstructed from the IRQ INPUT PINS, so it may not cover STIP.
#
#   Sequence (M-mode, mstatus.MIE = 0 throughout):
#     1. Set mie.STIE (mip[5] enable) and mip.STIP (software-set pending).
#     2. WFI. Spec REQUIRES an immediate wake (enabled+pending), with NO
#        trap (MIE=0) -- firmware must resume at after_wfi.
#     3. On resume, write 0xCAFEBABE and raise x31=0x22222222.
#
#   If the core gates its clock and never wakes, x31 never reaches
#   0x22222222 and the testbench reports a HANG.
#
# SRAM scratchpad (base 0x80000000):
#   0x00: post-WFI sentinel (0xCAFEBABE proves firmware resumed)
#   0x04: mip read-back after setup (must have bit5 set)
#   0x08: mie read-back after setup (must have bit5 set)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    .align 2
trap_handler:
    # No trap is expected (MIE=0, STI not delegated). If one fires, flag it
    # with a distinct sentinel so the TB can tell "unexpected trap" apart
    # from "hang".
    li   x31, 0xbadbad00
park_handler:
    j    park_handler

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)

    # Install (defensive) trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Ensure global interrupts are DISABLED (mstatus.MIE = 0).
    li   t0, 0x8
    csrc mstatus, t0

    # STI not delegated -> would target M-mode (but MIE=0 blocks any trap).
    csrw mideleg, zero

    # Enable supervisor-timer interrupt: mie.STIE = bit5.
    li   t0, 0x20
    csrs mie, t0

    # Software-set supervisor-timer pending: mip.STIP = bit5 (M-mode write).
    li   t0, 0x20
    csrs mip, t0

    # Read back mip / mie so the TB can confirm the wake condition was armed.
    csrr t0, mip
    sw   t0, 0x04(s1)
    csrr t0, mie
    sw   t0, 0x08(s1)
    lw   t0, 0x08(s1)          # load-back fence

    # Signal ready: TB will observe the sleep state, then expect a wake.
    li   x31, 0x21212121

    # Per spec, WFI must wake immediately here (STIP & STIE pending, MIE=0).
    wfi

after_wfi:
    # Firmware resumes here WITHOUT a trap (MIE=0).
    li   t0, 0xCAFEBABE
    sw   t0, 0x00(s1)
    lw   t0, 0x00(s1)          # load-back fence

    li   x31, 0x22222222

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
