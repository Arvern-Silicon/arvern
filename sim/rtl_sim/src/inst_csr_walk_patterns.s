#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_walk_patterns
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: walking-ones / walking-zeros through every writable
#              address-holding CSR, read back against its WARL rule
#
#   Each CSR k gets 32 walking-ones and 32 walking-zeros writes, each read
#   back immediately. Expected read-back = written & mask:
#     mtvec (0x305), stvec (0x105): mask ~0x2 -- traps_and_interrupts.md §11:
#       "MODE is WARL: writes of 2/3 store 0/1"; BASE otherwise unconstrained.
#     mepc (0x341), sepc (0x141), mnepc (0x741): IALIGN mask -- Priv §3.1.14:
#       "The low bit of mepc (mepc[0]) is always zero. On implementations that
#       support only IALIGN=32, the two low bits (mepc[1:0]) are always zero."
#       Smrnmi mnepc: "whenever IALIGN=32, bit mnepc[1] is masked on reads".
#       misa is read-only here, so C present -> ~0x1, C absent -> ~0x3.
#     mtval (0x343), stval (0x143): full width -- Priv §3.1.16 "a WARL
#       register that must be able to hold all valid virtual addresses".
#     mscratch (0x340), sscratch (0x140), mnscratch (0x740): full width.
#     jvt (0x017, C_EXTENSION >= 4): mask ~0x3F -- arvern_instructions.md:
#       "BASE[31:6] writable (64-byte aligned), MODE[5:0] read-only 0".
#   S-mode CSRs only when SU_MODE_EN. dpc is debug-only and skipped.
#   Every CSR is restored to a safe value right after its walk (mtvec to the
#   test handler); no trap is expected at all.
#
#   0x80000400 + 256*k: +4*i walking-one read-back, +128+4*i walking-zero
#   0x80000000: trap count (0 expected)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSTATUS,  0x744
.equ MSTATUSH,  0x310
.equ RES,       0x80000400

.section .text
.global main

main:
    j    _start

    .align 2
m_handler:
    lw   t0, 0(s1)
    addi t0, t0, 1
    sw   t0, 0(s1)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

.macro WALK k, csr, restore
    li   a1, RES + 256*\k
    li   t2, 1
    li   t3, 32
1:  csrw \csr, t2
    csrr t0, \csr
    sw   t0, 0(a1)
    not  t1, t2
    csrw \csr, t1
    csrr t0, \csr
    sw   t0, 128(a1)
    addi a1, a1, 4
    slli t2, t2, 1
    addi t3, t3, -1
    bnez t3, 1b
    csrw \csr, \restore
.endm

_start:
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE = 1 first
    csrw MSTATUSH, x0               # then MDT = 0

    li   sp, 0x80010000
    li   s1, 0x80000000
    mv   t0, s1
    li   t1, 0x80000F00
1:  sw   x0, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b

    la   s2, m_handler
    csrw mtvec, s2

    li   x31, 0x11111111            # sync: init done

    WALK 0, 0x305, s2               # mtvec -> back to the handler
.if CFG_SU_MODE_EN
    WALK 1, 0x105, s2               # stvec
.endif
    WALK 2, 0x341, x0               # mepc
.if CFG_SU_MODE_EN
    WALK 3, 0x141, x0               # sepc
.endif
    WALK 4, 0x741, x0               # mnepc
    WALK 5, 0x343, x0               # mtval
.if CFG_SU_MODE_EN
    WALK 6, 0x143, x0               # stval
.endif
    WALK 7, 0x340, x0               # mscratch
.if CFG_SU_MODE_EN
    WALK 8, 0x140, x0               # sscratch
.endif
    WALK 9, 0x740, x0               # mnscratch
.if CFG_C_EXTENSION >= 4
    WALK 10, 0x017, x0              # jvt
.endif

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
