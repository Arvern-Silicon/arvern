#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_irq
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT IRQ
#   Tests the interrupt-taken event (event selector 0x0A) on mhpmevent3.
#
#   Procedure:
#   1. Set mhpmevent3 = 0x0A (interrupt-taken event)
#   2. Zero mhpmcounter3
#   3. Signal testbench: ready to receive IRQs  (x31 = 0x11111111)
#   4. Testbench injects 4 software IRQs, one at a time
#   5. Firmware polls trap count at 0x8000FFF0 until >= 4
#   6. Inhibit counter, read, store to scratchpad
#   7. Signal end of test (x31 = 0xdeadbeef)
#
#   Scratchpad layout (base 0x80000000):
#   0x00: irq_hpm_count — mhpmcounter3 after 4 IRQs taken (expect 4)
#
#   Note: trap counter is at 0x8000FFF0 (maintained by _random_irq_init
#   handler); firmware polls it to know when 4 IRQs have been taken.
#----------------------------------------------------------------------------

.section .text
.global main

.equ MHPMEVENT3,    0x323
.equ MHPMCOUNTER3,  0xB03
.equ MCOUNTINHIBIT, 0x320


main:
    jal  t0, _random_irq_init        # set up trap handler, enable MIE+MSIE

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad slot
    li   t0, 0
    sw   t0, 0x00(s1)
    lw   t3, 0x00(s1)                # AHB fence

    # Set mhpmevent3 = 0x0A (interrupt-taken event)
    li   t0, 0x0A
    csrw MHPMEVENT3, t0

    # Zero mhpmcounter3
    csrw MHPMCOUNTER3, x0

    # Signal testbench: event set up and counter zeroed — ready for IRQs
    li   x31, 0x11111111

    # Poll trap counter at 0x8000FFF0 until at least 4 traps have been taken
    li   s2, 0x8000FFF0              # s2 = trap counter address
    li   s3, 4                       # s3 = threshold
poll_irq:
    lw   t0, 0(s2)                   # read trap count
    blt  t0, s3, poll_irq            # keep polling until 4 traps taken

    # Inhibit counter to freeze the count
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0

    # Read and store HPM counter value
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x00(s1)
    lw   t3, 0x00(s1)                # AHB fence

    # Clear inhibit
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0

    li   x31, 0xdeadbeef             # Sync: test done

end_of_test:
    j    end_of_test
