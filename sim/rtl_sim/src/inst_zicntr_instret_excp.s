#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_instret_excp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZICNTR -- minstret MUST NOT COUNT TRAPPING INSTRUCTIONS
#   Priv 3.1.11: "Instructions that cause synchronous exceptions, including
#   ECALL and EBREAK, are not considered to have retired and hence do not
#   increment minstret."
#
#   MEASUREMENT METHOD. Each probe is exactly:
#         csrr s2, minstret      <- read BEFORE (does not include itself)
#         <the instruction under test>
#     handler:
#         csrr s3, minstret      <- FIRST instruction of the handler
#   so delta = s3 - s2 counts only the `csrr s2` itself, plus the instruction
#   under test if it was (incorrectly) counted. Nothing else runs in between.
#     delta == 1  -> compliant: the faulting instruction did not retire
#     delta == 2  -> the faulting instruction was counted (the old behaviour)
#
#   Covers all four stages at which aRVern detects synchronous exceptions
#   (see excp_detect_in_{if,id,ex,wb} in arv_csr_traps.v), because the fix
#   un-retires at trap entry and must be right for every class:
#     ID stage: ECALL, EBREAK, illegal instruction
#     EX stage: load address misaligned, store address misaligned
#     WB stage: load access fault, store access fault  (resolve LATE, after an
#               AHB data phase -- these are the ones no decode-side gate reaches)
#
#   WHY THE STORE-ACCESS-FAULT PROBE IS ONLY A DIAGNOSTIC. A posted store's error
#   response arrives after the pipeline has moved on, and younger instructions
#   COMMIT before the trap is taken (measured: the instruction after a WB-class
#   faulting access executes once before the trap and again after MRET resumes).
#   Those instructions really did execute, so counting them is correct -- they are
#   then counted a SECOND time on re-execution. That over-count is a symptom of
#   the trap being imprecise, not of the counter, so no value asserted here would
#   mean anything until that is resolved. The load probe avoids it with a load-use
#   dependency, which stalls dispatch until the fault arrives. marv_ctl[6] resolves
#   it outright by holding younger instructions -- see trap_marv_ctl_ldst_precise,
#   which asserts the exact delta of 1 in that mode.
#
#   NEGATIVE CONTROL (phase 8): an INTERRUPT must NOT decrement. An interrupt
#   is taken between instructions and un-retires nothing, so a spurious undo
#   would show up as delta == 1 where 2 is correct. This is the check that
#   catches an over-broad qualification term.
#
#   Scratchpad layout (base 0x80000000): one delta per probe
#   0x00 ECALL          0x04 EBREAK        0x08 illegal
#   0x0C load misalign  0x10 store misalign
#   0x14 load acc fault 0x18 store acc fault (DIAGNOSTIC -- see below)
#   0x1C interrupt (negative control, expect 2)
#----------------------------------------------------------------------------

.equ MSTATUS_MIE, 0x00000008
.equ MIE_MSIE,    0x00000008
.equ ACLINT_MSIP0, 0x02000000

.include "firmware_config.inc"

.section .text
.global main

# Every probe is measured by advancing MEPC by a FIXED 4 in the handler, so the
# whole test must assemble to 4-byte instructions -- with C enabled the assembler
# would emit c.ebreak (2 bytes) and the handler would resume mid-stream (observed
# as a -c_mode TIMEOUT). Compression is irrelevant to what this test measures.
.option norvc

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    # The FIRST instruction must be the minstret read -- anything before
    # it would be counted and inflate every delta.
    #=================================================================
    .align 2

# Cause 5/7 are RNMIs now. Same measurement, but mnepc is already the resume
# point, so nothing is advanced here.
nmi_handler:
    csrr s3, minstret
    sub  s4, s3, s2
    sw   s4, 0(s5)
    lw   zero, 0(s5)
    .word 0x70200073               # mnret

    .align 2

m_trap_handler:
    csrr s3, minstret              # <-- must stay first
    sub  s4, s3, s2                # delta for this probe
    sw   s4, 0(s5)                 # store to the slot s5 points at

    # Advance MEPC past the faulting instruction. Every probe here is a
    # 4-byte instruction, and the IRQ probe (phase 8) needs no adjustment.
    csrr t0, mcause
    bltz t0, m_handler_irq         # interrupt: MEPC already points at the
                                   # not-yet-retired instruction
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

m_handler_irq:
    # Clear the ACLINT MSIP source so we make progress, and mask MIE.
    li   t0, ACLINT_MSIP0
    sw   x0, 0(t0)
    csrw mie, x0
    mret

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    la   t0, m_trap_handler
    csrw mtvec, t0
    csrw mstatush, x0        # MDT resets to 1; clear it or the first trap is an Smdbltrp double trap

    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x50(s1)
    lw   zero, 0x50(s1)

    li   x31, 0x11111111           # Sync: configured; tb programs nmi_vector

    li   t0, 20
wait_vec:
    addi t0, t0, -1
    bnez t0, wait_vec

    csrsi 0x744, 8                 # mnstatus.NMIE = 1 (else IRQs/RNMIs never deliver)

    li   x31, 0x1E1E1E1E           # Sync: NMIE armed

    #---------------------------------------------------------------
    # ID-stage class
    #---------------------------------------------------------------
    addi s5, s1, 0x00
    csrr s2, minstret
    ecall

    addi s5, s1, 0x04
    csrr s2, minstret
    ebreak

    addi s5, s1, 0x08
    csrr s2, minstret
    .word 0x00000000               # illegal instruction

    #---------------------------------------------------------------
    # EX-stage class (address misaligned)
    #---------------------------------------------------------------
    li   t1, 0x80000801            # deliberately odd
    addi s5, s1, 0x0C
    csrr s2, minstret
    lw   t2, 0(t1)

    addi s5, s1, 0x10
    csrr s2, minstret
    sw   t2, 0(t1)

    #---------------------------------------------------------------
    # WB-stage class (access fault). A WB fault surfaces only when the AHB
    # data phase returns, and aRVern keeps retiring meanwhile -- the trace
    # shows the instruction AFTER the faulting load retiring before the trap.
    # So each faulting access is followed by an instruction that DEPENDS on
    # it (or fences it), which stalls dispatch until the fault arrives.
    # Without that, the next instruction retires first and inflates the delta
    # -- and if it happens to write s5, the handler stores to the wrong slot.
    #---------------------------------------------------------------
    li   t1, 0x00000000            # unmapped in the tb AHB decoder
    addi s5, s1, 0x14
    csrr s2, minstret
    lw   t2, 0(t1)
    addi t2, t2, 1                 # load-use dependency: stalls until the fault

    addi s5, s1, 0x18
    csrr s2, minstret
    sw   t2, 0(t1)
    fence                          # drain the posted store before anything retires


    #---------------------------------------------------------------
    # PRECISION PROBE (diagnostic, not a compliance check).
    # Did the instruction AFTER a WB-class faulting access COMMIT before
    # the trap was taken, or was it squashed? s6/s7 are non-idempotent and
    # the handler never touches them. mepc = the faulting PC, so mret+4
    # resumes ON these instructions:
    #     4 => ran exactly once (squashed before the trap, then re-run)
    #     8 => committed BEFORE the trap AND re-executed after mret
    #---------------------------------------------------------------
    li   s6, 0
    li   s7, 0
    li   t1, 0x00000000

    addi s5, s1, 0x30
    csrr s2, minstret
    lw   t2, 0(t1)                 # WB-class load access fault
    addi s6, s6, 4                 # NON-IDEMPOTENT
    sw   s6, 0x34(s1)

    addi s5, s1, 0x38
    csrr s2, minstret
    sw   t2, 0(t1)                 # WB-class store access fault
    addi s7, s7, 4                 # NON-IDEMPOTENT
    sw   s7, 0x3C(s1)

    li   x31, 0x22222222           # Sync: all exception probes done

    #---------------------------------------------------------------
    # NEGATIVE CONTROL: an interrupt must NOT un-retire anything.
    # MSIP is armed while MIE=0, then the csrs that unmasks retires and
    # the IRQ is taken on the following instruction. Both the csrr and
    # the csrs retire, so the compliant delta is 2 -- a spurious undo
    # would make it 1.
    #---------------------------------------------------------------
    li   t0, MIE_MSIE
    csrw mie, t0
    li   t0, ACLINT_MSIP0
    li   t1, 1
    sw   t1, 0(t0)                 # MSIP pending, still masked
    nop
    nop
    nop
    nop

    addi s5, s1, 0x1C
    li   t0, MSTATUS_MIE
    # Smdbltrp: MDT resets to 1 and blocks MIE. Cleared BEFORE the minstret
    # read -- inside the measured window it would add one to the delta.
    csrw mstatush, x0

    csrr s2, minstret
    csrs mstatus, t0               # unmask -> IRQ taken on the next instruction
    nop

    li   x31, 0x33333333           # Sync: negative control done

end_of_test:
    li   x31, 0xdeadbeef
    j    end_of_test
