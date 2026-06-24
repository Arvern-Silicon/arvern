#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_lfault_pipelined
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: pipelined next-transfer leak past a load access fault.
#   When T1 = load to a fault-triggering address is followed immediately by
#   T2 = load or store with ≥1 AHB wait state, T2's address phase is issued
#   on the bus BEFORE the trap-kill signal stops it.
#
#   Two leak vectors:
#   Vector A (T2 = load): T2's loaded value writes to the destination
#   register post-trap (regfile clobbered).
#   Vector B (T2 = store): T2's store reaches the slave and writes memory
#   (slave-visible side-effect).
#
#   Test method per vector:
#   - Pre-initialise the destination (x10 / scratch memory) with SENTINEL.
#   - Sequence T1 then T2 with no instruction between.
#   - Trap handler skips BOTH T1 and T2 (advances mepc by 8) so that if no
#   leak occurs, T2 has no observable effect.
#   - Check the destination: SENTINEL = no leak; T2-value = LEAK (the bug).
#
#   The leak is timing-dependent: it requires at least one wait state on T1's
#   data phase so T2's address phase has time to be issued before kill takes
#   effect. The base variant may not expose it; -rwsram and friends will.
#----------------------------------------------------------------------------

.equ FAULT_ADDR,     0xA0000000        /* unmapped per ahb_decoder.v */
.equ SCRATCH_BASE,   0x80000000        /* SRAM_X */
.equ SCRATCH_A,      0x80000020        /* used in Phase A (load) */
.equ SCRATCH_B,      0x80000024        /* used in Phase B (store) */

.equ SENTINEL_A,     0x12345678        /* x10 pre-value (Phase A) */
.equ SENTINEL_B,     0x55555555        /* scratch[B] pre-value (Phase B) */
.equ SCRATCH_VAL_A,  0xCAFEBABE        /* what's at SCRATCH_A (T2 load target) */
.equ NEW_VAL_B,      0xDEADBEEF        /* T2's store value (Phase B) */

.section .text
.global main
main:
    li   sp, 0x80010000

    /* Trap handler that advances mepc by 8 (skip T1 + T2) */
    la   t0, h_skip2
    csrw mtvec, t0

    /* Enable MIE (not strictly required for sync exceptions, but consistent
       with check_cpu_reg's -rirq gate). */
    csrsi mstatus, 0x8

    /* Initialize SCRATCH_A with SCRATCH_VAL_A (so we can tell if T2 leaked) */
    li   t0, SCRATCH_A
    li   t1, SCRATCH_VAL_A
    sw   t1, 0(t0)

    /* Initialize SCRATCH_B with SENTINEL_B */
    li   t0, SCRATCH_B
    li   t1, SENTINEL_B
    sw   t1, 0(t0)

    /* Make sure stores reach SRAM before the fault test */
    fence rw, rw

    li   x31, 0xFFFFFFFF

    /* ===================================================================== */
    /* PHASE A: T1 = load fault, T2 = load -- check x10 is unclobbered      */
    /* ===================================================================== */

    /* Pre-load x10 (a0) with SENTINEL_A so we can detect a leak. */
    li   x10, SENTINEL_A

    /* Operands set up well in advance so T1 -> T2 are truly back-to-back */
    li   x11, FAULT_ADDR
    li   x12, SCRATCH_A

    /* T1: lw x13, 0(x11)  -- access fault (cause 5)                        */
    /* T2: lw x10, 0(x12)  -- if leak: x10 = 0xCAFEBABE; if clean: untouched */
    lw   x13, 0(x11)
    lw   x10, 0(x12)

    /* If we reach here, the handler skipped both T1 and T2. The destination
       of T2 was x10; observe its value to detect the leak. */
    fence rw, rw                     /* drain any in-flight transfers */
    li   x31, 0x11111111             /* sync -- TB checks x10 */

    /* ===================================================================== */
    /* PHASE B: T1 = load fault, T2 = store -- check SCRATCH_B is unmodified */
    /* ===================================================================== */

    li   x11, FAULT_ADDR
    li   x12, SCRATCH_B
    li   x14, NEW_VAL_B              /* T2's store value */

    /* T1: lw x13, 0(x11)             -- access fault                       */
    /* T2: sw x14, 0(x12)             -- if leak: SCRATCH_B := NEW_VAL_B    */
    lw   x13, 0(x11)
    sw   x14, 0(x12)

    /* Read SCRATCH_B back into x10 for the testbench to check.
       The `add x10, x10, x0` after the lw creates a read-x10 dependency that
       forces the pipeline to drain the lw's writeback into x10 before any
       subsequent instruction (notably the sync sentinel below) retires.
       Under SRAM wait states the lw can be in-flight when the next non-
       dependent instruction (li x31) would otherwise retire ahead of it. */
    fence rw, rw
    lw   x10, 0(x12)
    add  x10, x10, x0
    li   x31, 0x22222222             /* sync -- TB checks x10 */

    /* End of test */
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j end_of_test


/*===========================================================================*/
/* Trap handler -- advances mepc by 8 to skip both T1 and T2.                */
/* The handler is invoked with cause 5 (load-access-fault) on T1.            */
/*===========================================================================*/

.align 2
h_skip2:
    addi sp, sp, -8
    sw   t0, 0(sp)
    sw   t1, 4(sp)

    csrr t0, mepc
    addi t0, t0, 8                   /* skip T1 (4) + T2 (4) */
    csrw mepc, t0

    lw   t1, 4(sp)
    lw   t0, 0(sp)
    addi sp, sp, 8
    mret
