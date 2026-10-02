#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_single_step
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DMI single-step (Sdext dcsr.step, Debug Spec 1.0 — hart-side)
#   The hart spins in place on a self-targeting jalr, then the testbench walks it
#   one instruction at a time using dcsr.step. The firmware itself plays no part
#   in the stepping logic — it only provides a DETERMINISTIC, individually-
#   observable straight-line run of instructions for the debugger to step through.
#
#   The parking trick (no dpc write needed):
#     The hart spins on  `spin_self: jalr x0, 0(x12)`  with x12 = &spin_self, an
#     infinite self-jump. The testbench halts it there (the parked PC is always
#     spin_self — a single instruction, so the park is exact), abstract-WRITES
#     x12 = &step_start (the value the firmware pre-loaded into x13), then begins
#     single-stepping. The first step executes the jalr, redirecting control flow
#     to step_start; every step thereafter walks the addi run +4 at a time.
#
#   The step run is a STRAIGHT LINE of DISTINCT 32-bit (`.option norvc`) addi, each
#   writing a different GPR with a different value, so the testbench can tell
#   EXACTLY how many instructions retired by inspecting the GPRs after each step:
#     step_start+0   addi x5,  x0, 0x11    -> only x5  set after 1 addi-step
#     step_start+4   addi x6,  x0, 0x22    -> only x6  set after 2 addi-steps
#     step_start+8   addi x7,  x0, 0x33    -> only x7  set after 3 addi-steps
#     step_start+12  addi x28, x0, 0x44    -> run free after dcsr.step cleared
#     step_start+16  addi x29, x0, 0x55    -> run free after dcsr.step cleared
#   norvc guarantees +4 per step so the dpc advance is unambiguous in both the
#   STD and COMP builds.
#
#   Registers:
#     x5,x6,x7,x28,x29 : step-run targets (pre-init 0; final 0x11/0x22/0x33/0x44/0x55)
#     x12 : jalr spin base (&spin_self; testbench rewrites it to &step_start)
#     x13 : &step_start (testbench reads this to learn the redirect target)
#     x18 : sentinel marker, must survive untouched (expect 0xA5A5A5A5)
#     x31 : sync (11111111=spinning/halt-me-here, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched

    # pre-init every step-run target to 0 so the testbench has a clean baseline
    li   x5,  0
    li   x6,  0
    li   x7,  0
    li   x28, 0
    li   x29, 0

    la   x13, step_start        # redirect target (testbench abstract-reads this)
    la   x12, spin_self         # jalr base = self -> infinite self-jump (spin)

    li   x31, 0x11111111        # sync: spinning (testbench halts us at spin_self)
spin_self:
    jalr x0, 0(x12)             # spin in place; TB rewrites x12 to &step_start

    #=============================================================
    # STEP RUN: straight-line, distinct 32-bit instructions (+4 each).
    #   Reached only after the TB redirects x12 and single-steps the jalr.
    #=============================================================
.option push
.option norvc
step_start:
    addi x5,  x0, 0x11          # 1st addi-step: x5 = 0x11
    addi x6,  x0, 0x22          # 2nd addi-step: x6 = 0x22
    addi x7,  x0, 0x33          # 3rd addi-step: x7 = 0x33
    addi x28, x0, 0x44          # (run free after dcsr.step cleared)
    addi x29, x0, 0x55          # (run free after dcsr.step cleared)
.option pop

    li   x31, 0xdeadbeef        # final sync: test done (proves step was cleared + resumed)
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)
