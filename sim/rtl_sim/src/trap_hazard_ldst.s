#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_hazard_ldst
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP HAZARD LDST
#   Load/store pipeline hazard stress across trap boundaries.
#   Designed to expose forwarding bugs like the hazard_store_rs2 issue.
#
#   Tests patterns that stress the WB→EX forwarding path when traps
#   (ECALL/MRET) flush the pipeline:
#   - CSR read + store using same register right after MRET return
#   - Load + immediate store (same register) across trap boundary
#   - Multiple register reuse patterns with load-use hazards
#   - Store data forwarding after handler restores registers from stack
#   - Interleaved loads/stores with traps under random SRAM wait states
#
#   All tests are synchronous (ECALL/MRET). Random SRAM wait states (-all)
#   are critical for triggering timing-dependent forwarding bugs.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x0C: last MSTATUS
#   0x10: trap_handled flag
#
# Phase 2 (CSR read + store after MRET):
#   0x20: MSTATUS value stored via t0 after MRET
#   0x24: expected MSTATUS value
#
# Phase 3 (load + store same register across trap):
#   0x30: store result using t0 (should be load value, not stale)
#   0x34: store result using t1
#   0x38: store result using t2
#
# Phase 4 (handler stack restore + immediate store):
#   0x40: value stored via a0 right after handler return
#   0x44: value stored via a1 right after handler return
#   0x48: value stored via a2 right after handler return
#
# Phase 5 (interleaved load-store-trap pattern):
#   0x50: accumulated checksum
#   0x54: expected checksum
#
# Test data area:
#   0x80: test word 0 = 0x11111111
#   0x84: test word 1 = 0x22222222
#   0x88: test word 2 = 0x33333333
#   0x8C: test word 3 = 0x44444444
#   0x90: test word 4 = 0x55555555
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    # Save context on stack
    addi sp, sp, -32
    sw   t0, 28(sp)
    sw   t1, 24(sp)
    sw   t2, 20(sp)
    sw   t3, 16(sp)
    sw   t4, 12(sp)
    sw   a0,  8(sp)
    sw   a1,  4(sp)

    # Read trap CSRs
    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mstatus

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Store to working area
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    # Advance MEPC past ECALL (4 bytes)
    addi t1, t1, 4
    csrw mepc, t1

    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)
    lw   t4, 0x10(s1)

    # Restore context from stack
    # NOTE: This restore sequence is critical for testing.
    # After MRET, the restored register values must be visible
    # to the first instruction at the return address.
    # With random SRAM wait states, the stack loads may still
    # have pending WB data phases when MRET fires.
    lw   a1,  4(sp)
    lw   a0,  8(sp)
    lw   t4, 12(sp)
    lw   t3, 16(sp)
    lw   t2, 20(sp)
    lw   t1, 24(sp)
    lw   t0, 28(sp)
    addi sp, sp, 32

    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    # Initialize stack pointer
    li   sp, 0x80010000

    # Initialize scratchpad base pointer
    li   s1, 0x80000000

    # Zero scratchpad area
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x48(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)

    # Initialize test data
    li   t0, 0x11111111
    sw   t0, 0x80(s1)
    li   t0, 0x22222222
    sw   t0, 0x84(s1)
    li   t0, 0x33333333
    sw   t0, 0x88(s1)
    li   t0, 0x44444444
    sw   t0, 0x8C(s1)
    li   t0, 0x55555555
    sw   t0, 0x90(s1)

    #=================================================================
    # PHASE 1: Install trap handler, initialize registers
    #=================================================================

    # Install trap handler (direct mode)
    la   t0, trap_handler
    csrw mtvec, t0

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Signal: Phase 1 init complete
    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: CSR read + store using same register after MRET
    #   This is the exact pattern that triggered the hazard_store_rs2
    #   bug: handler restores t0 from stack (load in WB), then MRET
    #   returns. At return point, csrr writes t0 (new value), then
    #   sw t0 should use the csrr value, not the stale stack load.
    #=================================================================

    # Disable error_on_exception not needed (testbench already set)

    # Pre-load t0 with a known value that the handler will save/restore
    li   t0, 0xBADBAD00

    # ECALL to handler
    ecall

    # After handler returns here:
    # t0 was restored from stack (0xBADBAD00) -- load may still be in WB
    # csrr t0, mstatus overwrites t0 with MSTATUS value
    # sw t0 must use the csrr result, NOT the stale stack load
    csrr t0, mstatus
    sw   t0, 0x20(s1)
    lw   t1, 0x20(s1)

    # Also save expected value directly
    csrr t2, mstatus
    sw   t2, 0x24(s1)
    lw   t3, 0x24(s1)

    # Signal: Phase 2 complete
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Load + store same register across trap boundary
    #   For each of 3 registers, load a value from SRAM, then ECALL.
    #   After MRET return, the register was restored from stack.
    #   Immediately load a new value into the same register, then store.
    #   The store must use the NEW load value, not the old stack value.
    #=================================================================

    # Load known values into t0/t1/t2, then trap
    li   t0, 0xAAAA0001
    li   t1, 0xBBBB0002
    li   t2, 0xCCCC0003

    # ECALL (handler saves t0/t1/t2 to stack, restores on return)
    ecall

    # After MRET: t0/t1/t2 restored from stack (loads may be in WB pipeline)
    # Now load new values into same registers from SRAM data area
    lw   t0, 0x80(s1)           # t0 = 0x11111111
    lw   t1, 0x84(s1)           # t1 = 0x22222222
    lw   t2, 0x88(s1)           # t2 = 0x33333333

    # Store to verification area -- must be NEW values, not stale stack restores
    sw   t0, 0x30(s1)
    sw   t1, 0x34(s1)
    sw   t2, 0x38(s1)
    lw   t3, 0x38(s1)           # load-back fence

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: Handler restore + immediate use after MRET
    #   Load specific values into a0/a1/a2 before ECALL.
    #   Handler saves/restores them from stack.
    #   Right after MRET, store a0/a1/a2 to SRAM.
    #   Values stored must match what was loaded before ECALL.
    #=================================================================

    li   a0, 0xFACE0001
    li   a1, 0xFACE0002
    li   a2, 0xFACE0003

    ecall

    # After MRET: a0/a1/a2 restored from stack
    # Store immediately -- tests that stack load results are correct
    sw   a0, 0x40(s1)
    sw   a1, 0x44(s1)
    sw   a2, 0x48(s1)
    lw   t0, 0x48(s1)           # load-back fence

    # Signal: Phase 4 complete
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: Interleaved load-store-trap pattern
    #   Compute a checksum by loading test data words, adding them,
    #   and trapping between some additions. The final checksum
    #   must be correct despite traps interrupting the computation.
    #   Tests that register state is perfectly preserved across traps.
    #=================================================================

    li   a0, 0               # accumulator

    # Load and add first word
    lw   t0, 0x80(s1)        # 0x11111111
    add  a0, a0, t0

    # Trap in the middle
    ecall

    # Load and add second word
    lw   t0, 0x84(s1)        # 0x22222222
    add  a0, a0, t0

    # Another trap
    ecall

    # Load and add third word
    lw   t0, 0x88(s1)        # 0x33333333
    add  a0, a0, t0

    # Load and add fourth word (no trap between)
    lw   t0, 0x8C(s1)        # 0x44444444
    add  a0, a0, t0

    # Trap again
    ecall

    # Load and add fifth word
    lw   t0, 0x90(s1)        # 0x55555555
    add  a0, a0, t0

    # Store checksum
    sw   a0, 0x50(s1)

    # Compute expected checksum
    # 0x11111111 + 0x22222222 + 0x33333333 + 0x44444444 + 0x55555555
    # = 0xFF...FF55 => need to compute:
    # 0x11111111 + 0x22222222 = 0x33333333
    # + 0x33333333 = 0x66666666
    # + 0x44444444 = 0xAAAAAAAA
    # + 0x55555555 = 0xFFFFFFFF
    li   t0, 0x11111111
    li   t1, 0x22222222
    add  t0, t0, t1
    li   t1, 0x33333333
    add  t0, t0, t1
    li   t1, 0x44444444
    add  t0, t0, t1
    li   t1, 0x55555555
    add  t0, t0, t1
    sw   t0, 0x54(s1)
    lw   t1, 0x54(s1)        # load-back fence

    # Signal: Phase 5 complete
    li   x31, 0x55555555


    # Check callee-saved registers preserved
    # (implicit -- testbench checks)


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
