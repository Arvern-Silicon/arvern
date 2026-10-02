#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ldfault_vs_ecall
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: precise-exception ordering -- load access fault vs. ECALL.
#
#   Bug reproducer: an older load that takes an AHB bus error (load access
#   fault, mcause=5) is IMMEDIATELY followed by an ECALL (mcause=11 from
#   M-mode). While the load's data phase is still in flight (bus error
#   responses take 2 cycles; wait states widen the window), a buggy pipeline
#   lets the younger ECALL in decode raise its exception first and SILENTLY
#   DROPS the older load fault.
#
#   CORRECT behavior (precise exceptions, program order):
#     trap #1: mcause=5,  mepc=&lw  -- and the faulting load must NOT write rd
#     trap #2: mcause=11, mepc=&ecall (after handler skips the lw and mrets)
#
#   BUGGY behavior:
#     one single trap: mcause=11, mepc=&ecall -- load fault never reported,
#     load destination silently keeps its stale value.
#
#   The trap handler records each trap's (mcause, mepc) in successive
#   scratchpad slots indexed by trap_count, advances mepc by 4 and mrets.
#   The testbench then checks the count, the per-slot causes and the
#   per-slot mepc values against firmware-recorded expected addresses.
#
#   PHASE A (race):    lw t3, 0(a1) ; ecall           -- back-to-back
#   PHASE B (control): lw t3, 0(a1) ; 4x nop ; ecall  -- spaced far enough
#     that ordering is unambiguous even on buggy RTL (documents that the
#     failure in Phase A is a race-window issue, not a decode issue).
#
#   The 2-cycle AHB error response alone opens the window, so the test is
#   meaningful on the base variant; wait-state variants (-wssram/-rwsram/
#   -rwsper) widen the window further. No wait-state count is assumed by
#   any check.
#----------------------------------------------------------------------------

.equ FAULT_ADDR,   0xA0000000     /* unmapped per ahb_decoder.v -> AHB error */
.equ LD_SENTINEL,  0xBADBAD05     /* pre-value of the load destination (t3) */

#=========================================================================
# SRAM scratchpad layout (base s1 = 0x80000000)
#
#   0x00: trap_count (running; forced to 2 between Phase A and Phase B)
#
#   Trap record slots (slot i at 0x10 + 8*i, i capped to 0..7):
#   0x10: trap0 mcause      0x14: trap0 mepc      (Phase A, 1st trap)
#   0x18: trap1 mcause      0x1C: trap1 mepc      (Phase A, 2nd trap)
#   0x20: trap2 mcause      0x24: trap2 mepc      (Phase B, 1st trap)
#   0x28: trap3 mcause      0x2C: trap3 mepc      (Phase B, 2nd trap)
#
#   Expected mepc values (stored by firmware before triggering):
#   0x60: &seq_a_lw         0x64: &seq_a_ecall
#   0x68: &seq_b_lw         0x6C: &seq_b_ecall
#
#   0x70: Phase A trap_count snapshot (expected 2; buggy RTL -> 1)
#=========================================================================

.section .text
.option norvc                     /* every instruction 4 bytes: handler's
                                     mepc+=4 skip and back-to-back spacing
                                     hold in both plain and -c_mode builds */
.global main

.equ MNSTATUS, 0x744
.equ MNCAUSE,  0x742

main:
    j    _start

    #=================================================================
    # TRAP HANDLER
    #   - interrupts (mcause<0): ignored, mret to same mepc (defensive;
    #     the test must run with random IRQ injection disabled)
    #   - exceptions: record (mcause, mepc) in slot[trap_count],
    #     trap_count++, mepc += 4, mret
    #=================================================================
    .align 2
nmi_handler:
    li   s1, 0x80000000
    lw   t0, 0x7C(s1)
    addi t0, t0, 1
    sw   t0, 0x7C(s1)
    csrr t0, MNCAUSE
    sw   t0, 0x80(s1)
    lw   zero, 0x80(s1)
    .word 0x70200073

    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  0(sp)
    sw   t1,  4(sp)
    sw   t2,  8(sp)
    sw   t4, 12(sp)

    csrr t0, mcause
    bltz t0, handler_iret         /* interrupt: don't record, don't skip */

    csrr t1, mepc

    /* slot address = s1 + 0x10 + 8*(trap_count & 7) */
    lw   t2, 0x00(s1)
    andi t4, t2, 0x7
    slli t4, t4, 3
    addi t4, t4, 0x10
    add  t4, t4, s1
    sw   t0, 0(t4)                /* record mcause */
    sw   t1, 4(t4)                /* record mepc   */

    addi t2, t2, 1
    sw   t2, 0x00(s1)             /* trap_count++ */

    addi t1, t1, 4                /* skip faulting instruction (norvc) */
    csrw mepc, t1

handler_iret:
    lw   t4, 12(sp)
    lw   t2,  8(sp)
    lw   t1,  4(sp)
    lw   t0,  0(sp)
    addi sp, sp, 16
    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    /* Zero the scratchpad (0x00 .. 0x70) */
    mv   t0, s1
    li   t1, 0x80000074
1:  sw   x0, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b

    /* Install trap handler */
    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x78(s1)
    sw   zero, 0x7C(s1)
    sw   zero, 0x80(s1)
    lw   zero, 0x78(s1)

    /* Enable MSTATUS.MIE (consistent with other trap tests; no IRQ source
       is active -- this test must not run under -rirq) */
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrsi mstatus, 0x8

    /* Record expected mepc values for the testbench */
    la   t0, seq_a_lw
    sw   t0, 0x60(s1)
    la   t0, seq_a_ecall
    sw   t0, 0x64(s1)
    la   t0, seq_b_lw
    sw   t0, 0x68(s1)
    la   t0, seq_b_ecall
    sw   t0, 0x6C(s1)

    li   x31, 0xFFFFFFFF          /* sync: init done; tb programs nmi_vector */

    li   t0, 20
wait_vec:
    addi t0, t0, -1
    bnez t0, wait_vec

    csrsi MNSTATUS, 8             /* NMIE=1 -- the bus error must be DELIVERED */

    li   x31, 0xEEEEEEEE          /* sync: NMIE armed */

    #=================================================================
    # PHASE A (race): lw from erroring address IMMEDIATELY followed
    #                 by ecall.
    #   Correct: trap(5, &seq_a_lw) then trap(11, &seq_a_ecall)
    #   Buggy:   single trap(11, &seq_a_ecall), load fault dropped
    #=================================================================

    li   t3, LD_SENTINEL          /* preload load destination */
    li   a1, FAULT_ADDR
    fence rw, rw                  /* drain prior stores: lw/ecall issue
                                     truly back-to-back */
seq_a_lw:
    lw   t3, 0(a1)                /* older: load access fault (mcause=5) */
seq_a_ecall:
    ecall                         /* younger: ecall from M (mcause=11)  */

    /* Both handler returns land here. Preserve t3 for a race-free
       end-of-test register check, snapshot Phase A trap count, then
       force trap_count = 2 so Phase B records always land in slots
       2/3 even on buggy RTL (where Phase A produced only 1 trap). */
    mv   s2, t3                   /* s2 = t3 after Phase A */
    lw   t0, 0x00(s1)
    sw   t0, 0x70(s1)             /* snapshot Phase A count */
    li   t0, 2
    sw   t0, 0x00(s1)
    fence rw, rw
    lw   t0, 0x70(s1)             /* load-back: force store completion */

    li   x31, 0x11111111          /* sync: Phase A records ready */

    #=================================================================
    # PHASE B (control): same fault, but the ecall is spaced 4 nops
    #   after the lw -- ordering unambiguous even on buggy RTL.
    #   Expected (always): trap(5, &seq_b_lw) then trap(11, &seq_b_ecall)
    #=================================================================

    li   t3, LD_SENTINEL          /* preload load destination again */
    li   a1, FAULT_ADDR
    fence rw, rw
seq_b_lw:
    lw   t3, 0(a1)                /* load access fault (mcause=5) */
    nop
    nop
    nop
    nop
seq_b_ecall:
    ecall                         /* ecall (mcause=11) */

    mv   s3, t3                   /* s3 = t3 after Phase B */
    fence rw, rw
    lw   t0, 0x00(s1)             /* load-back: force store completion */

    li   x31, 0x22222222          /* sync: Phase B records ready */

    #=================================================================
    # END OF TEST
    #=================================================================
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
