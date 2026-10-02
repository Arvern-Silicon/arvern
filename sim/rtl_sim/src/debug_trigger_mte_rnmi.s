#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_mte_rnmi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sdtrig tcontrol.MTE across an Smrnmi RNMI entry / MNRET
#   Sdtrig rule for ordinary traps into M: MPTE <= MTE, MTE <= 0 on entry;
#   MRET restores MTE <= MPTE. The same protection must hold for the
#   resumable NMI: on RNMI entry MTE is saved into a hardware shadow and
#   cleared, so a native M-mode execute trigger (mcontrol6, m=1, action=0)
#   cannot raise a breakpoint inside the RNMI handler -- where NMIE=0 would
#   turn that breakpoint into an UNEXPECTED trap (critical error, lockup_o).
#   MNRET restores MTE from the shadow.
#
#   mcontrol6 tdata1: [31:28]=type(6) [15:12]=action [10:7]=match [6]=m
#                     [2]=execute. Arming word 0x60000044 = type6|m|execute,
#                     match=equal, action=0 (breakpoint).
#   tcontrol (0x7a5): MTE bit 3, MPTE bit 7.
#
#   PHASES (trigger 0 re-pointed each phase):
#     0  Self-check of the trigger machinery in this very test: trigger on
#        main_marker_0 fires once (mcause=3), handler disarms, marker runs.
#     1  tcontrol.MTE=1, trigger armed on rnmi_marker (INSIDE the RNMI
#        handler). Testbench fires the NMI. Inside the handler:
#          - tcontrol read into a slot BEFORE the marker (survives a lockup)
#          - the marker must execute (no breakpoint, no critical error)
#        then MNRET. After MNRET main reads tcontrol again: MTE=1 restored,
#        MPTE unchanged from the pre-NMI read.
#     3  Trigger re-pointed at main_marker_3: MUST fire (mcause=3) -- proves
#        MTE really is armed again after MNRET.
#     4  tcontrol = 0 (MTE=0), testbench fires a second NMI. Inside the
#        handler MTE reads 0; after MNRET MTE still reads 0 (MNRET restores
#        the value saved at this entry, 0). A trigger then armed on
#        main_marker_4 (action=0, m=1) must NOT fire, since MTE=0.
#
#   Scratchpad (byte offsets from 0x80000000):
#     0x00 total breakpoint traps         0x04 breakpoints at rnmi_marker (0)
#     0x08 RNMI entries (1)               0x0C unexpected traps (0)
#     0x10 tcontrol inside RNMI (MTE=0)   0x14 tcontrol pre-NMI (MTE=1)
#     0x18 tcontrol post-MNRET (MTE=1)    0x1C &main_marker_3
#     0x20 mepc at phase-3 breakpoint     0x24 mnepc inside RNMI
#     0x28 mncause inside RNMI            0x2C breakpoints at main_marker_0 (1)
#     0x30 breakpoints at main_marker_3 (1)
#     0x34 tcontrol pre-NMI #2 (0)        0x38 tcontrol post-MNRET #2 (MTE=0)
#     0x44 tcontrol inside RNMI #1        0x48 tcontrol inside RNMI #2 (MTE=0)
#
#   Registers:
#     s1 (x9) scratchpad base   sp (x2) handler stack
#     x24 (s8)  main_marker_3 side effect (PRE 0xB7B70000 -> 0x77)
#     x25 (s9)  main_marker_0 side effect (PRE 0xCCCC0000 -> 0x11)
#     x27 (s11) rnmi_marker side effect   (PRE 0xBEEF0000 -> 0x55)
#     x23 (s7)  main_marker_4 side effect (PRE 0xA4A40000 -> 0x44)
#     x31 sync: 11111111 = armed, fire the NMI; 22222222 = back from MNRET;
#               33333333 = MTE=0, fire the second NMI; deadbeef = done
#----------------------------------------------------------------------------

.section .text
.global main
.option norvc

main:
    j _start

    #---------------------------------------------------------------
    # M-mode trap handler. Breakpoints (mcause=3) are classified by
    # mepc, counted, the trigger is disarmed and mret returns WITHOUT
    # advancing mepc (the marker then executes). Any other cause is
    # unexpected: counted and skipped.
    #---------------------------------------------------------------
    .align 2
m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)
    csrr t0, mcause
    li   t1, 3
    bne  t0, t1, h_unexpected

    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)          # total breakpoints

    csrr t0, mepc
    la   t1, main_marker_0
    bne  t0, t1, 1f
    lw   t2, 0x2C(s1)
    addi t2, t2, 1
    sw   t2, 0x2C(s1)          # phase-0 breakpoint
    j    h_disarm
1:
    la   t1, rnmi_marker
    bne  t0, t1, 2f
    lw   t2, 0x04(s1)
    addi t2, t2, 1
    sw   t2, 0x04(s1)          # breakpoint INSIDE the RNMI handler (must stay 0)
    j    h_disarm
2:
    la   t1, main_marker_3
    bne  t0, t1, h_disarm
    sw   t0, 0x20(s1)          # mepc at the phase-3 breakpoint
    lw   t2, 0x30(s1)
    addi t2, t2, 1
    sw   t2, 0x30(s1)          # phase-3 breakpoint
h_disarm:
    csrw 0x7a0, x0             # tselect = 0
    csrw 0x7a1, x0             # disarm trigger 0
    j    h_ret
h_unexpected:
    lw   t0, 0x0C(s1)
    addi t0, t0, 1
    sw   t0, 0x0C(s1)          # unexpected-trap counter (must end == 0)
    csrr t0, mepc
    addi t0, t0, 4             # .option norvc: every instruction is 4 bytes
    csrw mepc, t0
h_ret:
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #---------------------------------------------------------------
    # RNMI handler (Smrnmi). Evidence is written to the scratchpad and
    # fenced BEFORE the marker, so it survives a critical-error lockup
    # at the marker.
    #---------------------------------------------------------------
    .align 2
rnmi_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    lw   t0, 0x08(s1)
    addi t0, t0, 1
    sw   t0, 0x08(s1)          # RNMI entries
    csrr t0, 0x7a5
    sw   t0, 0x10(s1)          # tcontrol inside the RNMI handler (expect MTE=0)
    lw   t1, 0x08(s1)
    slli t1, t1, 2
    add  t1, t1, s1
    sw   t0, 0x40(t1)          # per entry: 0x44 (first NMI), 0x48 (second NMI)
    csrr t0, 0x741
    sw   t0, 0x24(s1)          # mnepc
    csrr t0, 0x742
    sw   t0, 0x28(s1)          # mncause (expect 0x80000002)
    lw   t1, 0x28(s1)          # AHB fence: the stores above have landed
    addi t1, t1, 0             # consume the load before the marker
    .align 2
rnmi_marker:
    addi s11, x0, 0x55         # trigger 0 is armed HERE; must NOT fire (MTE=0)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    .word 0x70200073           # mnret: NMIE=1, MTE restored from the shadow

#=========================================================================
_start:
    csrsi 0x744, 8             # mnstatus.NMIE = 1 first ...
    csrw  mstatush, x0         # ... then clear MDT (resets to 1)
    li   sp, 0x8000F000
    li   s1, 0x80000000

    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    sw   x0, 0x08(s1)
    sw   x0, 0x0C(s1)
    sw   x0, 0x10(s1)
    sw   x0, 0x14(s1)
    sw   x0, 0x18(s1)
    sw   x0, 0x20(s1)
    sw   x0, 0x24(s1)
    sw   x0, 0x28(s1)
    sw   x0, 0x2C(s1)
    sw   x0, 0x30(s1)
    sw   x0, 0x34(s1)
    sw   x0, 0x38(s1)
    sw   x0, 0x44(s1)
    sw   x0, 0x48(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0
    la   t0, rnmi_handler
    csrw 0x7FD, t0             # marv_nmvec = RNMI handler
    la   t0, main_marker_3
    sw   t0, 0x1C(s1)

    li   s8,  0xB7B70000       # PRE main_marker_3
    li   s9,  0xCCCC0000       # PRE main_marker_0
    li   s11, 0xBEEF0000       # PRE rnmi_marker

    li   t0, 0x08
    csrw 0x7a5, t0             # tcontrol.MTE = 1

    #=================================================================
    # PHASE 0 : trigger machinery self-check (fires once in main)
    #=================================================================
    csrw 0x7a0, x0             # tselect = 0
    csrw 0x7a1, x0
    la   t1, main_marker_0
    csrw 0x7a2, t1
    li   t0, 0x60000044        # type6 | m | execute | match=equal | action=0
    csrw 0x7a1, t0
    # Arming latency: a csrw-written trigger does not cover the instruction
    # right behind it -- give the write a few instructions of slack.
    nop
    nop
    nop
    nop
    .align 2
main_marker_0:
    addi s9, x0, 0x11          # fires here; handler disarms; then runs

    #=================================================================
    # PHASE 1 : arm on the RNMI-handler marker, MTE=1, fire the NMI
    #=================================================================
    li   t0, 0x08
    csrw 0x7a5, t0             # re-establish MTE=1 after the phase-0 trap
    csrr t0, 0x7a5
    sw   t0, 0x14(s1)          # tcontrol pre-NMI

    csrw 0x7a0, x0
    csrw 0x7a1, x0
    la   t1, rnmi_marker
    csrw 0x7a2, t1
    li   t0, 0x60000044
    csrw 0x7a1, t0             # live: fires if MTE is still 1 inside the RNMI
    nop
    nop
    nop
    nop

    li   x31, 0x11111111       # sync: testbench fires the NMI

    li   t2, 20000
spin_rnmi:
    lw   t0, 0x08(s1)
    bnez t0, got_rnmi
    addi t2, t2, -1
    bnez t2, spin_rnmi
got_rnmi:
    csrr t0, 0x7a5
    sw   t0, 0x18(s1)          # tcontrol post-MNRET, read BEFORE any further trap
    lw   t1, 0x18(s1)
    addi t1, t1, 0

    li   x31, 0x22222222       # sync: back from MNRET

    #=================================================================
    # PHASE 3 : trigger re-pointed at a main marker MUST fire again
    #=================================================================
    csrw 0x7a0, x0
    csrw 0x7a1, x0
    la   t1, main_marker_3
    csrw 0x7a2, t1
    li   t0, 0x60000044
    csrw 0x7a1, t0
    nop
    nop
    nop
    nop
    .align 2
main_marker_3:
    addi s8, x0, 0x77          # fires here (mcause=3); handler disarms; then runs
    csrw 0x7a1, x0             # belt-and-braces: ensure disabled

    #=================================================================
    # PHASE 4 : MTE=0 before the NMI; MNRET restores 0
    #=================================================================
    li   s7, 0xA4A40000        # PRE main_marker_4
    csrw 0x7a5, x0             # tcontrol = 0: MTE=0, MPTE=0
    csrr t0, 0x7a5
    sw   t0, 0x34(s1)          # tcontrol pre-NMI #2

    li   x31, 0x33333333       # sync: testbench fires the second NMI

    li   t2, 20000
spin_rnmi2:
    lw   t0, 0x08(s1)
    li   t1, 2
    beq  t0, t1, got_rnmi2
    addi t2, t2, -1
    bnez t2, spin_rnmi2
got_rnmi2:
    csrr t0, 0x7a5
    sw   t0, 0x38(s1)          # tcontrol post-MNRET #2, before any further trap
    lw   t1, 0x38(s1)
    addi t1, t1, 0

    csrw 0x7a0, x0
    csrw 0x7a1, x0
    la   t1, main_marker_4
    csrw 0x7a2, t1
    li   t0, 0x60000044
    csrw 0x7a1, t0             # action=0 in M with MTE=0: must not fire
    nop
    nop
    nop
    nop
    .align 2
main_marker_4:
    addi s7, x0, 0x44
    csrw 0x7a1, x0

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
