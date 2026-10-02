#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_m_dbltrp_rnmi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Smdbltrp double trap diverted to the RNMI handler (NMIE=1)
#
#   PHASE A  ECALL (cause 11) traps to M and leaves MDT set. The handler does
#            NOT clear it and then executes an illegal instruction (cause 2).
#            That second trap is an unexpected double trap: with mnstatus.NMIE
#            armed it must divert to the RNMI handler, NOT to mtvec.
#            The RNMI handler proves the divert was clean:
#              mncause = 2       -- the precipitating cause, interrupt bit 0
#              mnepc   = PC of the illegal instruction inside the handler
#              mepc    = PC of the ECALL      -- the M stack is UNTOUCHED
#              mcause  = 11                   -- still phase A's cause
#            Two distinct causes (11 then 2) so an untouched mcause cannot be
#            confused with one the double trap overwrote.
#
#   PHASE C  A handler that clears MDT on entry takes an ordinary nested trap
#            through mtvec -- no divert, RNMI count stays 1. This is the
#            migration path every other handler in the suite relies on.
#
#   PHASE D  After the divert has been handled and MNRET'ed, the bench fires
#            the nmi_i pin. mncause must be an interrupt code again:
#            0x80000002 (Smrnmi: "If the reason is an interrupt, bit MXLEN-1
#            is set to 1") -- the divert's bit-31 = 0 does not stick.
#
# Scratchpad (base 0x80000000):
#   0x00 rnmi_count       0x04 mncause      0x08 mnepc     0x0C mepc
#   0x10 mcause           0x14 m_trap_count 0x18 expected mnepc
#   0x20 phase-A cause    0x24 rnmi_handler address (for the testbench)
#   0x28 phase-D mncause  0x2C phase-D rnmi count  0x30 phase-D mnstatus
#----------------------------------------------------------------------------

.equ MSTATUSH, 0x310
.equ MNSTATUS, 0x744
.equ MNEPC,    0x741
.equ MNCAUSE,  0x742

.section .text
.global main

main:
    j _start

    #=================================================================
    # HANDLER A -- entered by the ECALL. Deliberately does NOT clear
    # MDT, so its own fault becomes a double trap.
    #=================================================================
    .align 2
m_handler_a:
    csrr t0, mcause
    sw   t0, 0x20(s1)          # phase-A cause, for reference

    la   t0, a_fault_pc
    sw   t0, 0x18(s1)          # publish the PC that is about to fault

a_fault_pc:
    .word 0xFFFFFFFF           # illegal -> double trap -> RNMI handler
    mret                       # never reached

    #=================================================================
    # RNMI HANDLER -- where the double trap must land.
    #=================================================================
    .align 2
rnmi_handler:
    csrr t0, MNCAUSE
    sw   t0, 0x04(s1)
    csrr t0, MNEPC
    sw   t0, 0x08(s1)
    csrr t0, mepc
    sw   t0, 0x0C(s1)
    csrr t0, mcause
    sw   t0, 0x10(s1)

    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Recover. MNPP is M, so MNRET does not clear MDT -- clear it explicitly or
    # the next trap doubles straight back here.
    csrw MSTATUSH, x0
    la   t0, phase_c_start
    csrw MNEPC, t0
    .word 0x70200073           # mnret

    #=================================================================
    # HANDLER C -- clears MDT first thing, so a fault inside it is an
    # ordinary nested trap delivered through mtvec.
    #=================================================================
    .align 2
m_handler_c:
    csrw MSTATUSH, x0          # MDT = 0: nested traps are ordinary again

    lw   t0, 0x14(s1)
    addi t0, t0, 1
    sw   t0, 0x14(s1)

    li   t1, 1
    bne  t0, t1, c_second_entry
    .word 0xFFFFFFFF           # first entry: fault again -> ordinary nested trap

c_second_entry:
    la   t0, phase_done
    csrw mepc, t0
    mret

    #=================================================================
    # RNMI HANDLER D -- pin NMI after the divert; resumes at mnepc.
    #=================================================================
    .align 2
rnmi_handler_d:
    csrr t0, MNCAUSE
    sw   t0, 0x28(s1)
    csrr t0, MNSTATUS
    sw   t0, 0x30(s1)
    lw   t0, 0x2C(s1)
    addi t0, t0, 1
    sw   t0, 0x2C(s1)
    .word 0x70200073           # mnret

    #=================================================================
    # MAIN
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    sw   x0, 0x08(s1)
    sw   x0, 0x0C(s1)
    sw   x0, 0x10(s1)
    sw   x0, 0x14(s1)
    sw   x0, 0x18(s1)
    sw   x0, 0x20(s1)
    sw   x0, 0x28(s1)
    sw   x0, 0x2C(s1)
    sw   x0, 0x30(s1)

    la   t0, rnmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x24(s1)          # testbench programs nmi_vector from here

    la   t0, m_handler_a
    csrw mtvec, t0

    # MDT resets to 1. Clear it so phase A's ECALL is an ordinary trap and it is
    # the ECALL's own entry that re-arms MDT for handler A to double on.
    csrw MSTATUSH, x0

    li   x31, 0x11111111       # Sync: nmi_vector address published

    csrsi MNSTATUS, 8          # mnstatus.NMIE = 1 -> double traps divert

    li   x31, 0x22222222       # Sync: NMIE armed

    # MDT is set by the ECALL's own trap entry; handler A leaves it set.
    la   t0, a_ecall_pc
    sw   t0, 0x1C(s1)          # PC of the ECALL, for the mepc check
a_ecall_pc:
    ecall                      # cause 11 -> handler A -> double trap -> RNMI

phase_c_start:
    li   x31, 0x33333333       # Sync: returned from the RNMI handler

    la   t0, m_handler_c
    csrw mtvec, t0
    .word 0xFFFFFFFF           # -> handler C -> nested ordinary trap

phase_done:
    li   x31, 0x44444444       # Sync: phase C complete

    #--- PHASE D: pin NMI after the divert (NMIE is 1 again since the MNRET)
    la   t0, rnmi_handler_d
    csrw 0x7FD, t0             # marv_nmvec = handler D

    li   x31, 0x55555555       # Sync: bench pulses nmi_i
d_wait:
    lw   t0, 0x2C(s1)
    beqz t0, d_wait
    lw   zero, 0x30(s1)        # drain the handler's stores

    li   x31, 0x66666666       # Sync: phase D complete

    li   x31, 0xdeadbeef
1:  j 1b
