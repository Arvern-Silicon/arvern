#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_priority
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI PRIORITY
#   NMI priority verification (3 phases):
#   Phase 1: NMI fires when MSTATUS.MIE=0 (NMI is not gated by MIE)
#   Phase 2: NMI wins over simultaneous timer IRQ (NMI has higher priority)
#   Phase 3: NMI fires during countdown loop, before illegal instruction
#   exception (NMI is taken, then exception fires after mnret)
#
#   Scratchpad layout (base 0x80000000):
#   0x00: nmi_count           (incremented each NMI entry)
#   0x04: irq_count           (incremented each IRQ entry)
#   0x08: exc_count           (incremented each exception entry)
#   0x0C: last_mnepc          (mnepc saved by NMI handler on each entry)
#   0x10: last_mcause         (mcause saved by trap handler on each entry)
#   0x14: nmi_handler_addr    (for testbench to configure nmi_vector)
#   0x18: exc_inst_addr_p3    (address of phase 3 exception instruction)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI HANDLER (Smrnmi)
    # Entered when nmi_i asserts and NMIE=1.
    # On entry: hardware clears NMIE, saves PC to mnepc.
    # Saves mnepc to scratchpad, increments nmi_count.
    # Issues mnret to resume at interrupted PC.
    #=================================================================
    .align 2

nmi_handler:
    addi sp, sp, -8
    sw   t0,  4(sp)
    sw   t1,  0(sp)

    # Increment nmi_count
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Save MNEPC (address of interrupted instruction)
    csrr t1, 0x741          # mnepc = 0x741
    sw   t1, 0x0C(s1)

    lw   t1,  0(sp)
    lw   t0,  4(sp)
    addi sp, sp,  8

    .word 0x70200073         # mnret: restore NMIE=1, jump to mnepc

    #=================================================================
    # TRAP HANDLER (regular exceptions and IRQs via mtvec)
    # Handles both synchronous exceptions and asynchronous interrupts.
    # For interrupts: increments irq_count, disables the fired source.
    # For exceptions: increments exc_count, advances MEPC past the
    #                 faulting instruction (2-byte or 4-byte).
    #=================================================================
    .align 2

trap_handler:
    # Save context on stack
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)
    sw   t3,  0(sp)

    # Read mcause and save to scratchpad
    csrr t0, mcause
    sw   t0, 0x10(s1)

    # Check if this is an interrupt (MCAUSE MSB = 1)
    bltz t0, handle_irq

    # ---- Exception path: advance MEPC ----
    exc_inc:
    lw   t1, 0x08(s1)
    addi t1, t1, 1
    sw   t1, 0x08(s1)

    csrr t1, mepc
    # Read low 16 bits to determine instruction size
    lhu  t2, 0(t1)
    andi t2, t2, 0x3
    li   t3, 0x3
    beq  t2, t3, exc_skip4
    addi t1, t1, 2
    j    exc_done
exc_skip4:
    addi t1, t1, 4
exc_done:
    csrw mepc, t1
    j    handler_done

    # ---- IRQ path: disable the fired source ----
handle_irq:
    lw   t1, 0x04(s1)
    addi t1, t1, 1
    sw   t1, 0x04(s1)

    andi t1, t0, 0x1F         # extract cause code (bits 4:0)

    li   t2, 3
    beq  t1, t2, disable_msie
    li   t2, 7
    beq  t1, t2, disable_mtie
    li   t2, 11
    beq  t1, t2, disable_meie
    j    handler_done          # unknown cause

disable_msie:
    csrc mie, 8                # MIE.MSIE = bit 3 (fits in 5-bit immediate)
    j    handler_done

disable_mtie:
    li   t2, 0x80              # MIE.MTIE = bit 7 (> 5-bit, must use register)
    csrc mie, t2
    j    handler_done

disable_meie:
    li   t2, 0x800             # MIE.MEIE = bit 11 (> 5-bit, must use register)
    csrc mie, t2

handler_done:
    lw   t3,  0(sp)
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16

    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    # Initialize stack pointer
    li   sp, 0x80010000

    # Initialize scratchpad base pointer (kept throughout test)
    li   s1, 0x80000000

    # Zero scratchpad area
    li   t0, 0
    sw   t0, 0x00(s1)          # nmi_count
    sw   t0, 0x04(s1)          # irq_count
    sw   t0, 0x08(s1)          # exc_count
    sw   t0, 0x0C(s1)          # last_mnepc
    sw   t0, 0x10(s1)          # last_mcause
    sw   t0, 0x14(s1)          # nmi_handler_addr
    sw   t0, 0x18(s1)          # exc_inst_addr_p3

    # Store nmi_handler address for testbench to configure nmi_vector
    la   t0, nmi_handler
    sw   t0, 0x14(s1)

    # Install trap handler for regular exceptions and IRQs
    la   t0, trap_handler
    csrw mtvec, t0

    # Enable NMI (NMIE resets to 0 per Smrnmi spec; must be set before NMI can be taken)
    csrsi 0x744, 8             # mnstatus.NMIE = 1

    # Signal: init done, handler addresses stored
    li   x31, 0x11111111


    #=================================================================
    # PHASE 1: NMI fires when MSTATUS.MIE=0
    # MIE is 0 by default after reset. The testbench asserts nmi
    # while we are in the wait loop below. NMI is not gated by MIE,
    # so the handler must run and increment nmi_count to 1.
    #=================================================================

p1_wait_nmi:
    li   t0, 10000
p1_poll:
    addi t0, t0, -1
    bnez t0, p1_poll
    # Check if NMI was already taken
    lw   t0, 0x00(s1)          # nmi_count
    beqz t0, p1_wait_nmi

    # Signal: Phase 1 done (nmi_count >= 1 observed)
    li   x31, 0x12121212


    #=================================================================
    # PHASE 2: NMI wins over simultaneous timer IRQ
    # Enable MTIE + global MIE, then signal the testbench to assert
    # both NMI and irq_m_timer simultaneously. NMI should be taken first
    # (nmi_count => 2). After NMI returns, the timer IRQ is still
    # pending and gets served (irq_count => 1).
    #=================================================================

    # Enable MIE.MTIE (bit 7; > 5-bit, use register)
    li   t0, 0x80
    csrs mie, t0

    # Enable MSTATUS.MIE (bit 3; fits in 5-bit)
    csrs mstatus, 8

    # Signal: ready for testbench to assert NMI + irq_m_timer simultaneously
    li   x31, 0x22222222

    # Wait until nmi_count >= 2
p2_wait_nmi:
    lw   t0, 0x00(s1)          # nmi_count
    li   t1, 2
    blt  t0, t1, p2_wait_nmi

    # Wait until irq_count >= 1
p2_wait_irq:
    lw   t0, 0x04(s1)          # irq_count
    beqz t0, p2_wait_irq

    # Disable MSTATUS.MIE before next phase
    csrc mstatus, 8

    # Signal: Phase 2 done
    li   x31, 0x23232323


    #=================================================================
    # PHASE 3: NMI fires in countdown loop before exception instruction
    # Testbench asserts NMI immediately after Phase 2 (no extra sync
    # needed). The NMI fires somewhere in the countdown loop
    # (nmi_count => 3). After mnret the loop eventually exits and we
    # execute an illegal instruction (.word 0xFFFFFFFF) which triggers
    # the trap handler (exc_count => 1, last_mcause = 2). last_mnepc
    # must point somewhere before p3_exc_inst.
    #=================================================================

    # Countdown loop — NMI fires somewhere here
    # (testbench asserts NMI right after Phase 2 done sync)
p3_wait_nmi:
    li   t0, 10000
p3_poll:
    addi t0, t0, -1
    bnez t0, p3_poll
    # Check if nmi_count has reached 3
    lw   t0, 0x00(s1)          # nmi_count
    li   t1, 3
    blt  t0, t1, p3_wait_nmi

    # Signal: NMI taken; testbench should deassert NMI here
    li   x31, 0x34343434

    # Store the address of the upcoming illegal instruction for the testbench
    la   t0, p3_exc_inst
    sw   t0, 0x18(s1)

    # Execute illegal instruction — trap_handler will advance MEPC past it
p3_exc_inst:
    .word 0xFFFFFFFF

    # Signal: all phases complete
    li   x31, 0xdeadbeef


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
