#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_s_sie_sip_write_mask
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SIE/SIP WRITE-SIDE mideleg MASKING
#   Per RISC-V Privileged spec §12.1.3:
#   "writes to sip/sie bits where mideleg=0 must be ignored"
#
#   The read-side mask is correct in this design (sie/sip CSR reads AND with
#   mideleg). The WRITE-side however updates the shared sie_xxx / sip_ssip
#   flops UNCONDITIONALLY when sie_wr / sip_wr fires — corrupting M-mode's
#   MIE/MIP state when S-mode writes through SIE/SIP.
#
#   Three exploit primitives:
#   Variant A (set):   S-mode csrw sie, 0x222 with mideleg=0 sets MIE bits
#   Variant B (clear): S-mode csrw sie, 0 with mideleg=0 CLEARS MIE bits
#   Variant B' (clr): S-mode csrw sip, 0 with mideleg=0 CLEARS M's SSIP
#
#   TEST DISCRIMINATOR: after each S-mode write, M-mode reads MIE/MIP and
#   verifies its bits survived. Pre-fix the S-mode writes leak through;
#   post-fix the mideleg-gated write-side blocks them.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count
#   0x04: Phase 2 (Variant A — SET)   MIE readback   (expect 0x000, pre-fix non-zero)
#   0x08: Phase 3 (Variant B — CLR)   MIE readback   (expect 0x222, pre-fix 0)
#   0x0C: Phase 4 (Variant B' — CLR)  MIP[1] readback (expect 1, pre-fix 0)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER (M-mode direct)
    # Handles ECALL-from-S only — escapes back to M-mode by setting MPP=11
    # and advancing mepc past the ECALL.
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)
    sw   t3,  0(sp)

    csrr t0, mcause
    csrr t1, mepc

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # ECALL from S-mode (mcause==9) → escape back to M-mode
    li   t2, 9
    beq  t0, t2, _ecall_from_smode
    j    _trap_done

_ecall_from_smode:
    # Set MPP=11 (M-mode), mret to address past ECALL
    li   t2, 0x1800
    csrs mstatus, t2
    addi t1, t1, 4                 # skip past ECALL
    csrw mepc, t1

_trap_done:
    lw   t3,  0(sp)
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x8000F000
    li   s1, 0x80000000           # scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)

    # Install trap handler (direct mode)
    la   t0, trap_handler
    csrw mtvec, t0

    li   x31, 0x11111111          # init complete


    #=================================================================
    # PHASE 2 (Variant A — SET):
    # M-mode: mie=0, mideleg=0
    # S-mode: csrw sie, 0x222  (try to set non-delegated SSIE/STIE/SEIE)
    # M-mode: csrr t1, mie  → spec requires 0; pre-fix reads non-zero
    #=================================================================
    csrw mie,     zero                  # MIE = 0
    csrw mideleg, zero                  # nothing delegated

    # Drop to S-mode (MPP=01) at u_var_a_entry
    la   t0, s_var_a_entry
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0                    # clear MPP
    li   t0, 0x0800
    csrs mstatus, t0                    # MPP=01 (S)
    li   t0, 0x80
    csrc mstatus, t0                    # clear MPIE (so MIE stays 0 on return)
    mret

    .align 2
s_var_a_entry:
    # In S-mode: write sie with all SIE bits asserted
    li   t0, 0x222                      # try to set SSIE/STIE/SEIE
    csrw sie, t0
    ecall                               # escape to M-mode

    # After ECALL handler returns here in M-mode
    csrr t1, mie
    sw   t1, 0x04(s1)                   # Phase 2 result
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3 (Variant B — CLEAR):
    # M-mode: mie=0x222 (M wants SSIE/STIE/SEIE set), mideleg=0
    # S-mode: csrw sie, 0  (try to clear non-delegated bits)
    # M-mode: csrr t1, mie  → spec requires 0x222; pre-fix reads 0
    #=================================================================
    li   t0, 0x222
    csrw mie, t0                        # MIE = 0x222
    csrw mideleg, zero                  # nothing delegated

    la   t0, s_var_b_entry
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0                    # MPP=01 (S)
    li   t0, 0x88
    csrc mstatus, t0                    # clear MIE+MPIE → MIE stays 0 in S
    mret

    .align 2
s_var_b_entry:
    csrw sie, zero                      # try to clear all
    ecall

    csrr t1, mie
    sw   t1, 0x08(s1)                   # Phase 3 result
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4 (Variant B' — SIP clear):
    # M-mode: set mip[1] (SSIP) via csrw mip; mideleg=0; mie=0 to avoid
    # the very IRQ scenario this test is otherwise about — we want the
    # write-mask check, not the IRQ-eval check.
    # S-mode: csrw sip, 0  (try to clear M's SSIP)
    # M-mode: csrr t1, mip  → spec requires bit 1 still 1
    #=================================================================
    csrw mie, zero                      # block any IRQ during this phase
    li   t0, 0x2
    csrw mip, t0                        # set MIP.SSIP
    csrw mideleg, zero                  # nothing delegated

    la   t0, s_var_c_entry
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0
    li   t0, 0x88
    csrc mstatus, t0                    # clear MIE+MPIE → MIE stays 0 in S
    mret

    .align 2
s_var_c_entry:
    csrw sip, zero                      # try to clear SSIP
    ecall

    csrr t1, mip
    sw   t1, 0x0C(s1)                   # Phase 4 result
    li   x31, 0x44444444


    # Clean up: clear any residual sip_ssip so end-of-test trap_count is stable
    csrw mip, zero
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
