#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_hit0_step
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SINGLE STEP HALTING ON AN ARMED EXECUTE TRIGGER
#   Trigger 0 is armed by firmware as an execute breakpoint (action = 0) on
#   `target`. The debugger halts the hart, points dpc at `pre` (the
#   instruction before `target`) and single-steps: the step halts with dpc =
#   target, dcsr.cause = 4. The trigger has not fired (the step halt comes
#   first), so mcontrol6.hit0 must read 0. The debugger then disarms the
#   trigger and lets the program finish.
#   a0 = &pre, a1 = &target for the debugger.
#----------------------------------------------------------------------------

.section .text
.global main
main:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw  mstatush, x0              # mstatus.MDT   = 0
    la    t0, trap_handler
    csrw  mtvec, t0

    la    a0, pre
    la    a1, target
    csrw  0x7a0, x0                 # tselect = 0
    csrw  0x7a2, a1                 # tdata2  = target
    li    t0, 0x60000044            # mcontrol6: m, execute, action 0, match =
    csrw  0x7a1, t0
    csrsi 0x7a5, 8                  # tcontrol.mte = 1

    li    x31, 0x11111111
spin:
    j     spin

    .option push
    .option norvc
pre:
    addi  t1, x0, 1
target:
    addi  t2, x0, 2
    .option pop
    li    x31, 0xdeadbeef
end_of_test:
    j     end_of_test

    .align 2
trap_handler:
    li    x31, 0xbadbad00
park:
    j     park
