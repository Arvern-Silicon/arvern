#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ifault_err_straddle
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IFAULT EXCEPTION (ERROR RESPONSE STRADDLES BRANCH DISPATCH, E-1b)
#   REQUIRES the "err_word" testbench extension (see doc/verification_guide.md §6, "err_word hook"):
#   the .v arms word X = 0x8000E004 with a DETERMINISTIC pre-error wait-state
#   count (err_word_ws), so the 2-cycle AHB ERROR response can be placed
#   exactly on every alignment around a taken branch's detect/confirm cycles
#   (random wait states almost never align it).
#
#   Shape: X is the SEQUENTIAL SUCCESSOR of a TAKEN branch. The fetch unit
#   issues the sequential prefetch of X while the branch at X-4 is being
#   detected/confirmed; the branch redirect ABANDONS that prefetch, whose
#   delayed ERROR response then lands 0..7(+2) cycles later -- straddling
#   the detect cycle, the confirm cycle, or arriving well after both,
#   depending on the round's err_word_ws.
#
#   CORRECT behavior (fixed arv_fetch.v), EVERY round: the abandoned-
#   prefetch fault is DISCARDED -- no trap, execution continues at the
#   branch target (landing counter increments). trap_count stays 0.
#
#   BUGGY-LEGACY SIGNATURE this locks out: for the wait-state alignments
#   where the 2-cycle ERROR straddled the branch-detect/confirm cycles, the
#   abandoned fault was latched and reported as a SPURIOUS instruction
#   access fault after the (valid) redirect -- trap_count != 0 with a
#   phantom MCAUSE=1 signature (mepc at X or at the valid branch target).
#
#   Template at RUN_BASE = 0x8000E000 (built once, runtime copy):
#     +0x00  beq x0, x0, +16      ALWAYS taken -> +0x10
#     +0x04  X: lui s7, 0xBAD04   armed error word (abandoned prefetch);
#                                 poison if it ever executes
#     +0x08  lui s8, 0xBAD08      poison pad (over-prefetch guard)
#     +0x0C  jr t2                escape if flow somehow continues
#     +0x10  addi s10, s10, 1     branch target: landing counter
#     +0x14  jr t2                back to the round loop
#
#   8 rounds: round i re-runs the identical pattern with err_word_ws = i
#   (re-armed by the .v at each x31 = 0x51000001+i sync). Expected final
#   state: trap_count==0, landing counter s10==8, poisons s7/s8==0.
#----------------------------------------------------------------------------

.equ RUN_BASE,  0x8000E000    # template placement (6 words -> 0x8000E014)
.equ ERR_PC,    0x8000E004    # X: abandoned-prefetch error word (armed by .v)

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000):
#   0x00: trap_count         (expect 0 -- THE discriminator)
#   0x04: last MCAUSE        0x08: last MTVAL        0x0C: last MEPC
#   0x10: trap_handled flag  0x14: recovery address
#   0x18: escape marker      (0xBAD if a jr-t2 safety escape ever runs)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER  (ANY trap here is the BUG -- capture and bail out)
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

    # Any synchronous exception here is unexpected (the abandoned-prefetch
    # fault must be discarded). mepc may be un-resumable, so redirect to
    # the recovery label rather than MRET back (avoid re-fault livelock).
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
    # POSITION-INDEPENDENT TEMPLATE (copied to RUN_BASE = 0x8000E000)
    #
    # .option norvc: force 32-bit encodings for EVERY template word so
    # the block is exactly 6*4 bytes in BOTH std and comp builds; the
    # address math (X at +0x04, target at +0x10) assumes 4-byte words.
    # The beq encodes a PC-relative +16, invariant under relocation.
    #=================================================================
    .align 2
    .option push
    .option norvc
str_tmpl:
    beq  x0, x0, str_tgt          # +0x00: ALWAYS taken -> +0x10; the
                                  #        sequential prefetch of +0x04 is
                                  #        issued then ABANDONED
    lui  s7, 0xBAD04              # +0x04: X -- armed error word; poison if
                                  #        it ever executes
    lui  s8, 0xBAD08              # +0x08: poison pad
    jr   t2                       # +0x0C: escape if flow continues
str_tgt:
    addi s10, s10, 1              # +0x10: landing counter (expect 8)
    jr   t2                       # +0x14: back to the round loop
str_tmpl_end:
    .option pop

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80008000           # stack well below the run region
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)

    # Install handler, enable MIE
    la   t0, trap_handler
    csrw mtvec, t0
    li   t0, 0x8
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0

    # Recovery target if a (bug) trap fires
    la   t0, e1b_fail
    sw   t0, 0x14(s1)

    # Preservation + poison registers + landing counter
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s7, 0                    # poison: X executed          (x23)
    li   s8, 0                    # poison: X+4 pad executed    (x24)
    li   s10, 0                   # landing counter             (x26)

    li   x31, 0x11111111

    #=================================================================
    # Copy the 6-word template to RUN_BASE (0x8000E000..0x8000E014).
    # Copy happens BEFORE arming (first arm is at the round-0 sync), and
    # the err_word hook matches READS only, so the stores below can
    # never trip it either way.
    #=================================================================
    la   t0, str_tmpl
    la   t1, str_tmpl_end
    li   t4, RUN_BASE
copy_t:
    lw   t3, 0(t0)
    sw   t3, 0(t4)
    addi t0, t0, 4
    addi t4, t4, 4
    bne  t0, t1, copy_t
    lw   t3, -4(t4)               # read-back (0x8000E014 != X): stores drained

    #=================================================================
    # 8 ROUNDS: round i (i = 0..7) syncs x31 = 0x51000001+i; the .v
    # re-arms err_word_ws = i, then the firmware re-enters the block.
    # The taken branch abandons the prefetch of X; the delayed ERROR
    # lands on a different detect/confirm alignment each round and must
    # be DISCARDED every time.
    #=================================================================
    li   s11, 0x51000000          # sync value, pre-increment per round
    li   s9,  0x51000008          # final round's sync value

e1b_loop:
    addi s11, s11, 1
    addi x31, s11, 0              # sync: .v arms err_word_ws = round index
    la   t2, e1b_ret              # return target for the template's jr t2
    li   t0, RUN_BASE
    jalr x0, t0, 0                # enter block: taken branch past X

e1b_ret:
    bne  s11, s9, e1b_loop        # next round until 0x51000008 done

    j    e1b_finish

    .align 2
e1b_fail:
    # Reached ONLY via the trap handler (spurious trap = the bug) --
    # trap_count / archived MCAUSE / MEPC / MTVAL already hold the
    # signature. Bail out to the sentinel so the run always terminates.
    li   t0, 0xBAD
    sw   t0, 0x18(s1)
    j    e1b_finish

    #=================================================================
    # CONVERGENT SENTINEL -- lift the discriminators into registers:
    #   t3 (x28) = trap_count   (0 correct / >0 buggy-legacy)
    #   t4 (x29) = MCAUSE       (0 correct / 1 buggy-legacy)
    #   t5 (x30) = MEPC         (0 correct)
    #   t2 (x7)  = MTVAL        (0 correct)
    #=================================================================
e1b_finish:
    lw   t3, 0x00(s1)             # trap_count (also drains stores)
    lw   t4, 0x04(s1)             # archived MCAUSE
    lw   t5, 0x0C(s1)             # archived MEPC
    lw   t2, 0x08(s1)             # archived MTVAL
    li   x31, 0xDEADBEEF
end_of_test:
    j    end_of_test
