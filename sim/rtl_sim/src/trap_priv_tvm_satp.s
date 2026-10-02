#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_tvm_satp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TVM SATP - mstatus.TVM gates S-mode satp access
#   Requires SU_MODE_EN==1.
#
#   Priv §3.1.6.6: "When TVM=1, attempts to read or write the satp CSR or
#   execute an SFENCE.VMA or SINVAL.VMA instruction while executing in
#   S-mode will raise an illegal-instruction exception. When TVM=0, these
#   operations are permitted in S-mode."
#   Priv §12.1.11: "if satp is written with an unsupported MODE, the entire
#   write has no effect; no fields in satp are modified."
#   aRVern (arvern_instructions.md): satp is a WARL stub, reads 0 (MODE =
#   Bare), writes ignored; TVM is writable.
#
#   Phase S0 (TVM=0): S reads satp (0), writes Sv32 MODE (0x80000001, no
#     effect by spec), writes Bare+PPN (0x00000123, ignored per doc) -- no
#     trap, every read returns 0.
#   Phase M1: M sets TVM=1 (readback), then reads/writes satp: no trap
#     (TVM only affects S-mode), reads 0.
#   Phase S1 (TVM=1): csrr / csrrs x0 / csrw / csrrw x0 / csrrci 0 on satp
#     all trap (mcause=2, mtval=0, mepc=&probe, MPP=S, rd unwritten);
#     sscratch stays legal (control).
#   Phase M2: M clears TVM (readback).
#   Phase S2 (TVM=0 again): csrr satp no longer traps.
#
#   Probe mechanism as in trap_priv_csr_access_levels: s2 = index, s3 =
#   &probe, a0 = sentinel 0x5A5A5A5A. Slot 0x100 + 32*index: +0 mcause,
#   +4 mtval, +8 mepc-s3, +12 MPP, +16 rd; pre-filled 0xEEEEEEEE.
#
#   Scratchpad (base 0x80000000):
#   0x00: illegal-instruction trap count  (expect 5)
#   0x04: unexpected-trap mcause (0 if none)
#   0x08: mstatus.TVM after set    (expect 0x00100000)
#   0x0C: mstatus.TVM after clear  (expect 0)
#   0x100+: probe slots
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ SPAD,       0x80000000
.equ SLOT_BASE,  0x80000100
.equ SENT,       0x5A5A5A5A
.equ NSLOTS,     16
.equ TVM_BIT,    0x00100000

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
    #   cause 2: record the probe, skip it
    #   cause 9: ECALL from S -> continue in M at the address held in s4
    #=================================================================
    .align 2
m_handler:
    csrr t3, mcause
    li   t4, 2
    beq  t3, t4, m_illegal
    li   t4, 9
    beq  t3, t4, m_from_s
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
    li   t6, 0x7EEDBEEF
    csrw mtval, t6              # marker: the next trap must write mtval
    csrw mepc, t5
    mret

m_from_s:
    li   t4, 0x1800
    csrs mstatus, t4            # MPP = M
    csrw mepc, s4
    li   t6, 0x7EEDBEEF
    csrw mtval, t6              # marker: the next trap must write mtval
    mret

    #=================================================================
    # Enter S at the address in t1; ECALL from S resumes M at s4.
    #=================================================================
enter_s:
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0            # MPP = S
    csrw mepc, t1
    mret

    #=================================================================
    # MAIN
    #=================================================================
    .align 2
_start:
    csrsi 0x744, 8              # mnstatus.NMIE = 1 (first)
    csrw  mstatush, x0          # mstatus.MDT = 0 (second)

    PMP_ALLOW_ALL
    li   s1, SPAD

    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
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
    csrw medeleg, zero
    csrw mideleg, zero
    li   t0, 0x0BADF00D
    csrw sscratch, t0

    li   t0, TVM_BIT
    csrc mstatus, t0            # TVM = 0

    li   x31, 0x11111111

    la   s4, m_phase1
    la   t1, s_phase0
    j    enter_s

    #-----------------------------------------------------------------
    # S, TVM=0: satp accessible, reads 0
    #-----------------------------------------------------------------
    .align 2
s_phase0:
    li   a1, 0x80000001                     # MODE=Sv32, PPN=1 (unsupported)
    PROBE  0, csrr  a0, satp                # rd = 0
    PROBE  1, csrrw a0, satp, a1            # rd = 0 (old value)
    PROBE  2, csrr  a0, satp                # rd = 0 (write had no effect)
    li   a1, 0x00000123                     # MODE=Bare, PPN!=0
    PROBE  3, csrrw a0, satp, a1            # rd = 0
    PROBE  4, csrr  a0, satp                # rd = 0 (writes ignored, doc)
    ecall

    #-----------------------------------------------------------------
    # M, TVM=1: M-mode satp access unaffected
    #-----------------------------------------------------------------
    .align 2
m_phase1:
    li   t0, TVM_BIT
    csrs mstatus, t0
    csrr t0, mstatus
    li   t1, TVM_BIT
    and  t0, t0, t1
    sw   t0, 0x08(s1)

    li   a1, 0x80000001
    PROBE  5, csrr  a0, satp                # no trap, rd = 0
    PROBE  6, csrrw a0, satp, a1            # no trap, rd = 0
    PROBE  7, csrr  a0, satp                # no trap, rd = 0

    li   x31, 0x22222222
    la   s4, m_phase2
    la   t1, s_phase1
    j    enter_s

    #-----------------------------------------------------------------
    # S, TVM=1: every satp access traps; sscratch still legal
    #-----------------------------------------------------------------
    .align 2
s_phase1:
    li   a1, 0x00000000
    PROBE  8, csrr   a0, satp
    PROBE  9, csrrs  a0, satp, x0
    PROBE 10, csrw   satp, a1
    PROBE 11, csrrw  a0, satp, x0
    PROBE 12, csrrci a0, satp, 0
    PROBE 13, csrr   a0, sscratch           # control: rd = 0x0BADF00D
    ecall

    #-----------------------------------------------------------------
    # M: clear TVM
    #-----------------------------------------------------------------
    .align 2
m_phase2:
    li   t0, TVM_BIT
    csrc mstatus, t0
    csrr t0, mstatus
    li   t1, TVM_BIT
    and  t0, t0, t1
    sw   t0, 0x0C(s1)

    li   x31, 0x33333333
    la   s4, m_final
    la   t1, s_phase2
    j    enter_s

    #-----------------------------------------------------------------
    # S, TVM=0 again: satp accessible
    #-----------------------------------------------------------------
    .align 2
s_phase2:
    PROBE 14, csrr  a0, satp                # no trap, rd = 0
    ecall

    .align 2
m_final:
    lw   t0, 0x0C(s1)           # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
