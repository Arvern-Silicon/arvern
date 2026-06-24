#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_event_lsu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM EVENT LSU
#   Verifies the LSU-stall HPM event counter (event selector 0x02).
#
#   Uses a load-use address hazard to create guaranteed LSU stalls:
#   lw t0, 0x60(s1)    — loads s1 value (0x80000000) into t0
#   lw t1, 0x00(t0)    — RS1=t0, which is the destination of the previous
#   load, causing a 1-cycle hazard stall in EX stage
#
#   Scratchpad[0x60] is pre-initialized to 0x80000000 (= s1) so that t0
#   holds a valid SRAM address for the second load.
#
#   4 hazard pairs are executed, guaranteeing >= 4 LSU stall events.
#   With SRAM wait states the count will be higher.
#
#   Scratchpad layout (base 0x80000000):
#   0x00: p1_lsu_count — counter3 after 4 hazard pairs (expect >= 4)
#   0x60: pre-initialized to 0x80000000 (= s1 value, valid SRAM address)
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
    # Pre-initialize scratchpad[0x60] = s1 = 0x80000000
    # This MUST be done before enabling the counter so the stores
    # are not counted as LSU stall events.
    # scratchpad[0x60] holds a valid SRAM address so that
    # lw t0, 0x60(s1) loads 0x80000000 into t0, and then
    # lw t1, 0x00(t0) is a valid load from SRAM base.
    #=================================================================
    sw   s1, 0x60(s1)                # scratchpad[0x60] = 0x80000000

    #=================================================================
    # Configure HPM counter 3 to count LSU-stall events (0x02)
    #=================================================================
    li   t0, 2
    csrw MHPMEVENT3, t0              # event selector = 0x02 (LSU stall)

    # Zero counter3
    csrw MHPMCOUNTER3, x0

    # Inhibit counter3 while setting up
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0      # set inhibit bit 3

    # Clear inhibit — counting starts now
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit bit 3

    .align 2                         # ensure load pairs are 4-byte aligned so lw instructions are not split across AHB words

    #=================================================================
    # 4 load-use hazard pairs
    # Each pair: lw t0, 0x60(s1) followed immediately by lw t1, 0x00(t0)
    # RS1 of 2nd load == destination of 1st load => 1 hazard stall per pair
    #=================================================================

    # Pair 1
    lw   t0, 0x60(s1)                # t0 = 0x80000000
    lw   t1, 0x00(t0)                # RS1=t0 (just loaded) — HAZARD STALL

    # Pair 2
    lw   t0, 0x60(s1)                # t0 = 0x80000000
    lw   t1, 0x00(t0)                # RS1=t0 (just loaded) — HAZARD STALL

    # Pair 3
    lw   t0, 0x60(s1)                # t0 = 0x80000000
    lw   t1, 0x00(t0)                # RS1=t0 (just loaded) — HAZARD STALL

    # Pair 4
    lw   t0, 0x60(s1)                # t0 = 0x80000000
    lw   t1, 0x00(t0)                # RS1=t0 (just loaded) — HAZARD STALL

    #=================================================================
    # Inhibit counter and read result
    #=================================================================
    li   t0, 0x8
    csrrs x0, MCOUNTINHIBIT, t0      # set inhibit bit 3 (freeze counter)

    csrr t0, MHPMCOUNTER3
    sw   t0, 0x00(s1)                # p1_lsu_count
    lw   t3, 0x00(s1)                # AHB fence

    # Clear inhibit (restore counter running state)
    li   t0, 0x8
    csrrc x0, MCOUNTINHIBIT, t0      # clear inhibit bit 3

    li   x31, 0xdeadbeef             # Sync: test done

end_of_test:
    j    end_of_test
