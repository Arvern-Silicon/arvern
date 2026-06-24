#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_wfi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: WFI
#   Wait For Interrupt instruction verification:
#   - WFI stall + interrupt wakeup + handler + MRET resume
#   - MEPC points past WFI (instruction after WFI)
#   - WFI wakeup with MIE=0 (no trap, just resume)
#   - Register preservation across WFI + interrupt
#
#   IRQ signals driven by testbench (block-level verification).
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x0C: last MSTATUS
#   0x10: trap_handled flag
#   0x18: MTVEC readback
#
# Phase 2 (WFI + interrupt):
#   0x20: MCAUSE             (expect 0x80000007)
#   0x24: MEPC               (expect address of after_wfi2)
#   0x28: MSTATUS in handler
#   0x2C: expected MEPC      (address of after_wfi2 label)
#   0x30: post-WFI confirm   (0xDEADBEEF proves firmware resumed)
#   0x34: MSTATUS after MRET
#
# Phase 3 (WFI with MIE=0, wakeup without trap):
#   0x40: trap_count before
#   0x44: trap_count after   (should match 0x40)
#   0x48: post-WFI confirm   (0xCAFEBABE proves firmware resumed)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #=================================================================
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
    csrr t2, mstatus

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Save to working area
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    # Check if interrupt or exception
    bltz t0, handle_interrupt

    # Exception: advance MEPC
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, advance_4
    addi t1, t1, 2
    j    exc_done
advance_4:
    addi t1, t1, 4
exc_done:
    csrw mepc, t1
    j    handler_done

handle_interrupt:
    andi t3, t0, 0x1F
    li   t4, 3
    beq  t3, t4, disable_msie
    li   t4, 7
    beq  t3, t4, disable_mtie
    li   t4, 11
    beq  t3, t4, disable_meie
    j    handler_done

disable_msie:
    li   t4, 0x8
    csrc mie, t4
    j    handler_done
disable_mtie:
    li   t4, 0x80
    csrc mie, t4
    j    handler_done
disable_meie:
    li   t4, 0x800
    csrc mie, t4

handler_done:
    li   t4, 1
    sw   t4, 0x10(s1)
    lw   t4, 0x10(s1)         # load-back fence

    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24

    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x48(s1)

    #=================================================================
    # PHASE 1: Install trap handler
    #=================================================================

    la   t0, trap_handler
    csrw mtvec, t0
    csrr t0, mtvec
    sw   t0, 0x18(s1)
    lw   t1, 0x18(s1)

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: WFI + timer interrupt
    #=================================================================

    # Enable MIE.MTIE + MSTATUS.MIE
    li   t0, 0x80
    csrs mie, t0
    li   t0, 0x8
    csrs mstatus, t0

    # Store expected MEPC (= address of instruction after WFI)
    la   t0, after_wfi2
    sw   t0, 0x2C(s1)

    # Clear trap_handled
    sw   zero, 0x10(s1)

    # Signal ready for interrupt
    li   x31, 0x21212121

    # Execute WFI - CPU stalls here until interrupt
    wfi

after_wfi2:
    # If we reach here, WFI completed and handler returned via MRET

    # Store confirmation that firmware resumed
    li   t0, 0xDEADBEEF
    sw   t0, 0x30(s1)

    # Copy saved CSRs to Phase 2 area
    lw   t0, 0x04(s1)
    sw   t0, 0x20(s1)         # MCAUSE
    lw   t0, 0x08(s1)
    sw   t0, 0x24(s1)         # MEPC
    lw   t0, 0x0C(s1)
    sw   t0, 0x28(s1)         # MSTATUS in handler

    # Read MSTATUS after MRET
    csrr t0, mstatus
    sw   t0, 0x34(s1)
    lw   t1, 0x34(s1)         # load-back

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: WFI with MIE=0 (wakeup without trap)
    #=================================================================

    # Disable MSTATUS.MIE
    li   t0, 0x8
    csrc mstatus, t0

    # Re-enable MIE.MTIE (handler disabled it)
    li   t0, 0x80
    csrs mie, t0

    # Save trap_count before
    lw   t0, 0x00(s1)
    sw   t0, 0x40(s1)
    lw   t1, 0x40(s1)         # load-back

    # Signal ready
    li   x31, 0x31313131

    # Execute WFI - should wake up when testbench asserts irq_m_timer
    # but NO trap taken because MSTATUS.MIE=0
    wfi

after_wfi3:
    # Firmware resumes here without going through handler

    # Store confirmation
    li   t0, 0xCAFEBABE
    sw   t0, 0x48(s1)

    # Check trap_count unchanged
    lw   t0, 0x00(s1)
    sw   t0, 0x44(s1)

    # Disable MIE.MTIE before re-enabling global MIE
    li   t0, 0x80
    csrc mie, t0

    # Re-enable MSTATUS.MIE
    li   t0, 0x8
    csrs mstatus, t0

    lw   t1, 0x44(s1)         # load-back

    li   x31, 0x33333333


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
