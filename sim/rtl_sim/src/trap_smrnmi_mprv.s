#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_smrnmi_mprv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SMRNMI × MPRV (NMIE=0 ⇒ MPRV clear)
#   Bug-sensitive reproducer: an RNMI handler must signal its loads/stores at
#   M-mode privilege even when mstatus.MPRV=1/MPP=U, because RISC-V Privileged
#   spec §8.3 requires the hart to behave as though MPRV were clear while
#   mnstatus.NMIE=0 (inside an RNMI handler).
#
#   Sequence:
#   - M-mode sets NMIE=1 (so the NMI can be taken), MPP=U, MPRV=1, then
#   spins. Testbench asserts NMI.
#   - NMI entry HW-clears NMIE→0; handler runs in M-mode with MPRV=1/MPP=U.
#   - PROBE A (in handler): store to 0x80000100. Spec-correct = M-mode AHB
#   (HPROT[1]=1, HSMODE=0). RTL missing the NMIE gate on the MPRV term
#   (arv_csr_traps.v:2120) instead emits U (HPROT[1]=0) — this is the
#   discriminating check: PASS with the gate, FAIL without it.
#   - Handler sets mnstatus.MNPP=U, then mnret restores NMIE→1 and returns
#   to U-mode. Ratified Smrnmi spec (verbatim): "If MNRET changes the
#   privilege mode to a mode less privileged than M, it also sets
#   mstatus.MPRV to 0." So the M→U mnret must clear MPRV.
#   - The resumed U-mode code executes ECALL back to M (mcause=8 proves the
#   hart really landed in U).
#   - PROBE B (in the M-mode ecall handler): mstatus snapshot to 0x18 must
#   have MPRV (bit 17) = 0, and the store to 0x80000104 must be M-mode AHB
#   (HPROT[1]=1) because MPRV was cleared by the mnret-to-U. RTL that fails
#   to clear MPRV instead reads bit17=1 and (with MPP=U) emits a U-tagged
#   store.
#
#   Requires Smrnmi present (Smrnmi). x31 sync: 0x11111111 armed, 0xdeadbeef done,
#   0x0BADBADB = unexpected mtvec trap (FAIL).
#
#   Scratchpad (base 0x80000000):
#   0x00 nmi_count  0x08 nmi_handler_addr  0x0C nmi_done flag
#   0x10 mnstatus-in-handler  0x14 mstatus-in-handler
#   0x18 mstatus-post-mnret (PROBE B snapshot: bit 17 MPRV must be 0)
#   0x100 PROBE A target (in-handler)   0x104 PROBE B target (post-mnret)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    .align 2
    # mtvec handler — expected exactly once: ECALL-from-U (mcause=8) after
    # mnret returned to U-mode. Any other trap flags a FAIL.
m_trap_handler:
    csrr t0, mcause
    li   t1, 8                 # environment call from U-mode
    bne  t0, t1, unexpected_trap

    # PROBE B — ratified Smrnmi spec (verbatim): "If MNRET changes the
    # privilege mode to a mode less privileged than M, it also sets
    # mstatus.MPRV to 0." The mnret above went M→U, so MPRV must be 0 now:
    #   - mstatus snapshot (0x18) must have bit 17 (MPRV) clear;
    #   - this M-mode store must be M-tagged on AHB (HPROT[1]=1, HSMODE=0).
    # RTL that fails to clear MPRV reads bit17=1 and (MPP=U) emits a
    # U-tagged store instead.
    csrr t2, mstatus
    sw   t2, 0x18(s1)
    li   t2, 0x5A5A5A5A
    sw   t2, 0x104(s1)

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

    # Diagnostic snapshots: NMIE must be 0 here; MPRV=1, MPP=00.
    csrr t1, 0x744             # mnstatus
    sw   t1, 0x10(s1)
    csrr t1, mstatus
    sw   t1, 0x14(s1)

    # PROBE A — bug-sensitive store. NMIE=0 here ⇒ spec §8.3 mandates
    # effective MPRV=0 ⇒ M-mode AHB privilege. Buggy RTL emits U.
    li   t2, 0xA5A5A5A5
    sw   t2, 0x100(s1)

    # release the spin-wait
    li   t0, 0xAA
    sw   t0, 0x0C(s1)

    # Point mnret at U-mode: clear mnstatus.MNPP (bits 12:11) to 00 = U.
    # This makes MNRET "change the privilege mode to a mode less privileged
    # than M", which per the ratified Smrnmi spec must clear mstatus.MPRV.
    li   t1, 0x1800
    csrc 0x744, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    .word 0x70200073           # mnret: restore NMIE=1, resume at mnepc


_start:
    li   sp, 0x80010000
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   s1, 0x80000000

    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)

    # mtvec (safety net)
    la   t0, m_trap_handler
    csrw mtvec, t0

    # publish NMI handler address for the testbench
    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x08(s1)

    # enable NMI: mnstatus.NMIE=1 (resets to 0; required so the NMI is taken)
    csrsi 0x744, 8

    # MPP = U (clear bits 12:11), MPRV = 1 (bit 17)
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x20000
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0

    # Armed (MPRV=1, MPP=U, NMIE=1). Signal the testbench to assert NMI.
    li   x31, 0x11111111

wait_nmi:
    lw   t0, 0x0C(s1)
    beqz t0, wait_nmi          # spin until the NMI handler releases us

    # Resumed via mnret — the handler set mnstatus.MNPP=U, so we are now in
    # U-mode and NMIE=1 again. Ratified Smrnmi spec (verbatim): "If MNRET
    # changes the privilege mode to a mode less privileged than M, it also
    # sets mstatus.MPRV to 0." ECALL back to M-mode (mcause=8 proves we are
    # in U); PROBE B in the ecall handler verifies MPRV now reads 0.
    ecall

    # not reached — the ecall handler never returns here
hang_after_ecall:
    j    hang_after_ecall
