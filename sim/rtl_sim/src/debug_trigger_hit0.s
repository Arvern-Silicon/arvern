#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_hit0
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sdtrig mcontrol6 hit0 STATUS bit (Debug Spec 1.0, MXLEN=32)
#   FIRING test proving the mcontrol6.hit0 bit (tdata1 bit 22) reports WHICH
#   trigger fired and entered Debug Mode, and that the debugger can clear it.
#
#   hit0 semantics under test:
#     - hardware SETS hit0=1 only on the trigger that FIRES + enters Debug Mode
#       (action=1 enter-Debug triggers);
#     - a trigger that did NOT fire keeps hit0=0 (discriminates which one fired);
#     - the debugger CLEARS hit0 by writing tdata1 with bit[22]=0, leaving the
#       rest of the mcontrol6 config unchanged;
#     - hit1 (bit 25) is NOT implemented -> stays 0.
#
#   mcontrol6 (type=6) tdata1 bit layout referenced here:
#     [31:28]=type(6) [27]=dmode [25]=hit1 [22]=hit0 [21]=select
#     [19:16]=size [15:12]=action [10:7]=match [6]=m
#     [4]=s [3]=u [2]=execute [1]=store [0]=load
#   Trigger CSRs: tselect 0x7a0, tdata1 0x7a1, tdata2 0x7a2, tcontrol 0x7a5.
#   tcontrol.mte (bit3) = 1 : enable M-mode triggers.
#
#   All triggers here use action=1 (ENTER DEBUG) which REQUIRES dmode=1, so they
#   are armed by the DEBUGGER (the .v) while the hart is halted. The firmware only
#   pre-loads the tdata2 targets, stashes the target PCs for the debugger's dpc
#   compare, and spins so the debugger can arm; on fire the hart auto-enters Debug
#   Mode and the .v reads hit0 over the DMI abstract Access Register.
#
#   PHASE 1 (EXECUTE breakpoints -- the priority): two execute triggers armed at
#     once. Trigger 0 -> &trig_tgt_A (reached first), trigger 1 -> &trig_tgt_B.
#     Both action=1. The hart reaches A first -> only trigger 0 fires. The .v
#     asserts trigger0.hit0==1 while trigger1.hit0==0 (which one fired is now
#     readable), then clears trigger0.hit0 and confirms the config survives. The
#     .v disarms BOTH triggers before resume (trigger 1 stays armed otherwise and
#     would re-enter Debug at B with no debugger servicing it -> hang). After
#     disarm+resume trig_tgt_A executes (x5=0xAA -> scratch 0x40).
#
#   PHASE 2 (STORE data-address watchpoint): shows hit0 works for the load/store
#     path too. Trigger 0 armed as a store watchpoint (action=1) on &P2_DATA; on
#     fire the .v asserts trigger0.hit0==1, clears it (config intact), disarms and
#     resumes -> the sw then executes (P2_DATA=0x2B2B2B2B -> scratch 0x44).
#
#   Scratchpad (byte offsets from SRAM base 0x80000000):
#     0x40 A x5 final (0x000000AA -- executed after Phase-1 disarm)
#     0x44 P2_DATA final (0x2B2B2B2B -- stored after Phase-2 disarm)
#
#   Registers:
#     sp (x2) trap stack        s1 (x9) SRAM scratchpad base
#     x5  A execute side-effect target (PRE 0xBEEF0000 -> 0xAA)
#     x6  &trig_tgt_A (read by the .v, compared to dpc)
#     x7  &trig_tgt_B (Phase-1 trigger 1 target address)
#     a3  Phase-2 data pointer (&P2_DATA)   a4  Phase-2 store value
#     x31 sync (11111111=Phase-1 armed/spinning, 22222222=Phase-2 armed/spinning,
#              deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

_start:
    li   sp, 0x8000F000        # trap-handler stack (no M-mode trap is expected)
    li   s1, 0x80000000        # SRAM scratchpad base

    # tcontrol.mte = 1 : enable M-mode triggers.
    li   t0, 0x08
    csrw 0x7a5, t0


    #=================================================================
    # PHASE 1 : two EXECUTE triggers, action=1 (ENTER DEBUG).
    #   Firmware pre-loads tdata2 for BOTH triggers; the DEBUGGER (the .v)
    #   arms tdata1 (execute | action=1 | dmode=1) on each while halted.
    #=================================================================
    # Trigger 0 -> &trig_tgt_A (equal-match execute target, reached first).
    # NOTE: x6/x7 hold the target addresses for the .v to compare against dpc.
    # Load them DIRECTLY (x6 is ABI t1, so a `la t1, ...` scratch would alias and
    # clobber x6) -- keep x6=&trig_tgt_A / x7=&trig_tgt_B intact.
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # tdata1 = 0 (disabled until debugger arms it)
    la   x6, trig_tgt_A        # x6 = &trig_tgt_A (debugger reads it, compares dpc)
    csrw 0x7a2, x6             # tdata2 = &trig_tgt_A

    # Trigger 1 -> &trig_tgt_B (a DIFFERENT address, never reached this phase).
    li   t0, 1
    csrw 0x7a0, t0             # tselect = 1
    csrw 0x7a1, x0             # tdata1 = 0 (disabled until debugger arms it)
    la   x7, trig_tgt_B        # x7 = &trig_tgt_B
    csrw 0x7a2, x7             # tdata2 = &trig_tgt_B

    li   x5, 0xBEEF0000        # PRE sentinel for the A execute side effect

    li   x31, 0x11111111       # sync: both pre-loaded; spin so debugger arms

    li   a0, 0
    li   a1, 0x00001000
spin1:
    addi a0, a0, 1
    blt  a0, a1, spin1
    # fall through to trig_tgt_A. With the debugger-armed action=1 trigger 0,
    # the hart AUTO-ENTERS Debug Mode here BEFORE the addi executes; only
    # trigger 0 fires (trigger 1 matches B, which is never reached).
    .align 2
trig_tgt_A:
    addi x5, x0, 0xAA          # A side effect (runs only after debugger disarms)
    sw   x5, 0x40(s1)          # A x5 final (expect 0xAA -> eventually executed)
    nop
    .align 2
trig_tgt_B:
    nop                        # trigger 1 target address (disarmed before we run here)
    nop


    #=================================================================
    # PHASE 2 : STORE data-address watchpoint, action=1 (ENTER DEBUG).
    #   Firmware pre-loads tdata2 = &P2_DATA; the DEBUGGER arms tdata1
    #   (store | action=1 | dmode=1) while halted. Proves hit0 sets for
    #   the load/store watchpoint path too.
    #=================================================================
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # tdata1 = 0 (disabled until debugger arms it)
    li   a3, 0x80001100        # a3 = &P2_DATA (watched DATA address, survives)
    csrw 0x7a2, a3             # tdata2 = &P2_DATA
    li   a4, 0x2B2B2B2B        # a4 = store value (survives)
    li   t0, 0x5A5A0000
    sw   t0, 0(a3)             # P2_DATA pre-sentinel

    li   x31, 0x22222222       # sync: Phase-2 pre-loaded; spin so debugger arms

    li   a0, 0
    li   a1, 0x00001000
spin2:
    addi a0, a0, 1
    blt  a0, a1, spin2
    # fall through to p2_sw. With the debugger-armed action=1 store watchpoint,
    # the hart AUTO-ENTERS Debug Mode here BEFORE the sw modifies P2_DATA.
    .align 2
p2_sw:
    sw   a4, 0(a3)             # store watchpoint fires BEFORE this completes
    lw   a5, 0(a3)             # load back (after disarm+resume -> 0x2B2B2B2B)
    sw   a5, 0x44(s1)          # P2_DATA final (expect 0x2B2B2B2B) for the .v


    li   x31, 0xdeadbeef       # final sync: test done

end_of_test:
    nop
    j    end_of_test
