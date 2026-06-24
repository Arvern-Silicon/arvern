#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ifault_seq
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IFAULT EXCEPTION (SEQUENTIAL)
#   Instruction access fault triggered by a SEQUENTIAL fall-off past the end
#   of mapped, executable SRAM (SRAM_X: 0x80000000..0x8000FFFF, 64 KiB; the
#   gap up to SRAM_NX at 0x81000000 is unmapped, like the JALR target in
#   trap_excp_ifault).
#
#   The faulting fetch is NOT a JAL/JALR redirect: a JALR only *lands* into a
#   stream of valid, non-branch instructions (4-byte NOPs) that the test
#   writes into SRAM_X at runtime, whose last word sits exactly at
#   0x8000FFFC.  The processor then increments the PC SEQUENTIALLY off the
#   end of SRAM_X into 0x80010000 (unmapped -> AHB error response) -> the
#   faulting fetch is the SEQUENTIAL one, not the JALR.
#
#   (A JALR is used to *land* because SRAM_X at 0x8xxxxxxx is outside JAL's
#   +/-1 MiB reach from ROM at 0x2xxxxxxx; the JALR is only the landing, the
#   fault-triggering fetch is the SEQUENTIAL fall-off past 0x8000FFFC.)
#
#   Spec: for an instruction-access-fault (mcause=1) MEPC and MTVAL must both
#   equal the EXACT PC of the instruction whose fetch faulted.  Here that PC
#   is 0x80010000 (first word past the last valid instruction).  An off-by-
#   one-word (non-C, 0x8000FFFC) or off-by-one-parcel (C-mode, 0x8000FFFE)
#   skew makes the MEPC/MTVAL checks fail with a visible PC mismatch.
#
#   Two phases exercise both fetch-buffer states at the faulting cycle:
#   Phase A: buffer empty   - JALR lands 1 instr before the boundary, so
#   the decoder is directly waiting on the faulting fetch.
#   Phase B: buffer non-empty- JALR lands >=16 instrs before the boundary;
#   the speculative prefetch of 0x80010000 errors while a buffered
#   pre-fault instruction is still being drained.  This is where a
#   PC skew manifests.  Empirically the primary trigger is -rsalu
#   (random ALU stalls): the ALU-stall backpressure lets the fetch
#   buffer fill ahead, producing the buffer-non-empty state at the
#   faulting cycle.  -rwsram alone does NOT trigger it.
#
#   Both phases fault at the SAME address (0x80010000): there is exactly one
#   SRAM_X fall-off boundary.  The discriminator between phases is the buffer
#   state, not the address; distinct x31 sentinels & recovery labels keep
#   them separable.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000) -- low addresses only; the
# boundary-tail NOPs live near the SRAM_X top (0x8000FFBC..0x8000FFFC).
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MTVAL
#   0x0C: last MEPC
#   0x10: trap_handled flag
#   0x14: recovery address (set before triggering IF exception)
#
# Phase A (sequential fall-off, buffer EMPTY at fault):
#   0x20: MCAUSE             (expect 1)
#   0x24: MEPC               (expect 0x80010000)
#   0x28: MTVAL              (expect 0x80010000)
#
# Phase B (sequential fall-off, buffer NON-EMPTY at fault):
#   0x30: MCAUSE             (expect 1)
#   0x34: MEPC               (expect 0x80010000)
#   0x38: MTVAL              (expect 0x80010000)
#=========================================================================

.equ NOP_ENC,       0x00000013    # 4-byte ADDI x0,x0,0 (bits[1:0]=11 -> always
                                  # a whole 32-bit instr, never a C parcel)
.equ SRAMX_TOP,     0x8000FFFC    # last valid instruction (Phase A tail)
.equ SRAMX_RUN,     0x8000FFBC    # Phase B 17-NOP run start (17*4 -> 0x8000FFFC)
.equ FAULT_PC,      0x80010000    # first word past SRAM_X (unmapped)

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

    # Save to working area
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    sw   t1, 0x0C(s1)

    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)

    # Check if interrupt (MSB = 1)
    bltz t0, handle_interrupt

    # Instruction-fetch exceptions (cause 0 or 1): MEPC points at an
    # invalid/unmapped address, so we cannot read the instruction there.
    # Redirect to a known-good recovery label set up by the test code.
    beqz t0, use_recovery_addr     # cause 0: inst addr misaligned
    li   t3, 1
    beq  t0, t3, use_recovery_addr # cause 1: inst access fault

    # For other exceptions: advance MEPC past faulting instruction
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
    lw   t1, 0x14(s1)             # load recovery address from scratchpad

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
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80008000          # stack well below the boundary-tail region
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
    # PHASE 1: Install trap handler, init regs, build the SRAM_X tail
    #=================================================================

    la   t0, trap_handler
    csrw mtvec, t0

    # Enable MSTATUS.MIE
    li   t0, 0x8
    csrs mstatus, t0

    # Initialize callee-saved registers (preservation check)
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    #-----------------------------------------------------------------
    # Build the 17-NOP boundary run in SRAM_X:
    #   0x8000FFBC .. 0x8000FFFC  (17 words; last word = Phase A tail)
    # Each word is a whole 4-byte NOP (0x00000013) so no instruction
    # straddles the 0x80010000 boundary (keeps this purely sequential).
    #-----------------------------------------------------------------
    li   t0, NOP_ENC
    li   t1, SRAMX_RUN           # 0x8000FFBC
    li   t2, FAULT_PC            # 0x80010000 (loop end, exclusive)
build_tail:
    sw   t0, 0(t1)
    addi t1, t1, 4
    bne  t1, t2, build_tail

    # No fence.i: this core has no instruction cache and the stores
    # complete (drain over AHB) before the JALR below, so the fetch
    # path sees the just-written SRAM_X words. Avoiding fence.i keeps
    # the test assembling under march variants without zifencei.

    li   x31, 0x11111111


    #=================================================================
    # PHASE A: Sequential fall-off, fetch buffer EMPTY at fault.
    #
    # JALR lands at 0x8000FFFC (exactly ONE valid instruction before
    # the SRAM_X boundary).  The decoder is directly waiting on the
    # faulting sequential fetch of 0x80010000.
    #=================================================================

    # Store recovery address (handler returns here after the fault)
    la   t0, recovery_pA
    sw   t0, 0x14(s1)

    # Land on the single tail NOP via register-indirect jump.
    li   t0, SRAMX_TOP           # 0x8000FFFC
    jalr x0, t0, 0

recovery_pA:
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)            # MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x24(s1)            # MEPC
    lw   t0, 0x08(s1)
    sw   t0, 0x28(s1)            # MTVAL (last slot the .v reads)
    lw   t1, 0x28(s1)            # load-back: stalls until the (possibly
                                 # wait-stated) MTVAL store has committed,
                                 # so the x31 sentinel below is only set
                                 # AFTER all three slots are visible to
                                 # the testbench (no all-PASS-but-MTVAL=0
                                 # sentinel race under -rwsram).

    li   x31, 0x22222222


    #=================================================================
    # PHASE B: Sequential fall-off, fetch buffer NON-EMPTY at fault.
    #
    # JALR lands at 0x8000FFBC, the start of the 16-NOP pre-fault run
    # (then the final tail NOP at 0x8000FFFC).  The speculative prefetch
    # of 0x80010000 errors while a buffered pre-fault instruction is
    # still being drained.  Empirically -rsalu (ALU-stall backpressure
    # fills the fetch buffer ahead) is the primary trigger for the skew.
    #=================================================================

    # Store recovery address
    la   t0, recovery_pB
    sw   t0, 0x14(s1)

    # Land at the start of the long pre-fault run.
    li   t0, SRAMX_RUN           # 0x8000FFBC
    jalr x0, t0, 0

recovery_pB:
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)            # MCAUSE
    lw   t0, 0x0C(s1)
    sw   t0, 0x34(s1)            # MEPC
    lw   t0, 0x08(s1)
    sw   t0, 0x38(s1)            # MTVAL (last slot the .v reads)
    lw   t1, 0x38(s1)            # load-back: same wait-state sentinel
                                 # race guard as recovery_pA above.

    li   x31, 0x33333333

    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
