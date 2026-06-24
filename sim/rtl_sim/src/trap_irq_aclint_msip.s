#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_aclint_msip
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ACLINT MSWI end-to-end (self-IPI)
#   Verifies aRVern -> ahb_aclint -> aRVern machine-software IRQ loop:
#     - Firmware enables MIE.MSIE + MSTATUS.MIE
#     - Firmware writes MSIP[0] = 1 (a self-IPI; bit-0 of the MSWI register)
#     - ACLINT drives irq_m_software_o = 1 -> core takes MSI trap
#       (mcause = 0x80000003)
#     - Handler clears MSIP[0] = 0 and MRETs
#     - Test verifies one trap was taken and MSIP cleared
#
#   ACLINT address map (SiFive CLINT-compatible base = 0x02000000):
#     0x02000000 + 4*hart : MSIP[hart]   (MSWI window)
#----------------------------------------------------------------------------

.section .text
.global main

# ACLINT MSWI MSIP[hart=0]
.equ ACLINT_MSIP0,  0x02000000

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#=========================================================================

main:
    j _start

    #=====================================================================
    # TRAP HANDLER (M-mode MSI path)
    #=====================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  12(sp)
    sw   t1,   8(sp)
    sw   t2,   4(sp)

    csrr t0, mcause
    csrr t1, mepc

    # trap_count++
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    sw   t0, 0x04(s1)               # last MCAUSE
    sw   t1, 0x08(s1)               # last MEPC

    # Only handle Machine Software Interrupt (cause 0x80000003)
    li   t2, 0x80000003
    bne  t0, t2, handler_done

    # Clear MSIP[0] at the ACLINT (this drops irq_m_software_o)
    li   t0, ACLINT_MSIP0
    sw   zero, 0(t0)

handler_done:
    lw   t2,   4(sp)
    lw   t1,   8(sp)
    lw   t0,  12(sp)
    addi sp, sp, 16
    mret


    #=====================================================================
    # MAIN
    #=====================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # MSIP[0] should reset to 0 (MSWI register is hclk-domain flop, reset 0)
    li   t0, ACLINT_MSIP0
    lw   t1, 0(t0)
    bnez t1, fail                   # if non-zero, ACLINT is in a bad state

    # Enable MIE.MSIE (bit 3) + MSTATUS.MIE
    li   t0, 0x008
    csrs mie, t0
    li   t0, 0x008
    csrs mstatus, t0

    li   x31, 0x11111111            # signal: ACLINT MSWI configured

    # Trigger the MSI: write MSIP[0] = 1
    li   t0, ACLINT_MSIP0
    li   t1, 1
    sw   t1, 0(t0)

    # Wait for the trap (handler will clear MSIP[0])
    li   t3, 0
wait_msi:
    addi t3, t3, 1
    lw   t4, 0x00(s1)               # poll trap_count
    beqz t4, wait_msi
    # trap fired

    # Re-read MSIP[0] -- handler should have cleared it
    li   t0, ACLINT_MSIP0
    lw   t1, 0(t0)
    bnez t1, fail                   # MSIP should be 0 after handler

    li   x31, 0xdeadbeef
    j end_of_test

fail:
    li   x31, 0xbadbad00
    j end_of_test

end_of_test:
    nop
    j end_of_test
