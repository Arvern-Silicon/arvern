#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_sba_running
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SBA on a RUNNING hart. The DM's system bus master shares the
#   hart's data AHB port but ARBITRATES for it, so a debugger can read and
#   write memory without halting first.
#   The firmware plants known words in SRAM, then spins in a deliberately
#   data-bus-heavy loop (a store + a load every iteration) so every SBA access
#   the testbench issues has to arbitrate against real hart traffic. While the
#   hart is RUNNING the testbench performs SBA reads, an SBA write and an
#   autoincrement block read - all must succeed with sberror=0 - and confirms
#   the loop counter keeps advancing across them. After halting, the same
#   accesses still work. Post-resume the firmware reads all three words back
#   for the final architectural check.
#
#   SRAM layout (base 0x80004000):
#     [0x00] = 0xFEEDC0DE  (planted; SBA-read while running, never written)
#     [0x04] = 0x0BADF00D  (seed; SBA-overwritten to 0xBAADF00D while RUNNING)
#     [0x08] = 0x0BADF00D  (seed; SBA-overwritten to 0xD00DFEED while HALTED)
#     [0x40] = loop scratch (hammered by the spin loop, never touched by SBA)
#
#   Registers:
#     x10 : SRAM base 0x80004000
#     x11 : scratch (planted values)
#     x5  : loop counter (frozen while halted; TB samples it to prove the hart runs)
#     x6  : loop bound
#     x7  : store payload / x8 : load sink / x9 : compare (spin-loop bus traffic)
#     x24 : sticky load-data mismatch accumulator (expect 0: SBA never corrupted a load)
#     x20 : post-resume read-back of [0x00]  (expect 0xFEEDC0DE)
#     x21 : post-resume read-back of [0x04]  (expect 0xBAADF00D, written while RUNNING)
#     x23 : post-resume read-back of [0x08]  (expect 0xD00DFEED, written while HALTED)
#     x31 : sync (11111111=spinning, 22222222=post-resume, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x10, 0x80004000        # SRAM base

    li   x11, 0xFEEDC0DE        # plant word0 (SBA reads this while the hart runs)
    sw   x11, 0x00(x10)
    li   x11, 0x0BADF00D        # seed word1 (SBA overwrites while RUNNING)
    sw   x11, 0x04(x10)
    sw   x11, 0x08(x10)         # seed word2 (SBA overwrites while HALTED)

    li   x20, 0                 # post-resume read-back of [0x00]
    li   x21, 0                 # post-resume read-back of [0x04]
    li   x23, 0                 # post-resume read-back of [0x08]
    li   x7,  0                 # spin-loop store payload
    li   x24, 0                 # sticky load-data mismatch accumulator (must stay 0)
    li   x5,  0                 # loop counter (frozen while halted)
    li   x6,  0x00000400        # loop bound: ~5k cycles, comfortably longer than the
                                # ~350 the TB needs for its SBA sequence, while still
                                # completing under the sim timeout in the slowest
                                # wait-state variants (the body is 2 bus accesses deep)

    li   x31, 0x11111111        # sync: spinning -> TB runs the SBA accesses here
spin:
    sw   x7,  0x40(x10)         # keep the data bus busy so SBA must arbitrate for it
    lw   x8,  0x40(x10)         # ... and read it straight back
    xor  x9,  x8, x7            # must be 0: SBA traffic (including a FAULTING SBA
    or   x24, x24, x9           # access) must never corrupt the hart's own load data
    addi x7,  x7, 1
    addi x5,  x5, 1
    blt  x5,  x6, spin          # count up to the bound (paused while halted)

    # --- after resume: read all three words back for the final check ---
    li   x10, 0x80004000
    lw   x20, 0x00(x10)         # expect 0xFEEDC0DE (never written)
    lw   x21, 0x04(x10)         # expect 0xBAADF00D (SBA write while RUNNING)
    lw   x23, 0x08(x10)         # expect 0xD00DFEED (SBA write while HALTED)
    or   x22, x20, x21          # consume the loads: the load-use interlock guarantees
    or   x22, x22, x23          # x20/x21/x23 have RETIRED before "done" is signalled

    li   x31, 0x22222222        # sync: post-resume read-back done
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)
