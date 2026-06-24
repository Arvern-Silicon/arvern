#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ifault_mispred
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IFAULT EXCEPTION (MISPREDICT)
#   Instruction access fault reached via the SEQUENTIAL fall-off past SRAM_X
#   (0x8000FFFC last valid word, 0x80010000 first unmapped word), but with a
#   CONDITIONAL BRANCH that is resolved NOT-TAKEN sitting just upstream of
#   the faulting fetch.
#
#   Why this shape: arvern's single-cycle branch SPECULATIVELY TAKES a
#   detected conditional branch (id_branch_detect_o redirect) and then
#   CANCELS it (branch_cancelled) when the resolved condition was not-taken.
#   That speculative detect clears fetch_fault_freeze in arv_fetch.v. The
#   question this test answers: when a real instruction-access-fault is
#   pending on the fall-through path, can the speculative-take/cancel of the
#   upstream branch DROP that fault (fetch_fault_freeze cleared, never re-
#   armed)? Spec says the fault MUST still be reported precisely. A dropped
#   fault shows up as a missing/!=1 MCAUSE, a skewed/zero MEPC/MTVAL, a wrong
#   trap_count, or (if it livelocks) the harness watchdog firing.
#
#   The architectural truth is branch-direction-independent: the branch is
#   NOT taken (t5 != 0 for `beq x0,t5`), so execution falls through the NOP
#   run sequentially into 0x80010000 -> AHB error -> mcause=1, and MEPC and
#   MTVAL must BOTH equal exactly 0x80010000. The branch target is a valid
#   mapped SRAM_X word (so a speculatively-taken fetch does not itself fault,
#   isolating the cancel->fall-through->fault path).
#
#   The branch is built position-independently: a template block (branch +
#   NOPs) is assembled in .text (the assembler encodes the PC-relative B-imm)
#   and copied verbatim into SRAM_X, so the encoded offset stays correct at
#   the SRAM_X placement.
#
#   Phase A: branch placed near the boundary (buffer ~empty at the fault) --
#   the cancel and the faulting speculative prefetch are tightly
#   coupled.
#   Phase B: branch placed earlier with a long NOP run after it; under the
#   -rsalu variant the fetch buffer fills ahead so the speculative
#   prefetch of 0x80010000 errors while the cancelled branch is
#   still in flight (the same-cycle detect-vs-dph_error window).
#----------------------------------------------------------------------------

.equ NOP_ENC,       0x00000013    # 4-byte ADDI x0,x0,0 (bits[1:0]=11 -> 32-bit)
.equ SRAMX_TOP,     0x8000FFFC    # last valid instruction word
.equ FAULT_PC,      0x80010000    # first word past SRAM_X (unmapped)
.equ SRAMX_RUN,     0x8000FFB0    # Phase B run start (19 words -> 0x8000FFFC)
.equ SRAMX_RUN_A,   0x8000FFF0    # Phase A run start (4 words -> 0x8000FFFC)

.section .text
.global main

main:
    j _start

    #=================================================================
    # TRAP HANDLER
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

    # Save cause / mtval / mepc to working area
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    sw   t1, 0x0C(s1)

    li   t4, 1
    sw   t4, 0x10(s1)

    # Interrupt? (MSB set) -> handle separately
    bltz t0, handle_interrupt

    # Instruction-fetch exceptions (cause 0 or 1): MEPC is unmapped,
    # so redirect to a test-provided recovery label.
    beqz t0, use_recovery_addr     # cause 0: inst addr misaligned
    li   t3, 1
    beq  t0, t3, use_recovery_addr # cause 1: inst access fault

    # Other exceptions: advance MEPC past the faulting instruction
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, advance_4
    addi t1, t1, 2
    j    exc_done
advance_4:
    addi t1, t1, 4
    j    exc_done

use_recovery_addr:
    lw   t1, 0x14(s1)              # recovery address from scratchpad

exc_done:
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
    # POSITION-INDEPENDENT BRANCH TEMPLATE (copied into SRAM_X)
    #
    #   mispred_tmpl:   beq x0, t5, mt_skip   # NOT taken (t5 != 0);
    #                                         # speculatively taken then
    #                                         # cancelled by the core
    #                   nop                   # <- architectural fall-through
    #   mt_skip:        nop                   # speculative-taken landing
    #                                         #   (valid mapped word)
    #
    # The beq encodes the PC-relative offset (mt_skip - beq), which is
    # invariant under relocation, so copying the words verbatim into
    # SRAM_X keeps the branch correct at its SRAM_X address.
    #
    # .option norvc: force 32-bit encodings for EVERY template word so
    # the block is exactly 3*4 bytes in BOTH std and comp builds. The
    # SRAM_X address math (.equ run starts, the word copy loop, the
    # 0x8000FFFC last-word / 0x80010000 fault PC) all assume 4-byte
    # words; without this the comp build would compress the nops to 2
    # bytes and shift the whole layout.
    #=================================================================
    .align 2
    .option push
    .option norvc
mispred_tmpl:
    beq  x0, t5, mt_skip
    nop
mt_skip:
    nop
mispred_tmpl_end:
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
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)

    #=================================================================
    # PHASE 1: handler install, reg init
    #=================================================================
    la   t0, trap_handler
    csrw mtvec, t0

    li   t0, 0x8                   # MSTATUS.MIE
    csrs mstatus, t0

    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # t5 != 0  =>  `beq x0, t5, mt_skip`  is NOT taken (fall-through).
    li   t5, 0x1

    li   x31, 0x11111111

    #=================================================================
    # PHASE A: branch near the boundary (buffer ~empty at fault).
    #
    # SRAM_X layout from 0x8000FFF0 (4 words):
    #   0x8000FFF0  beq x0,t5,mt_skip   (not taken)
    #   0x8000FFF4  nop                  (fall-through)
    #   0x8000FFF8  nop                  (mt_skip target - valid)
    #   0x8000FFFC  nop                  (last valid word)
    #   0x80010000  <unmapped>           -> instruction access fault
    #=================================================================
    la   t0, recovery_pA
    sw   t0, 0x14(s1)

    # Copy the 3-word template to 0x8000FFF0, then 1 trailing NOP @0x8000FFFC
    la   t0, mispred_tmpl
    la   t1, mispred_tmpl_end
    li   t2, SRAMX_RUN_A           # 0x8000FFF0
copy_a:
    lw   t3, 0(t0)
    sw   t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    bne  t0, t1, copy_a
    li   t3, NOP_ENC               # trailing NOP at 0x8000FFFC
    li   t4, SRAMX_TOP
    sw   t3, 0(t4)
    lw   t3, 0(t4)                 # read-back: stores drained before fetch

    li   t0, SRAMX_RUN_A           # land on the branch
    jalr x0, t0, 0

recovery_pA:
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)              # MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x24(s1)              # MEPC
    lw   t0, 0x08(s1)
    sw   t0, 0x28(s1)              # MTVAL (last slot the .v reads)
    lw   t1, 0x28(s1)              # load-back: sentinel only after stores commit

    li   x31, 0x22222222

    #=================================================================
    # PHASE B: branch earlier, long NOP run after it (buffer non-empty
    # under -rsalu). SRAM_X from 0x8000FFB0 (19 words):
    #   0x8000FFB0  beq x0,t5,mt_skip   (not taken)
    #   0x8000FFB4  nop                  (fall-through)
    #   0x8000FFB8  nop                  (mt_skip - valid)
    #   0x8000FFBC..0x8000FFFC  NOP run (17 words)
    #   0x80010000  <unmapped>           -> instruction access fault
    #=================================================================
    la   t0, recovery_pB
    sw   t0, 0x14(s1)

    la   t0, mispred_tmpl
    la   t1, mispred_tmpl_end
    li   t2, SRAMX_RUN             # 0x8000FFB0
copy_b:
    lw   t3, 0(t0)
    sw   t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    bne  t0, t1, copy_b

    # Fill NOPs from end-of-template (0x8000FFBC) up to FAULT_PC
    li   t3, NOP_ENC
    li   t4, FAULT_PC              # exclusive loop end
fill_b:
    sw   t3, 0(t2)
    addi t2, t2, 4
    bne  t2, t4, fill_b
    lw   t3, -4(t4)                # read-back last word: stores committed

    li   t0, SRAMX_RUN             # land on the branch
    jalr x0, t0, 0

recovery_pB:
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)              # MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x34(s1)              # MEPC
    lw   t0, 0x08(s1)
    sw   t0, 0x38(s1)              # MTVAL (last slot the .v reads)
    lw   t1, 0x38(s1)              # load-back sentinel race guard

    li   x31, 0x33333333

    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
