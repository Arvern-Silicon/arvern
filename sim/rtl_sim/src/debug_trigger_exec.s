#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_exec
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sdtrig EXECUTE (instruction-address) trigger FIRING (Debug 1.0)
#   This is a FIRING test for type=6 (mcontrol6) execute triggers. An execute
#   trigger fires JUST BEFORE the matching instruction executes -- the matching
#   instruction does NOT retire. Every phase proves this by a "side effect did
#   NOT happen" assertion: the target instruction writes a known value into a
#   GPR; at fire-time that GPR must still hold its PRE value.
#
#   mcontrol6 (type=6) tdata1 bit layout used here:
#     [31:28]=type(6) [27]=dmode [15:12]=action [10:7]=match [6]=m
#     [4]=s [3]=u [2]=execute [1]=store [0]=load
#   Trigger CSRs: tselect 0x7a0, tdata1 0x7a1, tdata2 0x7a2, tcontrol 0x7a5.
#   tcontrol.mte (bit3) gates M-mode triggers -> set =1 so M-mode execute
#   triggers can fire; on M-trap-entry hardware auto-clears mte (the crux of E).
#
#   PHASES (single trigger, re-armed each phase; trigger index 0):
#     A  action=1 (ENTER DEBUG), match=0 (equal). Armed by the DEBUGGER while
#        halted (action=1 requires dmode=1 -> debugger-only). Firmware pre-loads
#        tdata2=&trig_tgt_A and x6=&trig_tgt_A. On fire: hart auto-enters Debug,
#        dcsr.cause=2, dpc=&trig_tgt_A, x5 still PRE (0xBEEF0000). The .v then
#        disarms + resumes; trig_tgt_A then executes (x5=0xAA -> scratch 0x40).
#     B  action=0 (BREAKPOINT), match=0 (equal). Hart-side. Fires -> mcause=3,
#        mepc=&trig_tgt_B, mtval=0; handler captures x7==PRE (side effect not
#        taken), counts exactly 1 trap, disarms, mret -> instr then executes.
#     C  action=0 (BREAKPOINT), match=1 (NAPOT, 8-byte range). tdata2=base|0x3.
#        We JUMP into the range at base+4 so the fire address (mepc) != the
#        nominal base -- discriminates NAPOT from an equal match (which would
#        require PC==base|0x3, an unaligned address that never occurs).
#     D  PRIV-GATING negative: m=0 (u=1) execute trigger must NOT fire in
#        M-mode -> the target executes, side effect DID happen (x29=0x66), no trap.
#     E  mte non-re-fire: an action=0 M-mode execute trigger whose NAPOT range
#        covers ALL code fires once at e_after; on M-trap-entry mte auto-clears,
#        so the handler's own (in-range) instructions do NOT re-fire. Handler
#        runs EXACTLY ONCE (counter==1). A core that fails to clear mte re-fires
#        inside the handler -> nested trap storm -> hang/timeout (FAIL).
#     F  NEGATIVE control: an enabled but execute=0 (load-match) trigger must
#        NOT fire on an instruction FETCH -> target executes (x30=0x77), no trap.
#
#   Scratchpad (byte offsets from SRAM base 0x80000000):
#     0x00 B mcause(3)   0x04 B mepc      0x08 B mtval(0)  0x0C B x7@fire(PREB)
#     0x10 B counter(1)  0x14 &trig_tgt_B
#     0x18 C mcause(3)   0x1C C mepc      0x20 C x28@fire(PREC) 0x24 &c_tgt
#     0x28 C counter(1)
#     0x2C D x29 final(0x66)  0x30 unexpected-trap counter (D&F, expect 0)
#     0x34 E counter(1)
#     0x38 F x30 final(0x77)
#     0x40 A x5 final(0xAA)
#
#   Registers:
#     s1 (x9)  SRAM scratchpad base       sp (x2) trap-handler stack
#     x5  A target (PRE 0xBEEF0000)        x6  &trig_tgt_A (read by .v in Debug)
#     x7  B target (PRE 0xB7B70000)        x28 C target (PRE 0xCCCC0000)
#     x29 D target (PRE 0xDDDD0000)        x30 F target (PRE 0xFFFF0000)
#     x31 sync (11111111=A armed/spinning, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #---------------------------------------------------------------
    # Phase B M-mode breakpoint handler (mcause=3 from execute trigger).
    # Captures cause/epc/tval + target reg (must be PRE), counts the
    # trap, disarms trigger 0, returns (mepc unchanged -> instr now runs).
    #---------------------------------------------------------------
    .align 2
handler_B:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    csrr t0, mcause
    sw   t0, 0x00(s1)          # expect 3 (breakpoint)
    csrr t0, mepc
    sw   t0, 0x04(s1)          # expect &trig_tgt_B (== 0x14 slot)
    csrr t0, mtval
    sw   t0, 0x08(s1)          # expect 0
    sw   x7, 0x0C(s1)          # target reg AT FIRE -> must be PREB (not 0xCC)
    lw   t0, 0x10(s1)
    addi t0, t0, 1
    sw   t0, 0x10(s1)          # B trap counter (must end == 1)
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # disarm trigger 0
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #---------------------------------------------------------------
    # Phase C M-mode breakpoint handler (NAPOT match).
    #---------------------------------------------------------------
    .align 2
handler_C:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    csrr t0, mcause
    sw   t0, 0x18(s1)          # expect 3
    csrr t0, mepc
    sw   t0, 0x1C(s1)          # expect &c_tgt (== 0x24 slot, = base+4)
    sw   x28, 0x20(s1)         # target reg AT FIRE -> must be PREC (not 0x55)
    lw   t0, 0x28(s1)
    addi t0, t0, 1
    sw   t0, 0x28(s1)          # C trap counter (must end == 1)
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0             # disarm
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #---------------------------------------------------------------
    # Phase E handler: mte non-re-fire. DISARM FIRST so a (correct)
    # single entry leaves the trigger off; count exactly one entry.
    # Does NOT advance mepc -> returns to e_after which then runs.
    #---------------------------------------------------------------
    .align 2
handler_E:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0             # disarm trigger 0 (break any re-fire loop)
    lw   t0, 0x34(s1)
    addi t0, t0, 1
    sw   t0, 0x34(s1)          # E counter (must end == 1)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #---------------------------------------------------------------
    # Shared UNEXPECTED-trap handler for phases D and F. A trigger that
    # WRONGLY fires lands here; bump 0x30 (must end 0), disarm, and skip
    # the offending 32-bit instruction so the test still terminates.
    #---------------------------------------------------------------
    .align 2
handler_unexpected:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    lw   t0, 0x30(s1)
    addi t0, t0, 1
    sw   t0, 0x30(s1)          # unexpected-trap counter (must end == 0)
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0             # disarm to avoid an infinite re-trap
    csrr t0, mepc
    addi t0, t0, 4             # skip offending (32-bit) instruction
    csrw mepc, t0
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


_start:
    csrsi 0x744, 8            # Smdbltrp: a trap in M-mode with NMIE=0 is an unexpected trap
    csrw mstatush, x0        # MDT resets to 1; clear it or the first trap is an Smdbltrp double trap
    li   sp, 0x8000F000        # trap-handler stack
    li   s1, 0x80000000        # SRAM scratchpad base

    # Clear the counter slots the handlers accumulate into.
    li   t0, 0
    sw   t0, 0x10(s1)          # B counter
    sw   t0, 0x28(s1)          # C counter
    sw   t0, 0x30(s1)          # D/F unexpected counter
    sw   t0, 0x34(s1)          # E counter

    # tcontrol.mte = 1 : enable M-mode triggers (else execute triggers never
    # fire in M-mode). Auto-cleared by hardware on each M-trap entry (phase E).
    li   t0, 0x08
    csrw 0x7a5, t0


    #=================================================================
    # PHASE A : action=1 (ENTER DEBUG), match=0 (equal).
    #   Firmware only pre-loads tdata2 + a copy of the target address;
    #   the DEBUGGER (the .v) arms tdata1 (action=1, dmode=1) while halted.
    #=================================================================
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # tdata1 = 0 (disabled until debugger arms it)
    la   t1, trig_tgt_A
    csrw 0x7a2, t1             # tdata2 = &trig_tgt_A (equal-match target)
    mv   x6, t1                # x6 = &trig_tgt_A (debugger reads it, compares dpc)
    li   x5, 0xBEEF0000        # PREA sentinel (side effect target reg)

    li   x31, 0x11111111       # sync: A pre-loaded; spin so debugger can arm A

    li   a0, 0
    li   a1, 0x00001000
spinA:
    addi a0, a0, 1
    blt  a0, a1, spinA
    # fall through to trig_tgt_A. With the debugger-armed action=1 trigger,
    # the hart AUTO-ENTERS Debug Mode here BEFORE the addi executes.
    .align 2
trig_tgt_A:
    addi x5, x0, 0xAA          # A side effect (runs only after debugger disarms)
    sw   x5, 0x40(s1)          # A x5 final (expect 0xAA -> eventually executed)


    #=================================================================
    # PHASE B : action=0 (BREAKPOINT), match=0 (equal). Hart-side.
    #=================================================================
    la   t0, handler_B
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # disable while configuring
    la   t1, trig_tgt_B
    csrw 0x7a2, t1             # tdata2 = &trig_tgt_B
    sw   t1, 0x14(s1)          # store target addr for .v mepc compare
    li   x7, 0xB7B70000        # PREB sentinel
    li   t0, 0x60000044        # type6 | m | execute | match=0 | action=0
    csrw 0x7a1, t0             # ENABLE -> live
    # Arming latency: a software-written (csrw) trigger does NOT affect the
    # immediately-following instruction -- the csrw must retire (update tdata1)
    # before the target reaches the id_pc boundary. A few instructions of slack
    # (the debugger-armed Phase A and the j-into-range Phases C/E get this for
    # free). Without it the enable lands one cycle after id_pc==&trig_tgt_B.
    nop
    nop
    nop
    nop
    .align 2
trig_tgt_B:
    addi x7, x0, 0xCC          # B side effect; fires BEFORE this executes
    nop                        # (handler disarms + mret -> the addi runs now)


    #=================================================================
    # PHASE C : action=0 (BREAKPOINT), match=1 (NAPOT, 8-byte range).
    #   tdata2 = base | 0x3  => range [base, base+7]. Jump in at base+4 so
    #   the fire address differs from base (discriminates NAPOT vs equal).
    #=================================================================
    la   t0, handler_C
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0
    la   t1, c_blk
    ori  t1, t1, 0x3           # NAPOT 8-byte (2 trailing ones)
    csrw 0x7a2, t1
    la   t1, c_tgt
    sw   t1, 0x24(s1)          # store &c_tgt (= base+4) for .v mepc compare
    li   x28, 0xCCCC0000       # PREC sentinel
    li   t0, 0x600000C4        # type6 | m | execute | match=1 (NAPOT) | action=0
    csrw 0x7a1, t0             # ENABLE
    j    c_tgt                 # enter the NAPOT range at base+4 (skip base+0)
    .align 3
c_blk:
    add  x0, x0, x0            # base+0 : 4-byte filler (jumped over, never run)
c_tgt:
    addi x28, x0, 0x55         # base+4 : fires here (in range, mepc != base)
    nop                        # (handler disarms + mret -> the addi runs now)


    #=================================================================
    # PHASE D : PRIV-GATING negative. m=0 (u=1) execute trigger must NOT
    #   fire in M-mode -> the target MUST execute (side effect happens).
    #=================================================================
    la   t0, handler_unexpected
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0
    la   t1, trig_tgt_D
    csrw 0x7a2, t1
    li   x29, 0xDDDD0000       # PRED sentinel
    li   t0, 0x6000000C        # type6 | u | execute (m=0) | match=0 | action=0
    csrw 0x7a1, t0             # ENABLE (but m=0 -> no M-mode fire)
    .align 2
trig_tgt_D:
    addi x29, x0, 0x66         # MUST execute (no fire) -> x29 = 0x66
    sw   x29, 0x2C(s1)         # D x29 final (expect 0x66)
    csrw 0x7a1, x0             # disarm


    #=================================================================
    # PHASE E : mte non-re-fire. NAPOT range covers ALL code. The trigger
    #   fires once at e_after; on M-trap entry mte auto-clears so the
    #   handler's own (in-range) instructions do NOT re-fire.
    #=================================================================
    la   t0, handler_E
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0
    la   t1, e_after
    li   t2, 0xFFFF0000
    and  t1, t1, t2            # 64KB-block base of the code region
    li   t2, 0x00007FFF        # NAPOT 64KB mask (15 trailing ones), built in a reg --
    or   t1, t1, t2            #   ori's 12-bit imm cannot hold 0x7FFF; covers all code
    csrw 0x7a2, t1
    li   t0, 0x600000C4        # type6 | m | execute | match=1 (NAPOT) | action=0
    csrw 0x7a1, t0             # ENABLE -> the NEXT fetched instr (e_after) fires
e_after:
    nop                        # fires here; handler runs EXACTLY once (mte cleared)
    csrw 0x7a1, x0             # belt-and-braces: ensure disabled


    #=================================================================
    # PHASE F : NEGATIVE control. Enabled but execute=0 (load-match)
    #   trigger must NOT fire on an instruction FETCH -> target executes.
    #=================================================================
    la   t0, handler_unexpected
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0
    la   t1, trig_tgt_F
    csrw 0x7a2, t1
    li   x30, 0xFFFF0000       # PREF sentinel
    li   t0, 0x60000041        # type6 | m | load (execute=0) -> no fetch match
    csrw 0x7a1, t0             # ENABLE (load trigger)
    .align 2
trig_tgt_F:
    addi x30, x0, 0x77         # MUST execute (no fire) -> x30 = 0x77
    sw   x30, 0x38(s1)         # F x30 final (expect 0x77)
    csrw 0x7a1, x0             # disarm


    li   x31, 0xdeadbeef       # final sync: test done

end_of_test:
    nop
    j    end_of_test
