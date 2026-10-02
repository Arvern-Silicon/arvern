#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_gpr_jalr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DM-written GPR visible to a post-resume jalr base (Debug Module)
#   Proves that a value written to a GPR by the Debug Module (abstract Access
#   Register write) while the hart is halted is FULLY visible to a subsequent
#   jalr that uses that GPR as its base register after resume -- including the
#   case where that same GPR (x12) was the base of the jalr the hart was spinning
#   on at the instant it was halted (so any per-base jalr fast-path is "primed"
#   on x12 before the DM overwrites it).
#
#   The hart spins on `jalr x0, 0(x12)` with x12 pointing at the jalr itself, so
#   it self-loops -- the first jalr "misses" on base x12, every later iteration
#   reuses base x12. The testbench halts mid-spin, reads the address of
#   good_target from x13 (computed by `la`, robust to linking), DM-writes it into
#   x12, and resumes. The post-resume jalr MUST use the NEW (DM-written) x12 as
#   its target and land on good_target; if it used a STALE base it would self-
#   loop forever and never set x20/x31.
#
#   Registers:
#     x12 : jalr base; initially = jalr_loop (self-loop), DM-overwritten = good_target
#     x13 : address of good_target (TB reads this via probes while halted)
#     x20 : marker (0x00000BAD pre-set; success path overwrites with 0x0000600D)
#     x31 : sync (11111111=spinning on jalr, 22222222=reached good_target, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    la   x12, jalr_loop        # jalr base: initially points at the self-loop below
    la   x13, good_target      # address the TB will DM-write into x12 (read via probes)
    li   x20, 0x00000BAD       # pre-set marker = BAD; success path overwrites it

    li   x31, 0x11111111       # sync: about to spin on the jalr (TB halts us here)
jalr_loop:
    jalr x0, 0(x12)            # jump to [x12]; x12==jalr_loop => self-loop (base primed on x12)

good_target:
    li   x20, 0x0000600D       # success marker -- only reached if jalr used the DM-written x12
    li   x31, 0x22222222       # sync: reached good_target after resume
    li   x31, 0xdeadbeef       # final sync: test done
end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)
