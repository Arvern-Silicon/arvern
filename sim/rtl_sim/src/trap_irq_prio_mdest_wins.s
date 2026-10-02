#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_prio_mdest_wins
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: INTERRUPT PRIORITY -- DESTINED PRIVILEGE OUTRANKS CAUSE ORDER
#   Interrupt priority is two-level: the destined privilege mode is compared
#   first, and the cause order (MEI > MSI > MTI > SEI > SSI > STI) only breaks
#   ties between interrupts destined for the SAME mode.
#
#   Here MIDELEG=SSI only, so with both SSIP and STIP pending in S-mode:
#     SSI (cause 1) is delegated  -> destined for S
#     STI (cause 5) is NOT        -> destined for M
#   Cause order alone would pick SSI (1 before 5). The correct answer is STI,
#   because an M-destined interrupt must never wait behind an S-destined one --
#   otherwise S-mode code runs with an enabled M-mode interrupt pending.
#
#   The M handler also samples mstatus.SIE, which must still be 1: a trap taken
#   to M-mode does not touch SIE. That sample is the ONLY witness of the bug --
#   picking SSI first still ends up in the M handler with cause STI, because the
#   M-destined STI immediately preempts the half-entered S handler. Cause and
#   ordering therefore look correct either way; SIE=0 is what gives it away.
#
#   Derived from riscv-arch-test InterruptsS-00, where arvern took the
#   delegated SSI first and so reported mstatus.SIE=0 to the M handler.
#
#   Scratchpad layout (base 0x80000000):
#   0x00: irq_count
#   0x04: cause of trap 0   (expect 0x80000005, STI)
#   0x08: mode  of trap 0   (expect 3, M-mode handler)
#   0x0C: cause of trap 1   (expect 0x80000001, SSI)
#   0x10: mode  of trap 1   (expect 1, S-mode handler)
#   0x14: mstatus.SIE seen by the M handler (expect 1)
#   0x18: mie snapshot before entering S-mode
#   0x1C: mip snapshot before entering S-mode
#----------------------------------------------------------------------------

.equ MIE_SSIE,      0x00000002      # mie.SSIE  (bit 1)
.equ MIE_STIE,      0x00000020      # mie.STIE  (bit 5)
.equ MIP_SSIP,      0x00000002      # mip.SSIP  (bit 1, M-writable)
.equ MIP_STIP,      0x00000020      # mip.STIP  (bit 5, M-writable)
.equ MIDELEG_SSI,   0x00000002      # delegate ONLY the supervisor software IRQ
.equ MSTATUS_SIE,   0x00000002      # mstatus.SIE (bit 1)
.equ MSTATUS_MIE,   0x00000008      # mstatus.MIE (bit 3)
.equ MSTATUS_MPP,   0x00001800      # mstatus.MPP (bits 12:11)
.equ MSTATUS_MPP_S, 0x00000800      # mstatus.MPP = S

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    # Records MCAUSE and mstatus.SIE, clears STIP, returns to S-mode.
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    lw   t0, 0x00(s1)              # t0 = irq_count
    slli t1, t0, 3                 # 8 bytes per record
    add  t1, t1, s1
    csrr t2, mcause
    sw   t2, 0x04(t1)              # record MCAUSE
    li   t2, 3                     # M-mode
    sw   t2, 0x08(t1)

    # mstatus.SIE must be untouched by a trap taken to M-mode.
    csrr t2, mstatus
    andi t2, t2, MSTATUS_SIE
    srli t2, t2, 1
    sw   t2, 0x14(s1)

    addi t0, t0, 1
    sw   t0, 0x00(s1)

    li   t1, MIP_STIP
    csrc mip, t1                   # clear the source so we make progress

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #=================================================================
    # S-MODE TRAP HANDLER
    # Records SCAUSE, clears SSIP (S-writable because it is delegated).
    #=================================================================
    .align 2

s_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    lw   t0, 0x00(s1)
    slli t1, t0, 3
    add  t1, t1, s1
    csrr t2, scause
    sw   t2, 0x04(t1)              # record SCAUSE
    li   t2, 1                     # S-mode
    sw   t2, 0x08(t1)

    addi t0, t0, 1
    sw   t0, 0x00(s1)

    li   t1, MIP_SSIP
    csrc sip, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    sret

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   s1, 0x80000000

    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0
    la   t0, s_trap_handler
    csrw stvec, t0

    li   t0, MIDELEG_SSI
    csrw mideleg, t0               # SSI -> S-mode, STI stays M-mode

    # Smrnmi: mnstatus.NMIE resets to 0 and "when NMIE=0, all interrupts are
    # disabled", so this must be set before any ordinary
    # interrupt can be delivered. Smrnmi is unconditional.
    csrsi 0x744, 8                 # mnstatus.NMIE = 1

    li   t0, MIE_SSIE | MIE_STIE
    csrw mie, t0

    li   t0, MSTATUS_MIE
    csrc mstatus, t0               # MIE=0: nothing fires while still in M-mode
    li   t0, MSTATUS_SIE
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0               # SIE=1: the delegated SSI is deliverable in S

    li   x31, 0x11111111           # Sync: configured, still in M-mode

    # Arm both sources together, while M-mode interrupts are masked.
    li   t0, MIP_SSIP | MIP_STIP
    csrs mip, t0

    csrr t0, mie
    sw   t0, 0x18(s1)
    csrr t0, mip
    sw   t0, 0x1C(s1)

    # Drop to S-mode via MRET. In S-mode M-destined interrupts are enabled
    # unconditionally (current privilege < M), so mstatus.MIE is irrelevant.
    li   t0, MSTATUS_MPP
    csrc mstatus, t0
    li   t0, MSTATUS_MPP_S
    csrs mstatus, t0
    la   t0, s_mode_entry
    csrw mepc, t0
    mret

s_mode_entry:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    li   x31, 0x22222222           # Sync: both interrupts serviced

end_of_test:
    li   x31, 0xdeadbeef
    j    end_of_test
