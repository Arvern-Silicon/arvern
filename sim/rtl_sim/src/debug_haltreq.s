#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_haltreq
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DEBUG HALTREQ (Sdext, Debug Spec 1.0 — hart-side)
#   External halt/resume handshake under the frozen-hart model. The firmware runs
#   loops whose results are HALT-LOCATION-INDEPENDENT but depend on every body
#   instruction executing EXACTLY ONCE, so a dpc-off-by-one (replay or skip at the
#   resume boundary) corrupts a checked register even though the loops self-
#   terminate on their own counters.
#
#   Phase A — pure add/addi loop (off-by-one detector):
#     x5 = sum(i=1..256) = 0x8080.  Halted at two different offsets in one run.
#   Phase B — divide loop (multi-cycle in-flight op drain):
#     x10 = 0x12345/7 = 0x299C (the in-flight DIV must drain correctly across the
#     stall) and x9 = sum(i=1..64) = 0x820 (off-by-one detector for the non-DIV
#     body instructions). Halt lands mid-DIV (33-cycle op, M-ext on).
#
#   Registers:
#     x5  : Phase-A sum               (expect 0x00008080)
#     x9  : Phase-B counter sum       (expect 0x00000820)
#     x10 : Phase-B last quotient     (expect 0x0000299C)
#     x7  : sentinel marker, intact   (expect 0xA5A5A5A5)
#     x31 : sync sentinel (11111111=in loop A, 22222222=A done, 33333333=in loop B,
#           44444444=B done, deadbeef=test done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x7, 0xA5A5A5A5         # sentinel marker, must survive untouched

    #=============================================================
    # PHASE A: pure add/addi loop — off-by-one detector
    #   x5 = sum(i=1..256) = 32896 = 0x8080, independent of halt location
    #=============================================================
    li   x5, 0                 # sum
    li   x8, 1                 # i
    li   x6, 0x101             # N+1 = 257

    li   x31, 0x11111111       # sync A: halt me during the sum loop
loopA:
    add  x5, x5, x8            # every pass must run exactly once
    addi x8, x8, 1
    blt  x8, x6, loopA

    li   x31, 0x22222222       # sync: phase A complete

    #=============================================================
    # PHASE B: divide loop — multi-cycle in-flight op drain
    #   x10 = 0x12345 / 7 = 0x299C   (DIV must drain correctly across halt)
    #   x9  = sum(i=1..64) = 2080 = 0x820   (off-by-one detector)
    #=============================================================
    li   x9,  0                # acc
    li   x8,  1                # i
    li   x6,  0x41             # N+1 = 65
    li   x18, 0x12345          # dividend
    li   x11, 7                # divisor

    li   x31, 0x33333333       # sync B: halt me during the div loop
loopB:
    div  x10, x18, x11         # 33-cycle op; must drain correctly across the stall
    add  x9,  x9,  x8          # off-by-one detector (sum of i)
    addi x8,  x8,  1
    blt  x8,  x6,  loopB

    li   x31, 0x44444444       # sync: phase B complete

    li   x31, 0xdeadbeef       # final sync: test done

end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)
