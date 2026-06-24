#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_exception
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT EXCEPTION
#   Tests HPM counter event selector for exception-taken event:
#   Phase 1 — mhpmevent3 = 0x09 (exception): expects counter3 = 4
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_excp_count — counter3 after 4 ecall instructions (expect 4)
#
#   The _random_irq_init trap handler handles M-mode ecall (mcause=11) by
#   advancing mepc by 4 and executing mret.  Each ecall causes exactly one
#   exception-taken pulse (trap_taken & ~trap_is_irq), incrementing counter3.
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320

main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad word 0x00 (result slot)
    sw   x0, 0x00(s1)
    lw   t3, 0x00(s1)                # AHB fence


    #=================================================================
    # PHASE 1: exception-taken event (mhpmevent3 = 0x09)
    # Execute exactly 4 ecall instructions between inhibit clear and
    # inhibit set.  Each ecall causes mcause=11 (M-mode ecall).
    # The _random_irq_init handler advances mepc by 4 and returns.
    # The exception-taken event fires once per ecall:
    #   trap_taken=1 & trap_is_irq=0 → core_events[8]=1 for that cycle.
    #=================================================================

    # Set mhpmevent3 = 0x09 (exception-taken)
    li   t0, 9
    csrw 0x323, t0

    # Zero counter3
    csrw 0xB03, x0

    # Set inhibit bit for counter3 (bit 3 = 0x8)
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Clear inhibit — counting window opens
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    # Execute exactly 4 ecall instructions
    ecall                            # exception 1: mcause=11, mepc+=4, mret
    ecall                            # exception 2
    ecall                            # exception 3
    ecall                            # exception 4

    # Close counting window immediately after 4th ecall returns
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Read and store counter3 result with inhibit active
    csrr t0, 0xB03
    sw   t0, 0x00(s1)
    lw   t3, 0x00(s1)               # AHB fence

    # Clear inhibit
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0xdeadbeef            # Sync: all done

end_of_test:
    j    end_of_test
