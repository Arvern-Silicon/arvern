#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_csr_value_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: value walk through every software-writable value CSR
#
#   Per CSR: write 0xFFFFFFFF, 0, then walking ones and walking zeros over all
#   32 bits (66 writes); each write is read back at once and compared with
#   (written & mask). Every CSR is restored before the next one is walked;
#   mtvec/marv_nmvec/stvec are trashed only between two CSR instructions, and
#   no trap is expected anywhere.
#
#   CSR          mask        basis
#   mtvec/stvec  ~0x2        traps_and_interrupts.md: "MODE is WARL: writes of
#                            2/3 store 0/1"
#   mepc/sepc/   IALIGN      Priv 3.1.14: "The low bit of mepc (mepc[0]) is
#   mnepc        (~1 with C, always zero. On implementations that support only
#                 ~3 without) IALIGN=32, the two low bits (mepc[1:0]) are
#                            always zero." Smrnmi: "The low bit of mnepc
#                            (mnepc[0]) is always zero. On implementations
#                            that support only IALIGN=32, the two low bits
#                            (mnepc[1:0]) are always zero."
#   mtval/stval  full        Priv 3.1.16: "a WARL register that must be able
#                            to hold all valid virtual addresses"
#   m/s/mnscratch full
#   mtval2       full / 0    arvern_instructions.md: "RAZ/WI when
#                            SU_MODE_EN == 0"; traps_and_interrupts.md
#                            "(full MRW 32-bit)"
#   marv_nmvec   ~0x3        arvern_instructions.md: "32-bit, 4-byte aligned;
#                            [1:0] read-only zero"
#   marv_ctl     0xF         arvern_instructions.md: "4 bits at [3:0]
#                            ([31:4] WARL-zero)"
#   jvt          ~0x3F       arvern_instructions.md: "BASE[31:6] writable
#                            (64-byte aligned), MODE[5:0] read-only 0"
#   tdata2       full        debug_interface.md: "32-bit match value"
#                            (trigger 0, disarmed by tdata1 = 0 first)
#   pmpaddr0     0x3FFFFFFF  arvern_instructions.md: "Granularity G = 0 ...
#                            pmpaddr[33:32] read as zero"; Priv 3.7.1: "Each
#                            PMP address register encodes bits 33-2 of a
#                            34-bit physical address for RV32" (pmpcfg0 OFF)
#
#   Not walked: marv_epc/marv_eaddr (MRO), marv_estat (W1C status), dpc and
#   dscratch0/1 (Debug-Mode only, illegal from the hart), counters (they
#   count), mhpmevent/tselect/tcontrol/status/enable/deleg registers (control
#   fields, covered by their own WARL tests). No CSR holds a critical-error
#   PC: critical-error entry changes no architectural state.
#
#   Results: s0 = compares executed, s1 = mismatches, s2 = first failing
#   CSR id, s3/s4 = its written/read value, s8 = traps taken.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSTATUS,  0x744
.equ MSTATUSH,  0x310

.if CFG_C_EXTENSION
.equ EPC_MASK,  0xFFFFFFFE
.else
.equ EPC_MASK,  0xFFFFFFFC
.endif

.if CFG_SU_MODE_EN
.equ MTVAL2_MASK, 0xFFFFFFFF
.else
.equ MTVAL2_MASK, 0x00000000
.endif

.section .text
.global main

main:
    j    _start

    .align 2
m_handler:
    addi s8, s8, 1
    csrr t2, mepc
    addi t2, t2, 4
    csrw mepc, t2
    mret

# a0 = value written, t0 = mask
.macro RT csr, id
    csrw \csr, a0
    csrr a1, \csr
    and  a2, a0, t0
    addi s0, s0, 1
    beq  a1, a2, 9f
    addi s1, s1, 1
    bnez s2, 9f
    li   s2, \id
    mv   s3, a0
    mv   s4, a1
9:
.endm

.macro WALK id, csr, mask, restore
    li   t0, \mask
    li   a0, -1
    RT   \csr, \id
    li   a0, 0
    RT   \csr, \id
    li   t1, 1
8:  mv   a0, t1
    RT   \csr, \id
    not  a0, t1
    RT   \csr, \id
    slli t1, t1, 1
    bnez t1, 8b
    csrw \csr, \restore
.endm

_start:
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE = 1 first
    csrw MSTATUSH, x0               # then MDT = 0

    li   s0, 0
    li   s1, 0
    li   s2, 0
    li   s3, 0
    li   s4, 0
    li   s8, 0
    la   s6, m_handler
    csrw mtvec, s6
    csrr s7, 0x7FD                  # marv_nmvec
    csrr s5, 0x7FF                  # marv_ctl

    li   x31, 0x11111111            # sync: init done

    WALK  1, 0x305, 0xFFFFFFFD, s6  # mtvec
    WALK  2, 0x341, EPC_MASK,   x0  # mepc
    WALK  3, 0x343, 0xFFFFFFFF, x0  # mtval
    WALK  4, 0x340, 0xFFFFFFFF, x0  # mscratch
    WALK  5, 0x34B, MTVAL2_MASK, x0 # mtval2
    WALK  6, 0x740, 0xFFFFFFFF, x0  # mnscratch
    WALK  7, 0x741, EPC_MASK,   x0  # mnepc
    WALK  8, 0x7FD, 0xFFFFFFFC, s7  # marv_nmvec
    WALK  9, 0x7FF, 0x0000000F, s5  # marv_ctl
.if CFG_SU_MODE_EN
    WALK 10, 0x105, 0xFFFFFFFD, s6  # stvec
    WALK 11, 0x141, EPC_MASK,   x0  # sepc
    WALK 12, 0x143, 0xFFFFFFFF, x0  # stval
    WALK 13, 0x140, 0xFFFFFFFF, x0  # sscratch
.endif
.if CFG_C_EXTENSION >= 4
    WALK 14, 0x017, 0xFFFFFFC0, x0  # jvt
.endif
.if CFG_DEBUG_EN
.if CFG_DM_TRIGGER_NR > 0
    csrw 0x7A0, x0                  # tselect = 0
    csrw 0x7A1, x0                  # tdata1 = 0: disarmed
    WALK 15, 0x7A2, 0xFFFFFFFF, x0  # tdata2
.endif
.endif
.if CFG_PMP_NR > 0
    WALK 16, 0x3B0, 0x3FFFFFFF, x0  # pmpaddr0
.endif

    csrr t0, mtvec                  # restored vectors
    csrr t1, 0x7FD
    csrr t2, 0x7FF
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
