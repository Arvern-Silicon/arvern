#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_alu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT ALU
#   Verifies the ALU-stall HPM event counter (event selector 0x03).
#
#   Multi-cycle divide operations stall the pipeline for several cycles
#   while the divider completes:
#   DIV_TYPE=1 (radix-8,  12 cycles): 11 stall cycles per DIVU
#   DIV_TYPE=2 (radix-4,  17 cycles): 16 stall cycles per DIVU
#   DIV_TYPE=3 (radix-2,  33 cycles): 32 stall cycles per DIVU
#
#   This test executes one DIVU instruction and checks that the ALU stall
#   counter is > 0 afterwards.
#
#   Requires: M_EXTENSION == 2 (full RV32M with divide support).
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_alu_count — counter3 after 1 division (expect > 0)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MHPMEVENT3,    0x323
.equ MHPMCOUNTER3,  0xB03

main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero the scratchpad word used for result
    li   t0, 0
    sw   t0, 0x00(s1)

    #=================================================================
    # Configure HPM counter 3 to count ALU-stall events (0x03)
    #=================================================================
    li   t0, 3
    csrw MHPMEVENT3, t0              # event selector = 0x03 (ALU stall)

    # Zero counter3
    csrw MHPMCOUNTER3, x0

    # Inhibit counter3 while setting up
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0      # set inhibit bit 3

    # Clear inhibit — counting starts now
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit bit 3

    #=================================================================
    # Execute 1 unsigned divide
    # DIVU stalls the pipeline for multiple cycles (11-32 depending on
    # DIV_TYPE): each stall cycle increments the ALU stall counter.
    #=================================================================
    li   t0, 0x12345678
    li   t1, 0x1234
    divu t2, t0, t1                  # multi-cycle unsigned divide

    #=================================================================
    # Inhibit counter and read result
    #=================================================================
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0      # set inhibit bit 3 (freeze counter)

    csrr t0, MHPMCOUNTER3
    sw   t0, 0x00(s1)                # p1_alu_count
    lw   t3, 0x00(s1)                # AHB fence

    # Clear inhibit (restore counter running state)
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit bit 3

    li   x31, 0xdeadbeef             # Sync: test done

end_of_test:
    j    end_of_test
