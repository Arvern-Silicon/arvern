#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_ls_action1_idx
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: load and store watchpoints with action=1 on trigger index 1
#   and on the highest implemented index
#   debug_interface.md §8: "Load/store (data-address) watchpoints ... fires
#   at EX, before the access completes (store does not modify memory; load
#   does not update its destination): action=1 -> Debug Mode, dcsr.cause=2,
#   dpc = the load/store instruction's PC".
#   debug_interface.md §7: "On resume: privilege restored from dcsr.prv,
#   PC <- dpc" (so the load/store re-executes).
#
#   The debugger (the .v) halts the hart at `wait`, arms one trigger per
#   phase through abstract access and resumes; each phase halts on its
#   access, the .v checks and disarms it and arms the next one:
#     ld1: load  watchpoint on trigger 1           (LD1 0x80001000)
#     st1: store watchpoint on trigger 1           (ST1 0x80001010)
#     ld2: load  watchpoint on trigger NR-1        (LD2 0x80001020)
#     st2: store watchpoint on trigger NR-1        (ST2 0x80001030)
#   After each resume the access is performed; the firmware captures the
#   loaded value / the stored word for the final check.
#
#   Registers: x6/x7/x8/x9 = &ld1/&st1/&ld2/&st2, x5 load destination
#   (0xBEEF0000 before ld1, 0xBEEF0001 before ld2), x21 = ld1 value
#   (0x0B0B0B0B), x22 = [ST1] after st1 (0xA5A5A5A5), x23 = ld2 value
#   (0x0C0C0C0C), x24 = [ST2] after st2 (0xC5C5C5C5), x29 release flag,
#   x31 sync (11111111 = waiting, deadbeef = done).
#----------------------------------------------------------------------------

.section .text
.global main

.option norvc

main:
    li   t0, 0x0B0B0B0B
    li   a3, 0x80001000
    sw   t0, 0(a3)                 # LD1 data
    li   t0, 0x5A5A5A5A
    li   a4, 0x80001010
    sw   t0, 0(a4)                 # ST1 sentinel
    li   t0, 0x0C0C0C0C
    li   a5, 0x80001020
    sw   t0, 0(a5)                 # LD2 data
    li   t0, 0x5C5C5C5C
    li   a6, 0x80001030
    sw   t0, 0(a6)                 # ST2 sentinel
    li   a2, 0xA5A5A5A5
    li   a7, 0xC5C5C5C5

    la   x6, ld1
    la   x7, st1
    la   x8, ld2
    la   x9, st2
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x24, 0
    li   x5, 0xBEEF0000
    li   x29, 0
    li   x31, 0x11111111
wait:
    beq  x29, x0, wait

ld1:
    lw   x5, 0(a3)
    mv   x21, x5
    li   x5, 0xBEEF0001
st1:
    sw   a2, 0(a4)
    lw   x22, 0(a4)
ld2:
    lw   x5, 0(a5)
    mv   x23, x5
st2:
    sw   a7, 0(a6)
    lw   x24, 0(a6)
    or   x25, x22, x24             # consume the loads before the final sync

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
