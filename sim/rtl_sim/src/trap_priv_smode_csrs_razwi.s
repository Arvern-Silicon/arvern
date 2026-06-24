#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_smode_csrs_razwi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: SU_MODE PRIV - S-mode shadow CSRs RAZ/WI + misa[S]/misa[U]=0
#   Under SU_MODE_EN=0 the entire S-mode CSR shadow set is RAZ/WI:
#     sstatus(0x100), sie(0x104), stvec(0x105), scounteren(0x106),
#     sscratch(0x140), sepc(0x141), scause(0x142), stval(0x143),
#     sip(0x144), satp(0x180)
#   None of these accesses must trap (the CSR banks are still "known").
#   misa[18] (S) and misa[20] (U) must both read 0 to reflect the
#   advertised privilege set.
#
#   Phase 2: read all 10 S-mode CSRs at reset -> each must be 0; no traps.
#   Phase 3: write 0xDEADBEEF to all 10, re-read -> each must still be 0.
#   Phase 4: read misa -> verify bit[18]=0 and bit[20]=0.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count (must remain 0; any trap here is unexpected)
#   0x04: last MCAUSE (debug-only if a trap fires)
#
# Phase 2: pre-write reads (expect 0)
#   0x20: sstatus    (0x100)
#   0x24: sie        (0x104)
#   0x28: stvec      (0x105)
#   0x2C: scounteren (0x106)
#   0x30: sscratch   (0x140)
#   0x34: sepc       (0x141)
#   0x38: scause     (0x142)
#   0x3C: stval      (0x143)
#   0x40: sip        (0x144)
#   0x44: satp       (0x180)
#
# Phase 3: post-write reads (expect 0)
#   0x50: sstatus
#   0x54: sie
#   0x58: stvec
#   0x5C: scounteren
#   0x60: sscratch
#   0x64: sepc
#   0x68: scause
#   0x6C: stval
#   0x70: sip
#   0x74: satp
#
# Phase 4: misa
#   0x80: misa readback (S-bit must be 0, U-bit must be 0)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER (defensive; should never fire in this test)
    #=================================================================
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

    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)
    sw   t0, 0x3C(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)
    sw   t0, 0x58(s1)
    sw   t0, 0x5C(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x64(s1)
    sw   t0, 0x68(s1)
    sw   t0, 0x6C(s1)
    sw   t0, 0x70(s1)
    sw   t0, 0x74(s1)
    sw   t0, 0x80(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Initialize callee-saved registers (RV32E-safe markers in x0-x15)
    li   s0, 0xAAAAAAAA
    li   a0, 0xBBBBBBBB
    li   a1, 0xCCCCCCCC
    li   a2, 0xDDDDDDDD
    li   a3, 0xEEEEEEEE

    li   a5, 0x11111111


    #=================================================================
    # PHASE 2: Read all 10 S-mode shadow CSRs (expect 0, no trap)
    #=================================================================

    csrr t0, 0x100             # sstatus
    sw   t0, 0x20(s1)
    csrr t0, 0x104             # sie
    sw   t0, 0x24(s1)
    csrr t0, 0x105             # stvec
    sw   t0, 0x28(s1)
    csrr t0, 0x106             # scounteren
    sw   t0, 0x2C(s1)
    csrr t0, 0x140             # sscratch
    sw   t0, 0x30(s1)
    csrr t0, 0x141             # sepc
    sw   t0, 0x34(s1)
    csrr t0, 0x142             # scause
    sw   t0, 0x38(s1)
    csrr t0, 0x143             # stval
    sw   t0, 0x3C(s1)
    csrr t0, 0x144             # sip
    sw   t0, 0x40(s1)
    csrr t0, 0x180             # satp
    sw   t0, 0x44(s1)
    lw   t0, 0x44(s1)         # load-back fence

    li   a5, 0x22222222


    #=================================================================
    # PHASE 3: Write 0xDEADBEEF to each, re-read (expect still 0)
    #=================================================================

    li   t1, 0xDEADBEEF

    csrw 0x100, t1             # sstatus
    csrr t0, 0x100
    sw   t0, 0x50(s1)

    csrw 0x104, t1             # sie
    csrr t0, 0x104
    sw   t0, 0x54(s1)

    csrw 0x105, t1             # stvec
    csrr t0, 0x105
    sw   t0, 0x58(s1)

    csrw 0x106, t1             # scounteren
    csrr t0, 0x106
    sw   t0, 0x5C(s1)

    csrw 0x140, t1             # sscratch
    csrr t0, 0x140
    sw   t0, 0x60(s1)

    csrw 0x141, t1             # sepc
    csrr t0, 0x141
    sw   t0, 0x64(s1)

    csrw 0x142, t1             # scause
    csrr t0, 0x142
    sw   t0, 0x68(s1)

    csrw 0x143, t1             # stval
    csrr t0, 0x143
    sw   t0, 0x6C(s1)

    csrw 0x144, t1             # sip
    csrr t0, 0x144
    sw   t0, 0x70(s1)

    csrw 0x180, t1             # satp
    csrr t0, 0x180
    sw   t0, 0x74(s1)
    lw   t0, 0x74(s1)         # load-back fence

    li   a5, 0x33333333


    #=================================================================
    # PHASE 4: misa read - bit[18] (S) and bit[20] (U) must be 0
    #=================================================================

    csrr t0, misa              # 0x301
    sw   t0, 0x80(s1)
    lw   t0, 0x80(s1)         # load-back fence

    li   a5, 0xdeadbeef


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
