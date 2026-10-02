#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_reset_halt_unfetchable
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sdext halt-on-reset (resethaltreq) — hart-side firmware
#   (RISC-V Debug Spec 1.0, dmcontrol.setresethaltreq + ndmreset).
#
#   What the debugger tests (all driven from the .v):
#     - At power-on resethaltreq is 0, so the hart BOOTS NORMALLY and runs this
#       firmware. It signals "I'm running" via x31=0x11111111 and spins.
#     - The testbench then arms halt-on-reset (setresethaltreq) and pulses
#       ndmreset. The hart comes out of that reset and must ENTER DEBUG MODE
#       BEFORE EXECUTING ANY INSTRUCTION: dcsr.cause=5, dpc=reset vector,
#       minstret=0 (the KEY proof that zero instructions retired since reset).
#     - After clrresethaltreq + resume the hart runs again from the reset vector,
#       executing the reset-vector instruction, and must reach 0xdeadbeef.
#
#   The re-run problem and how the phase flag solves it:
#     The reset vector IS the top of `main`, so on resume-from-reset-halt the hart
#     re-executes `main` from the very first instruction. To make the SECOND run
#     diverge to the done path (instead of spinning forever again), the firmware
#     keeps a boot-phase flag in SRAM. ndmreset resets ONLY the hart (dut_hresetn),
#     NOT the SRAM, so the flag persists across the reset:
#       first boot : SRAM flag == 0 (power-on)  -> take first-boot path, set flag,
#                    signal 0x11111111, spin (TB reset-halts here).
#       re-run     : SRAM flag == magic         -> branch to resumed_path -> done.
#     The reset-vector instruction (li x5,...) STILL executes on the re-run before
#     the branch, so "resume ran the first instruction" holds.
#
#   Registers:
#     x5  : first-instruction marker (0x1234ABCD) — narration; minstret==0 is the
#           real "did-not-execute-during-reset-halt" discriminator.
#     x18 : sentinel (0xA5A5A5A5), must survive untouched.
#     x9  : SRAM scratchpad base (0x80000000).
#     x6  : boot-phase magic (0x0B007B00).
#     x7  : loaded phase flag.
#     x31 : sync (11111111 = running/reset-halt-me, deadbeef = done).
#
#   SRAM scratchpad (base 0x80000000):
#     0x00: boot-phase flag (0 at power-on, magic after first boot; survives ndmreset)
#----------------------------------------------------------------------------

.section .text
.global main

main:
reset_entry:
    li   x5,  0x1234ABCD        # FIRST instruction at the reset vector (must NOT
                                #   retire during reset-halt: minstret==0 proves it)
    li   x18, 0xA5A5A5A5        # sentinel, must survive untouched
    li   x9,  0x80000000        # SRAM scratchpad base
    li   x6,  0x0B007B00        # boot-phase magic

    lw   x7,  0(x9)             # read boot-phase flag (power-on=0; persists ndmreset)
    beq  x7,  x6, resumed_path  # already magic -> this is the post-reset-halt re-run

    #---------------------------------------------------------------
    # FIRST BOOT: arm the phase flag, then announce + spin so the TB
    # can drive setresethaltreq + ndmreset while we sit here.
    #---------------------------------------------------------------
    sw   x6,  0(x9)             # phase flag = magic (survives ndmreset; hart-only reset)
    lw   x7,  0(x9)             # load-back fence: store has landed before we sync

    li   x31, 0x11111111        # sync: running -> testbench, reset-halt me now
spin_here:
    j    spin_here             # spin forever; TB set-resethaltreq + ndmreset from here

    #---------------------------------------------------------------
    # POST-RESET-HALT RE-RUN lands here (reached only after resume,
    # having re-executed the reset-vector instruction above).
    #---------------------------------------------------------------
resumed_path:
    li   x31, 0xdeadbeef        # done: proves resume re-ran the reset vector & finished
end_of_test:
    j    end_of_test           # infinite loop (hart keeps RUNNING for the one-shot check)
