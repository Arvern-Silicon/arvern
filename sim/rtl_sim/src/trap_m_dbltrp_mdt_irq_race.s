#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_m_dbltrp_mdt_irq_race
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Smdbltrp -- M-mode IRQ racing an explicit MDT set
#
#   Priv 3.1.6.2: "When the MDT bit is set to 1 by an explicit CSR write, the
#   MIE bit is cleared to 0." The write is atomic: once the `csrs mstatush`
#   that sets MDT has retired, no interrupt may be taken with MIE=1, and an
#   interrupt taken with MDT=1 would be a double trap diverted to the RNMI
#   handler (mnstatus.NMIE=1) -- a bogus divert with no first trap.
#
#   The testbench sweeps a level machine-timer interrupt over 32 cycle
#   offsets around the `csrs mstatush, MDT` so that on one of them the IRQ
#   becomes pending on the very cycle the CSR write executes with MIE=1.
#
#   Per iteration (MIE=1, MTIE=1, timer line low):
#     sync 0x51000000+i, 16 NOPs, csrs mstatush(MDT), 8 NOPs, read mstatus,
#     csrc mstatush(MDT), csrs mstatus(MIE), wait until one IRQ was taken.
#
#   Legal outcomes: the IRQ is taken BEFORE the csrs retires (mepc <= its
#   address) or AFTER the MIE re-enable. A trap with mepc strictly inside the
#   MIE=0 window (csrs_mdt, reenable] is the bug; an RNMI-handler entry is the
#   bug's double-trap signature.
#
#   Register conventions (no memory scratch needed):
#     s2  (x18) iteration counter          expect 32
#     s3  (x19) RNMI handler entries       expect 0
#     s4  (x20) IRQ taken inside MIE=0 window (mepc-classified)   expect 0
#     s5  (x21) total M IRQs taken         expect 32 (one per iteration)
#     s6  (x22) OR of mstatus.MIE read after every csrs mstatush  expect 0
#     s7  (x23) last mcause seen by the M handler
#     s8  (x24) per-iteration "IRQ taken" flag (1 = still waiting)
#     s9  (x25) unexpected synchronous exceptions   expect 0
#     s10 (x26) address of the csrs mstatush
#     s11 (x27) address of the csrs mstatus (MIE re-enable)
#     t3  (x28) last mncause seen by the RNMI handler
#     t4  (x29) IRQs taken before the csrs retired (diagnostic only)
#     t5  (x30) IRQs taken after the MIE re-enable (diagnostic only)
#     x31       testbench sync
#----------------------------------------------------------------------------

.equ MSTATUSH, 0x310
.equ MNSTATUS, 0x744
.equ MNEPC,    0x741
.equ MNCAUSE,  0x742
.equ MDT_MASK, 0x00000400
.equ MIE_MASK, 0x00000008
.equ MTIE_MASK,0x00000080

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # M TRAP HANDLER. Classifies an interrupt by mepc against the
    # MIE=0 window, then holds until the testbench drops the line.
    #=================================================================
    .align 2
m_handler:
    addi sp, sp, -8
    sw   t0, 4(sp)
    sw   t1, 0(sp)

    csrr s7, mcause
    bgez s7, m_exception

    csrr t0, mepc
    bleu t0, s10, m_before      # mepc <= csrs_mdt: csrs not retired, legal
    bgtu t0, s11, m_after       # mepc >  reenable: MIE=1 again, legal
    addi s4, s4, 1              # BUG: IRQ taken with mepc inside MIE=0 window
    j    m_taken
m_before:
    addi t4, t4, 1
    j    m_taken
m_after:
    addi t5, t5, 1
m_taken:
    addi s5, s5, 1              # testbench drops the timer line on this
    li   s8, 0
m_spin:                         # level IRQ: wait for the line to drop
    csrr t0, mip
    andi t0, t0, MTIE_MASK
    bnez t0, m_spin
    j    m_done

m_exception:
    addi s9, s9, 1
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0

m_done:
    lw   t1, 0(sp)
    lw   t0, 4(sp)
    addi sp, sp, 8
    mret

    #=================================================================
    # RNMI HANDLER -- entered only on the bogus double-trap divert.
    # Recover so the failure is counted instead of hanging the test.
    #=================================================================
    .align 2
rnmi_handler:
    addi s3, s3, 1
    csrr t3, MNCAUSE
    csrw MSTATUSH, x0           # MNPP=M: mnret does not clear MDT
    .word 0x70200073            # mnret -> mnepc (the interrupted PC)

    #=================================================================
    # MAIN
    #=================================================================
_start:
    li   sp, 0x80010000

    li   s2, 0
    li   s3, 0
    li   s4, 0
    li   s5, 0
    li   s6, 0
    li   s7, 0
    li   s8, 0
    li   s9, 0
    li   t3, 0
    li   t4, 0
    li   t5, 0

    la   t0, rnmi_handler
    csrw 0x7FD, t0              # marv_nmvec = RNMI handler
    la   t0, m_handler
    csrw mtvec, t0
    la   s10, csrs_mdt
    la   s11, reenable

    csrsi MNSTATUS, 8           # mnstatus.NMIE = 1 first ...
    csrw  MSTATUSH, x0          # ... then MDT = 0 (boot order per Smdbltrp)

    li   t0, MTIE_MASK
    csrs mie, t0
    csrsi mstatus, MIE_MASK

    li   x31, 0x11111111

main_loop:
    li   s8, 1
    li   t1, MDT_MASK
    li   t2, MIE_MASK
    li   t0, 0x51000000
    add  x31, t0, s2            # per-iteration sync: tb asserts MTIP at +i cycles

    .rept 16
    nop
    .endr
csrs_mdt:
    csrs MSTATUSH, t1           # MDT = 1 -> hardware must clear MIE atomically
    .rept 8
    nop
    .endr
    csrr t0, mstatus
    andi t0, t0, MIE_MASK
    or   s6, s6, t0             # must stay 0
    csrc MSTATUSH, t1           # MDT = 0
reenable:
    csrs mstatus, t2            # MIE = 1: a pending IRQ is taken here
wait_irq:
    bnez s8, wait_irq

    addi s2, s2, 1
    li   t0, 32
    blt  s2, t0, main_loop

    li   x31, 0xdeadbeef
1:  j 1b
