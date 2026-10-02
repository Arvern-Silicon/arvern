#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_mnret_below_m
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MNRET executed below M-mode raises illegal instruction
#
#   Priv §8.4 (Smrnmi): "MNRET is an M-mode-only instruction that uses the
#   values in mnepc and mnstatus to return to the program counter, privilege
#   mode, and virtualization mode of the interrupted context."
#   traps_and_interrupts.md §2, cause 2: "a privileged instruction
#   (MRET/SRET/MNRET/WFI) executed at insufficient privilege".
#   traps_and_interrupts.md §2 mtval table: cause 2 -> "0".
#   Priv §3.1.8: "if M-mode has delegated illegal-instruction exceptions to
#   S-mode, and S-mode software later executes an illegal instruction, the
#   trap is taken in S-mode."
#
#   mnepc is seeded with the address of bad_landing: an MNRET that were
#   executed instead of trapping would jump there and set the BAD flag.
#
#   Case 0  S-mode, medeleg[2]=0 -> M handler, mcause 2, mepc = MNRET, MPP = S
#   Case 1  U-mode, medeleg[2]=0 -> M handler, mcause 2, mepc = MNRET, MPP = U
#   Case 2  S-mode, medeleg[2]=1 -> S handler, scause 2, sepc = MNRET, SPP = S
#   Case 3  U-mode, medeleg[2]=1 -> S handler, scause 2, sepc = MNRET, SPP = U
#   Each case then executes the next instruction (continue marker) in the
#   original mode and returns to M with ECALL (medeleg[8]/[9] stay 0).
#
#   Slot k at 0x80000100 + 32*k:
#     +0 handler id (1 = M, 2 = S)   +4 cause   +8 epc   +12 tval
#     +16 previous privilege (MPP or SPP)       +20 expected epc (MNRET PC)
#     +24 continue marker 0x600D0000|k          +28 cause-2 trap count
#   0x80000000: BAD flag (0 expected)   0x80000004: unexpected-cause count
#   0x80000008: mnepc at the end         0x8000000C: expected mnepc
#   0x80000010: mnstatus at the end
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSCRATCH, 0x740
.equ MNEPC,     0x741
.equ MNSTATUS,  0x744
.equ MSTATUSH,  0x310
.equ SLOTS,     0x80000100

.section .text
.global main

main:
    j    _start

#=========================================================================
# M-mode handler: cause 2 is recorded and skipped; ECALL from S/U (8/9)
# returns to M-mode at s11.
#=========================================================================
    .align 2
m_handler:
    csrr t0, mcause
    li   t1, 8
    beq  t0, t1, m_to_m
    li   t1, 9
    beq  t0, t1, m_to_m
    li   t1, 2
    bne  t0, t1, m_unexpected
    li   t1, 1
    sw   t1, 0(s9)
    sw   t0, 4(s9)
    csrr t1, mepc
    sw   t1, 8(s9)
    csrr t2, mtval
    sw   t2, 12(s9)
    csrr t2, mstatus
    srli t2, t2, 11
    andi t2, t2, 3
    sw   t2, 16(s9)
    lw   t2, 28(s9)
    addi t2, t2, 1
    sw   t2, 28(s9)
    addi t1, t1, 4
    csrw mepc, t1
    mret
m_unexpected:
    lw   t1, 4(s1)
    addi t1, t1, 1
    sw   t1, 4(s1)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    mret
m_to_m:
    li   t1, 0x1800
    csrs mstatus, t1               # MPP = M
    csrw mepc, s11
    mret

#=========================================================================
# S-mode handler: cause 2 recorded and skipped
#=========================================================================
    .align 2
s_handler:
    csrr t0, scause
    li   t1, 2
    bne  t0, t1, s_unexpected
    li   t1, 2
    sw   t1, 0(s9)
    sw   t0, 4(s9)
    csrr t1, sepc
    sw   t1, 8(s9)
    csrr t2, stval
    sw   t2, 12(s9)
    csrr t2, sstatus
    srli t2, t2, 8
    andi t2, t2, 1
    sw   t2, 16(s9)
    lw   t2, 28(s9)
    addi t2, t2, 1
    sw   t2, 28(s9)
    addi t1, t1, 4
    csrw sepc, t1
    sret
s_unexpected:
    lw   t1, 4(s1)
    addi t1, t1, 1
    sw   t1, 4(s1)
    csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    sret

#=========================================================================
# Landing pad of an MNRET that did not trap
#=========================================================================
    .align 2
bad_landing:
    li   t0, 0xBAD
    sw   t0, 0(s1)
    li   x31, 0xBADBAD00
1:  j    1b

#=========================================================================
# Drop from M to the privilege in a0 (0 = U, 1 = S) at the address in a1;
# the case returns to M at s11 with ECALL.
#=========================================================================
    .align 2
enter_mode:
    li   t0, 0x1800
    csrc mstatus, t0
    slli t0, a0, 11
    csrs mstatus, t0
    csrw mepc, a1
    mret

#=========================================================================
# Case body, run in S or U. s9 = slot, s10 = case index.
#=========================================================================
    .align 2
case_body:
    la   t0, mnret_pc
    sw   t0, 20(s9)
mnret_pc:
    .word 0x70200073               # mnret -> illegal instruction below M
    li   t0, 0x600D0000
    or   t0, t0, s10
    sw   t0, 24(s9)
    ecall                          # back to M at s11

#=========================================================================
_start:
    csrsi MNSTATUS, 8              # Smdbltrp boot: NMIE = 1 first
    csrw MSTATUSH, x0              # then MDT = 0

    li   sp, 0x80010000
    li   s1, 0x80000000
    PMP_ALLOW_ALL

    # clear the scratchpad
    mv   t0, s1
    li   t1, 0x80000200
1:  sw   x0, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b

    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0
    csrw medeleg, x0
    csrw mideleg, x0
    li   t0, (1 << 24)
    csrc mstatus, t0               # sstatus.SDT = 0: horizontal S traps allowed

    la   t0, bad_landing
    csrw MNEPC, t0
    sw   t0, 0x0C(s1)

    li   x31, 0x11111111           # sync: init done

    #--- case 0: S, not delegated -> M
    li   s10, 0
    li   s9, SLOTS + 0*32
    li   a0, 1
    la   a1, case_body
    la   s11, 2f
    j    enter_mode
2:
    #--- case 1: U, not delegated -> M
    li   s10, 1
    li   s9, SLOTS + 1*32
    li   a0, 0
    la   a1, case_body
    la   s11, 2f
    j    enter_mode
2:
    li   x31, 0x22222222           # sync: M-handled cases done

    li   t0, (1 << 2)
    csrs medeleg, t0
    li   t0, (1 << 24)
    csrc mstatus, t0

    #--- case 2: S, delegated -> S (horizontal)
    li   s10, 2
    li   s9, SLOTS + 2*32
    li   a0, 1
    la   a1, case_body
    la   s11, 2f
    j    enter_mode
2:
    li   t0, (1 << 24)
    csrc mstatus, t0
    #--- case 3: U, delegated -> S
    li   s10, 3
    li   s9, SLOTS + 3*32
    li   a0, 0
    la   a1, case_body
    la   s11, 2f
    j    enter_mode
2:
    csrw medeleg, x0

    csrr t0, MNEPC
    sw   t0, 0x08(s1)
    csrr t0, MNSTATUS
    sw   t0, 0x10(s1)

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
