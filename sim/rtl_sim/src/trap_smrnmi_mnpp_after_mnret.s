#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_smrnmi_mnpp_after_mnret
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SMRNMI - mnstatus.MNPP IS REWRITTEN TO M BY MNRET
#   Lock-in test for the accepted deviation of the same name in
#   doc/spec_compliance_notes.md: Smrnmi defines MNPP as the privilege at RNMI
#   entry and says nothing about its value after MNRET; the field is WARL.
#   aRVern rewrites it to M on MNRET (mirroring the mstatus.MPP rule for MRET);
#   sail-riscv leaves it unchanged. Firmware must therefore not use MNPP to
#   recover the pre-RNMI privilege after the return.
#
#   Two deliveries, two reads:
#     RNMI #1 taken from M-mode
#       - in-handler:  MNPP reads M (11) and NMIE reads 0            -> 0x10
#       - handler writes MNPP = U (00) so the return goes M->U
#       - after mnret: U-mode cannot read mnstatus, so it ECALLs; the M-mode
#         ecall handler reads mnstatus -> 0x14. MNPP must read M (11) there,
#         NOT the U it was written to: that is the deviation under test.
#     RNMI #2 taken from U-mode (the ecall handler returns to U first)
#       - in-handler:  MNPP reads U (00) - the entry privilege is captured
#         correctly, which is what makes the post-MNRET value a rewrite and
#         not a "never updated" artefact                              -> 0x18
#       - handler leaves MNPP alone; mnret returns to U (MNPP=U); the second
#         ECALL then reads mnstatus in M -> 0x1C, MNPP must read M again.
#
#   Requires SU_MODE_EN==1 (U-mode entry) and Smrnmi (always present).
#   x31 sync: 0x11111111 armed for NMI #1, 0x22222222 armed for NMI #2,
#   0xdeadbeef done, 0x0BADBADB = unexpected trap (FAIL).
#
#   Scratchpad (base 0x80000000):
#     0x00 nmi_count          0x04 ecall_count
#     0x10 mnstatus in RNMI #1 handler (expect MNPP=11, NMIE=0)
#     0x14 mnstatus after mnret #1     (expect MNPP=11 - the deviation)
#     0x18 mnstatus in RNMI #2 handler (expect MNPP=00, entry from U)
#     0x1C mnstatus after mnret #2     (expect MNPP=11 - the deviation)
#     0x20 mcause of the first ecall   0x24 mcause of the second ecall
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSTATUS, 0x744
.equ MNVEC,    0x7FD
.equ MNPP_MASK, 0x1800          # mnstatus[12:11]

.section .text
.global main

main:
    j _start

    .align 2
    # mtvec handler: exactly two ECALL-from-U traps (mcause=8) are expected.
    # The first re-arms for RNMI #2 and returns to U; the second ends the test.
m_trap_handler:
    csrr t0, mcause
    li   t1, 8                  # environment call from U-mode
    bne  t0, t1, unexpected_trap

    # ecall_count++
    lw   t0, 0x04(s1)
    addi t0, t0, 1
    sw   t0, 0x04(s1)

    csrr t2, mcause
    li   t1, 1
    bne  t0, t1, second_ecall

    #--- first ECALL: post-mnret read of mnstatus (PROBE 1) --------------
    csrr t2, MNSTATUS
    sw   t2, 0x14(s1)
    sw   t0, 0x20(s1)           # 1 == first ecall seen

    # Return to U-mode and let the testbench fire RNMI #2 from there.
    li   t0, 0x1800             # mstatus.MPP = U (00)
    csrc mstatus, t0
    la   t0, u_code_2
    csrw mepc, t0
    li   x31, 0x22222222        # armed: testbench asserts NMI #2
    mret

second_ecall:
    #--- second ECALL: post-mnret read after the U-mode RNMI (PROBE 2) ---
    csrr t2, MNSTATUS
    sw   t2, 0x1C(s1)
    sw   t0, 0x24(s1)           # 2 == second ecall seen
    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test

unexpected_trap:
    li   x31, 0x0BADBADB
unexpected_trap_loop:
    j    unexpected_trap_loop

    .align 2
nmi_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    # nmi_count++
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Snapshot mnstatus in the handler: NMIE must be 0 (hardware cleared it on
    # entry) and MNPP must hold the privilege the hart was interrupted in.
    csrr t1, MNSTATUS
    li   t2, 1
    bne  t0, t2, nmi_handler_2
    sw   t1, 0x10(s1)           # RNMI #1: entered from M  -> MNPP = 11
    # Write MNPP = U so this mnret goes M->U. The value written here is what
    # the deviation overwrites: after mnret, MNPP reads M again.
    li   t1, MNPP_MASK
    csrc MNSTATUS, t1
    j    nmi_handler_ret

nmi_handler_2:
    sw   t1, 0x18(s1)           # RNMI #2: entered from U  -> MNPP = 00
    # MNPP is left as captured (U), so this mnret also returns to U-mode.

nmi_handler_ret:
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    .word 0x70200073            # mnret: restore NMIE=1, resume at mnepc


_start:
    li   sp, 0x80010000
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   s1, 0x80000000

    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    la   t0, nmi_handler
    csrw MNVEC, t0              # marv_nmvec: this test places its own RNMI vector

    # Smdbltrp boot rule: arm NMIE first, then clear MDT.
    csrsi MNSTATUS, 8
    csrw  mstatush, x0

    # Armed in M-mode: the testbench asserts NMI #1 here, so MNPP is captured
    # as M (11) on entry.
    li   x31, 0x11111111

wait_nmi_1:
    lw   t0, 0x00(s1)
    beqz t0, wait_nmi_1         # spin in M until RNMI #1 has been delivered

    # The handler set MNPP=U, so the mnret above returned here... in U-mode.
    # U-mode cannot read mnstatus (it is an M-mode CSR), so ECALL into M and
    # read it there.
u_code_1:
    ecall

    # Reached only in U-mode after the first ecall handler's mret.
u_code_2:
    lw   t0, 0x00(s1)           # wait for RNMI #2 (this load is U-mode, PMP-allowed)
    li   t1, 2
    bne  t0, t1, u_code_2
    ecall                       # second ECALL: PROBE 2 runs in M

hang:
    j    hang
