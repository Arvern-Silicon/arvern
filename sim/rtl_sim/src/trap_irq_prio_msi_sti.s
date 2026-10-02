#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_prio_msi_sti
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: INTERRUPT PRIORITY -- MSI vs STI
#   With MIDELEG=0 both MSI (cause 3) and a non-delegated STI (cause 5) target
#   M-mode. The ISA fixes the order MEI > MSI > MTI > SEI > SSI > STI, so with
#   both pending and both enabled MSI must be taken first and STI second.
#
#   Derived from riscv-arch-test InterruptsS-00
#   (cp_interrupts_s_nodeleg_stip_stie), where arvern was observed reporting
#   MCAUSE=0x80000005 (STI) when 0x80000003 (MSI) was expected.
#
#   Scratchpad layout (base 0x80000000):
#   0x00: irq_count
#   0x04: MCAUSE of interrupt 0   (expect 0x80000003, MSI)
#   0x08: MCAUSE of interrupt 1   (expect 0x80000005, STI)
#----------------------------------------------------------------------------

.equ ACLINT_MSIP0, 0x02000000      # ACLINT MSWI: MSIP[hart 0]
.equ MIE_MSIE,     0x00000008      # mie.MSIE  (bit 3)
.equ MIE_STIE,     0x00000020      # mie.STIE  (bit 5)
.equ MIP_STIP,     0x00000020      # mip.STIP  (bit 5, M-writable)
.equ MSTATUS_MIE,  0x00000008      # mstatus.MIE (bit 3)

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    # Records MCAUSE, clears that one source, and returns. The second
    # interrupt is then taken on the next instruction.
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    lw   t0, 0x00(s1)              # t0 = irq_count
    slli t1, t0, 2
    addi t1, t1, 0x04
    add  t1, t1, s1
    csrr t2, mcause
    sw   t2, 0(t1)                 # record MCAUSE

    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Clear whichever source fired so we make progress.
    li   t1, 0x80000003            # MSI
    beq  t2, t1, clear_msi
    li   t1, 0x80000005            # STI
    beq  t2, t1, clear_sti
    j    handler_done

clear_msi:
    li   t1, ACLINT_MSIP0
    sw   x0, 0(t1)
    j    handler_done

clear_sti:
    li   t1, MIP_STIP
    csrc mip, t1

handler_done:
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    csrw mideleg, x0               # nothing delegated: both target M-mode

    # Smrnmi: mnstatus.NMIE resets to 0 and "when NMIE=0, all interrupts are
    # disabled", so this must be set before any ordinary
    # interrupt can be delivered. Smrnmi is unconditional.
    csrsi 0x744, 8                 # mnstatus.NMIE = 1

    li   t0, MIE_MSIE | MIE_STIE
    csrw mie, t0

    li   x31, 0x11111111           # Sync: configured, interrupts still masked

    # Arm both sources while MIE=0 so they become pending together.
    li   t0, MIP_STIP
    csrs mip, t0                   # STIP is M-writable
    li   t1, ACLINT_MSIP0
    li   t2, 1
    sw   t2, 0(t1)                 # MSIP via the ACLINT MSWI

    # Give the ACLINT's MSIP a moment to reach the core before unmasking, so
    # both are genuinely pending in the same cycle.
    nop
    nop
    nop
    nop

    # Snapshot the CSR state just before unmasking, so a no-interrupt failure
    # can be told apart from a wrong-priority one.
    csrr t0, mie
    sw   t0, 0x0C(s1)
    csrr t0, mip
    sw   t0, 0x10(s1)
    csrr t0, mstatus
    sw   t0, 0x14(s1)

    li   t0, MSTATUS_MIE
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0               # unmask -> highest priority wins first

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
