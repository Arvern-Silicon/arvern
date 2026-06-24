#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_mideleg_routing
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: mideleg per-cause IRQ routing
#   Spec reference: RISC-V Privileged §3.1.6.1, §3.1.8, §12.1.3
#
#   mideleg[i]=1 -> cause i routes to S-mode
#   mideleg[i]=0 -> cause i routes to M-mode
#   mideleg has no bits for MSI=3 / MTI=7 / MEI=11 (M-class always to M)
#
#   Exercises each affected line of the IRQ priority vector in arv_csr_traps:
#   Phase 1: mideleg.SSI=0 + assert SSIP -> trap cause 1 (M-mode)
#   Phase 2: mideleg.STI=0 + assert STIP -> trap cause 5 (M-mode)
#   Phase 3: mideleg.SSI=1 + assert MSI (HW pin) -> trap cause 3 (M-mode)
#   (verifies MSI is NOT cross-masked by an unrelated mideleg bit)
#   Phase 4: mideleg.STI=1 + assert MTI (HW pin) -> trap cause 7 (M-mode)
#   (verifies MTI is NOT cross-masked by an unrelated mideleg bit)
#
#   Synchronisation invariants:
#   - MIE stays 1 throughout the test; mie.{XIE} bit is set/unset per phase
#   so only one IRQ source is enabled at a time.
#   - Each phase spins until the handler's count-store releases it (the
#   count store is sequenced AFTER the cause store, so when count changes
#   cause is guaranteed to already be visible -- release-acquire pair).
#   - The handler either clears the mip pending bit (SSI, STI) or masks
#   the source in mie (MSI, MTI -- HW-driven, not software-clearable);
#   so the IRQ doesn't immediately re-fire after MRET.
#----------------------------------------------------------------------------

.equ SCRATCH,         0x80000000
.equ COUNT_OFFSET,    0x00
.equ LAST_CAUSE_OFF,  0x04

.section .text
.global main
main:
    /* ----- One-time setup ----- */
    li   sp, 0x80010000
    li   s1, SCRATCH
    sw   zero, COUNT_OFFSET(s1)
    sw   zero, LAST_CAUSE_OFF(s1)

    la   t0, m_handler
    csrw mtvec, t0

    csrw mideleg, zero
    csrw mie,     zero
    li   t0, ((1 << 1) | (1 << 5) | (1 << 9))   /* SSIP, STIP, SEIP-sw */
    csrc mip, t0                                /* clear sticky bits */

    /* Enable MIE -- stays 1 for the whole test; per-phase enable is via mie */
    csrsi mstatus, 0x8

    li   x31, 0xFFFFFFFF

    /* ===================================================================== */
    /* Phase 1: mideleg.SSI=0  +  SSIP -> trap cause 1 to M-mode             */
    /* ===================================================================== */
    csrw mideleg, zero
    li   t0, (1 << 1)              /* SSIE */
    csrw mie, t0

    lw   t1, COUNT_OFFSET(s1)      /* count_before */

    li   t0, (1 << 1)              /* SSIP */
    csrs mip, t0                   /* assert -- handler runs, clears SSIP */

    /* Spin until handler's count-store releases us */
    li   t4, 10000
phase1_spin:
    lw   t5, COUNT_OFFSET(s1)
    bne  t5, t1, phase1_done
    addi t4, t4, -1
    bnez t4, phase1_spin
phase1_done:

    lw   t2, COUNT_OFFSET(s1)
    sub  t2, t2, t1                /* x7  = delta = 1 */
    csrr t3, mscratch              /* x28 = mcause (passed via CSR) */    /* x28 = mcause = 1 */

    li   x31, 0x11111111

    /* ===================================================================== */
    /* Phase 2: mideleg.STI=0  +  STIP -> trap cause 5 to M-mode             */
    /* ===================================================================== */
    csrw mideleg, zero
    li   t0, (1 << 5)              /* STIE */
    csrw mie, t0

    lw   t1, COUNT_OFFSET(s1)

    li   t0, (1 << 5)              /* STIP */
    csrs mip, t0

    li   t4, 10000
phase2_spin:
    lw   t5, COUNT_OFFSET(s1)
    bne  t5, t1, phase2_done
    addi t4, t4, -1
    bnez t4, phase2_spin
phase2_done:

    lw   t2, COUNT_OFFSET(s1)
    sub  t2, t2, t1
    csrr t3, mscratch              /* x28 = mcause (passed via CSR) */

    li   x31, 0x22222222

    /* ===================================================================== */
    /* Phase 3: mideleg.SSI=1  +  irq_m_software (HW MSIP) -> cause 3 (M)      */
    /* Verifies that mideleg.SSI (cause 1 delegation) does NOT mask the      */
    /* unrelated machine-software interrupt (cause 3); per spec the mideleg  */
    /* register has no bit for cause 3.                                      */
    /* ===================================================================== */
    li   t0, (1 << 1)              /* mideleg.SSI=1 (delegate SSI) */
    csrw mideleg, t0
    li   t0, (1 << 3)              /* MSIE */
    csrw mie, t0

    lw   t1, COUNT_OFFSET(s1)

    li   x31, 0x30303030           /* signal TB: assert irq_m_software */

    li   t4, 10000
phase3_spin:
    lw   t5, COUNT_OFFSET(s1)
    bne  t5, t1, phase3_done
    addi t4, t4, -1
    bnez t4, phase3_spin
phase3_done:

    lw   t2, COUNT_OFFSET(s1)
    sub  t2, t2, t1
    csrr t3, mscratch              /* x28 = mcause (passed via CSR) */

    li   x31, 0x33333333

    /* ===================================================================== */
    /* Phase 4: mideleg.STI=1  +  irq_m_timer (HW MTIP) -> cause 7 (M)         */
    /* Same invariant as Phase 3 for the timer pair: mideleg.STI (cause 5    */
    /* delegation) must NOT mask the unrelated machine timer (cause 7).      */
    /* ===================================================================== */
    li   t0, (1 << 5)              /* mideleg.STI=1 (delegate STI) */
    csrw mideleg, t0
    li   t0, (1 << 7)              /* MTIE */
    csrw mie, t0

    lw   t1, COUNT_OFFSET(s1)

    li   x31, 0x40404040           /* signal TB: assert irq_m_timer */

    li   t4, 10000
phase4_spin:
    lw   t5, COUNT_OFFSET(s1)
    bne  t5, t1, phase4_done
    addi t4, t4, -1
    bnez t4, phase4_spin
phase4_done:

    lw   t2, COUNT_OFFSET(s1)
    sub  t2, t2, t1
    csrr t3, mscratch              /* x28 = mcause (passed via CSR) */

    li   x31, 0x44444444

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j end_of_test


/*===========================================================================*/
/* M-mode trap handler                                                       */
/*   1. Records mcause (low 5 bits) in scratch.                              */
/*   2. Increments trap count -- this is the release signal for main's spin */
/*      (must be ordered AFTER the cause store).                             */
/*   3. For software-writable causes (SSI=1, STI=5), clears the mip pending  */
/*      bit so the IRQ doesn't immediately re-fire after MRET.               */
/*      For HW-driven causes (MSI=3, MTI=7), masks the bit in mie instead    */
/*      (the testbench deasserts the pin later, in its check sequence).      */
/*===========================================================================*/

.align 2
m_handler:
    addi sp, sp, -16
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)

    li   t0, SCRATCH

    /* (1) Record mcause in mscratch CSR (not memory) -- avoids load/store
       race against main's check under SRAM wait states. CSR writes have
       strict program-order semantics so main's subsequent csrr is guaranteed
       to see this value. */
    csrr t1, mcause
    andi t1, t1, 0x1F
    csrw mscratch, t1

    /* (2) Increment count in memory -- this is the release signal main spins
       on. The count store may still be in-flight via posted-store semantics
       when main observes the new value (via store-buffer forwarding), but
       since cause lives in mscratch we don't care about memory drain order. */
    lw   t2, COUNT_OFFSET(t0)
    addi t2, t2, 1
    sw   t2, COUNT_OFFSET(t0)

    /* (3) Dispatch on cause (still in t1) */
    li   t2, 1
    beq  t1, t2, clear_ssip
    li   t2, 3
    beq  t1, t2, mask_msie
    li   t2, 5
    beq  t1, t2, clear_stip
    li   t2, 7
    beq  t1, t2, mask_mtie
    j    h_done

clear_ssip:
    li   t1, (1 << 1)
    csrc mip, t1
    j    h_done

clear_stip:
    li   t1, (1 << 5)
    csrc mip, t1
    j    h_done

mask_msie:
    li   t1, (1 << 3)
    csrc mie, t1
    j    h_done

mask_mtie:
    li   t1, (1 << 7)
    csrc mie, t1
    j    h_done

h_done:
    lw   t2, 8(sp)
    lw   t1, 4(sp)
    lw   t0, 0(sp)
    addi sp, sp, 16
    mret
