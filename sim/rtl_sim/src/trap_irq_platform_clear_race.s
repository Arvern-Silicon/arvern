#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_platform_clear_race
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PLATFORM IRQ PENDING CLEAR RIGHT AFTER THE SOURCE DROPS
#   The bench models a level-sensitive device on irq_platform_i[0]: the line
#   is high while periph #0 register 1 differs from register 0, so a store to
#   register 1 raises it and a store of the same value to register 0 drops it
#   at the end of that store's data phase.
#
#   Each trial raises the line, waits for mip[16], drops the line with a store
#   (with and without a read-back of the device), then clears mip[16] (csrc
#   mip) after 0..7 nops. Without the read-back the store may still be in
#   flight at the csrc: the mip write waits for it. mip[16] must read 0
#   afterwards in every trial. With SU_MODE_EN the same sweep clears the bit
#   through sip (mideleg[16] = 1).
#
#   Interrupts stay disabled (mie = 0): only the pending bit is observed.
#
#   s1 (x9)  = trials whose clear was refused (expected 0)
#   s0 (x8)  = trials run
#----------------------------------------------------------------------------
.include "firmware_config.inc"

.equ PERIPH0, 0x10040000

# One trial: \rb = read the device back, \n = nops before the clear, \csr = mip/sip
.macro TRIAL rb, n, csr
    addi  a1, a1, 1
    sw    a1, 4(a0)                 # line high
1:  csrr  t0, mip
    and   t0, t0, t1
    beqz  t0, 1b                    # mip[16] latched
    sw    a1, 0(a0)                 # line low at the end of this data phase
    .if \rb
    lw    t2, 0(a0)
    .endif
    .rept \n
    nop
    .endr
    csrc  \csr, t1
    csrr  t0, mip
    and   t0, t0, t1
    beqz  t0, 2f
    addi  s1, s1, 1                 # refused
    csrc  mip, t1
2:  addi  s0, s0, 1
.endm

.macro SWEEP csr
    TRIAL 0, 0, \csr
    TRIAL 0, 1, \csr
    TRIAL 0, 2, \csr
    TRIAL 0, 3, \csr
    TRIAL 0, 4, \csr
    TRIAL 0, 5, \csr
    TRIAL 0, 6, \csr
    TRIAL 0, 7, \csr
    TRIAL 1, 0, \csr
    TRIAL 1, 1, \csr
    TRIAL 1, 2, \csr
    TRIAL 1, 3, \csr
    TRIAL 1, 4, \csr
    TRIAL 1, 5, \csr
    TRIAL 1, 6, \csr
    TRIAL 1, 7, \csr
.endm

.section .text
.global main
main:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw  mstatush, x0              # mstatus.MDT   = 0
    csrw  mie, x0

    li    a0, PERIPH0
    li    a1, 0
    sw    a1, 0(a0)
    sw    a1, 4(a0)
    li    t1, 0x00010000            # mip[16]
    li    s0, 0
    li    s1, 0
    csrc  mip, t1

    li    x31, 0x11111111

    SWEEP mip

.if CFG_SU_MODE_EN
    csrs  mideleg, t1
    SWEEP sip
    csrc  mideleg, t1
.endif

    li    x31, 0xdeadbeef

end_of_test:
    nop
    j end_of_test
