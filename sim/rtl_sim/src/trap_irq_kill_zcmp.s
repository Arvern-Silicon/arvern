#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_kill_zcmp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP IRQ KILL ZCMP
#   Verifies that IRQs correctly abort and restart Zcmp UOP operations:
#   Phase 1: Init
#   Phase 2: CM.PUSH with IRQ bombardment (UOP kill)
#   Phase 3: CM.POP with IRQ bombardment (UOP kill)
#   Phase 4: CM.POPRET with IRQ bombardment (UOP kill)
#   Phase 5: CM.PUSH latency measurement WITHOUT kill
#   Phase 6: CM.PUSH latency measurement WITH kill
#   Phase 7: Register preservation check
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
#   0x14: handler_mode (0=disable MIE source, 1=pulse mode)
#
# Phase 2 (CM.PUSH):
#   0x20: SP after push
#   0x24: stack[ra]
#   0x28: stack[s0]
#   0x2C: trap_count after phase 2
#
# Phase 3 (CM.POP):
#   0x40: ra after pop
#   0x44: s0 after pop
#   0x48: SP after pop
#   0x4C: trap_count after phase 3
#
# Phase 4 (CM.POPRET):
#   0x60: arrival flag
#   0x64: s0 after popret
#   0x68: SP after popret
#   0x6C: trap_count after phase 4
#
# Phase 5 (CM.PUSH latency, no kill):
#   0x80: SP after push (expect 0x80007FE0)
#   0x84: trap_count after phase 5
#
# Phase 6 (CM.PUSH latency, with kill):
#   0x90: SP after push (expect 0x80007FE0)
#   0x94: trap_count after phase 6
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
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x48(s1)
    sw   t0, 0x4C(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x64(s1)
    sw   t0, 0x68(s1)
    sw   t0, 0x6C(s1)
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
    # PHASE 2: CM.PUSH with IRQ bombardment (UOP kill)
    #   Execute cm.push {ra, s0}, -32 while testbench fires rapid IRQs.
    #   Verify stack contents are correct after push completes.
    #   Note: avoid clobbering s1 (scratchpad ptr used by trap handler)
    #=================================================================

    # Re-enable MIE.MTIE + MIE.MEIE
    li   t0, 0x880
    csrs mie, t0

    # Clear trap state
    sw   zero, 0x10(s1)
    sw   zero, 0x00(s1)

    # Set handler to pulse mode (don't disable MIE source)
    li   t0, 1
    sw   t0, 0x14(s1)

    # Signal: ready for CM.PUSH + IRQ
    li   x31, 0x21212121

    # Save callee-saved regs we will clobber
    addi sp, sp, -20
    sw   s2, 16(sp)
    sw   s3, 12(sp)
    sw   s4,  8(sp)
    sw   s5,  4(sp)
    sw   s6,  0(sp)

    # Load test values into registers that cm.push will save
    li   ra, 0xAA110011
    li   s0, 0xBB220022

    # Save main sp, switch to UOP test stack
    mv   s4, sp
    li   sp, 0x80008000

    # Execute cm.push under IRQ bombardment
    nop
    cm.push {ra, s0}, -32

    # Save SP value after push
    mv   a0, sp             # a0 = new SP (expect 0x80008000 - 32 = 0x80007FE0)

    # Read back stack contents to verify
    # cm.push {ra, s0}, -32: ra at [SP+24], s0 at [SP+28]
    lw   a1, 24(sp)         # ra  at [SP+24]
    lw   a2, 28(sp)         # s0  at [SP+28]

    # Restore main stack pointer
    mv   sp, s4

    # Store results to scratchpad
    sw   a0, 0x20(s1)       # SP after push
    sw   a1, 0x24(s1)       # stack[ra]
    sw   a2, 0x28(s1)       # stack[s0]

    # Store trap_count
    lw   t0, 0x00(s1)
    sw   t0, 0x2C(s1)

    # Restore callee-saved registers
    lw   s2, 16(sp)
    lw   s3, 12(sp)
    lw   s4,  8(sp)
    lw   s5,  4(sp)
    lw   s6,  0(sp)
    addi sp, sp, 20

    # Signal: Phase 2 complete
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: CM.POP with IRQ bombardment (UOP kill)
    #   Set up stack with known values, execute cm.pop {ra, s0}, 32
    #   under IRQs, verify registers loaded correctly.
    #   Note: avoid clobbering s1 (scratchpad ptr used by trap handler)
    #=================================================================

    # Re-enable MIE.MTIE + MIE.MEIE
    li   t0, 0x880
    csrs mie, t0

    # Clear trap state
    sw   zero, 0x10(s1)
    sw   zero, 0x00(s1)

    # Keep handler in pulse mode
    li   t0, 1
    sw   t0, 0x14(s1)

    # Signal: ready for CM.POP + IRQ
    li   x31, 0x31313131

    # Save callee-saved registers on main stack
    addi sp, sp, -20
    sw   s2, 16(sp)
    sw   s3, 12(sp)
    sw   s4,  8(sp)
    sw   s5,  4(sp)
    sw   s6,  0(sp)

    # Set up UOP test stack with known values
    # cm.pop {ra, s0}, 32 reads from:
    #   ra  at [SP+24]
    #   s0  at [SP+28]
    li   a0, 0x80008100     # UOP test SP for pop
    li   t0, 0x11CAFE11
    sw   t0, 24(a0)         # ra value
    li   t0, 0x22CAFE22
    sw   t0, 28(a0)         # s0 value

    # Set registers to different pattern (to confirm pop overwrites them)
    li   ra, 0xDEAD0001
    li   s0, 0xDEAD0002

    # Save main sp, switch to UOP test stack
    mv   s4, sp
    li   sp, 0x80008100

    nop
    cm.pop {ra, s0}, 32

    # Save results before restoring anything
    mv   a0, ra             # ra after pop
    mv   a1, s0             # s0 after pop
    mv   a2, sp             # SP after pop (expect 0x80008100 + 32 = 0x80008120)

    # Restore main stack pointer
    mv   sp, s4

    # Store results to scratchpad
    sw   a0, 0x40(s1)       # ra after pop
    sw   a1, 0x44(s1)       # s0 after pop
    sw   a2, 0x48(s1)       # SP after pop

    # Store trap_count
    lw   t0, 0x00(s1)
    sw   t0, 0x4C(s1)

    # Restore callee-saved registers
    lw   s2, 16(sp)
    lw   s3, 12(sp)
    lw   s4,  8(sp)
    lw   s5,  4(sp)
    lw   s6,  0(sp)
    addi sp, sp, 20

    # Signal: Phase 3 complete
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: CM.POPRET with IRQ bombardment (UOP kill)
    #   Set up stack with known values including return address,
    #   execute cm.popret {ra, s0}, 32 under IRQs, verify registers
    #   and PC target. Avoids clobbering s1 (scratchpad ptr).
    #=================================================================

    # Re-enable MIE.MTIE + MIE.MEIE
    li   t0, 0x880
    csrs mie, t0

    # Clear trap state
    sw   zero, 0x10(s1)
    sw   zero, 0x00(s1)

    # Keep handler in pulse mode
    li   t0, 1
    sw   t0, 0x14(s1)

    # Signal: ready for CM.POPRET + IRQ
    li   x31, 0x41414141

    # Save callee-saved registers on main stack
    addi sp, sp, -20
    sw   s2, 16(sp)
    sw   s3, 12(sp)
    sw   s4,  8(sp)
    sw   s5,  4(sp)
    sw   s6,  0(sp)

    # Set up UOP test stack with known values
    # cm.popret {ra, s0}, 32 reads from:
    #   ra  at [SP+24]
    #   s0  at [SP+28]
    li   a0, 0x80008200     # UOP test SP for popret

    la   t0, popret_target
    sw   t0, 24(a0)         # ra = address of popret_target
    li   t0, 0xAA00BB00
    sw   t0, 28(a0)         # s0 value

    # Set registers to different pattern
    li   ra, 0xDEAD0003
    li   s0, 0xDEAD0004

    mv   s4, sp             # save main sp in s4

    # Set SP and execute popret
    li   sp, 0x80008200

    nop
    cm.popret {ra, s0}, 32

    # Should NOT reach here - popret jumps to popret_target
    li   a0, 0xDEADDEAD
    j    popret_done

popret_target:
    # We arrived via cm.popret - success!
    li   a0, 1              # arrival flag

popret_done:
    # Save results
    mv   a1, s0             # s0 after popret
    mv   a2, sp             # SP after popret (expect 0x80008200 + 32 = 0x80008220)

    # Restore main stack pointer
    mv   sp, s4

    # Store results to scratchpad (s1 is still valid)
    sw   a0, 0x60(s1)       # arrival flag
    sw   a1, 0x64(s1)       # s0 after popret
    sw   a2, 0x68(s1)       # SP after popret

    # Store trap_count
    lw   t0, 0x00(s1)
    sw   t0, 0x6C(s1)

    # Restore callee-saved registers
    lw   s2, 16(sp)
    lw   s3, 12(sp)
    lw   s4,  8(sp)
    lw   s5,  4(sp)
    lw   s6,  0(sp)
    addi sp, sp, 20

    # Signal: Phase 4 complete
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: CM.PUSH latency measurement WITHOUT kill
    #   Execute CM.PUSH repeatedly without kill feature. Testbench
    #   measures IRQ response latency when UOP must complete.
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

    # Signal: ready for no-kill CM.PUSH latency
    li   x31, 0x51515151

    # Save callee-saved regs
    addi sp, sp, -20
    sw   s2, 16(sp)
    sw   s3, 12(sp)
    sw   s4,  8(sp)
    sw   s5,  4(sp)
    sw   s6,  0(sp)

    # Run CM.PUSH 20 times in a loop
    li   s7, 0
    li   s8, 20

nokill_push_loop:
    bge  s7, s8, nokill_push_done

    # Set known values
    li   ra, 0xAA110011
    li   s0, 0xBB220022

    # Switch to UOP test stack
    mv   s4, sp
    li   sp, 0x80008000

    nop
    cm.push {ra, s0}, -32

    # Save SP result (only on last iteration)
    mv   a0, sp
    mv   sp, s4

    addi s7, s7, 1
    j    nokill_push_loop

nokill_push_done:
    # Store SP from last push
    sw   a0, 0x80(s1)

    # Store trap_count
    lw   t0, 0x00(s1)
    sw   t0, 0x84(s1)

    # Restore callee-saved registers
    lw   s2, 16(sp)
    lw   s3, 12(sp)
    lw   s4,  8(sp)
    lw   s5,  4(sp)
    lw   s6,  0(sp)
    addi sp, sp, 20

    # Signal: Phase 5 complete
    li   x31, 0x52525252


    #=================================================================
    # PHASE 6: CM.PUSH latency measurement WITH kill
    #   Same CM.PUSH loop with kill enabled. Testbench measures
    #   IRQ response latency when UOP is aborted immediately.
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

    # Signal: ready for kill CM.PUSH latency
    li   x31, 0x61616161

    # Save callee-saved regs
    addi sp, sp, -20
    sw   s2, 16(sp)
    sw   s3, 12(sp)
    sw   s4,  8(sp)
    sw   s5,  4(sp)
    sw   s6,  0(sp)

    # Run CM.PUSH 20 times in a loop
    li   s7, 0
    li   s8, 20

kill_push_loop:
    bge  s7, s8, kill_push_done

    # Set known values
    li   ra, 0xAA110011
    li   s0, 0xBB220022

    # Switch to UOP test stack
    mv   s4, sp
    li   sp, 0x80008000

    nop
    cm.push {ra, s0}, -32

    # Save SP result (only on last iteration)
    mv   a0, sp
    mv   sp, s4

    addi s7, s7, 1
    j    kill_push_loop

kill_push_done:
    # Store SP from last push
    sw   a0, 0x90(s1)

    # Store trap_count
    lw   t0, 0x00(s1)
    sw   t0, 0x94(s1)

    # Restore callee-saved registers
    lw   s2, 16(sp)
    lw   s3, 12(sp)
    lw   s4,  8(sp)
    lw   s5,  4(sp)
    lw   s6,  0(sp)
    addi sp, sp, 20

    # Signal: Phase 6 complete
    li   x31, 0x62626262


    #=================================================================
    # PHASE 7: Final register preservation check
    #=================================================================

    # Disable all interrupts
    li   t0, 0xFFFFFFFF
    csrc mie, t0

    # Reset handler_mode to default
    sw   zero, 0x14(s1)

    # Signal: end of test (testbench checks callee-saved regs)
    li   x31, 0x77777777


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
