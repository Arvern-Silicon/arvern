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
#   core reports as a load-access-fault (cause 5) or store-access-fault
#   (cause 7) trap. Accesses to the S-context (ctx 1) from S-mode must
#   continue to succeed.
#
#   Phases:
#     1. M-mode programs PLIC, drops to S-mode.
#     2. S-mode reads ctx-0 threshold (0x0C200000)   -> load access fault.
#     3. S-mode writes ctx-0 enable   (0x0C002000)   -> store access fault.
#     4. S-mode reads ctx-1 threshold (0x0C201000)   -> succeeds (value 0).
#
#   The M-mode handler catches both faults, records MCAUSE/MTVAL and
#   advances MEPC by the length of the trapping load/store (4 bytes for the
#   non-compressed `lw` / `sw` we use here), then MRETs back to S-mode.
#----------------------------------------------------------------------------

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
#   0x04: 1st MCAUSE   (expect 5 = load access fault)
#   0x08: 1st MTVAL    (expect 0x0C200000)
#   0x0C: 2nd MCAUSE   (expect 7 = store access fault)
#   0x10: 2nd MTVAL    (expect 0x0C002000)
#   0x14: ctx-1 threshold read (S-mode legit access)
#=========================================================================

main:
    j _start

    .align 2
m_trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mtval

    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Record cause/tval into the slot for this trap number (1 -> 0x04/0x08;
    # 2 -> 0x0C/0x10).
    li   t4, 1
    beq  t3, t4, log_first
    li   t4, 2
    beq  t3, t4, log_second
    j    advance_pc                 # unexpected; just advance and return

log_first:
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    j    advance_pc

log_second:
    sw   t0, 0x0C(s1)
    sw   t2, 0x10(s1)

advance_pc:
    # The trapping instruction is a non-compressed lw/sw (4 bytes).
    addi t1, t1, 4
    csrw mepc, t1

    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
    mret


_start:
    li   sp, 0x80010000
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

    # 1) Denied access: S-mode load from ctx-0 threshold -> load access fault.
    # The aRVern pipeline retires the next instruction (li x31, ...) while
    # the faulting load is still walking the AHB; the trap arrives a few
    # cycles after x31 has already changed. To make the sync deterministic,
    # we poll trap_count BEFORE advancing x31 -- if the access wrongly
    # succeeds (no fault), the poll hangs and the test times out, which is
    # the correct failure mode.
    li   t1, PLIC_TH_M
    lw   t2, 0(t1)                  # << expected to load-access-fault

poll_trap_1:
    lw   t3, 0x00(s1)
    li   t4, 1
    bne  t3, t4, poll_trap_1

    li   x31, 0x22222222

    # 2) Denied access: S-mode write to ctx-0 enable -> store access fault.
    li   t0, 0x12345678
    li   t1, PLIC_EN_M
    sw   t0, 0(t1)                  # << expected to store-access-fault

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
