#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_smode_csrs_absent
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SU_MODE PRIV - the S-mode CSRs do not exist, and neither do the
#              registers that only serve a lower privilege
#
#   With SU_MODE_EN=0 a hart has no S-mode, so per Priv 2.1 the S-mode CSR
#   addresses are non-existent and every access raises illegal-instruction:
#     sstatus(0x100) sie(0x104) stvec(0x105) scounteren(0x106)
#     sscratch(0x140) sepc(0x141) scause(0x142) stval(0x143) sip(0x144) satp(0x180)
#
#   The same applies to three M-mode registers whose only purpose is to serve a
#   lower privilege, and which the spec therefore ties to S/U existing:
#     medeleg(0x302) mideleg(0x303)  -- Priv 3.1.8: "In harts without S-mode, the
#                                      medeleg and mideleg registers should not exist"
#     mcounteren(0x306)             -- Priv 3.1.11: required only if U-mode exists
#     menvcfg(0x30A) menvcfgh(0x31A) -- configure the next-lower privilege
#
#   misa[18] (S) and misa[20] (U) must both read 0 to match.
#
#   Phase 2: read each of the 15 addresses -> 15 illegal-instruction traps
#   Phase 3: write each of the 15 -> 15 more traps (30 total)
#   Phase 4: misa bits 18 and 20 are zero
#
# Requires SU_MODE_EN==0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#   0x00: trap count
#   0x04: last MCAUSE
#=========================================================================

main:
    j _start

    .align 2

trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    csrr t0, mcause
    csrr t1, mepc

    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)
    sw   t0, 0x04(s1)

    # Every faulting access here is a 32-bit CSR instruction.
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

#=========================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)

    la   t0, trap_handler
    csrw mtvec, t0

    # Arm NMIE, then clear MDT. Either left alone makes every M-mode trap
    # "unexpected", diverting it away from mtvec.
    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw  mstatush, x0          # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    #=================================================================
    # PHASE 2: every read traps
    #=================================================================
    csrr t0, 0x100              # sstatus
    csrr t0, 0x104              # sie
    csrr t0, 0x105              # stvec
    csrr t0, 0x106              # scounteren
    csrr t0, 0x140              # sscratch
    csrr t0, 0x141              # sepc
    csrr t0, 0x142              # scause
    csrr t0, 0x143              # stval
    csrr t0, 0x144              # sip
    csrr t0, 0x180              # satp
    csrr t0, 0x302              # medeleg
    csrr t0, 0x303              # mideleg
    csrr t0, 0x306              # mcounteren
    csrr t0, 0x30A              # menvcfg
    csrr t0, 0x31A              # menvcfgh

    lw   a0, 0x00(s1)           # trap count -- expect 15
    lw   a1, 0x04(s1)           # last MCAUSE -- expect 2 (illegal instruction)
    addi t0, a1, 0              # consume the load: hold the sync until it retires

    li   x31, 0x11111111

    #=================================================================
    # PHASE 3: every write traps too
    #=================================================================
    li   t1, 0xDEADBEEF
    csrw 0x100, t1
    csrw 0x104, t1
    csrw 0x105, t1
    csrw 0x106, t1
    csrw 0x140, t1
    csrw 0x141, t1
    csrw 0x142, t1
    csrw 0x143, t1
    csrw 0x144, t1
    csrw 0x180, t1
    csrw 0x302, t1
    csrw 0x303, t1
    csrw 0x306, t1
    csrw 0x30A, t1
    csrw 0x31A, t1

    lw   a2, 0x00(s1)           # trap count -- expect 30
    addi t0, a2, 0              # consume the load: hold the sync until it retires

    #=================================================================
    # PHASE 4: misa advertises neither S nor U
    #=================================================================
    csrr a3, misa

    li   x31, 0x22222222

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
1:  j    1b
