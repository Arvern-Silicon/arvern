#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_triggers
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sdtrig trigger-CSR register-file conformance (Debug Spec 1.0)
#   This phase tests the trigger CSR FILE only (storage / WARL / access rules).
#   Triggers do NOT fire yet (no match logic), so nothing here arms a breakpoint.
#
#   Two access paths are exercised:
#     - HART-SIDE (this firmware, M-mode csrr/csrw): checks A,B,C,D,F,G,H below,
#       storing every readback into an SRAM scratchpad the testbench inspects.
#     - DEBUGGER-SIDE (the .v, abstract Access Register while halted): debugger
#       round-trips + the dmode write-protection interlock (check E). The firmware
#       cooperates with E by attempting M-mode writes to a dmode-locked trigger
#       (which must be DROPPED) between two debugger halts.
#
#   Trigger CSRs: tselect 0x7a0, tdata1 0x7a1, tdata2 0x7a2, tdata3 0x7a3,
#                 tinfo 0x7a4, tcontrol 0x7a5. tdata1 is mcontrol6 (type=6).
#
#   Checks performed HART-SIDE (scratchpad byte offsets from SRAM base):
#     A tselect round-trip + WARL clamp
#         0x00 tselect=0   readback         (expect 0)
#         0x04 tselect=1   readback         (expect 1; needs >=2 triggers)
#         0x08 tselect=0xFF readback        (clamped: != 0xFF, a legal index)
#         0x0C tselect=clamp readback       (idempotent: == 0x08 value)
#     B per-trigger tdata1/tdata2 storage (independence)
#         0x10 trig0 tdata1                 0x14 trig0 tdata2 (TRIG0_T2)
#         0x18 trig1 tdata1                 0x1C trig1 tdata2 (TRIG1_T2)
#         0x20 trig0 tdata1 re-read         0x24 trig0 tdata2 re-read (TRIG0_T2)
#     C tdata1.type WARL
#         0x28 readback after writing type=0xF (type must be 6 or 0, not 0xF)
#     D WARL dmode=0 & action=1 prevented
#         0x2C readback after M-mode write action=1,dmode=0 (must NOT be that combo)
#     F tinfo
#         0x30 tinfo (bit 6 = mcontrol6 supported, must be set)
#     G tdata3 RAZ/WI
#         0x34 readback after writing nonzero (expect 0)
#     H D-mode-only CSR isolation guard
#         0x38 mcause from a M-mode `csrr dcsr` (0x7b0) -> ILLEGAL (expect 2)
#         0x3C trap counter (exactly 1 trap = the dcsr one)
#     E firmware leg (dmode write-protection): after the debugger locks trigger 0
#       with dmode=1, the firmware's M-mode writes to it must be DROPPED.
#         0x40 trig0 tdata1 after dropped M-mode write (must equal debugger value)
#         0x44 trig0 tdata2 after dropped M-mode write (must equal E_SENTINEL_DBG)
#
#   Registers:
#     x9  (s1) : SRAM scratchpad base (0x80000000)
#     x2  (sp) : stack (trap handler save area)
#     x18      : sentinel marker, must survive all abstract accesses (0xA5A5A5A5)
#     x31      : sync (11111111=hart-side done/spinning,
#                      22222222=dropped-write leg done/spinning, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #---------------------------------------------------------------
    # M-mode trap handler: records mcause + counts traps, then skips
    # the offending (always 32-bit) instruction. Only the deliberate
    # `csrr dcsr` (check H) is expected to land here.
    #---------------------------------------------------------------
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)

    csrr t0, mcause
    sw   t0, 0x38(s1)          # H: record mcause (expect 2 = illegal instruction)

    lw   t1, 0x3C(s1)
    addi t1, t1, 1
    sw   t1, 0x3C(s1)          # H: bump trap counter (must end == 1)

    csrr t1, mepc
    addi t1, t1, 4             # csrr/csrw are always 32-bit -> +4
    csrw mepc, t1

    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


_start:
    csrsi 0x744, 8            # Smdbltrp: a trap in M-mode with NMIE=0 is an unexpected trap
    csrw mstatush, x0        # MDT resets to 1; clear it or the first trap is an Smdbltrp double trap
    li   x18, 0xA5A5A5A5       # GPR sentinel (the debugger must not perturb it)
    li   sp,  0x8000F000       # stack for the trap handler
    li   s1,  0x80000000       # SRAM scratchpad base

    # Clear the H scratchpad slots BEFORE installing the handler / any trap.
    li   t0, 0
    sw   t0, 0x38(s1)          # mcause slot
    sw   t0, 0x3C(s1)          # trap counter

    la   t0, trap_handler
    csrw mtvec, t0             # direct-mode M trap vector


    #=================================================================
    # A: tselect (0x7a0) round-trip + WARL clamp
    #=================================================================
    li   t0, 0
    csrw 0x7a0, t0
    csrr t1, 0x7a0
    sw   t1, 0x00(s1)          # expect 0

    li   t0, 1
    csrw 0x7a0, t0
    csrr t1, 0x7a0
    sw   t1, 0x04(s1)          # expect 1 (legal index, needs >=2 triggers)

    li   t0, 0xFF
    csrw 0x7a0, t0
    csrr t2, 0x7a0             # t2 = clamped index
    sw   t2, 0x08(s1)          # expect a LEGAL index (!= 0xFF)

    csrw 0x7a0, t2             # re-write the clamp value: a legal index is idempotent
    csrr t1, 0x7a0
    sw   t1, 0x0C(s1)          # expect == 0x08 readback


    #=================================================================
    # B: per-trigger tdata1/tdata2 storage independence
    #    Use action=0 (exception) + match=0 (exact) so dmode=0 stays a
    #    legal combo and tdata2 is a clean 32-bit R/W match value.
    #=================================================================
    # --- trigger 0 ---
    li   t0, 0
    csrw 0x7a0, t0            # tselect = 0
    li   t0, 0x60000041       # type6 | m | load   (dmode=0, action=0, match=0)
    csrw 0x7a1, t0            # tdata1
    li   t0, 0x8000ABC0
    csrw 0x7a2, t0            # tdata2 = TRIG0_T2
    csrr t1, 0x7a1
    sw   t1, 0x10(s1)
    csrr t1, 0x7a2
    sw   t1, 0x14(s1)         # expect 0x8000ABC0

    # --- trigger 1 ---
    li   t0, 1
    csrw 0x7a0, t0            # tselect = 1
    li   t0, 0x60000042       # type6 | m | store  (distinct from trigger 0)
    csrw 0x7a1, t0
    li   t0, 0xCAFE0008
    csrw 0x7a2, t0            # tdata2 = TRIG1_T2
    csrr t1, 0x7a1
    sw   t1, 0x18(s1)
    csrr t1, 0x7a2
    sw   t1, 0x1C(s1)         # expect 0xCAFE0008

    # --- re-select trigger 0: its state must be untouched by the trigger-1 writes ---
    li   t0, 0
    csrw 0x7a0, t0
    csrr t1, 0x7a1
    sw   t1, 0x20(s1)         # expect == 0x10 readback
    csrr t1, 0x7a2
    sw   t1, 0x24(s1)         # expect == TRIG0_T2 (0x8000ABC0)


    #=================================================================
    # C: tdata1.type WARL  (trigger 0 selected)
    #    Write type=0xF (unsupported) -> readback type must be 6 or 0.
    #=================================================================
    li   t0, 0xF0000041       # type=0xF + m + load
    csrw 0x7a1, t0
    csrr t1, 0x7a1
    sw   t1, 0x28(s1)


    #=================================================================
    # D: WARL dmode=0 & action=1 prevented  (trigger 0 selected)
    #    M-mode cannot set dmode (stays 0); writing action=1 must be
    #    WARL-forced to a legal combo (action != 1 while dmode=0).
    #=================================================================
    li   t0, 0x60001041       # type6 | action=1 (bits[15:12]=1) | m | load, dmode=0
    csrw 0x7a1, t0
    csrr t1, 0x7a1
    sw   t1, 0x2C(s1)


    #=================================================================
    # F: tinfo (0x7a4) -- bit 6 set (mcontrol6 / type 6 supported)
    #=================================================================
    csrr t1, 0x7a4
    sw   t1, 0x30(s1)


    #=================================================================
    # G: tdata3 (0x7a3) RAZ/WI -- write nonzero, must read 0
    #=================================================================
    li   t0, 0xFFFFFFFF
    csrw 0x7a3, t0
    csrr t1, 0x7a3
    sw   t1, 0x34(s1)         # expect 0


    #=================================================================
    # H: D-mode-only CSR isolation guard.
    #    With triggers ENABLED, a M-mode read of dcsr (0x7b0) must STILL
    #    raise illegal-instruction (the adjacent trigger CSRs in the same
    #    0x7Ax/0x7Bx bank must NOT have leaked dcsr/dpc/dscratch to M-mode).
    #    The handler records mcause (-> 0x38, expect 2) and counts the trap.
    #=================================================================
    csrr t1, 0x7b0           # ILLEGAL in M-mode -> traps to trap_handler

    li   x31, 0x11111111      # sync: hart-side checks complete, now spin


    #---------------------------------------------------------------
    # Spin so the debugger can halt us, set dmode=1 on trigger 0,
    # then resume. (Halt lands somewhere inside this loop.)
    #---------------------------------------------------------------
    li   a0, 0
    li   a1, 0x00001000
spin1:
    addi a0, a0, 1
    blt  a0, a1, spin1


    #=================================================================
    # E (firmware leg): trigger 0 is now dmode-locked by the debugger.
    #    These M-mode writes MUST be DROPPED (not trap, just ignored).
    #=================================================================
    li   t0, 0
    csrw 0x7a0, t0           # tselect = 0 (the locked trigger)
    li   t0, 0x60000042       # try to change tdata1 -> must be dropped
    csrw 0x7a1, t0
    li   t0, 0xDEADBEEF       # try to change tdata2 -> must be dropped
    csrw 0x7a2, t0
    csrr t1, 0x7a1
    sw   t1, 0x40(s1)         # expect == debugger-written tdata1 (unchanged)
    csrr t1, 0x7a2
    sw   t1, 0x44(s1)         # expect == E_SENTINEL_DBG (unchanged)

    li   x31, 0x22222222      # sync: dropped-write leg done, spin again


    #---------------------------------------------------------------
    # Spin again so the debugger can re-halt and confirm it can still
    # modify the dmode-locked trigger.
    #---------------------------------------------------------------
    li   a0, 0
    li   a1, 0x00001000
spin2:
    addi a0, a0, 1
    blt  a0, a1, spin2

    #=================================================================
    # G: full-width tdata1/tdata2 exercise across every implemented trigger
    #    The count is discovered at RUNTIME so this works for any DM_TRIGGER_NR:
    #    tselect is WARL and clamps to the highest legal index, so writing all
    #    ones reads back DM_TRIGGER_NR-1 (arv_debug_trigger.v:107).
    #
    #    Slot 0 is skipped: section F leaves it dmode-locked, so M-mode writes to
    #    it are dropped by design. Slots 1..NR-1 are swept.
    #
    #    tdata2 gets complementary patterns so every bit is driven both ways.
    #    tdata1 alternates between "all live WARL fields set" and "cleared":
    #      A = 0x600100DF  size=1 match=1 m=1 s=1 u=1 execute=1 store=1 load=1
    #      B = 0x60020000  size=2, every other live field 0
    #    dmode and action stay 0 (the hart cannot set dmode; action=1 needs it).
    #    The tdata2 values are addresses nothing fetches or touches, so an armed
    #    trigger cannot fire during the sweep. Each slot is disarmed on the way out.
    #
    #    Layout: 0x48 = implemented count, then 4 words per slot from 0x4C.
    #=================================================================
    li   t0, 0xFFFFFFFF
    csrw 0x7a0, t0
    csrr t2, 0x7a0            # t2 = highest legal index = NR-1
    addi t3, t2, 1
    sw   t3, 0x48(s1)         # publish NR for the testbench

    li   t4, 1                # slot index; slot 0 is dmode-locked
g_loop:
    blt  t2, t4, g_done
    csrw 0x7a0, t4            # tselect = idx

    addi t5, t4, -1
    slli t5, t5, 4            # (idx-1) * 16 bytes
    add  t5, t5, s1

    li   t0, 0xAAAAAAAA
    csrw 0x7a2, t0
    csrr t1, 0x7a2
    sw   t1, 0x4C(t5)

    li   t0, 0x600100DF
    csrw 0x7a1, t0
    csrr t1, 0x7a1
    sw   t1, 0x50(t5)

    li   t0, 0x55555555       # complement: drives every tdata2 bit the other way
    csrw 0x7a2, t0
    csrr t1, 0x7a2
    sw   t1, 0x54(t5)

    li   t0, 0x60020000
    csrw 0x7a1, t0
    csrr t1, 0x7a1
    sw   t1, 0x58(t5)

    csrw 0x7a1, zero          # disarm before moving on
    addi t4, t4, 1
    j    g_loop
g_done:

    li   x31, 0xdeadbeef      # final sync: test done

end_of_test:
    nop
    j    end_of_test
