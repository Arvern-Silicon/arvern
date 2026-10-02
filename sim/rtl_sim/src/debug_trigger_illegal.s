#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_illegal
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sdtrig execute trigger on the PC of an ILLEGAL instruction
#   (Debug 1.0). Per the Debug Spec exception-priority table, an
#   instruction-address breakpoint (mcontrol6 execute trigger) OUTRANKS the
#   illegal-instruction exception: when an enabled execute trigger matches
#   the PC of an illegal instruction, the TRIGGER must win -- breakpoint
#   exception (mcause=3) for action=0, or Debug Mode entry (dcsr.cause=2)
#   for action=1 -- and the illegal-instruction exception (mcause=2) must
#   NOT be raised. The illegal word never "executes" either way.
#
#   The illegal instruction is `.word 0xFFFFFFFF` (all-ones, guaranteed
#   illegal by the ISA spec; bits[1:0]=11 so it occupies 4 bytes). The SAME
#   word address is reached in all three phases.
#
#   mcontrol6 (type=6) tdata1 bit layout used here:
#     [31:28]=type(6) [27]=dmode [15:12]=action [10:7]=match [6]=m
#     [4]=s [3]=u [2]=execute [1]=store [0]=load
#   Trigger CSRs: tselect 0x7a0, tdata1 0x7a1, tdata2 0x7a2, tcontrol 0x7a5.
#   tcontrol.mte (bit3) is set so M-mode action=0 triggers can fire.
#
#   PHASES (trigger index 0):
#     A  action=0 (BREAKPOINT), match=0 (equal), M-mode, armed by csrw with
#        several nops of arming slack (a csrw-armed trigger cannot match the
#        immediately-following instruction). Execution falls into the illegal
#        word -> trigger fires FIRST: mcause=3 (NOT 2), mepc=&illegal_word,
#        mtval=0, exactly 1 trap. handler_A disarms the trigger and mrets to
#        recover_A (a label AFTER the illegal word).
#     B  NEGATIVE control: trigger disabled, jump back to the SAME illegal
#        word -> now the normal illegal-instruction exception wins:
#        mcause=2, mepc=&illegal_word, mtval=0 (core convention, see
#        trap_excp_cross_stage_priority), exactly 1 trap. handler_B mrets
#        to recover_B.
#     C  action=1 (ENTER DEBUG), match=0 (equal), armed by the DEBUGGER
#        while halted (action=1 requires dmode=1 -> debugger-only).
#        Firmware pre-loads tdata2=&illegal_word, stashes &illegal_word in
#        x6 and &recover_C in x7, then spins so the .v can halt + arm.
#        After resume the firmware jumps to the illegal word -> hart
#        AUTO-ENTERS Debug Mode: dcsr.cause=2, dpc=&illegal_word, and NO
#        M-mode trap was taken (unexpected counter stays 0). The .v then
#        disarms, writes dpc=&recover_C (x7) and resumes.
#
#   Scratchpad (byte offsets from SRAM base 0x80000000):
#     0x00 A mcause(3)   0x04 A mepc     0x08 A mtval(0)  0x0C A counter(1)
#     0x10 B mcause(2)   0x14 B mepc     0x18 B mtval(0)  0x1C B counter(1)
#     0x20 &illegal_word (written by main; mepc compare reference)
#     0x24 fellthrough marker (must stay 0: illegal word never executed)
#     0x28 C unexpected-M-trap counter (must stay 0: trigger won, no trap)
#     0x2C C completion marker (0xC0DE0001 written at recover_C)
#
#   Registers:
#     s1 (x9)  SRAM scratchpad base       sp (x2) trap-handler stack
#     x6  &illegal_word (read by .v in Debug Mode, dpc compare)
#     x7  &recover_C    (read by .v in Debug Mode, written into dpc)
#     x20 A mcause (expect 3 -- trigger outranked illegal)
#     x21 B mcause (expect 2 -- illegal wins once trigger disabled)
#     x31 sync (11111111=A done, 22222222=B done, 33333333=C armed/spinning,
#               deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #---------------------------------------------------------------
    # Phase A M-mode handler: the execute trigger must have OUTRANKED
    # the illegal-instruction exception -> mcause=3 (breakpoint).
    # Captures cause/epc/tval, counts the trap, disarms trigger 0,
    # and mrets PAST the illegal word (recover_A).
    #---------------------------------------------------------------
    .align 2
handler_A:
    addi sp, sp, -16
    sw   t0, 12(sp)
    csrr t0, mcause
    sw   t0, 0x00(s1)          # expect 3 (breakpoint) -- NOT 2 (illegal)
    mv   x20, t0               # persistent copy for check_cpu_reg
    csrr t0, mepc
    sw   t0, 0x04(s1)          # expect &illegal_word (== 0x20 slot)
    csrr t0, mtval
    sw   t0, 0x08(s1)          # expect 0
    lw   t0, 0x0C(s1)
    addi t0, t0, 1
    sw   t0, 0x0C(s1)          # A trap counter (must end == 1)
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # disarm trigger 0
    la   t0, recover_A
    csrw mepc, t0              # resume AFTER the illegal word
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #---------------------------------------------------------------
    # Phase B M-mode handler: trigger disabled, so the plain
    # illegal-instruction exception must win -> mcause=2.
    #---------------------------------------------------------------
    .align 2
handler_B:
    addi sp, sp, -16
    sw   t0, 12(sp)
    csrr t0, mcause
    sw   t0, 0x10(s1)          # expect 2 (illegal instruction)
    mv   x21, t0               # persistent copy for check_cpu_reg
    csrr t0, mepc
    sw   t0, 0x14(s1)          # expect &illegal_word (== 0x20 slot)
    csrr t0, mtval
    sw   t0, 0x18(s1)          # expect 0 (core's illegal-instruction convention)
    lw   t0, 0x1C(s1)
    addi t0, t0, 1
    sw   t0, 0x1C(s1)          # B trap counter (must end == 1)
    la   t0, recover_B
    csrw mepc, t0              # resume AFTER the illegal word
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #---------------------------------------------------------------
    # Phase C UNEXPECTED-trap handler: with the debugger-armed action=1
    # trigger the hart must enter Debug Mode, NOT trap to M. Landing
    # here means the illegal-instruction exception wrongly won (or any
    # stray trap): bump the 0x28 counter (must end 0) and redirect to
    # recover_C so the test still terminates. (The dmode=1 trigger
    # cannot be disarmed from M-mode; no revisit of the address occurs.)
    #---------------------------------------------------------------
    .align 2
handler_C_unexpected:
    addi sp, sp, -16
    sw   t0, 12(sp)
    lw   t0, 0x28(s1)
    addi t0, t0, 1
    sw   t0, 0x28(s1)          # unexpected-trap counter (must end == 0)
    la   t0, recover_C
    csrw mepc, t0
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


_start:
    csrsi 0x744, 8            # Smdbltrp: a trap in M-mode with NMIE=0 is an unexpected trap
    csrw mstatush, x0        # MDT resets to 1; clear it or the first trap is an Smdbltrp double trap
    li   sp, 0x8000F000        # trap-handler stack
    li   s1, 0x80000000        # SRAM scratchpad base

    # Clear the slots the handlers accumulate into.
    sw   x0, 0x0C(s1)          # A counter
    sw   x0, 0x1C(s1)          # B counter
    sw   x0, 0x24(s1)          # fellthrough marker
    sw   x0, 0x28(s1)          # C unexpected counter
    sw   x0, 0x2C(s1)          # C completion marker

    # Reference copy of the illegal word address for the .v mepc compares.
    la   t0, illegal_word
    sw   t0, 0x20(s1)

    # Sentinels: a phase whose handler never runs leaves these unchanged
    # and the final check_cpu_reg comparisons fail.
    li   x20, 0xBAD0BAD0
    li   x21, 0xBAD0BAD0

    # tcontrol.mte = 1 : enable M-mode triggers (else action=0 execute
    # triggers never fire in M-mode). Auto-cleared on M-trap entry,
    # restored from mpte by mret.
    li   t0, 0x08
    csrw 0x7a5, t0

    #=================================================================
    # PHASE A : action=0 (BREAKPOINT), equal match on &illegal_word.
    #   The trigger must fire BEFORE the illegal-instruction exception
    #   is raised (instruction-address breakpoint has higher priority).
    #=================================================================
    la   t0, handler_A
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # disable while configuring
    la   t1, illegal_word
    csrw 0x7a2, t1             # tdata2 = &illegal_word
    li   t0, 0x60000044        # type6 | m | execute | match=0 | action=0
    csrw 0x7a1, t0             # ENABLE -> live
    # Arming latency: a csrw-armed trigger does NOT affect the immediately-
    # following instruction -- leave several instructions of slack before
    # the target address (same lesson as debug_trigger_exec phase B).
    nop
    nop
    nop
    nop
    nop
    nop
    # fall through into the illegal word: the armed execute trigger fires
    # here (mcause=3); the illegal-instruction exception must NOT be seen.
    .align 2
illegal_word:
    .word 0xFFFFFFFF           # guaranteed illegal (all-ones, 32-bit encoding)
    # Must NEVER execute nor be fallen through (every phase traps or enters
    # Debug at illegal_word and resumes at a recover_* label further down).
    li   t0, 0xBAD
    sw   t0, 0x24(s1)          # fellthrough marker (must stay 0)

recover_A:
    li   x31, 0x11111111       # sync: phase A complete

    #=================================================================
    # PHASE B : NEGATIVE control. Trigger fully disabled (handler_A
    #   already disarmed it); the SAME illegal word address must now
    #   raise the plain illegal-instruction exception (mcause=2).
    #=================================================================
    la   t0, handler_B
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # belt-and-braces: ensure disarmed
    nop
    nop
    j    illegal_word          # -> illegal-instruction trap to handler_B

recover_B:
    li   x31, 0x22222222       # sync: phase B complete

    #=================================================================
    # PHASE C : action=1 (ENTER DEBUG), equal match on &illegal_word.
    #   Firmware only pre-loads tdata2 + address stashes; the DEBUGGER
    #   (the .v) arms tdata1 (action=1, dmode=1) while halted. On the
    #   jump to illegal_word the hart must AUTO-ENTER Debug Mode
    #   (dcsr.cause=2, dpc=&illegal_word) -- no M-mode trap.
    #=================================================================
    la   t0, handler_C_unexpected
    csrw mtvec, t0             # any M-trap here is a FAIL (counted at 0x28)
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # disabled until the debugger arms it
    la   t1, illegal_word
    csrw 0x7a2, t1             # tdata2 = &illegal_word (equal-match target)
    la   x6, illegal_word      # x6 = &illegal_word (debugger compares dpc)
    la   x7, recover_C         # x7 = &recover_C (debugger writes into dpc)

    li   x31, 0x33333333       # sync: C pre-loaded; spin so debugger can arm

    li   a0, 0
    li   a1, 0x00001000
spinC:
    addi a0, a0, 1
    blt  a0, a1, spinC
    j    illegal_word          # trigger fires -> Debug Mode entry (no M-trap)

recover_C:
    li   t0, 0xC0DE0001
    sw   t0, 0x2C(s1)          # C completion marker

    li   x31, 0xdeadbeef       # final sync: test done

end_of_test:
    nop
    j    end_of_test
