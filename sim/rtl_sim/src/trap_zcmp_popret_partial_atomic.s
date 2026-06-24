#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_zcmp_popret_partial_atomic
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Zcmp cm.popret PARTIAL-ATOMICITY
#   Per RISC-V Unprivileged spec §28.13.4.2:
#   "The optional li a0, 0, stack pointer adjustment and optional ret must
#   only be committed only when it is certain that the entire POP/POPRET
#   instruction will commit. For POPRET once the stack pointer adjustment
#   has been committed the ret must execute."
#
#   The SP-adjustment commit at sequencer state=1 fires ONE CYCLE BEFORE the
#   registered dph_error of the trailing (ra) load that has already taken an
#   AHB error response. Net effect: when the LAST load of cm.popret faults,
#   the trap handler sees:
#   - s2/s1/s0 = loaded from earlier (successful) DPHs
#   - ra      = stale (the faulting load's WB write was correctly killed)
#   - sp      = sp_old + stack_adj  (BUG: should be sp_old since the
#   trailing ret cannot execute, the SP update must be
#   atomic with the ret commit)
#
#   SP-VALUE is the primary discriminator:
#   Pre-fix : sp = 0x2000000C  (sp_old + 48)  → FAIL
#   Post-fix: sp = 0x1FFFFFDC  (sp_old)        → PASS
#
#   Note: s2/s1/s0 commit-as-they-go is a known residual (D-1 in the
#   assessment). Fixing it would require a transactional shadow buffer. The
#   sp-update fix alone closes the security-impacting MRET-retry hijack path
#   (since the retry would otherwise read from sp_old + 48 = one frame above
#   the original, where attacker-controlled values may sit).
#
#   MEMORY MAP USED:
#   sp_old   = 0x1FFFFFDC  (unmapped — accessing it as a load would fault)
#   sp+32    = 0x1FFFFFFC  (unmapped — ra LOAD faults here)
#   sp+36    = 0x20000000  (ROM start, mapped)  — s0 load
#   sp+40    = 0x20000004  (ROM, mapped)        — s1 load
#   sp+44    = 0x20000008  (ROM, mapped)        — s2 load
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count   (sanity — expect 1 LD-access-fault)
#   0x04: trap mcause  (expect 5 = LD access fault)
#   0x08: trap mepc    (expect cm.popret PC)
#   0x0C: recovery PC  (input to handler)
#   0x10: captured sp  (post-trap sp value)  ← PRIMARY DISCRIMINATOR
#   0x14: captured ra
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER (M-mode direct)
    # The faulting context has sp = 0x1FFFFFDC (unmapped). The handler
    # CANNOT push to sp. Swap sp with mscratch (which the firmware
    # pre-loaded with a known-good trap-stack base).
    #=================================================================
    .align 2
trap_handler:
    csrrw sp, mscratch, sp        # swap: sp ↔ mscratch
                                  # mscratch now holds the FAULTING-context sp
                                  # sp now holds the trap-handler stack
    addi  sp, sp, -32
    sw    t0, 28(sp)
    sw    t1, 24(sp)
    sw    t2, 20(sp)
    sw    t3, 16(sp)
    sw    s1, 12(sp)

    li    s1, 0x80000000          # restore scratchpad base
    csrr  t0, mcause
    csrr  t1, mepc

    # Capture the faulting-context sp (currently in mscratch) — this is
    # the PRIMARY DISCRIMINATOR for the bug.
    csrr  t2, mscratch
    sw    t2, 0x10(s1)            # captured sp

    # Also capture ra for forensic reference
    sw    ra, 0x14(s1)            # captured ra

    # trap_count++
    lw    t3, 0x00(s1)
    addi  t3, t3, 1
    sw    t3, 0x00(s1)

    # mcause / mepc
    sw    t0, 0x04(s1)
    sw    t1, 0x08(s1)

    # Redirect mepc to recovery
    lw    t3, 0x0C(s1)
    csrw  mepc, t3

    lw    s1, 12(sp)
    lw    t3, 16(sp)
    lw    t2, 20(sp)
    lw    t1, 24(sp)
    lw    t0, 28(sp)
    addi  sp, sp, 32
    csrrw sp, mscratch, sp        # swap back: sp ↔ mscratch
    mret


_start:
    # Working SP for the prologue (inside SRAM)
    li   sp, 0x8000F000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Configure mscratch as the trap-handler stack base (inside SRAM,
    # below the working sp we'll use for the test, to avoid overlap)
    li   t0, 0x8000E800
    csrw mscratch, t0

    # Recovery address: where mret should land after the fault
    la   t0, recovery_after_popret
    sw   t0, 0x0C(s1)

    # Pre-init sentinel-bearing registers (s0/s1/s2/ra/sp)
    # Note: s1 (=x9) is used as the scratchpad base — we save and restore
    # it across the cm.popret. Use a different scratch for s1 pre-init.
    li   s0, 0xA0A0A0A0
    # We can't use s1=0xA1A1A1A1 (need s1=scratchpad). The test post-trap
    # restores s1 in the handler.
    li   s2, 0xA2A2A2A2
    li   ra, 0xFEEDFACE

    li   x31, 0x11111111

    #=================================================================
    # PHASE 2: cm.popret with sp positioned so the LAST load (ra @ sp+32)
    # faults but all earlier loads (s2/s1/s0 @ sp+36..sp+44) succeed in
    # mapped ROM.
    #=================================================================

    # Position sp at boundary where:
    #   sp+32 = 0x1FFFFFFC (unmapped → ra LOAD faults)
    #   sp+36 = 0x20000000 (ROM start → s0 LOAD succeeds)
    #   sp+40 = 0x20000004 (ROM → s1 LOAD succeeds)
    #   sp+44 = 0x20000008 (ROM → s2 LOAD succeeds)
    li   sp, 0x1FFFFFDC

    li   x31, 0x12121212

    # cm.popret {ra, s0-s2}, 48
    # Encoding: bits[15:10]=101111, [9:8]=10, [7:4]=rlist=7=0111,
    # [3:2]=spimm=2=10, [1:0]=10 → 0xBE7A
    # rlist=7 → pop ra,s0,s1,s2 ; stack_adj_base=16, +spimm*16=32 → 48 bytes
    .hword 0xBE7A                  # cm.popret rlist=7 spimm=2

    # If we reach here pre-fix, the cm.popret partial-state bug presented:
    # sp got updated but ra didn't (and execution somehow continued — it
    # may not, the trap handler redirects to recovery_after_popret).
    li   x31, 0xBADBAD01

recovery_after_popret:
    # Trap handler redirected here. Restore working sp + scratchpad base.
    li   sp, 0x8000F000
    li   s1, 0x80000000

    li   x31, 0x22222222

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
