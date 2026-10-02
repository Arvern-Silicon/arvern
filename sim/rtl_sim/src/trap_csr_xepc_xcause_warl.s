#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_csr_xepc_xcause_warl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: XEPC/XCAUSE WARL - trap CSR write/read-back rules
#   Runs in M-mode on every configuration; the S-bank part is assembled only
#   when CFG_SU_MODE_EN.
#
#   mepc/sepc (Priv §3.1.14, §12.1.7): "The low bit of mepc (mepc[0]) is
#     always zero. On implementations that support only IALIGN=32, the two
#     low bits (mepc[1:0]) are always zero." and "mepc is a WARL register
#     that must be able to hold all valid virtual addresses." misa is
#     read-only here, so IALIGN is fixed: C present -> mask 0xFFFFFFFE,
#     C absent -> mask 0xFFFFFFFC. Without translation every 32-bit value is
#     a valid physical address (pmpaddr[31:30] read 0: 32-bit space), so the
#     other bits must round-trip.
#   mtval/stval (Priv §3.1.16, §12.1.9): "a WARL register that must be able
#     to hold all valid virtual addresses and the value 0" -> full 32-bit
#     round-trip.
#   mcause/scause (Priv §3.1.15, §12.1.8): "The Exception Code is a WLRL
#     field, so is only guaranteed to hold supported exception codes." Only
#     supported values are read back; an all-ones write is checked for "no
#     trap" only (WLRL, Priv §2.3.2: may return arbitrary bits), followed by
#     a supported value that must read back.
#   mtinst (0x34A), medelegh (0x312): RAZ/WI (arvern_instructions.md CSR
#     table) -- no trap, read 0 after an all-ones write.
#   mtval2 (0x34B): full 32-bit MRW at SU_MODE_EN=1, RAZ/WI at SU_MODE_EN=0
#     (arvern_instructions.md).
#
#   Every access is a PROBE: s2 = index, s3 = &probe, a0 = sentinel
#   0x5A5A5A5A. A trap records into slot 0x100 + 32*index (+0 mcause) and is
#   skipped; a non-trapping probe leaves +0 at 0xEEEEEEEE. +16 = rd after.
#
#   Scratchpad (base 0x80000000):
#   0x00: trap count (expect 0)
#   0x04: unexpected (non-illegal) mcause (0 if none)
#   0x100+: probe slots
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ SPAD,       0x80000000
.equ SLOT_BASE,  0x80000100
.equ SENT,       0x5A5A5A5A
.equ NSLOTS,     51

.macro PROBE idx, insn:vararg
    li   s2, \idx
    li   a0, SENT
    la   s3, 991f
991:
    \insn
    li   t0, SLOT_BASE + (\idx * 32)
    sw   a0, 16(t0)
.endm

# write pattern then read back: two probes (w_idx, w_idx+1)
.macro WR_RD idx, csr, val
    li   a1, \val
    PROBE \idx, csrw \csr, a1
    PROBE (\idx + 1), csrr a0, \csr
.endm

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE HANDLER (direct). Uses t3-t6 only. Any trap is a failure;
    # an illegal-instruction is recorded in the probe slot and skipped.
    #=================================================================
    .align 2
m_handler:
    csrr t3, mcause
    li   t4, 2
    beq  t3, t4, m_illegal
    sw   t3, 0x04(s1)
    li   x31, 0x0BADBADB
m_fail_loop:
    j    m_fail_loop

m_illegal:
    slli t4, s2, 5
    add  t4, t4, s1
    sw   t3, 0x100(t4)
    csrr t5, mtval
    sw   t5, 0x104(t4)
    csrr t5, mepc
    sub  t6, t5, s3
    sw   t6, 0x108(t4)
    csrr t6, mstatus
    srli t6, t6, 11
    andi t6, t6, 3
    sw   t6, 0x10C(t4)
    lw   t6, 0x00(s1)
    addi t6, t6, 1
    sw   t6, 0x00(s1)
    addi t5, t5, 4
    csrw mepc, t5
    mret

    #=================================================================
    # MAIN
    #=================================================================
    .align 2
_start:
    csrsi 0x744, 8              # mnstatus.NMIE = 1 (first)
    csrw  mstatush, x0          # mstatus.MDT = 0 (second)

    li   s1, SPAD
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    li   t0, SLOT_BASE
    li   t1, SLOT_BASE + (NSLOTS * 32)
    li   t2, 0xEEEEEEEE
fill_loop:
    sw   t2, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, fill_loop

    la   t0, m_handler
    csrw mtvec, t0

    li   x31, 0x11111111

    # ---- mepc: IALIGN low-bit mask, other bits round-trip ----
    WR_RD  0, mepc, 0xFFFFFFFF
    WR_RD  2, mepc, 0xAAAAAAAA
    WR_RD  4, mepc, 0x55555555

    # ---- mtval: full width ----
    WR_RD  6, mtval, 0xFFFFFFFF
    WR_RD  8, mtval, 0xAAAAAAAA
    WR_RD 10, mtval, 0x55555555

    # ---- mcause: supported codes read back ----
    WR_RD 12, mcause, 0x0000000B    # ECALL from M
    WR_RD 14, mcause, 0x80000007    # MTI
    WR_RD 16, mcause, 0x8000001F    # platform IRQ 15 (cause 31)
    WR_RD 18, mcause, 0x00000002    # illegal instruction

    # ---- mcause: all-ones must not trap; a supported value then reads back ----
    li   a1, 0xFFFFFFFF
    PROBE 20, csrw mcause, a1
    WR_RD 21, mcause, 0x80000003    # MSI

    # ---- mtinst (0x34A): RAZ/WI ----
    li   a1, 0xFFFFFFFF
    PROBE 23, csrw 0x34A, a1
    PROBE 24, csrr a0, 0x34A
    li   a1, 0xAAAAAAAA
    PROBE 25, csrrw a0, 0x34A, a1

    # ---- medelegh (0x312): RAZ/WI ----
    WR_RD 26, 0x312, 0xFFFFFFFF

    # ---- mtval2 (0x34B): MRW with S/U, RAZ/WI without ----
    WR_RD 28, 0x34B, 0xA5A5A5A5

.if CFG_SU_MODE_EN
    # ---- sepc: same IALIGN rule as mepc ----
    WR_RD 30, sepc, 0xFFFFFFFF
    WR_RD 32, sepc, 0xAAAAAAAA
    WR_RD 34, sepc, 0x55555555

    # ---- stval: full width ----
    WR_RD 36, stval, 0xFFFFFFFF
    WR_RD 38, stval, 0xAAAAAAAA
    WR_RD 40, stval, 0x55555555

    # ---- scause: supported S-level codes read back ----
    WR_RD 42, scause, 0x80000009    # SEI
    WR_RD 44, scause, 0x00000008    # ECALL from U
    WR_RD 46, scause, 0x8000001F    # delegated platform IRQ 15

    # ---- scause: all-ones must not trap; a supported value then reads back ----
    li   a1, 0xFFFFFFFF
    PROBE 48, csrw scause, a1
    WR_RD 49, scause, 0x80000001    # SSI
.endif

    lw   t0, 0x00(s1)           # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
