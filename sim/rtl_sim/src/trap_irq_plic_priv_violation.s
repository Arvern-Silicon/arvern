#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_plic_priv_violation
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PLIC PRIV_CHECK_EN privilege filter (S-mode -> M-ctx denied)
#   With PRIV_CHECK_EN=1, an S-mode access to a register that lives in the
#   M-context (ctx 0) must produce an AHB-Lite ERROR response, which the
#   core reports as a resumable data-bus-error RNMI (mncause = 0x80000003,
#   faulting address in marv_eaddr) -- never mcause 5/7. Accesses to the
#   S-context (ctx 1) from S-mode must continue to succeed.
#
#   Phases:
#     1. M-mode programs PLIC, drops to S-mode.
#     2. S-mode reads ctx-0 threshold (0x0C200000)   -> AHB ERROR -> RNMI.
#     3. S-mode writes ctx-0 enable   (0x0C002000)   -> AHB ERROR -> RNMI.
#     4. S-mode reads ctx-1 threshold (0x0C201000)   -> succeeds (value 0).
#
#   The RNMI handler records mncause and marv_eaddr for each, then mnret
#   resumes S-mode after the access. A synchronous trap (mcause 5/7) must
#   never fire; the M-mode trap handler only counts it as a negative control.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ PLIC_TH_M,      0x0C200000        # threshold[ctx0=M]   -- denied to S
.equ PLIC_EN_M,      0x0C002000        # enable[ctx0=M]      -- denied to S
.equ PLIC_PRI1,      0x0C000004        # priority[1]
.equ PLIC_EN_S,      0x0C002080        # enable[ctx1=S]      -- allowed to S
.equ PLIC_TH_S,      0x0C201000        # threshold[ctx1=S]   -- allowed to S

#=========================================================================
# Scratchpad (base 0x80000000)
#   0x00: trap_count
#   0x04: 1st mncause    (expect 0x80000003 = data-bus error)
#   0x08: 1st marv_eaddr (expect 0x0C200000)
#   0x0C: 2nd mncause    (expect 0x80000003)
#   0x10: 2nd marv_eaddr (expect 0x0C002000)
#   0x14: ctx-1 threshold read (S-mode legit access)
#=========================================================================

main:
    j _start

    .align 2
# An S-mode PLIC access that AHB-ERRORs is a DATA-BUS ERROR: an RNMI to
# M-mode, non-delegable, not a delegable S-mode fault. mnstatus.MNPP records
# the S-mode it escalated from, and mnret returns there.
nmi_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, 0x742                  # mncause
    csrr t1, 0x744                  # mnstatus (MNPP = the mode we escalated from)
    csrr t2, 0xFFD                  # marv_eaddr

    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    li   t4, 1
    beq  t3, t4, log_first
    j    log_second

log_first:
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    sw   t1, 0x18(s1)
    j    nmi_done

log_second:
    sw   t0, 0x0C(s1)
    sw   t2, 0x10(s1)

nmi_done:
    li   t0, 0x5
    csrw 0x7FE, t0                  # W1C so the next fault captures its own

    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
    .word 0x70200073                # mnret -- restores S-mode from MNPP

    .align 2
# NEGATIVE CONTROL: mcause 5/7 RESERVED -- must never fire.
m_trap_handler:
    addi sp, sp, -8
    sw   t0, 4(sp)
    sw   t1, 0(sp)
    lw   t0, 0x1C(s1)
    addi t0, t0, 1
    sw   t0, 0x1C(s1)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    lw   t1, 0(sp)
    lw   t0, 4(sp)
    addi sp, sp, 8
    mret


_start:
    li   sp, 0x80010000
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   s1, 0x80000000

    # Zero scratchpad
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x10(s1)
    sw   zero, 0x14(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x20(s1)
    sw   zero, 0x1C(s1)
    lw   zero, 0x20(s1)

    li   x31, 0x1E1E1E1E            # tb programs nmi_vector here

    li   t0, 20
wait_vec:
    addi t0, t0, -1
    bnez t0, wait_vec

    csrsi 0x744, 8                  # mnstatus.NMIE = 1

    # Program PLIC: priority[1]=5; enable src 1 in BOTH ctx 0 and ctx 1 so
    # the S-mode legit read of threshold[ctx1] hits the same general layout
    # the other tests use. M-mode does the programming, so PRIV_CHECK_EN
    # allows it.
    li   t0, 5
    li   t1, PLIC_PRI1
    sw   t0, 0(t1)

    li   t0, 2
    li   t1, PLIC_EN_M
    sw   t0, 0(t1)
    li   t0, 2
    li   t1, PLIC_EN_S
    sw   t0, 0(t1)

    li   t0, 0
    li   t1, PLIC_TH_M
    sw   t0, 0(t1)
    li   t0, 0
    li   t1, PLIC_TH_S
    sw   t0, 0(t1)

    li   x31, 0x11111111

    # Drop to S-mode: MPP=01, MPIE=1
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0
    li   t0, 0x80
    csrs mstatus, t0
    la   t0, s_mode_entry
    csrw mepc, t0
    mret


    .align 2
s_mode_entry:
    # Sanity-marker for the testbench
    li   x31, 0x21212121

    # 1) Denied access: S-mode load from ctx-0 threshold -> AHB ERROR -> RNMI.
    # The aRVern pipeline retires the next instruction (li x31, ...) while
    # the faulting load is still walking the AHB; the trap arrives a few
    # cycles after x31 has already changed. To make the sync deterministic,
    # we poll trap_count BEFORE advancing x31 -- if the access wrongly
    # succeeds (no fault), the poll hangs and the test times out, which is
    # the correct failure mode.
    li   t1, PLIC_TH_M
    lw   t2, 0(t1)                  # << expected to raise the data-bus-error RNMI

poll_trap_1:
    lw   t3, 0x00(s1)
    li   t4, 1
    bne  t3, t4, poll_trap_1

    li   x31, 0x22222222

    # 2) Denied access: S-mode write to ctx-0 enable -> AHB ERROR -> RNMI.
    li   t0, 0x12345678
    li   t1, PLIC_EN_M
    sw   t0, 0(t1)                  # << expected to raise the data-bus-error RNMI

poll_trap_2:
    lw   t3, 0x00(s1)
    li   t4, 2
    bne  t3, t4, poll_trap_2

    li   x31, 0x33333333

    # 3) Allowed access: S-mode read of ctx-1 threshold should succeed.
    li   t1, PLIC_TH_S
    lw   t2, 0(t1)
    sw   t2, 0x14(s1)

    li   x31, 0x44444444

end_of_test:
    j    end_of_test
