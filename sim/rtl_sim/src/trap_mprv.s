#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_mprv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MPRV
#   MSTATUS.MPRV verification:
#   Phase 1: M-mode store with MPRV=0 (normal: privileged access)
#   Phase 2: M-mode store with MPRV=1, MPP=U (U-mode access on AHB)
#   Phase 3: M-mode store with MPRV=1, MPP=S (S-mode access on AHB)
#   Phase 4: M-mode store with MPRV=1, MPP=M (M-mode access on AHB)
#   Phase 5: MPRV cleared on MRET to S-mode (MPP!=M)
#   Phase 6: MPRV NOT cleared on MRET to M-mode (MPP=M)
#   Phase 7: Back-to-back CSR write + store (timing check)
#
#   Convention: a0 controls trap handler return behavior:
#   a0 = 0  →  normal return (same privilege mode)
#   a0 = 1  →  return to M-mode (set MPP = 11)
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Probe store addresses (firmware stores here, testbench captures HPROT):
#   0x100: Phase 1 probe store (MPRV=0, M-mode)
#   0x104: Phase 2 probe store (MPRV=1, MPP=U)
#   0x108: Phase 3 probe store (MPRV=1, MPP=S)
#   0x10C: Phase 4 probe store (MPRV=1, MPP=M)
#   0x110: Phase 5 probe store (after MRET cleared MPRV, back in M-mode)
#   0x114: Phase 7 probe store (back-to-back CSR write + store)
#
# Result storage (firmware stores MSTATUS snapshots):
#   0x200: Phase 1 MSTATUS
#   0x204: Phase 2 MSTATUS
#   0x208: Phase 3 MSTATUS
#   0x20C: Phase 4 MSTATUS
#   0x210: Phase 5 MSTATUS (after MRET cleared MPRV, back in M-mode)
#   0x214: Phase 6 MSTATUS (after MRET to M-mode, MPRV preserved)
#   0x218: Phase 7 MSTATUS
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc

    # Check if interrupt (MSB set)
    bltz t0, m_handler_irq

    # Synchronous exception: advance MEPC past ECALL (4 bytes)
    addi t1, t1, 4
    csrw mepc, t1

    # If a0 == 1, return to M-mode (set MPP = 11)
    li   t4, 1
    bne  a0, t4, m_handler_done
    li   t4, 0x1800
    csrs mstatus, t4           # Set MPP = 11
    j    m_handler_done

m_handler_irq:
    # Interrupt: don't advance MEPC, just return
    j    m_handler_done

m_handler_done:
    lw   t4,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    li   s2, 0xDEADBEEF        # Probe store value

    # Smrnmi: mnstatus.NMIE resets to 0, and while NMIE=0 the hart must
    # behave as though MPRV were clear (RISC-V Priv spec). This test
    # exercises MPRV in normal M-mode (not an RNMI handler), so NMIE must
    # be 1 for MPRV to take effect on NMI_EN=1 builds (the default config).
    csrsi 0x744, 8             # set mnstatus.NMIE (bit 3)


    #=================================================================
    # PHASE 1: M-mode store with MPRV=0 (normal privileged access)
    #          Expected: HPROT[1]=1 (privileged), HSMODE=0
    #=================================================================

    # Ensure MPRV=0
    li   t0, 0x20000            # MPRV bit (bit 17)
    csrc mstatus, t0

    # Snapshot MSTATUS
    csrr t0, mstatus
    sw   t0, 0x200(s1)

    # Probe store (testbench captures HPROT here)
    sw   s2, 0x100(s1)

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: M-mode store with MPRV=1, MPP=U-mode
    #          Expected: HPROT[1]=0 (user), HSMODE=0
    #=================================================================

    # Set MPP = 00 (U-mode)
    li   t0, 0x1800
    csrc mstatus, t0

    # Set MPRV = 1
    li   t0, 0x20000
    csrs mstatus, t0

    # Snapshot MSTATUS
    csrr t0, mstatus
    sw   t0, 0x204(s1)

    # Probe store (should use U-mode privilege on AHB)
    sw   s2, 0x104(s1)

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: M-mode store with MPRV=1, MPP=S-mode
    #          Expected: HPROT[1]=1 (privileged), HSMODE=1
    #=================================================================

    # Clear MPRV first
    li   t0, 0x20000
    csrc mstatus, t0

    # Set MPP = 01 (S-mode)
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0

    # Set MPRV = 1
    li   t0, 0x20000
    csrs mstatus, t0

    # Snapshot MSTATUS
    csrr t0, mstatus
    sw   t0, 0x208(s1)

    # Probe store (should use S-mode privilege on AHB)
    sw   s2, 0x108(s1)

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: M-mode store with MPRV=1, MPP=M-mode
    #          Expected: HPROT[1]=1 (privileged), HSMODE=0
    #=================================================================

    # Clear MPRV first
    li   t0, 0x20000
    csrc mstatus, t0

    # Set MPP = 11 (M-mode)
    li   t0, 0x1800
    csrs mstatus, t0

    # Set MPRV = 1
    li   t0, 0x20000
    csrs mstatus, t0

    # Snapshot MSTATUS
    csrr t0, mstatus
    sw   t0, 0x20C(s1)

    # Probe store (should use M-mode privilege on AHB)
    sw   s2, 0x10C(s1)

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: MPRV cleared on MRET to S-mode (MPP != M)
    #          Set MPRV=1, MPP=S, do MRET → should clear MPRV
    #          Then ECALL back to M-mode (a0=1 → handler sets MPP=11)
    #          Back in M-mode: verify MPRV=0, do probe store
    #          Expected: HPROT[1]=1 (privileged), HSMODE=0
    #=================================================================

    # Clear MPRV
    li   t0, 0x20000
    csrc mstatus, t0

    # Set MPP = 01 (S-mode) for MRET target
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0

    # Set MPRV = 1
    li   t0, 0x20000
    csrs mstatus, t0

    # Set MEPC to S-mode entry
    la   t0, s_mode_p5
    csrw mepc, t0

    # Clear MPIE so MIE stays 0 after MRET
    li   t0, 0x80
    csrc mstatus, t0

    mret                       # → S-mode, MPRV should be cleared (MPP!=M)

s_mode_p5:
    # Now in S-mode, ECALL back to M-mode
    li   a0, 1                 # Tell handler to set MPP=11 (return to M-mode)
    ecall

    # Back in M-mode (handler set MPP=11, MRET → M-mode)
    # MPRV should be 0 (was cleared by the first MRET to S-mode)
    csrr t0, mstatus
    sw   t0, 0x210(s1)

    # Probe store (MPRV=0, M-mode → privileged)
    sw   s2, 0x110(s1)

    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: MPRV NOT cleared on MRET to M-mode (MPP=M)
    #          Set MPRV=1, MPP=M, do MRET → MPRV should stay 1
    #          (Because MPP == M, so no clearing)
    #          Verify MSTATUS.MPRV is still 1 after MRET
    #=================================================================

    # Clear MPRV first
    li   t0, 0x20000
    csrc mstatus, t0

    # Set MPP = 11 (M-mode)
    li   t0, 0x1800
    csrs mstatus, t0

    # Set MPRV = 1
    li   t0, 0x20000
    csrs mstatus, t0

    # Set MEPC to after the MRET
    la   t0, after_mret_p6
    csrw mepc, t0

    # Clear MPIE so MIE stays 0 after MRET (prevent interrupts)
    li   t0, 0x80
    csrc mstatus, t0

    mret                       # → M-mode (MPP=M), MPRV should NOT be cleared

after_mret_p6:
    # Still in M-mode, MPRV should still be 1
    # Note: MPP was reset to 2'b00 by MRET, so MPRV=1 with MPP=00
    # means stores now use U-mode privilege (this is correct per spec)
    csrr t0, mstatus
    sw   t0, 0x214(s1)

    # Clear MPRV for Phase 7
    li   t0, 0x20000
    csrc mstatus, t0

    # Fence to ensure the store above has completed on AHB
    # (memory barrier for testbench SRAM read with random wait states)
    fence

    li   x31, 0x66666666


    #=================================================================
    # PHASE 7: Back-to-back CSR write (set MPRV) + store
    #          Verify correct HPROT on the immediately following store
    #          Expected: HPROT[1]=0 (user), HSMODE=0
    #=================================================================

    # Ensure MPRV=0 and set MPP=U first
    li   t0, 0x20000
    csrc mstatus, t0
    li   t0, 0x1800
    csrc mstatus, t0

    # Snapshot MSTATUS (MPRV=0, MPP=00)
    csrr t0, mstatus
    sw   t0, 0x218(s1)

    # Back-to-back: set MPRV=1 then immediately store
    li   t0, 0x20000
    csrs mstatus, t0            # Set MPRV=1 (MPP=U from above)
    sw   s2, 0x114(s1)          # Immediately following store → should use U-mode

    li   x31, 0x77777777


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
