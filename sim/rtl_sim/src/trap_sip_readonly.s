#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_sip_readonly
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SIP READ-ONLY BITS
#   Verify that SIP.STIP and SIP.SEIP are read-only per RISC-V spec:
#   Phase 2: M-mode writes STIP via MIP -> verify it reads back via SIP
#   Phase 3: S-mode tries to set STIP via SIP -> verify it stays 0
#   Phase 4: S-mode tries to set SEIP via SIP -> verify it stays 0
#   Phase 5: S-mode writes SSIP via SIP -> verify it succeeds (writable)
#   Phase 6: M-mode writes SEIP via MIP -> verify it reads back via SIP
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
#   0x000: m_trap_count
#   0x004: last MCAUSE
#   0x008: last MEPC
#   0x00C: m_trap_handled flag
#
#   Phase 2: M-mode sets MIP.STIP, reads SIP
#     0x020: SIP value after M-mode sets MIP.STIP
#
#   Phase 3: S-mode tries to set SIP.STIP
#     0x030: SIP value before S-mode write
#     0x034: SIP value after S-mode CSRS attempt
#
#   Phase 4: S-mode tries to set SIP.SEIP
#     0x040: SIP value before
#     0x044: SIP value after CSRS attempt
#
#   Phase 5: S-mode writes SIP.SSIP (should work)
#     0x050: SIP value before
#     0x054: SIP value after CSRS
#
#   Phase 6: M-mode sets MIP.SEIP, reads SIP
#     0x060: SIP value after M-mode sets MIP.SEIP
#=========================================================================

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -20
    sw   t0, 16(sp)
    sw   t1, 12(sp)
    sw   t2,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc

    # Increment trap count
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    # Save MCAUSE
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)

    # Check if ECALL (cause 8, 9, 11)
    andi t2, t0, 0x1F
    li   t4, 8
    beq  t2, t4, m_ecall
    li   t4, 9
    beq  t2, t4, m_ecall
    li   t4, 11
    beq  t2, t4, m_ecall
    j    m_handler_done

m_ecall:
    addi t1, t1, 4
    csrw mepc, t1
    # If a0 == 1, return to M-mode
    li   t4, 1
    bne  a0, t4, m_handler_done
    li   t4, 0x1800
    csrs mstatus, t4           # Set MPP = 11
    j    m_handler_done

m_handler_done:
    li   t4, 1
    sw   t4, 0x0C(s1)

    lw   t4,  4(sp)
    lw   t2,  8(sp)
    lw   t1, 12(sp)
    lw   t0, 16(sp)
    addi sp, sp, 20
    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)
    sw   t0, 0x60(s1)

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: M-mode writes MIP.STIP, reads SIP to verify visible
    #=================================================================

    # Delegate STI so STIP is visible in SIP
    li   t0, (1 << 5)
    csrs mideleg, t0

    # Set MIP.STIP (bit 5) from M-mode
    li   t0, 0x20
    csrs mip, t0

    # Read SIP (through MSTATUS/SIP shadow) — in M-mode we read via CSR
    csrr t0, sip
    sw   t0, 0x20(s1)

    # Clear MIP.STIP
    li   t0, 0x20
    csrc mip, t0

    fence
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: S-mode tries to set SIP.STIP (should fail, read-only)
    #=================================================================

    # Keep STI delegated
    # Enter S-mode
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP
    li   t0, 0x0880
    csrs mstatus, t0           # MPP=01, MPIE=1

    la   t0, s_mode_p3
    csrw mepc, t0

    mret                       # -> S-mode

s_mode_p3:
    # Read SIP before
    csrr t0, sip
    sw   t0, 0x30(s1)

    # Try to set SIP.STIP (bit 5) — should be ignored (read-only)
    li   t0, 0x20
    csrs sip, t0

    # Read SIP after
    csrr t0, sip
    sw   t0, 0x34(s1)

    # Return to M-mode
    li   a0, 1
    ecall

    fence
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: S-mode tries to set SIP.SEIP (should fail, read-only)
    #=================================================================

    # Delegate SEI so SEIP is visible in SIP
    li   t0, (1 << 9)
    csrs mideleg, t0

    # Enter S-mode
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0880
    csrs mstatus, t0

    la   t0, s_mode_p4
    csrw mepc, t0

    mret

s_mode_p4:
    # Read SIP before
    csrr t0, sip
    sw   t0, 0x40(s1)

    # Try to set SIP.SEIP (bit 9) — should be ignored
    li   t0, 0x200
    csrs sip, t0

    # Read SIP after
    csrr t0, sip
    sw   t0, 0x44(s1)

    # Return to M-mode
    li   a0, 1
    ecall

    fence
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: S-mode writes SIP.SSIP (should succeed, writable)
    #=================================================================

    # Delegate SSI
    li   t0, (1 << 1)
    csrs mideleg, t0

    # Enter S-mode (with SIE=0 to prevent SSIP from actually firing)
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0880
    csrs mstatus, t0
    # Clear SSTATUS.SIE
    li   t0, 0x2
    csrc mstatus, t0

    la   t0, s_mode_p5
    csrw mepc, t0

    mret

s_mode_p5:
    # Read SIP before
    csrr t0, sip
    sw   t0, 0x50(s1)

    # Set SIP.SSIP (bit 1) — should succeed
    li   t0, 0x2
    csrs sip, t0

    # Read SIP after
    csrr t0, sip
    sw   t0, 0x54(s1)

    # Clear it back
    li   t0, 0x2
    csrc sip, t0

    # Return to M-mode
    li   a0, 1
    ecall

    fence
    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: M-mode writes MIP.SEIP, reads SIP to verify visible
    #=================================================================

    # SEI still delegated from Phase 4
    # Set MIP.SEIP (bit 9) from M-mode
    li   t0, 0x200
    csrs mip, t0

    # Read SIP
    csrr t0, sip
    sw   t0, 0x60(s1)

    # Clear MIP.SEIP
    li   t0, 0x200
    csrc mip, t0

    # Clean up delegations
    li   t0, 0x222
    csrc mideleg, t0

    fence
    li   x31, 0x66666666


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
