#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ifault_wrongpath_tgt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IFAULT EXCEPTION (WRONG-PATH BRANCH TARGET)
#   Companion to trap_excp_ifault_mispred / trap_excp_ifault_popret. In the
#   mispred test, the not-taken branch's TARGET is a valid mapped word and
#   the fault lives on the real fall-through path (fault MUST be reported).
#   Here the roles are inverted: the conditional branch is NOT taken, and
#   its TARGET is the first UNMAPPED word past SRAM_X. The core
#   speculatively takes the detected branch and fetches the target; that
#   wrong-path fetch gets an AHB error; the branch is then resolved
#   not-taken and cancelled. The wrong-path fault MUST be DISCARDED -- the
#   architectural path (the fall-through) is perfectly valid. A correct
#   core delivers NO trap and continues down the fall-through.
#
#   The bug this reproduces (verified to fail deterministically on the BASE
#   variant): the wrong-path AHB error is latched and NOT cleaned up by the
#   branch cancel, so a SPURIOUS instruction-access-fault (mcause=1) is
#   reported at the valid fall-through PC: mepc = mtval = 0x8000FFF4.
#
#   SRAM_X = 0x80000000 .. 0x8000FFFF (64 KiB, executable).
#   0x80010000 = first address PAST SRAM_X -> unmapped -> AHB error.
#
#   Layout at the TOP of SRAM_X (built at runtime by copying the template):
#     0x8000FFF0: beq x0, t5, +16     (target 0x80010000 = unmapped;
#                                      t5 preset to 1 -> NOT taken)
#     0x8000FFF4: jr t2               (fall-through escape; t2 preset to
#                                      escape_land, a valid landing pad)
#     0x8000FFF8: nop
#     0x8000FFFC: nop                 (last valid word)
#     0x80010000: <unmapped>          (the wrong-path speculative fetch)
#
#   DISCRIMINATOR: trap_count MUST be 0. The branch falls through, jr t2
#   escapes to escape_land, and no architectural fault exists on that path.
#   trap_count=1 with mcause=1 and mepc=mtval=0x8000FFF4 (a mapped, valid
#   PC) is the wrong-path-target spurious-IAF bug.
#----------------------------------------------------------------------------

.equ SRAMX_RUN,     0x8000FFF0    # template placement (4 words -> 0x8000FFFC)
.equ SRAMX_TOP,     0x8000FFFC    # last valid instruction word
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
    # mepc may even be unmapped, so always redirect to the recovery label
    # rather than MRET back (avoid re-faulting / livelock).
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
    # POSITION-INDEPENDENT TEMPLATE (copied to the top of SRAM_X)
    #
    #   wrongpath_tmpl:  beq x0, t5, wp_tgt  # +16; NOT taken (t5 != 0);
    #                                        # speculatively taken then
    #                                        # cancelled by the core
    #                    jr  t2              # fall-through escape to
    #                                        # escape_land (valid pad)
    #                    nop
    #                    nop                 # pads out to SRAM_X top
    #   wp_tgt:                              # tmpl+16; after the copy to
    #                                        # 0x8000FFF0 this is exactly
    #                                        # 0x80010000 = first UNMAPPED
    #
    # The beq encodes the PC-relative offset (wp_tgt - beq) = +16, which
    # is invariant under relocation, so copying the words verbatim into
    # SRAM_X points the target at the first unmapped word.
    #
    # .option norvc: force 32-bit encodings for EVERY template word so
    # the block is exactly 4*4 bytes in BOTH std and comp builds. The
    # SRAM_X address math (0x8000FFF0 run start, 0x8000FFFC last word,
    # 0x80010000 wrong-path target) all assume 4-byte words.
    #=================================================================
    .align 2
    .option push
    .option norvc
wrongpath_tmpl:
    beq  x0, t5, wp_tgt
    jr   t2
    nop
    nop
wp_tgt:
wrongpath_tmpl_end:
    .option pop

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80008000           # stack well below the boundary region
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x1C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)

    # Install handler, enable MIE
    la   t0, trap_handler
    csrw mtvec, t0
    li   t0, 0x8
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0

    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC

    # t5 != 0  =>  `beq x0, t5, wp_tgt`  is NOT taken (fall-through).
    li   t5, 0x1

    # t2 = fall-through escape target for the `jr t2` in the template.
    la   t2, escape_land

    # Recovery target if a (bug) trap fires
    la   t0, recovery
    sw   t0, 0x14(s1)

    li   x31, 0x11111111

    #=================================================================
    # Copy the 4-word template to 0x8000FFF0 .. 0x8000FFFC:
    #   0x8000FFF0  beq x0,t5,+16   (target 0x80010000 -- unmapped)
    #   0x8000FFF4  jr  t2          (fall-through escape)
    #   0x8000FFF8  nop
    #   0x8000FFFC  nop             (last valid word)
    #=================================================================
    la   t0, wrongpath_tmpl
    la   t1, wrongpath_tmpl_end
    li   t4, SRAMX_RUN             # 0x8000FFF0
copy_t:
    lw   t3, 0(t0)
    sw   t3, 0(t4)
    addi t0, t0, 4
    addi t4, t4, 4
    bne  t0, t1, copy_t
    lw   t3, -4(t4)                # read-back: stores drained before fetch

    li   t0, SRAMX_RUN             # land on the branch
    jalr x0, t0, 0

    # Fall-through here only if the jalr did NOT redirect (unexpected).
    li   t0, 0xBAD
    sw   t0, 0x18(s1)             # fall-through marker
    j    finish

    .align 2
escape_land:
    # The `jr t2` fall-through escape landed here. A correct core takes
    # NO trap on this path -> trap_count stays 0.
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
    # completes; trap_count (SPAD 0x00) is the discriminator. The trap
    # signature is also lifted into registers so a failure is visible
    # directly in the check_cpu_reg report:
    #   t3 (x28) = trap_count   (0 correct / 1 buggy)
    #   t4 (x29) = MCAUSE       (0 correct / 0x00000001 buggy)
    #   t5 (x30) = MEPC         (0 correct / 0x8000FFF4 buggy)
    #   t2 (x7)  = MTVAL        (0 correct / 0x8000FFF4 buggy)
    #=================================================================
finish:
    lw   t3, 0x00(s1)             # trap_count (also drains stores)
    lw   t4, 0x20(s1)             # archived MCAUSE
    lw   t5, 0x24(s1)             # archived MEPC
    lw   t2, 0x28(s1)             # archived MTVAL
    li   x31, 0xDEADBEEF
end_of_test:
    j    end_of_test
