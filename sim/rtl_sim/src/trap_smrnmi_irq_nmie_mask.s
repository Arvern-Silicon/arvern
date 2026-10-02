#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_smrnmi_irq_nmie_mask
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SMRNMI x IRQ (NMIE=0 must mask ALL interrupts)
#   Bug-sensitive reproducer for the Smrnmi global interrupt gate. Ratified
#   Smrnmi: "When NMIE=0, all interrupts are disabled." While the hart
#   executes the RNMI handler (mnstatus.NMIE hardware-cleared to 0 on NMI
#   entry), a standard machine external interrupt -- even with mstatus.MIE=1
#   and mie.MEIE=1 -- must be held pending and taken only AFTER mnret
#   restores NMIE=1. Buggy RTL takes the IRQ inside the RNMI handler,
#   clobbering the resumable NMI state.
#
#   Choreography (2 identical iterations, fully bench-handshaken):
#   - M-mode enables mstatus.MIE + mie.MEIE + mnstatus.NMIE, signals ARM,
#     then runs a long checksum loop (golden = 0x0000DCDC).
#   - Bench pulses NMI mid-loop. RNMI handler sets the global marker s2=1,
#     signals the bench FROM INSIDE the handler (x31=0xA0A0000N), then runs
#     a ~100-iteration delay loop. On the in-handler sync the bench asserts
#     irq_m_external and HOLDS it -- this is the NMIE=0 window.
#   - Handler clears s2 and mnret's. The IRQ stays pending; correct RTL
#     takes it only now (NMIE back to 1), mid-checksum-loop resume.
#   - mtvec handler snapshots the s2 marker (MUST be 0), logs mcause,
#     bumps irq_count, disables mie.MEIE (line is bench-held), mret.
#   - Main code finishes the checksum (proves mnret resumed at the exact
#     interrupted PC: any skipped/replayed instruction diverges), stores it,
#     spin-waits for irq_count, signals DONE; bench drops the IRQ line.
#
#   Discriminators (checked by the bench at the end):
#   - s2 snapshot log MUST be 0 for every IRQ trap. ==1 -> IRQ was taken
#     inside the RNMI handler with NMIE=0 (BUG).
#   - checksum == 0x0000DCDC per iteration (mnret resumability).
#   - irq_count == 2, nmi_count == 2, every logged mcause == 0x8000000B.
#
#   Requires Smrnmi present (Smrnmi). Deterministic IRQ ordering: must be
#   excluded from random-IRQ injection (no_random_irq).
#
#   Scratchpad (base 0x80000000):
#   0x00 irq_count               0x08 nmi_handler addr (bench -> nmi_vector)
#   0x1C mnstatus-in-RNMI        0x20 checksum iter1    0x24 checksum iter2
#   0x28 nmi_count               0x2C mncause-in-RNMI
#   0xA0+(n-1)*4 mcause log      0xC0+(n-1)*4 s2-marker snapshot log
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # MTVEC HANDLER (machine external IRQ expected)
    #   Records mcause and a snapshot of the "inside RNMI handler"
    #   marker (s2) into per-trap log slots, bumps irq_count, then
    #   disables mie.MEIE so the bench-held line does not re-fire.
    #   Preserves every register it touches (it may preempt the
    #   checksum loop or -- on buggy RTL -- the RNMI delay loop).
    #=================================================================
    .align 2
m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)
    sw   t3,  0(sp)

    csrr t0, mcause

    # irq_count++
    lw   t1, 0x00(s1)
    addi t1, t1, 1
    sw   t1, 0x00(s1)

    # Log slots indexed by (irq_count-1)
    addi t2, t1, -1
    slli t2, t2, 2
    add  t2, t2, s1
    sw   t0, 0xA0(t2)          # mcause log
    sw   s2, 0xC0(t2)          # s2 marker snapshot: MUST be 0 (spec) / 1 (bug)

    # Disable mie.MEIE (bit 11): line is held high by the bench
    li   t3, 0x800
    csrc mie, t3

    lw   t3,  0(sp)
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


    #=================================================================
    # RNMI HANDLER (bench drives nmi_vector to this PC)
    #   NMIE=0 by construction for its whole body. Sets the global
    #   marker s2=1, syncs the bench from INSIDE the handler, then
    #   delays ~100 loop iterations while the bench holds
    #   irq_m_external asserted. Spec: the IRQ must NOT be taken in
    #   here. Clears s2 immediately before mnret.
    #   Preserves t0/t1 (it preempts the checksum loop); never
    #   touches t2/s3.
    #=================================================================
    .align 2
nmi_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)

    li   s2, 1                 # marker: inside RNMI handler (NMIE=0)

    # nmi_count++
    lw   t0, 0x28(s1)
    addi t0, t0, 1
    sw   t0, 0x28(s1)

    # Diagnostic snapshots: mnstatus.NMIE must be 0, mncause bit31 must be 1
    csrr t1, 0x744             # mnstatus
    sw   t1, 0x1C(s1)
    csrr t1, 0x742             # mncause
    sw   t1, 0x2C(s1)

    # Sync the bench FROM INSIDE the handler: x31 = 0xA0A00000 + nmi_count.
    # The bench asserts irq_m_external on seeing this and holds it.
    li   t1, 0xA0A00000
    add  t1, t1, t0
    mv   x31, t1

    # Long delay: the NMIE=0 window during which the held IRQ must stay
    # masked. Buggy RTL vectors to m_trap_handler in here with s2==1.
    li   t0, 100
nmi_delay:
    addi t0, t0, -1
    bnez t0, nmi_delay

    li   s2, 0                 # clear marker just before leaving

    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    .word 0x70200073           # mnret: NMIE->1, resume at mnepc


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # scratchpad base

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x1C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0xA0(s1)
    sw   t0, 0xA4(s1)
    sw   t0, 0xA8(s1)
    sw   t0, 0xC0(s1)
    sw   t0, 0xC4(s1)
    sw   t0, 0xC8(s1)

    li   s2, 0                 # inside-RNMI marker: clear

    # Install mtvec handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Publish RNMI handler address for the bench (drives nmi_vector)
    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x08(s1)

    # Enable NMI: mnstatus.NMIE = 1 (bit 3; resets to 0)
    csrsi 0x744, 8

    # Enable global machine interrupts: mstatus.MIE = 1
    li   t0, 0x8
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0

    # Sync: init done -- bench latches nmi_vector
    li   x31, 0x11111111


    #=================================================================
    # ITERATION 1
    #=================================================================

    # Enable mie.MEIE (bit 11) -- IRQ line is deasserted at this point
    li   t0, 0x800
    csrs mie, t0

    # ARM: bench pulses NMI a few cycles after seeing this, landing
    # mid-checksum-loop.
    li   x31, 0x21212121

    # Checksum loop (golden = 0x0000DCDC). NMI preempts it; correct RTL
    # also takes the post-mnret pending IRQ inside it. Any skipped or
    # replayed instruction diverges the result.
    li   t0, 1
    li   t1, 200
    li   s3, 0
chk_loop_1:
    add  s3, s3, t0
    slli t2, t0, 1
    xor  s3, s3, t2
    addi t0, t0, 3
    addi t1, t1, -1
    bnez t1, chk_loop_1

    sw   s3, 0x20(s1)          # checksum iter1

    # Wait for the IRQ trap to have been handled (correct RTL: fired
    # right after mnret; buggy RTL: fired inside the RNMI handler --
    # either way irq_count reaches 1, keeping the test hang-free).
wait_irq_1:
    lw   t0, 0x00(s1)
    li   t2, 1
    bne  t0, t2, wait_irq_1

    # DONE: bench deasserts irq_m_external on seeing this
    li   x31, 0x22222222

    # Give the bench time to drop the line before re-enabling MEIE
    li   t0, 50
post1_delay:
    addi t0, t0, -1
    bnez t0, post1_delay


    #=================================================================
    # ITERATION 2 (identical, fresh sync values)
    #=================================================================

    li   t0, 0x800
    csrs mie, t0               # re-enable mie.MEIE

    li   x31, 0x31313131       # ARM: bench pulses NMI

    li   t0, 1
    li   t1, 200
    li   s3, 0
chk_loop_2:
    add  s3, s3, t0
    slli t2, t0, 1
    xor  s3, s3, t2
    addi t0, t0, 3
    addi t1, t1, -1
    bnez t1, chk_loop_2

    sw   s3, 0x24(s1)          # checksum iter2

wait_irq_2:
    lw   t0, 0x00(s1)
    li   t2, 2
    bne  t0, t2, wait_irq_2

    li   x31, 0x33333333       # DONE: bench deasserts irq_m_external

    li   t0, 50
post2_delay:
    addi t0, t0, -1
    bnez t0, post2_delay


    #=================================================================
    # END OF TEST
    #=================================================================
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
