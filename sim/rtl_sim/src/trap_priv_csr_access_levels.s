#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_csr_access_levels
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSR PRIV LEVELS - address-encoded CSR privilege from U and S
#   Requires SU_MODE_EN==1.
#
#   Priv §2.1: "The next two bits (csr[9:8]) encode the lowest privilege
#   level that can access the CSR." and "Attempts to access a CSR without
#   appropriate privilege level raise illegal-instruction exceptions".
#   aRVern writes mtval = 0 on an illegal instruction (spec-legal).
#
#   Phase U (MPP=U at trap): every S-level (0x1xx) and M-level (0x3xx,
#     0x7xx, 0xFxx) CSR access (reads, and writes to sscratch, sepc, stvec,
#     scounteren, mscratch) traps with mcause=2, mtval=0,
#     mepc=&probe, and rd is left unwritten.
#   Phase S (MPP=S at trap): every M-level CSR access traps the same way,
#     including the core's custom M-level CSRs marv_ctl (0x7FF) and
#     marv_epc (0xFFC). Two sscratch accesses are legal controls (no trap,
#     rd written).
#   Final (M): the CSRs that U/S tried to write (mscratch, sscratch before
#     the S control, sepc, stvec) keep their M-written values.
#
#   Probe mechanism: s2 = probe index, s3 = address of the probing
#   instruction, a0 = sentinel 0x5A5A5A5A (the rd of every probe), a1 = the
#   write operand. The M handler (illegal-instruction only) records, in the
#   32-byte slot 0x100 + 32*index: +0 mcause, +4 mtval, +8 mepc-s3, +12 MPP.
#   The probe then stores a0 to +16. Slots are pre-filled with 0xEEEEEEEE,
#   so a probe that does not trap leaves +0 at 0xEEEEEEEE. Every handler
#   exit leaves mtval at 0x7EEDBEEF, so mtval=0 in a slot proves the trap
#   wrote it.
#
#   Scratchpad (base 0x80000000):
#   0x00: illegal-instruction trap count   (expect 31)
#   0x04: unexpected-trap mcause (0 if none)
#   0x08: mscratch at end  (expect 0x2468ACE0)
#   0x0C: sepc at end      (expect 0x20001230)
#   0x10: stvec at end     (expect 0x20000100)
#   0x14: sscratch at end  (expect 0xA5A5A5A5, written by the S control)
#   0x100+: probe slots
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ SPAD,       0x80000000
.equ SLOT_BASE,  0x80000100
.equ SENT,       0x5A5A5A5A
.equ NSLOTS,     33

.macro PROBE idx, insn:vararg
    li   s2, \idx
    li   a0, SENT
    la   s3, 991f
991:
    \insn
    li   t0, SLOT_BASE + (\idx * 32)
    sw   a0, 16(t0)
.endm

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE HANDLER (direct). Uses t3-t6 only.
    #=================================================================
    .align 2
m_handler:
    csrr t3, mcause
    li   t4, 2
    beq  t3, t4, m_illegal
    li   t4, 8
    beq  t3, t4, m_from_u
    li   t4, 9
    beq  t3, t4, m_from_s
    sw   t3, 0x04(s1)
    li   x31, 0x0BADBADB
m_fail_loop:
    j    m_fail_loop

m_illegal:
    slli t4, s2, 5
    add  t4, t4, s1
    sw   t3, 0x100(t4)          # mcause
    csrr t5, mtval
    sw   t5, 0x104(t4)          # mtval
    csrr t5, mepc
    sub  t6, t5, s3
    sw   t6, 0x108(t4)          # mepc - &probe (expect 0)
    csrr t6, mstatus
    srli t6, t6, 11
    andi t6, t6, 3
    sw   t6, 0x10C(t4)          # MPP
    lw   t6, 0x00(s1)
    addi t6, t6, 1
    sw   t6, 0x00(s1)
    addi t5, t5, 4              # every probe is a 32-bit CSR instruction
    li   t6, 0x7EEDBEEF
    csrw mtval, t6              # marker: the next trap must write mtval
    csrw mepc, t5
    mret

m_from_u:                       # U phase done -> enter S phase
    li   t4, 0x1800
    csrc mstatus, t4
    li   t4, 0x0800
    csrs mstatus, t4
    la   t4, s_code
    csrw mepc, t4
    li   t6, 0x7EEDBEEF
    csrw mtval, t6
    mret

m_from_s:                       # S phase done -> back to M
    li   t4, 0x1800
    csrs mstatus, t4
    la   t4, m_final
    csrw mepc, t4
    mret

    #=================================================================
    # MAIN
    #=================================================================
    .align 2
_start:
    csrsi 0x744, 8              # mnstatus.NMIE = 1 (Smrnmi boot, first)
    csrw  mstatush, x0          # mstatus.MDT = 0 (Smdbltrp boot, second)

    PMP_ALLOW_ALL
    li   s1, SPAD

    # Clear the summary words, pre-fill the probe slots
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x10(s1)
    sw   zero, 0x14(s1)
    li   t0, SLOT_BASE
    li   t1, SLOT_BASE + (NSLOTS * 32)
    li   t2, 0xEEEEEEEE
fill_loop:
    sw   t2, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, fill_loop

    la   t0, m_handler
    csrw mtvec, t0
    li   t0, 0x7EEDBEEF
    csrw mtval, t0              # marker: the first trap must write mtval

    # Known values in the CSRs U/S will try to write (no delegation:
    # medeleg/mideleg stay 0, so stvec is never used as a vector)
    li   t0, 0x2468ACE0
    csrw mscratch, t0
    li   t0, 0x13572468
    csrw sscratch, t0
    li   t0, 0x20001230
    csrw sepc, t0
    li   t0, 0x20000100
    csrw stvec, t0
    csrw medeleg, zero
    csrw mideleg, zero

    li   a1, 0xA5A5A5A5
    li   x31, 0x11111111

    # Enter U-mode (MPP=00)
    li   t0, 0x1800
    csrc mstatus, t0
    la   t0, u_code
    csrw mepc, t0
    mret

    #=================================================================
    # U-MODE PROBES (all must trap, MPP=U)
    #=================================================================
    .align 2
u_code:
    PROBE  0, csrr  a0, sstatus
    PROBE  1, csrrw a0, sscratch, a1
    PROBE  2, csrrs a0, stvec, x0
    PROBE  3, csrr  a0, scause
    PROBE  4, csrw  sepc, a1
    PROBE  5, csrr  a0, stval
    PROBE  6, csrr  a0, sie
    PROBE  7, csrrc a0, sip, a1
    PROBE  8, csrr  a0, satp
    PROBE  9, csrrw a0, scounteren, a1
    PROBE 10, csrr  a0, mstatus
    PROBE 11, csrrw a0, mscratch, a1
    PROBE 12, csrr  a0, mepc
    PROBE 13, csrr  a0, mtvec
    PROBE 14, csrr  a0, mhartid
    PROBE 15, csrr  a0, 0x744         # mnstatus
    PROBE 32, csrw  stvec, a1
    ecall                              # cause 8 -> S phase

    #=================================================================
    # S-MODE PROBES (M-level CSRs trap with MPP=S; sscratch legal)
    #=================================================================
    .align 2
s_code:
    PROBE 16, csrr  a0, mstatus
    PROBE 17, csrrw a0, mscratch, a1
    PROBE 18, csrr  a0, mtvec
    PROBE 19, csrw  mepc, a1
    PROBE 20, csrr  a0, mcause
    PROBE 21, csrr  a0, mie
    PROBE 22, csrr  a0, mip
    PROBE 23, csrr  a0, medeleg
    PROBE 24, csrr  a0, 0x31A         # menvcfgh
    PROBE 25, csrr  a0, 0x740         # mnscratch
    PROBE 26, csrr  a0, mvendorid
    PROBE 27, csrr  a0, 0x7FF         # marv_ctl (custom, M-level address)
    PROBE 28, csrr  a0, 0xFFC         # marv_epc (custom, M-level read-only)
    PROBE 29, csrrw a0, sscratch, a1  # legal: rd = 0x13572468
    PROBE 30, csrr  a0, sscratch      # legal: rd = 0xA5A5A5A5
    PROBE 31, csrr  a0, 0x34B         # mtval2
    ecall                              # cause 9 -> back to M

    #=================================================================
    # FINAL (M)
    #=================================================================
    .align 2
m_final:
    csrr t0, mscratch
    sw   t0, 0x08(s1)
    csrr t0, sepc
    sw   t0, 0x0C(s1)
    csrr t0, stvec
    sw   t0, 0x10(s1)
    csrr t0, sscratch
    sw   t0, 0x14(s1)
    lw   t0, 0x14(s1)           # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
