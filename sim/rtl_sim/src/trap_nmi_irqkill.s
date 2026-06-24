#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_irqkill
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI IRQKILL
#   NMI irqkill verification (2 phases):
#   Phase 1: irqkill enabled (irqkill_cfg default 0x7). NMI fires during
#   a 33-cycle radix-2 DIV — the operation is killed immediately
#   and the NMI handler is entered without waiting for completion.
#   After mnret, division restarts and produces the correct result.
#   Phase 2: irqkill disabled (irqkill_cfg=0x0). NMI fires during another
#   33-cycle DIV — the NMI is held off until the div finishes,
#   then taken. Div result is still correct (no restart needed).
#
#   Scratchpad layout (base 0x80000000):
#   0x00: nmi_count           (incremented each NMI entry)
#   0x04: div_result_p1       (result of phase 1 division after restart)
#   0x08: div_result_p2       (result of phase 2 division)
#   0x0C: nmi_handler_addr    (for testbench to configure nmi_vector)
#   0x10: last_mnepc          (mnepc saved by NMI handler on each entry)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI HANDLER (Smrnmi)
    # Entered when nmi_i asserts and NMIE=1.
    # On entry: hardware clears NMIE, saves PC to mnepc.
    # Increments nmi_count, saves mnepc to scratchpad, then mnret.
    # If the NMI killed a multi-cycle operation, hardware will restart
    # it from the instruction pointed to by mnepc on return.
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
    sw   t1, 0x10(s1)       # last_mnepc

    lw   t1,  0(sp)
    lw   t0,  4(sp)
    addi sp, sp,  8

    .word 0x70200073         # mnret: restore NMIE=1, jump to mnepc


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
    sw   t0, 0x04(s1)          # div_result_p1
    sw   t0, 0x08(s1)          # div_result_p2
    sw   t0, 0x0C(s1)          # nmi_handler_addr
    sw   t0, 0x10(s1)          # last_mnepc

    # Store nmi_handler address for testbench to configure nmi_vector
    la   s2, nmi_handler
    sw   s2, 0x0C(s1)

    # Install a minimal trap handler for mtvec (not expected to fire here,
    # but required for a valid mtvec in case of stray exceptions)
    la   t0, _dummy_trap
    csrw mtvec, t0

    # irqkill_cfg CSR is at 0x7FF.
    # After reset, default is 0x7 (bits[2:0]=1 => muldiv kill enabled).
    # Phase 1 uses this default — no write needed.

    # Enable NMI (NMIE resets to 0 per Smrnmi spec; must be set before NMI can be taken)
    csrsi 0x744, 8             # mnstatus.NMIE = 1

    # Signal: init done, handler address stored
    li   x31, 0x11111111


    #=================================================================
    # PHASE 1: NMI kills in-progress DIV (irqkill enabled, default)
    # irqkill_cfg = 0x7 (default after reset): bit[0]=1 => muldiv kill
    # is active.  Testbench asserts NMI shortly after the sync below.
    # The DIV is a 33-cycle radix-2 division.  With irqkill active the
    # hardware aborts the operation on NMI and enters the handler
    # immediately (nmi_count => 1).  On mnret the DIV restarts from
    # the same instruction and completes normally.
    #
    # Division (unsigned): a0 = 0x80000001, a1 = 3  =>  a2 = 0x2AAAAAAB
    #=================================================================

    # Load dividend and divisor into registers before the sync so that
    # the div instruction immediately follows the sync write.
    li   a0, 0x80000001
    li   a1, 3

    # Signal: phase 1 ready — about to start div (testbench will assert NMI)
    li   x31, 0x12121212
    divu a2, a0, a1            # 33-cycle radix-2 div; NMI may kill this

    # Store phase 1 result (after potential restart)
    sw   a2, 0x04(s1)
    lw   t3, 0x04(s1)          # fence: ensures SW AHB data phase completes before sync

    # Signal: phase 1 done
    li   x31, 0x22222222


    #=================================================================
    # PHASE 2: NMI deferred until DIV completes (irqkill disabled)
    # Write 0x0 to irqkill_cfg (CSR 0x7FF) to disable all irqkill.
    # Testbench then asserts NMI while the same DIV is in progress.
    # With irqkill disabled, the NMI is held pending until the DIV
    # completes; nmi_count goes from 1 to 2 only after the result is
    # written to a2.  Div result is still correct.
    #
    # Division (unsigned): a0 = 0x80000001, a1 = 3  =>  a2 = 0x2AAAAAAB
    #=================================================================

    # Disable irqkill
    csrwi 0x7FF, 0x0

    # Load dividend and divisor before the sync
    li   a0, 0x80000001
    li   a1, 3

    # Signal: phase 2 ready — about to start div (testbench will assert NMI)
    li   x31, 0x23232323
    divu a2, a0, a1            # 33-cycle radix-2 div; NMI deferred until done

    # Store phase 2 result
    sw   a2, 0x08(s1)
    lw   t3, 0x08(s1)          # fence: ensures SW AHB data phase completes before sync

    # Signal: all done
    li   x31, 0xdeadbeef


    #=================================================================
    # DUMMY TRAP HANDLER (should not fire in normal test execution)
    #=================================================================
    .align 2
_dummy_trap:
    mret


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
