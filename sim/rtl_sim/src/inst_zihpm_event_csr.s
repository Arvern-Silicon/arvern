#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_csr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT CSR
#   Verifies the CSR-stall HPM event counter (event selector 0x04).
#
#   Reading the time CSR (0xC01) requires a grant from the external time
#   interface (time_gnt_i). The testbench introduces a delay before
#   asserting time_gnt, causing ex_csr_ready_i to be low for several cycles.
#   Each cycle where ~ex_csr_ready_i fires increments the CSR stall counter.
#
#   One time CSR read is performed; the resulting stall count must be > 0.
#
#   Note: the subsequent SW that saves time_lo to scratchpad does NOT count
#   as a CSR stall — only CSR instructions themselves (csrr/csrw etc.) that
#   stall the pipeline due to ~ex_csr_ready_i generate CSR stall events.
#
#   Requires: ZICNTR_EN == 1 (time CSR must be present).
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_csr_count — counter3 after 1 time CSR read (expect > 0)
#   0x04: time_lo      — value read from time CSR (confirms read succeeded)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MHPMEVENT3,    0x323
.equ MHPMCOUNTER3,  0xB03
.equ TIME,          0xC01

main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero the scratchpad words used
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)

    #=================================================================
    # Configure HPM counter 3 to count CSR-stall events (0x04)
    #=================================================================
    li   t0, 4
    csrw MHPMEVENT3, t0              # event selector = 0x04 (CSR stall)

    # Zero counter3
    csrw MHPMCOUNTER3, x0

    # Inhibit counter3 while setting up
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0      # set inhibit bit 3

    # Clear inhibit — counting starts now
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit bit 3

    #=================================================================
    # Read time CSR — causes CSR stall while waiting for time_gnt_i
    # Signal the testbench just before the read so it can force
    # time_gnt=0 for a guaranteed minimum number of stall cycles.
    #=================================================================
    li   x31, 0x11111111             # Sync: about to execute csrr TIME
    csrr t0, TIME                    # time (0xC01) — stalls until time_gnt_i
    sw   t0, 0x04(s1)                # save time_lo (SW does NOT cause CSR stall)

    #=================================================================
    # Inhibit counter and read result
    #=================================================================
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0      # set inhibit bit 3 (freeze counter)

    csrr t0, MHPMCOUNTER3
    sw   t0, 0x00(s1)                # p1_csr_count
    lw   t3, 0x00(s1)                # AHB fence

    # Clear inhibit (restore counter running state)
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit bit 3

    li   x31, 0xdeadbeef             # Sync: test done

end_of_test:
    j    end_of_test
