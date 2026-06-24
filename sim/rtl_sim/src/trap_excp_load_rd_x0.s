#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_load_rd_x0
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: LOAD with rd=x0 MUST still raise its exception.
#   Per RISC-V Unpriv ISA: using x0 as the destination of a load does NOT
#   suppress address-translation/access-check side-effects. An exception
#   that would normally fire MUST still fire.
#
#   If the LSU gated exception emission on rd!=0, then `lw x0, 0(rs1)` would
#   become a side-effect-free address-probe primitive. This test proves no
#   such gate exists by:
#   Phase A: lw x0, 0(x11) where x11 = unmapped addr -> cause 5 (LAF)
#   Phase B: lw x0, 0(x11) where x11 = misaligned    -> cause 4 (LAM)
#   The trap handler counts each entry. We then check the counters match the
#   number of faulting loads issued.
#----------------------------------------------------------------------------

.equ FAULT_ADDR,     0xA0000000        /* unmapped */
.equ MISALIGN_ADDR,  0x80000001        /* SRAM_X base + 1 (lw must be 4B aligned) */

.section .text
.global main
main:
    li   sp, 0x80010000

    /* Handler counts each cause-5 (LAF) and each cause-4 (LAM) entry */
    la   t0, h_count
    csrw mtvec, t0

    /* Pre-clear sentinels */
    li   x10, 0                       /* LAF counter */
    li   x9,  0                       /* LAM counter */
    li   x8,  0xCAFEBABE              /* Will be observed if x0 ever got written (it must not) */

    li   x31, 0xFFFFFFFF

    /* ===================================================================== */
    /* PHASE A: lw x0, 0(fault_addr) MUST trap with cause 5                  */
    /* ===================================================================== */
    li   x11, FAULT_ADDR
    lw   x0,  0(x11)                  /* MUST trap; rd=x0 must not suppress fault */
    /* Drain & sync: poll the LAF counter -- lw x0 has no writeback
     * dependency, so the pipeline doesn't stall waiting for the AHB error
     * response. Without the poll, `li x31` (and the TB check that
     * follows) can race ahead of the trap delivery under heavy ROM/SRAM
     * wait states (-gahb -rwsrom -rwsram -rsalu). The poll also acts as
     * the fence the trap handler's stores need. */
    fence rw, rw
phase_a_wait:
    beqz x10, phase_a_wait
    li   x31, 0x11111111              /* TB: check x10 == 1 (one LAF taken) */

    /* ===================================================================== */
    /* PHASE B: lw x0, 0(misaligned_addr) MUST trap with cause 4             */
    /* ===================================================================== */
    li   x11, MISALIGN_ADDR
    lw   x0,  0(x11)                  /* MUST trap; rd=x0 must not suppress misalign */
    /* LAM is detected synchronously in EX (no AHB transfer), so the trap
     * fires before subsequent instructions retire -- but poll for symmetry
     * with Phase A and to make the test robust to future LSU changes. */
    fence rw, rw
phase_b_wait:
    beqz x9, phase_b_wait
    li   x31, 0x22222222              /* TB: check x9 == 1 (one LAM taken) */

    /* ===================================================================== */
    /* PHASE C: also check non-x0 fault path is unchanged (control vector)   */
    /* ===================================================================== */
    li   x11, FAULT_ADDR
    lw   x13, 0(x11)                  /* MUST trap; rd=x13 */
    /* lw x13 stalls the pipeline waiting for the load result, so the AHB
     * response (here an error -> LAF) is delivered before subsequent
     * instructions retire. Poll anyway for symmetry. */
    fence rw, rw
    li   t3, 2
phase_c_wait:
    bne  x10, t3, phase_c_wait
    li   x31, 0x33333333              /* TB: check x10 == 2 (two LAFs total) */

    /* ===================================================================== */
    /* End                                                                   */
    /* ===================================================================== */
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j end_of_test


/*===========================================================================*/
/* Trap handler: counts cause-5 (LAF) and cause-4 (LAM) entries.             */
/* Advances mepc past the faulting lw (4 bytes).                             */
/*===========================================================================*/

.align 2
h_count:
    addi sp, sp, -16
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)

    csrr t0, mcause
    li   t1, 5
    beq  t0, t1, count_laf
    li   t1, 4
    beq  t0, t1, count_lam
    /* Unexpected cause: leave a marker in x7 so TB can see we got something else */
    li   x7, 0xBADCA05E
    j    h_done

count_laf:
    addi x10, x10, 1                  /* increment LAF counter */
    j    h_done

count_lam:
    addi x9,  x9,  1                  /* increment LAM counter */
    j    h_done

h_done:
    csrr t0, mepc
    addi t0, t0, 4                    /* skip the faulting lw */
    csrw mepc, t0

    lw   t2, 8(sp)
    lw   t1, 4(sp)
    lw   t0, 0(sp)
    addi sp, sp, 16
    mret
