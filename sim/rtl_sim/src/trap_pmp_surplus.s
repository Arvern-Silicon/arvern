#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_surplus
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP entries beyond PMP_NR are read-only zero and inert
#
#   Sixteen entries always exist architecturally; only the first PMP_NR are
#   writable and the rest read as zero (Priv 3.7.1). Writing the strongest
#   possible rule to a surplus entry -- locked, no permissions, NAPOT over the
#   whole address space -- must change nothing: the registers read back zero
#   and an ordinary store still lands. The last writable entry, by contrast,
#   takes a harmless write and reads it back.
#
# Requires 0 < PMP_NR < 16.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    .align 2
m_trap_handler:                 # any trap here is a failure: park
    li   x31, 0x0BAD0BAD
9:  j    9b

#=========================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    la   t0, m_trap_handler
    csrw mtvec, t0

    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw  mstatush, x0          # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    #-----------------------------------------------------------------
    # Entry 15 is surplus in every PMP_NR < 16 build.
    #-----------------------------------------------------------------
    li   t0, 0xFFFFFFFF
    csrw pmpaddr15, t0
    csrr a0, pmpaddr15          # expect 0
    li   t0, 0x98000000         # entry 15 = L | NAPOT, no permissions
    csrw pmpcfg3, t0
    csrr a1, pmpcfg3            # expect 0

    li   t0, 0x12345678
    sw   t0, 0x40(s1)           # would be refused if entry 15 were live
    lw   a2, 0x40(s1)           # expect 0x12345678

    #-----------------------------------------------------------------
    # The first surplus entry and the last writable one.
    #-----------------------------------------------------------------
.if CFG_PMP_NR == 4
    li   t0, 0x0BADF00D
    csrw pmpaddr4, t0
    csrr a3, pmpaddr4           # expect 0
    li   t0, 0x00000001         # entry 4 = R, A=OFF
    csrw pmpcfg1, t0
    csrr a4, pmpcfg1            # expect 0

    li   t0, 0x0BADF00D
    csrw pmpaddr3, t0
    csrr a5, pmpaddr3           # expect 0x0BADF00D
    li   t0, 0x01000000         # entry 3 = R, A=OFF: harmless
    csrw pmpcfg0, t0
    csrr a6, pmpcfg0            # expect 0x01000000
.elseif CFG_PMP_NR == 8
    li   t0, 0x0BADF00D
    csrw pmpaddr8, t0
    csrr a3, pmpaddr8           # expect 0
    li   t0, 0x00000001
    csrw pmpcfg2, t0
    csrr a4, pmpcfg2            # expect 0

    li   t0, 0x0BADF00D
    csrw pmpaddr7, t0
    csrr a5, pmpaddr7           # expect 0x0BADF00D
    li   t0, 0x01000000
    csrw pmpcfg1, t0
    csrr a6, pmpcfg1            # expect 0x01000000
.endif

    addi t0, a2, 0

    li   x31, 0x11111111

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
8:  j    8b
