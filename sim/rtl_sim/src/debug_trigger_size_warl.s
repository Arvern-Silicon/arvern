#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_size_warl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: mcontrol6.size WARL for execute triggers
#   Execute matches do not qualify on instruction size, so size is WARL 0 for
#   an execute-only trigger (a value that reads back must be honoured).
#   Triggers with load and/or store keep 1..3 (it qualifies the data access).
#     0x00: execute, size=3 -> size 0      0x04: execute, size=2 -> size 0
#     0x08: load,    size=2 -> size 2      0x0C: store,   size=3 -> size 3
#     0x10: execute+load, size=1 -> size 1
#----------------------------------------------------------------------------

.equ SBASE,          0x80000000

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

.macro PROBE off, val
    csrw 0x7a1, x0
    li   t0, \val
    csrw 0x7a1, t0
    csrr t1, 0x7a1
    srli t1, t1, 16
    andi t1, t1, 7
    sw   t1, \off(s1)
.endm

_start:
    li   s1, SBASE
    csrw 0x7a0, x0                 # tselect = 0
    li   x31, 0x11111111           # Sync: start

    PROBE 0x00, 0x60030044         # m | execute, size=3
    PROBE 0x04, 0x60020044         # m | execute, size=2
    PROBE 0x08, 0x60020041         # m | load,    size=2
    PROBE 0x0C, 0x60030042         # m | store,   size=3
    PROBE 0x10, 0x60010045         # m | execute | load, size=1
    csrw 0x7a1, x0

    lw   zero, 0x10(s1)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
