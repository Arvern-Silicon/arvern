#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_msip_clear_mret
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: LEVEL IRQ CLEARED BY THE STORE RIGHT BEFORE MRET / MIE SET
#   A minimal handler -- count, clear MSIP, mret, nothing in between -- and a
#   clear followed directly by setting mstatus.MIE: the interrupt must be taken
#   exactly once per IPI, whatever the bus timing (the clearing store may still
#   be in flight when mret or the CSR write takes effect).
#   Phase 1 runs 8 IPIs with marv_ctl.livelock_prot_en = 1 (reset value),
#   phase 2 runs 8 more with it cleared.
#   Phase 3 (livelock_prot_en = 1 again, mstatus.MIE = 0): raise MSIP, wait
#   for mip.MSIP, clear it with a store and set mstatus.MIE in the very next
#   instruction; no interrupt may be taken, 8 times.
#   s0 (x8) = handler entries (expected 16)
#----------------------------------------------------------------------------

.equ ACLINT_MSIP0, 0x02000000

.macro IPI
    li    s1, 0
    sw    t1, 0(t0)                 # MSIP0 = 1
1:  beqz  s1, 1b                    # handler sets s1
    .rept 20
    nop
    .endr
.endm

.macro PRE_ENABLE
    csrci mstatus, 8                # MIE = 0
    sw    t1, 0(t0)                 # MSIP0 = 1
1:  csrr  t2, mip
    andi  t2, t2, 8
    beqz  t2, 1b
    sw    x0, 0(t0)                 # MSIP0 = 0 ...
    csrsi mstatus, 8                # ... and MIE = 1 right after
    .rept 20
    nop
    .endr
.endm

.section .text
.global main
main:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw  mstatush, x0              # mstatus.MDT   = 0
    la    t2, trap_handler
    csrw  mtvec, t2
    li    t0, ACLINT_MSIP0
    li    t1, 1
    li    s0, 0
    li    t2, 0x8
    csrw  mie, t2                   # MSIE
    csrs  mstatus, t2               # MIE
    li    x31, 0x11111111

    IPI
    IPI
    IPI
    IPI
    IPI
    IPI
    IPI
    IPI

    csrci 0x7FF, 4                  # marv_ctl.livelock_prot_en = 0
    li    x31, 0x22222222

    IPI
    IPI
    IPI
    IPI
    IPI
    IPI
    IPI
    IPI

    csrsi 0x7FF, 4                  # marv_ctl.livelock_prot_en = 1
    li    x31, 0x33333333

    PRE_ENABLE
    PRE_ENABLE
    PRE_ENABLE
    PRE_ENABLE
    PRE_ENABLE
    PRE_ENABLE
    PRE_ENABLE
    PRE_ENABLE

    csrw  mie, x0
    li    x31, 0xdeadbeef
end_of_test:
    j     end_of_test

    .align 2
trap_handler:
    addi  s0, s0, 1
    li    s1, 1
    sw    x0, 0(t0)                 # MSIP0 = 0
    mret
