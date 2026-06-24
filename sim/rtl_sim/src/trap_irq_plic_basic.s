#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_plic_basic
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PLIC end-to-end (M-mode context)
#   Verifies the full aRVern -> ahb_plic -> aRVern external-IRQ loop:
#     - Firmware configures priorities, enables, threshold over AHB
#     - Testbench raises plic_irq_src[N] (level)
#     - PLIC gateway latches pending; arbiter compares vs threshold
#     - Core takes MEI trap; handler reads claim/complete register
#     - Handler signals TB to drop the line, then writes complete
#     - With two sources asserted together, the higher-priority source is
#       claimed first
#
#   PLIC address map (SiFive/QEMU-virt convention, base = 0x0C000000):
#     0x0C000000 + 4*N : priority[N]
#     0x0C001000       : pending word 0 (RO)
#     0x0C002000       : enable[ctx0=M][word 0]
#     0x0C200000       : threshold[ctx0=M]
#     0x0C200004       : claim/complete[ctx0=M]
#
#   IRQ sources are driven by the testbench (block-level verification of the
#   aRVern + ahb_plic pair).
#----------------------------------------------------------------------------

.section .text
.global main

# PLIC register addresses (M-mode context = ctx 0)
.equ PLIC_PRI_BASE,  0x0C000000
.equ PLIC_EN_M,      0x0C002000
.equ PLIC_TH_M,      0x0C200000
.equ PLIC_CLAIM_M,   0x0C200004

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#   0x00: trap_count               (incremented by handler)
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x0C: last claimed source ID   (handler reads from PLIC claim)
#   0x10..0x2C: per-trap claim log: claim[n] @ 0x10 + (n-1)*4
#   0x80: TB drop-source signal: handler writes claimed ID here,
#         TB monitors and drops plic_irq_src[ID]; handler zeros it
#         before MRET.
#=========================================================================

main:
    j _start

    #=====================================================================
    # TRAP HANDLER (M-mode external IRQ path)
    #=====================================================================
    .align 2
trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc

    # trap_count++
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    # last MCAUSE, MEPC
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)

    # Only handle Machine External Interrupt (cause 11)
    li   t3, 0x8000000B
    bne  t0, t3, handler_done

    # PLIC claim
    li   t3, PLIC_CLAIM_M
    lw   t4, 0(t3)                  # t4 = claimed source ID

    # last_claimed_id
    sw   t4, 0x0C(s1)

    # Sequential claim log: scratchpad[0x10 + (count-1)*4]
    addi t0, t2, -1
    slli t0, t0, 2
    add  t0, t0, s1
    sw   t4, 0x10(t0)

    # Signal TB: drop plic_irq_src[<ID>]
    sw   t4, 0x80(s1)

    # Busy-loop ~100 cycles. By the end the TB has dropped the source line,
    # so the PLIC gateway will not re-pend after we write complete below.
    li   t2, 100
plic_drop_wait:
    addi t2, t2, -1
    bnez t2, plic_drop_wait

    # PLIC complete (write source ID back to claim/complete register)
    li   t3, PLIC_CLAIM_M
    sw   t4, 0(t3)

    # Clear TB drop signal (so it stops dropping until next claim)
    sw   zero, 0x80(s1)

handler_done:
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
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
    sw   zero, 0x0C(s1)
    sw   zero, 0x10(s1)
    sw   zero, 0x14(s1)
    sw   zero, 0x18(s1)
    sw   zero, 0x1C(s1)
    sw   zero, 0x20(s1)
    sw   zero, 0x80(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    #---------------------------------------------------------------
    # PHASE 1: configure PLIC
    #   priority[1] = 3, priority[2] = 5, priority[3] = 7
    #   enable[ctx0][word0] bits 1..3 = 1 (sources 1,2,3 enabled)
    #   threshold[ctx0] = 0 (any priority > 0 fires)
    #---------------------------------------------------------------
    li   t0, 3
    li   t1, PLIC_PRI_BASE + 4*1
    sw   t0, 0(t1)
    li   t0, 5
    li   t1, PLIC_PRI_BASE + 4*2
    sw   t0, 0(t1)
    li   t0, 7
    li   t1, PLIC_PRI_BASE + 4*3
    sw   t0, 0(t1)

    li   t0, 0x0000000E             # bits 3..1 set
    li   t1, PLIC_EN_M
    sw   t0, 0(t1)

    li   t0, 0
    li   t1, PLIC_TH_M
    sw   t0, 0(t1)

    # Enable MIE.MEIE + global MSTATUS.MIE
    li   t0, 0x800
    csrs mie, t0
    li   t0, 0x8
    csrs mstatus, t0

    li   x31, 0x11111111            # signal: PLIC configured


    #---------------------------------------------------------------
    # PHASE 2: source 1 single-shot
    #   TB drives plic_irq_src[1] = 1. PLIC gateway pends it, target
    #   passes priority 3 > threshold 0 -> MEI trap. Handler claims
    #   (gets ID=1), TB drops src[1], handler completes.
    #---------------------------------------------------------------
phase2_wait:
    lw   t0, 0x00(s1)
    li   t1, 1
    bne  t0, t1, phase2_wait
    li   x31, 0x22222222


    #---------------------------------------------------------------
    # PHASE 3: source 2 single-shot
    #---------------------------------------------------------------
phase3_wait:
    lw   t0, 0x00(s1)
    li   t1, 2
    bne  t0, t1, phase3_wait
    li   x31, 0x33333333


    #---------------------------------------------------------------
    # PHASE 4: sources 1 + 3 asserted together
    #   Expected order: src 3 (pri 7) claimed first, then src 1 (pri 3).
    #---------------------------------------------------------------
phase4_wait:
    lw   t0, 0x00(s1)
    li   t1, 4                      # phase 2 + 3 + 2 traps from phase 4
    bne  t0, t1, phase4_wait
    li   x31, 0x44444444


    # End of test
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
