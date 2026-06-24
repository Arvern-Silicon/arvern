#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_kill_muldiv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP IRQ KILL MUL/DIV
#   Verifies that IRQs correctly abort and restart MUL/DIV operations:
#   Phase 1: Init
#   Phase 2: DIV interrupted by IRQ, result correct after restart
#   Phase 3: MUL interrupted by IRQ, result correct after restart
#   Phase 4: Repeated DIV loop with continuous IRQs
#   Phase 5: Repeated MUL loop with continuous IRQs
#   Phase 6: DIV latency measurement WITHOUT kill
#   Phase 7: DIV latency measurement WITH kill
#   Phase 8: Register preservation check
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
#   0x14: handler_mode (0=disable MIE source, 1=pulse mode, don't disable)
#
# Phase 2 (DIV single):
#   0x20: DIV  result (expect  7 / 3 = 2)
#   0x24: REM  result (expect  7 % 3 = 1)
#   0x28: DIVU result (expect 0xFFFFFFF9 / 3 = 0x55555553)
#   0x2C: REMU result (expect 0xFFFFFFF9 % 3 = 0)
#   0x30: trap_count after phase 2
#
# Phase 3 (MUL single):
#   0x40: MUL    result (expect 0x12345678 * 0xABCDEF01 low32)
#   0x44: MULH   result (expect signed high32)
#   0x48: MULHU  result (expect unsigned high32)
#   0x4C: MULHSU result (expect signed*unsigned high32)
#   0x50: trap_count after phase 3
#
# Phase 4 (DIV loop):
#   0x60: loop iteration count completed
#   0x64: last DIV result
#   0x68: trap_count after phase 4
#
# Phase 5 (MUL loop):
#   0x70: loop iteration count completed
#   0x74: last MUL result
#   0x78: trap_count after phase 5
#
# Phase 6 (DIV latency, no kill):
#   0x80: loop iteration count (expect 20)
#   0x84: trap_count after phase 6
#
# Phase 7 (DIV latency, with kill):
#   0x90: loop iteration count (expect 20)
#   0x94: trap_count after phase 7
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    # Save context on stack
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    # Read trap CSRs
    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mstatus

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Store to "last" working area
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)

    # Check if interrupt or exception
    bltz t0, handle_irq

    # ---- Exception path: should not happen in this test ----
    # Advance MEPC past instruction (compressed or standard)
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, advance_4b
    addi t1, t1, 2
    j    mepc_done
advance_4b:
    addi t1, t1, 4
mepc_done:
    csrw mepc, t1
    j    handler_done

handle_irq:
    # Check handler_mode: if pulse mode (!=0), don't disable MIE bits
    lw   t3, 0x14(s1)
    bnez t3, handler_done

    # Disable the specific MIE bit for the interrupt source
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
    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)

    # Restore context
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
    # Initialize stack pointer
    li   sp, 0x80010000

    # Initialize scratchpad base pointer
    li   s1, 0x80000000

    # Zero scratchpad area
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x48(s1)
    sw   t0, 0x4C(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x64(s1)
    sw   t0, 0x68(s1)
    sw   t0, 0x70(s1)
    sw   t0, 0x74(s1)
    sw   t0, 0x78(s1)
    sw   t0, 0x80(s1)
    sw   t0, 0x84(s1)
    sw   t0, 0x90(s1)
    sw   t0, 0x94(s1)

    #=================================================================
    # PHASE 1: Install trap handler, initialize registers
    #=================================================================

    # Install trap handler (direct mode)
    la   t0, trap_handler
    csrw mtvec, t0

    # Enable MSTATUS.MIE
    li   t0, 0x8
    csrs mstatus, t0

    # Enable IRQ kill feature: [0]=kill_muldiv, [1]=kill_uop, [2]=livelock_protect
    li   t0, 0x7
    csrw 0x7FF, t0

    # Initialize callee-saved registers to known pattern
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    # Signal: Phase 1 init complete
    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: Single DIV operations with IRQ
    #   Testbench fires timer IRQ while DIV is executing.
    #   After handler returns, DIV restarts and produces correct result.
    #=================================================================

    # Enable MIE.MTIE
    li   t0, 0x80
    csrs mie, t0

    # Clear trap state
    sw   zero, 0x10(s1)
    sw   zero, 0x00(s1)

    # Signal: ready for DIV + IRQ
    li   x31, 0x21212121

    # Delay to let testbench prepare
    nop
    nop

    # Execute DIV operations (testbench fires IRQ during these)
    li   a0, 7
    li   a1, 3
    div  a2, a0, a1         # 7 / 3 = 2
    rem  a3, a0, a1         # 7 % 3 = 1

    li   a0, 0xFFFFFFF9     # -7 unsigned = 4294967289
    li   a1, 3
    divu a4, a0, a1         # 4294967289 / 3 = 0x55555553
    remu a5, a0, a1         # 4294967289 % 3 = 0

    # Store results
    sw   a2, 0x20(s1)
    sw   a3, 0x24(s1)
    sw   a4, 0x28(s1)
    sw   a5, 0x2C(s1)

    # Store trap_count
    lw   t0, 0x00(s1)
    sw   t0, 0x30(s1)

    # Signal: Phase 2 complete
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: Single MUL operations with IRQ
    #   Same pattern: testbench fires IRQ during MUL execution.
    #=================================================================

    # Re-enable MIE.MTIE
    li   t0, 0x80
    csrs mie, t0

    # Clear trap state
    sw   zero, 0x10(s1)

    # Signal: ready for MUL + IRQ
    li   x31, 0x31313131

    # Delay to let testbench prepare
    nop
    nop

    # Execute MUL operations
    li   a0, 0x12345678
    li   a1, 0xABCDEF01
    mul    a2, a0, a1       # low 32 bits
    mulh   a3, a0, a1       # signed high 32 bits
    mulhu  a4, a0, a1       # unsigned high 32 bits
    mulhsu a5, a0, a1       # signed*unsigned high 32 bits

    # Store results
    sw   a2, 0x40(s1)
    sw   a3, 0x44(s1)
    sw   a4, 0x48(s1)
    sw   a5, 0x4C(s1)

    # Store trap_count
    lw   t0, 0x00(s1)
    sw   t0, 0x50(s1)

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: DIV loop with continuous IRQs
    #   Run 100 DIV operations while testbench continuously fires IRQs.
    #   Verify all results are correct.
    #=================================================================

    # Re-enable MIE.MTIE + MIE.MEIE + MIE.MSIE
    li   t0, 0x888
    csrs mie, t0

    # Clear trap state
    sw   zero, 0x10(s1)

    # Signal: ready for DIV loop + continuous IRQs
    li   x31, 0x41414141

    # DIV loop: compute (i * 17 + 5) / 7 for i=0..99
    li   s7, 0              # loop counter
    li   s8, 100            # loop limit

div_loop:
    bge  s7, s8, div_loop_done

    # Compute dividend = i * 17 + 5
    li   t1, 17
    mul  t0, s7, t1
    addi t0, t0, 5

    # DIV: result = dividend / 7
    li   t1, 7
    div  t2, t0, t1

    # REM: result = dividend % 7
    rem  t3, t0, t1

    # Verify: dividend == quotient * 7 + remainder
    li   t4, 7
    mul  t4, t2, t4
    add  t4, t4, t3
    bne  t4, t0, div_verify_fail

    addi s7, s7, 1
    j    div_loop

div_verify_fail:
    # Store failure marker
    li   t0, 0xDEAD0001
    sw   t0, 0x60(s1)
    j    div_loop_store

div_loop_done:
    sw   s7, 0x60(s1)       # store iteration count (expect 100)

div_loop_store:
    sw   t2, 0x64(s1)       # store last DIV result

    # Store trap_count
    lw   t0, 0x00(s1)
    sw   t0, 0x68(s1)

    # Signal: Phase 4 complete
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: MUL loop with continuous IRQs
    #   Run 100 MUL operations while testbench fires IRQs.
    #   Verify all results are correct using known identity.
    #=================================================================

    # Re-enable all IRQ bits
    li   t0, 0x888
    csrs mie, t0

    # Clear trap state
    sw   zero, 0x10(s1)

    # Signal: ready for MUL loop + continuous IRQs
    li   x31, 0x51515151

    # MUL loop: compute (i+1) * (i+1) for i=0..99, verify via add
    li   s7, 0              # loop counter
    li   s8, 100            # loop limit

mul_loop:
    bge  s7, s8, mul_loop_done

    # Compute (i+1) * (i+1)
    addi t0, s7, 1
    mul  t1, t0, t0         # (i+1)^2

    # Verify: (i+1)^2 == i^2 + 2*i + 1 == i*(i+2) + 1
    addi t2, s7, 2
    mul  t3, s7, t2         # i * (i+2)
    addi t3, t3, 1          # i*(i+2) + 1

    bne  t1, t3, mul_verify_fail

    addi s7, s7, 1
    j    mul_loop

mul_verify_fail:
    # Store failure marker
    li   t0, 0xDEAD0002
    sw   t0, 0x70(s1)
    j    mul_loop_store

mul_loop_done:
    sw   s7, 0x70(s1)       # store iteration count (expect 100)

mul_loop_store:
    sw   t1, 0x74(s1)       # store last MUL result (100*100 = 10000 = 0x2710)

    # Store trap_count
    lw   t0, 0x00(s1)
    sw   t0, 0x78(s1)

    # Signal: Phase 5 complete
    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: DIV latency measurement WITHOUT kill
    #   Run DIV loop without IRQ kill feature. Testbench measures
    #   IRQ response latency when DIV must complete before trap.
    #=================================================================

    # Disable IRQ kill feature
    li   t0, 0x0
    csrw 0x7FF, t0

    # Re-enable MIE.MTIE + MIE.MEIE
    li   t0, 0x880
    csrs mie, t0

    # Set handler to pulse mode (don't disable MIE source)
    li   t0, 1
    sw   t0, 0x14(s1)

    # Clear trap state
    sw   zero, 0x10(s1)
    sw   zero, 0x00(s1)

    # Signal: ready for no-kill DIV latency
    li   x31, 0x61616161

    # DIV loop: 20 iterations of (i*17+5) / 7
    li   s7, 0
    li   s8, 20

nokill_div_loop:
    bge  s7, s8, nokill_div_done

    li   t1, 17
    mul  t0, s7, t1
    addi t0, t0, 5

    li   t1, 7
    div  t2, t0, t1
    rem  t3, t0, t1

    # Verify: dividend == quotient * 7 + remainder
    li   t4, 7
    mul  t4, t2, t4
    add  t4, t4, t3
    bne  t4, t0, nokill_div_fail

    addi s7, s7, 1
    j    nokill_div_loop

nokill_div_fail:
    li   t0, 0xDEAD0006
    sw   t0, 0x80(s1)
    j    nokill_div_store

nokill_div_done:
    sw   s7, 0x80(s1)       # store iteration count (expect 20)

nokill_div_store:
    lw   t0, 0x00(s1)
    sw   t0, 0x84(s1)       # store trap_count

    # Signal: Phase 6 complete
    li   x31, 0x62626262


    #=================================================================
    # PHASE 7: DIV latency measurement WITH kill
    #   Run same DIV loop with IRQ kill enabled. Testbench measures
    #   IRQ response latency when DIV is aborted immediately.
    #=================================================================

    # Enable IRQ kill feature
    li   t0, 0x7
    csrw 0x7FF, t0

    # Re-enable MIE.MTIE + MIE.MEIE
    li   t0, 0x880
    csrs mie, t0

    # Set handler to pulse mode
    li   t0, 1
    sw   t0, 0x14(s1)

    # Clear trap state
    sw   zero, 0x10(s1)
    sw   zero, 0x00(s1)

    # Signal: ready for kill DIV latency
    li   x31, 0x71717171

    # DIV loop: 20 iterations of (i*17+5) / 7
    li   s7, 0
    li   s8, 20

kill_div_loop:
    bge  s7, s8, kill_div_done

    li   t1, 17
    mul  t0, s7, t1
    addi t0, t0, 5

    li   t1, 7
    div  t2, t0, t1
    rem  t3, t0, t1

    # Verify: dividend == quotient * 7 + remainder
    li   t4, 7
    mul  t4, t2, t4
    add  t4, t4, t3
    bne  t4, t0, kill_div_fail

    addi s7, s7, 1
    j    kill_div_loop

kill_div_fail:
    li   t0, 0xDEAD0007
    sw   t0, 0x90(s1)
    j    kill_div_store

kill_div_done:
    sw   s7, 0x90(s1)       # store iteration count (expect 20)

kill_div_store:
    lw   t0, 0x00(s1)
    sw   t0, 0x94(s1)       # store trap_count

    # Signal: Phase 7 complete
    li   x31, 0x72727272


    #=================================================================
    # PHASE 8: Final register preservation check
    #=================================================================

    # Disable all interrupts
    li   t0, 0xFFFFFFFF
    csrc mie, t0

    # Reset handler_mode to default
    sw   zero, 0x14(s1)

    # Signal: end of test (testbench checks callee-saved regs)
    li   x31, 0x88888888


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
