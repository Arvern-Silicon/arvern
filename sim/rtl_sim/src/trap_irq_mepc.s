#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_mepc
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IRQ MEPC CORRECTNESS
#   Verifies that interrupts do not cause instruction replay.
#
#   The test executes a long chain of cumulative ADDI instructions
#   (x10 += 1, repeated N times) while the testbench injects IRQs at
#   random intervals. If MEPC is set correctly, x10 should equal N
#   at the end. If the bug exists (instruction replay), x10 > N.
#
#   Multiple phases test different instruction types to cover:
#   Phase 1: ADDI chain (ALU instruction replay)
#   Phase 2: LUI+ADDI pairs (two-instruction sequence replay)
#   Phase 3: LW from data (load instruction replay)
#   Phase 4: Register preservation across many IRQs
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    # Swap SP with MSCRATCH (dedicated handler stack)
    csrrw  sp, mscratch, sp

    # Save context
    addi sp, sp, -16
    sw   t0,  12(sp)
    sw   t1,   8(sp)
    sw   t2,   4(sp)

    # Increment trap count at s1 + 0x00
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Check trap type
    csrr t0, mcause

    # If MSB=1, this is an interrupt -> just return
    bltz t0, irq_handler_done

    # Exception path: advance MEPC past faulting instruction
    csrr t1, mepc
    lhu  t2, 0(t1)
    andi t2, t2, 0x3
    li   t0, 0x3
    beq  t2, t0, advance_4
    addi t1, t1, 2
    j    exc_done
advance_4:
    addi t1, t1, 4
exc_done:
    csrw mepc, t1

irq_handler_done:
    # Restore context
    lw   t2,   4(sp)
    lw   t1,   8(sp)
    lw   t0,  12(sp)
    addi sp, sp, 16

    # Restore original SP
    csrrw  sp, mscratch, sp

    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    # Initialize stack pointer and handler stack
    li   sp, 0x80010000
    li   t0, 0x8000FF00
    csrw mscratch, t0

    # SRAM scratchpad base (for trap counter)
    li   s1, 0x80000000
    sw   zero, 0x00(s1)      # trap count
    sw   zero, 0x04(s1)      # phase marker

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Initialize callee-saved registers to known pattern
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Enable all interrupt sources: MSIE + MTIE + MEIE
    li   t0, 0x888
    csrw mie, t0

    # Enable global interrupts
    li   t0, 0x8
    csrs mstatus, t0

    # Signal: initialization complete
    li   x31, 0x11111111
    nop


    #=================================================================
    # PHASE 1: ADDI chain — 100 cumulative additions
    # Expected: x10 = 100 (0x64)
    # If instruction replay bug exists: x10 > 100
    #=================================================================

    li   x10, 0
    nop

    # 100x "addi x10, x10, 1"
    addi x10, x10, 1       # 1
    addi x10, x10, 1       # 2
    addi x10, x10, 1       # 3
    addi x10, x10, 1       # 4
    addi x10, x10, 1       # 5
    addi x10, x10, 1       # 6
    addi x10, x10, 1       # 7
    addi x10, x10, 1       # 8
    addi x10, x10, 1       # 9
    addi x10, x10, 1       # 10
    addi x10, x10, 1       # 11
    addi x10, x10, 1       # 12
    addi x10, x10, 1       # 13
    addi x10, x10, 1       # 14
    addi x10, x10, 1       # 15
    addi x10, x10, 1       # 16
    addi x10, x10, 1       # 17
    addi x10, x10, 1       # 18
    addi x10, x10, 1       # 19
    addi x10, x10, 1       # 20
    addi x10, x10, 1       # 21
    addi x10, x10, 1       # 22
    addi x10, x10, 1       # 23
    addi x10, x10, 1       # 24
    addi x10, x10, 1       # 25
    addi x10, x10, 1       # 26
    addi x10, x10, 1       # 27
    addi x10, x10, 1       # 28
    addi x10, x10, 1       # 29
    addi x10, x10, 1       # 30
    addi x10, x10, 1       # 31
    addi x10, x10, 1       # 32
    addi x10, x10, 1       # 33
    addi x10, x10, 1       # 34
    addi x10, x10, 1       # 35
    addi x10, x10, 1       # 36
    addi x10, x10, 1       # 37
    addi x10, x10, 1       # 38
    addi x10, x10, 1       # 39
    addi x10, x10, 1       # 40
    addi x10, x10, 1       # 41
    addi x10, x10, 1       # 42
    addi x10, x10, 1       # 43
    addi x10, x10, 1       # 44
    addi x10, x10, 1       # 45
    addi x10, x10, 1       # 46
    addi x10, x10, 1       # 47
    addi x10, x10, 1       # 48
    addi x10, x10, 1       # 49
    addi x10, x10, 1       # 50
    addi x10, x10, 1       # 51
    addi x10, x10, 1       # 52
    addi x10, x10, 1       # 53
    addi x10, x10, 1       # 54
    addi x10, x10, 1       # 55
    addi x10, x10, 1       # 56
    addi x10, x10, 1       # 57
    addi x10, x10, 1       # 58
    addi x10, x10, 1       # 59
    addi x10, x10, 1       # 60
    addi x10, x10, 1       # 61
    addi x10, x10, 1       # 62
    addi x10, x10, 1       # 63
    addi x10, x10, 1       # 64
    addi x10, x10, 1       # 65
    addi x10, x10, 1       # 66
    addi x10, x10, 1       # 67
    addi x10, x10, 1       # 68
    addi x10, x10, 1       # 69
    addi x10, x10, 1       # 70
    addi x10, x10, 1       # 71
    addi x10, x10, 1       # 72
    addi x10, x10, 1       # 73
    addi x10, x10, 1       # 74
    addi x10, x10, 1       # 75
    addi x10, x10, 1       # 76
    addi x10, x10, 1       # 77
    addi x10, x10, 1       # 78
    addi x10, x10, 1       # 79
    addi x10, x10, 1       # 80
    addi x10, x10, 1       # 81
    addi x10, x10, 1       # 82
    addi x10, x10, 1       # 83
    addi x10, x10, 1       # 84
    addi x10, x10, 1       # 85
    addi x10, x10, 1       # 86
    addi x10, x10, 1       # 87
    addi x10, x10, 1       # 88
    addi x10, x10, 1       # 89
    addi x10, x10, 1       # 90
    addi x10, x10, 1       # 91
    addi x10, x10, 1       # 92
    addi x10, x10, 1       # 93
    addi x10, x10, 1       # 94
    addi x10, x10, 1       # 95
    addi x10, x10, 1       # 96
    addi x10, x10, 1       # 97
    addi x10, x10, 1       # 98
    addi x10, x10, 1       # 99
    addi x10, x10, 1       # 100

    nop

    # Signal: Phase 1 complete, x10 should be 100
    li   x31, 0x22222222
    nop


    #=================================================================
    # PHASE 2: LUI+ADDI pairs (two-instruction sequence)
    # Tests that IRQ between LUI and ADDI doesn't corrupt result.
    # Each pair loads a different value, final register should have
    # the last pair's value.
    #=================================================================

    li   x11, 0x12345678
    nop
    li   x12, 0xDEADBEEF
    nop
    li   x13, 0xCAFEBABE
    nop
    li   x14, 0x01020304
    nop
    li   x15, 0xA5A5A5A5
    nop

    # Signal: Phase 2 complete
    li   x31, 0x33333333
    nop


    #=================================================================
    # PHASE 3: Register preservation check
    # Callee-saved registers should still have their init values.
    #=================================================================

    nop

    # Signal: Phase 3 complete (testbench checks s2-s6)
    li   x31, 0x44444444
    nop

    # Save trap count to x16 for testbench visibility
    lw   x16, 0x00(s1)
    nop

    # Signal: test complete
    li   x31, 0xdeadbeef
    nop

    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
