#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ifault_isolated_word
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IFAULT EXCEPTION (ISOLATED ERRORING WORD, E-2)
#   REQUIRES the "err_word" testbench extension (see doc/verification_guide.md §6, "err_word hook"):
#   the .v arms a SINGLE bus-erroring instruction word X = 0x8000F004 INSIDE
#   valid SRAM_X, whose successor X+4 is VALID -- unreachable with the
#   region-based TB error model (past SRAM_X, X+4 always errors too).
#
#   Shape: a conditional branch at X-4 is resolved NOT-TAKEN (t5 != 0), so
#   the core speculatively takes it (fetching the valid target at X+12),
#   then CANCELS and resumes the fall-through INTO X. The sequential
#   prefetch of X may already have received (or be receiving) its AHB error
#   when the speculative take/cancel happens. The fixed arv_fetch.v
#   freeze-clear-on-confirmed policy must HOLD the pending fault across the
#   cancelled speculation and report it precisely:
#       mcause = 1, mepc = mtval = X = 0x8000F004, exactly ONE trap/round.
#
#   BUGGY-LEGACY SIGNATURE this test locks out: the cancelled speculation
#   dropped the pending fault and the fetch stream slipped one word --
#   ZERO traps and X+4's instruction DATA silently executed at PC=X. The
#   word at X+4 is therefore a POISON instruction (lui s7, 0xBAD04): on the
#   legacy core s7 becomes 0xBAD04000 and trap_count stays 0.
#
#   Three rounds re-run the identical pattern while the .v re-arms the
#   deterministic pre-error wait-state count err_word_ws = {0, 1, 3},
#   moving the 2-cycle ERROR response across different alignments of the
#   speculate/cancel window.
#
#   Template at RUN_BASE = 0x8000F000 (built once, runtime copy):
#     +0x00  beq x0, t5, +16      NOT taken (t5=1); speculatively taken
#                                 to +0x10, then cancelled
#     +0x04  X: lui s8, 0xBAD08   fetch of this word ERRORS (TB hook);
#                                 content must never execute
#     +0x08  X+4: lui s7, 0xBAD04 THE POISON -- must never execute
#     +0x0C  jr t2                escape if flow somehow continues
#     +0x10  lui s9, 0xBAD09      wrong-path (speculative) target poison:
#                                 must never ARCHITECTURALLY execute
#     +0x14  jr t2                escape
#
#   Expected on fixed RTL, per round r in {0,1,2} (ws = 0,1,3):
#     one trap: mcause=1, mepc=mtval=0x8000F004; handler redirects to the
#     round's recovery label; s7/s8/s9 stay 0; escape marker stays 0.
#   Final: trap_count==3, rounds_done==3, all three archived signatures
#   identical and exact.
#----------------------------------------------------------------------------

.equ RUN_BASE,  0x8000F000    # template placement (6 words -> 0x8000F014)
.equ ERR_PC,    0x8000F004    # X: the isolated erroring word (armed by the .v)

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000):
#   0x00: trap_count
#   0x04: last MCAUSE        0x08: last MTVAL        0x0C: last MEPC
#   0x10: trap_handled flag  0x14: recovery address
#   0x18: escape marker      (0xBAD if the jr-t2 escape ever runs)
#   0x1C: rounds_done        (expect 3)
#   Round archives:  r0: 0x50/0x54/0x58   r1: 0x60/0x64/0x68
#                    r2: 0x70/0x74/0x78   (MCAUSE / MEPC / MTVAL)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER  (each round expects exactly ONE IAF trap here)
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

    # Synchronous exception: the expected IAF's mepc (=X) cannot be
    # resumed (it would re-fault), so always redirect to the recovery
    # label installed by the current round.
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
    # POSITION-INDEPENDENT TEMPLATE (copied to RUN_BASE = 0x8000F000)
    #
    # .option norvc: force 32-bit encodings for EVERY template word so
    # the block is exactly 6*4 bytes in BOTH std and comp builds; the
    # address math (X at +0x04, poison at +0x08, spec target at +0x10)
    # assumes 4-byte words. The beq encodes a PC-relative +16 which is
    # invariant under relocation.
    #=================================================================
    .align 2
    .option push
    .option norvc
iso_tmpl:
    beq  x0, t5, iso_spec         # +0x00: NOT taken (t5=1); spec take/cancel
    lui  s8, 0xBAD08              # +0x04: X -- fetch ERRORS; content is a
                                  #        poison in case the error is lost
                                  #        AND its data is executed
    lui  s7, 0xBAD04              # +0x08: X+4 -- THE isolated-word poison
    jr   t2                       # +0x0C: escape if flow continues
iso_spec:
    lui  s9, 0xBAD09              # +0x10: wrong-path target poison
    jr   t2                       # +0x14: escape
iso_tmpl_end:
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
    sw   t0, 0x1C(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)
    sw   t0, 0x58(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x64(s1)
    sw   t0, 0x68(s1)
    sw   t0, 0x70(s1)
    sw   t0, 0x74(s1)
    sw   t0, 0x78(s1)

    # Install handler, enable MIE
    la   t0, trap_handler
    csrw mtvec, t0
    li   t0, 0x8
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrsi 0x744, 8            # Smdbltrp: a trap in M-mode with NMIE=0 is an unexpected trap
    csrw mstatush, x0

    csrs mstatus, t0

    # Preservation + poison registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s7, 0                    # poison: X+4 executed        (x23)
    li   s8, 0                    # poison: X executed normally (x24)
    li   s9, 0                    # poison: spec target executed(x25)

    # t5 != 0  =>  `beq x0, t5, iso_spec` is NOT taken (fall-through into X)
    li   t5, 0x1

    # t2 = escape target for the template's `jr t2` safety nets
    la   t2, escape_land

    li   x31, 0x11111111

    #=================================================================
    # Copy the 6-word template to RUN_BASE (0x8000F000..0x8000F014).
    # Copy happens BEFORE arming (the .v arms at the per-round syncs),
    # and the err_word hook matches READS only, so the stores below can
    # never trip it either way.
    #=================================================================
    la   t0, iso_tmpl
    la   t1, iso_tmpl_end
    li   t4, RUN_BASE
copy_t:
    lw   t3, 0(t0)
    sw   t3, 0(t4)
    addi t0, t0, 4
    addi t4, t4, 4
    bne  t0, t1, copy_t
    lw   t3, -4(t4)               # read-back (0x8000F014 != X): stores drained

    #=================================================================
    # ROUND 0: err_word_ws = 0  (minimum 2-cycle ERROR)
    #=================================================================
    la   t0, recovery_r0
    sw   t0, 0x14(s1)
    lw   t0, 0x14(s1)             # drain before sync

    li   x31, 0x52000001          # .v arms: addr=ERR_PC, ws=0, en=1

    li   t0, RUN_BASE
    jalr x0, t0, 0                # branch (not taken) -> falls into X -> IAF

recovery_r0:
    lw   t0, 0x04(s1)
    sw   t0, 0x50(s1)             # r0 MCAUSE (expect 1)
    lw   t0, 0x0C(s1)
    sw   t0, 0x54(s1)             # r0 MEPC   (expect 0x8000F004)
    lw   t0, 0x08(s1)
    sw   t0, 0x58(s1)             # r0 MTVAL  (expect 0x8000F004)
    lw   t0, 0x1C(s1)
    addi t0, t0, 1
    sw   t0, 0x1C(s1)             # rounds_done = 1

    #=================================================================
    # ROUND 1: err_word_ws = 1  (one OKAY wait cycle before the ERROR)
    #=================================================================
    la   t0, recovery_r1
    sw   t0, 0x14(s1)
    lw   t0, 0x14(s1)

    li   x31, 0x52000002          # .v re-arms: ws=1

    li   t0, RUN_BASE
    jalr x0, t0, 0

recovery_r1:
    lw   t0, 0x04(s1)
    sw   t0, 0x60(s1)             # r1 MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x64(s1)             # r1 MEPC
    lw   t0, 0x08(s1)
    sw   t0, 0x68(s1)             # r1 MTVAL
    lw   t0, 0x1C(s1)
    addi t0, t0, 1
    sw   t0, 0x1C(s1)             # rounds_done = 2

    #=================================================================
    # ROUND 2: err_word_ws = 3  (three OKAY wait cycles before the ERROR)
    #=================================================================
    la   t0, recovery_r2
    sw   t0, 0x14(s1)
    lw   t0, 0x14(s1)

    li   x31, 0x52000003          # .v re-arms: ws=3

    li   t0, RUN_BASE
    jalr x0, t0, 0

recovery_r2:
    lw   t0, 0x04(s1)
    sw   t0, 0x70(s1)             # r2 MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x74(s1)             # r2 MEPC
    lw   t0, 0x08(s1)
    sw   t0, 0x78(s1)             # r2 MTVAL
    lw   t0, 0x1C(s1)
    addi t0, t0, 1
    sw   t0, 0x1C(s1)             # rounds_done = 3
    j    finish

    .align 2
escape_land:
    # Reached ONLY via a template `jr t2` safety net, i.e. execution
    # continued past X without trapping (the legacy-bug flavour where the
    # fault is dropped but the stream stays aligned). Marker must stay 0.
    li   t0, 0xBAD
    sw   t0, 0x18(s1)
    j    finish

    #=================================================================
    # CONVERGENT SENTINEL -- lift the discriminators into registers:
    #   t3 (x28) = trap_count   (3 correct / 0 buggy-legacy)
    #   t4 (x29) = r0 MCAUSE    (1 correct)
    #   t5 (x30) = r0 MEPC      (0x8000F004 correct)
    #   t2 (x7)  = r0 MTVAL     (0x8000F004 correct)
    #   s7 (x23) = X+4 poison   (0 correct / 0xBAD04000 buggy-legacy)
    #=================================================================
finish:
    lw   t3, 0x00(s1)             # trap_count (also drains stores)
    lw   t4, 0x50(s1)             # r0 MCAUSE
    lw   t5, 0x54(s1)             # r0 MEPC
    lw   t2, 0x58(s1)             # r0 MTVAL
    li   x31, 0xDEADBEEF
end_of_test:
    j    end_of_test
