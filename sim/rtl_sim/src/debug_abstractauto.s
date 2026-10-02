#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_abstractauto
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: abstractauto.autoexecdata[0] (DMI 0x18 bit 0) auto-exec check
#   The hart spins in a counted loop while the testbench acts as the debugger
#   over the DMI bus. All the action is debugger-driven (over DMI); the firmware
#   only parks distinctive sentinels in a few GPRs and spins so the halt is clean.
#
#   Per RISC-V Debug Spec 1.0, when abstractauto.autoexecdata0=1, ANY debugger
#   access (read OR write) to data0 (DMI 0x04) re-executes the last abstract
#   command written to `command` (DMI 0x17), reproducing all cmderr/busy rules.
#
#   Registers:
#     x5  : write-autoexec target   (init 0x51515151, DMI-injected 0x11111111
#                                     then auto-replayed to 0x22222222)
#     x6  : read-autoexec source    (init 0x62626262, DMI-injected KNOWN 0x6C6C6C6C)
#     x7  : neighbor sentinel, never accessed  (expect 0x73737373)
#     x8  : loop counter (frozen while halted)
#     x9  : loop bound
#     x31 : sync (11111111=spinning, 22222222=loop done, deadbeef=done)
#
#   NOTE: firmware never touches x5/x6/x7 inside the spin loop, so the values the
#   debugger injects while halted survive the brief running windows and the final
#   resume; the testbench cross-checks them.
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x5,  0x51515151        # distinct from the DMI-injected 0x11111111 (step 2a proof)
    li   x6,  0x62626262        # distinct from the DMI-injected KNOWN 0x6C6C6C6C (step 3)
    li   x7,  0x73737373        # neighbor: must never be touched by any abstract access
    li   x8,  0                 # loop counter (frozen while halted)
    li   x9,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)

    li   x31, 0x11111111        # sync: about to spin (TB halts us here)
spin:
    addi x8,  x8, 1
    blt  x8,  x9, spin          # count up to the bound (paused while halted)

    li   x31, 0x22222222        # sync: loop finished after final resume
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)
