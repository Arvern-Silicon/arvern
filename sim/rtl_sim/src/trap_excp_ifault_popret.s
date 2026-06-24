#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ifault_popret
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IFAULT EXCEPTION (UOP-FINAL BRANCH / CM.POPRET)
#   Companion to trap_excp_ifault_mispred. There, a CONDITIONAL branch is
#   speculatively taken then CANCELLED upstream of a sequential IAF, and the
#   fault MUST still be reported (it is on the real fall-through path).
#
#   Here the upstream redirect is a CM.POPRET (a UOP-final branch that is
#   ALWAYS CONFIRMED, never cancelled). The faulting fetch is on the
#   ABANDONED sequential-prefetch path PAST the popret -- the popret redirects
#   away to a VALID return target, so the abandoned-path fault MUST be
#   DISCARDED. A correct core delivers NO trap.
#
#   The bug this guards against (was: spec_compliance_notes "Spurious IAF at
#   UOP-final branch target"): the abandoned-path AHB error registers as
#   dph_error one cycle AFTER the popret's branch-detect clears
#   fetch_fault_freeze, re-arming the freeze, so the deferred-IAF release
#   condition can fire at the popret's (valid) return target -> a SPURIOUS
#   inst-access-fault (mcause=1) at a perfectly mapped address.
#
#   SRAM_X = 0x80000000 .. 0x8000FFFF (64 KiB, executable).
#   0x80010000 = first address PAST SRAM_X -> unmapped -> AHB error.
#
#   Layout near the boundary (built at runtime into SRAM_X):
#     0x8000FFFC: C.NOP                 (0x0001)
#     0x8000FFFE: CM.POPRET {ra}, 16    (2-byte Zcmp; pops ra, returns)
#     0x80010000: <unmapped>            (the abandoned sequential prefetch)
#   The popret's popped ra points to a VALID landing label (popret_land).
#
#   DISCRIMINATOR: trap_count MUST be 0. The popret returns cleanly to
#   popret_land; no architectural fault exists on that path. A non-zero
#   trap_count (with mcause=1 at a mapped mepc) is the spurious-IAF bug.
#
#   Reachability: like the mispred Phase B, hitting the exact
#   detect-vs-dph_error same-cycle window needs fetch/AHB alignment; the
#   timing matrix (-rwsrom / -rsalu / -gahb) shifts the speculative prefetch
#   of 0x80010000 into the popret-confirm cycle. Base variant is the
#   deterministic anchor.
#----------------------------------------------------------------------------

.equ SRAMX_TOP_W,   0x8000FFFC    # last valid SRAM_X word (holds C.NOP + popret)
.equ NOPRET_WORD,   0xBE420001    # LE: [FFFC]=0x0001 C.NOP ;
                                  #     [FFFE]=0xBE42 = CM.POPRET {ra}, 16
.equ FAULT_PC,      0x80010000    # first word past SRAM_X (unmapped)

.section .text
.global main

main:
    j _start

    #=================================================================
    # TRAP HANDLER  (any trap here is the BUG -- capture and recover)
    #=================================================================
    .align 2

trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mtval

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Save cause / mtval / mepc
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    sw   t1, 0x0C(s1)

    li   t4, 1
    sw   t4, 0x10(s1)

    # Interrupt? (MSB set) -> handle separately
    bltz t0, handle_interrupt

    # Any synchronous exception here is unexpected. For inst-fetch faults
    # (cause 0/1) mepc may be unmapped, so always redirect to the recovery
    # label rather than MRET (avoid re-faulting / livelock).
    lw   t1, 0x14(s1)
    csrw mepc, t1
    j    handler_done

handle_interrupt:
    andi t3, t0, 0x1F
    li   t4, 7
    beq  t3, t4, disable_mtie
    j    handler_done
disable_mtie:
    li   t4, 0x80
    csrc mie, t4

handler_done:
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
    mret

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80004000           # stack well below the boundary region
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)

    # Install handler, enable MIE
    la   t0, trap_handler
    csrw mtvec, t0
    li   t0, 0x8
    csrs mstatus, t0

    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC

    li   x31, 0x11111111

    #=================================================================
    # Build the boundary word: C.NOP @ 0x8000FFFC, CM.POPRET @ 0x8000FFFE
    #=================================================================
    li   t0, NOPRET_WORD          # 0xBE020001
    li   t1, SRAMX_TOP_W          # 0x8000FFFC
    sw   t0, 0(t1)
    lw   t2, 0(t1)                # drain the store before the jump

    # Recovery target if a (bug) trap fires
    la   t0, recovery
    sw   t0, 0x14(s1)

    # Set up the popret stack frame. CM.POPRET {ra}, 16 with current SP:
    #   loads ra <- [SP + 12], then SP += 16, then jumps to ra.
    # Point the popped ra at popret_land (the VALID return target).
    la   t0, popret_land
    sw   t0, 12(sp)               # ra slot for cm.popret {ra},16

    # Land directly on the C.NOP at 0x8000FFFC. The C.NOP retires, then
    # CM.POPRET @ 0x8000FFFE executes (pops ra -> popret_land, redirects),
    # while the sequential prefetch of 0x80010000 (abandoned) faults.
    li   t0, SRAMX_TOP_W          # 0x8000FFFC
    jalr x0, t0, 0

    # Fall-through here only if the popret did NOT redirect (unexpected).
    li   t0, 0xBAD
    sw   t0, 0x18(s1)             # fall-through marker
    j    finish

    .align 2
popret_land:
    # The popret returned here. A correct core takes NO trap on this
    # (valid, mapped) path -> trap_count stays 0.
    li   t0, 1
    sw   t0, 0x1C(s1)             # landed marker
    j    finish

recovery:
    # Reached only if a (spurious) trap fired. Archive the captured trap
    # context so the .v can report exactly what happened.
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)             # MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x24(s1)             # MEPC
    lw   t0, 0x08(s1)
    sw   t0, 0x28(s1)             # MTVAL
    j    finish

    #=================================================================
    # CONVERGENT SENTINEL -- both paths terminate here so the run always
    # completes; trap_count (SPAD 0x00) is the discriminator.
    #=================================================================
finish:
    lw   t1, 0x28(s1)             # drain stores before the sentinel
    li   x31, 0xDEADBEEF
end_of_test:
    j    end_of_test
