#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_platform
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT PLATFORM
#   Tests platform events 0x0B through 0x12 (platform_events[0] through [7])
#   on mhpmcounter3.
#
#   For each platform event i (i=0..7):
#   1. Set mhpmevent3 = 0x0B + i
#   2. Zero mhpmcounter3
#   3. Signal testbench with sync value (0x11111111..0x88888888)
#   4. Delay loop (~30 iterations) to allow testbench to inject 4 pulses
#   5. Inhibit counter, read, store to scratchpad[i*4]
#   6. Clear inhibit
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p0_count — mhpmcounter3 for platform event 0 (expect 4)
#   0x04: p1_count — mhpmcounter3 for platform event 1 (expect 4)
#   0x08: p2_count — mhpmcounter3 for platform event 2 (expect 4)
#   0x0C: p3_count — mhpmcounter3 for platform event 3 (expect 4)
#   0x10: p4_count — mhpmcounter3 for platform event 4 (expect 4)
#   0x14: p5_count — mhpmcounter3 for platform event 5 (expect 4)
#   0x18: p6_count — mhpmcounter3 for platform event 6 (expect 4)
#   0x1C: p7_count — mhpmcounter3 for platform event 7 (expect 4)
#----------------------------------------------------------------------------

.section .text
.global main

.equ MHPMEVENT3,    0x323
.equ MHPMCOUNTER3,  0xB03
.equ MCOUNTINHIBIT, 0x320


main:
    jal  t0, _random_irq_init        # set up trap handler, enable MIE

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base

    # Zero scratchpad (8 words)
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)
    lw   t3, 0x1C(s1)                # AHB fence


    #=================================================================
    # Platform event 0 (event 0x0B, hpm_platform_events_i[0])
    #=================================================================
    li   t0, 0x0B
    csrw MHPMEVENT3, t0
    csrw MHPMCOUNTER3, x0            # zero counter
    li   x31, 0x11111111             # signal testbench: ready for event 0

    # Delay loop: ~30 iterations to give testbench time to inject pulses
    li   t0, 30
plat0_delay:
    addi t0, t0, -1
    bnez t0, plat0_delay

    # Inhibit, read, and store counter
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x00(s1)
    lw   t3, 0x00(s1)                # AHB fence
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0


    #=================================================================
    # Platform event 1 (event 0x0C, hpm_platform_events_i[1])
    #=================================================================
    li   t0, 0x0C
    csrw MHPMEVENT3, t0
    csrw MHPMCOUNTER3, x0            # zero counter
    li   x31, 0x22222222             # signal testbench: ready for event 1

    li   t0, 30
plat1_delay:
    addi t0, t0, -1
    bnez t0, plat1_delay

    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x04(s1)
    lw   t3, 0x04(s1)                # AHB fence
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0


    #=================================================================
    # Platform event 2 (event 0x0D, hpm_platform_events_i[2])
    #=================================================================
    li   t0, 0x0D
    csrw MHPMEVENT3, t0
    csrw MHPMCOUNTER3, x0            # zero counter
    li   x31, 0x33333333             # signal testbench: ready for event 2

    li   t0, 30
plat2_delay:
    addi t0, t0, -1
    bnez t0, plat2_delay

    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x08(s1)
    lw   t3, 0x08(s1)                # AHB fence
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0


    #=================================================================
    # Platform event 3 (event 0x0E, hpm_platform_events_i[3])
    #=================================================================
    li   t0, 0x0E
    csrw MHPMEVENT3, t0
    csrw MHPMCOUNTER3, x0            # zero counter
    li   x31, 0x44444444             # signal testbench: ready for event 3

    li   t0, 30
plat3_delay:
    addi t0, t0, -1
    bnez t0, plat3_delay

    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x0C(s1)
    lw   t3, 0x0C(s1)                # AHB fence
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0


    #=================================================================
    # Platform event 4 (event 0x0F, hpm_platform_events_i[4])
    #=================================================================
    li   t0, 0x0F
    csrw MHPMEVENT3, t0
    csrw MHPMCOUNTER3, x0            # zero counter
    li   x31, 0x55555555             # signal testbench: ready for event 4

    li   t0, 30
plat4_delay:
    addi t0, t0, -1
    bnez t0, plat4_delay

    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x10(s1)
    lw   t3, 0x10(s1)                # AHB fence
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0


    #=================================================================
    # Platform event 5 (event 0x10, hpm_platform_events_i[5])
    #=================================================================
    li   t0, 0x10
    csrw MHPMEVENT3, t0
    csrw MHPMCOUNTER3, x0            # zero counter
    li   x31, 0x66666666             # signal testbench: ready for event 5

    li   t0, 30
plat5_delay:
    addi t0, t0, -1
    bnez t0, plat5_delay

    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x14(s1)
    lw   t3, 0x14(s1)                # AHB fence
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0


    #=================================================================
    # Platform event 6 (event 0x11, hpm_platform_events_i[6])
    #=================================================================
    li   t0, 0x11
    csrw MHPMEVENT3, t0
    csrw MHPMCOUNTER3, x0            # zero counter
    li   x31, 0x77777777             # signal testbench: ready for event 6

    li   t0, 30
plat6_delay:
    addi t0, t0, -1
    bnez t0, plat6_delay

    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x18(s1)
    lw   t3, 0x18(s1)                # AHB fence
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0


    #=================================================================
    # Platform event 7 (event 0x12, hpm_platform_events_i[7])
    #=================================================================
    li   t0, 0x12
    csrw MHPMEVENT3, t0
    csrw MHPMCOUNTER3, x0            # zero counter
    li   x31, 0x88888888             # signal testbench: ready for event 7

    li   t0, 30
plat7_delay:
    addi t0, t0, -1
    bnez t0, plat7_delay

    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0
    csrr t0, MHPMCOUNTER3
    sw   t0, 0x1C(s1)
    lw   t3, 0x1C(s1)                # AHB fence
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0


    li   x31, 0xdeadbeef             # Sync: all platform event tests done

end_of_test:
    j    end_of_test
