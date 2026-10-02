#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_s_dbltrp_warl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP S DBLTRP WARL (Ssdbltrp CSR surface)
#   Requires SU_MODE_EN==1. Deterministic (sync exceptions only, no IRQs).
#
#   CSR surface checks for Ssdbltrp on aRVern:
#   1. menvcfgh.DTE (0x31A bit 27, i.e. menvcfg bit 59) RESETS TO 1
#      (protection-by-default) -- read at boot BEFORE any menvcfgh write.
#   2. DTE is WARL both ways: write-0-read-0, write-1-read-1 (left at 1).
#   3. mtval2 (0x34B, M-level) is readable from M-mode without trapping.
#   4. sstatus.SDT (bit 24) is software-writable both ways when DTE=1:
#      set/clear/set from S-mode OUTSIDE any handler, then execute an
#      illegal instruction -> even though no first trap occurred, the
#      delegated trap must be redirected as a DOUBLE TRAP to M with
#      mcause=16 and mtval2=2, proving SDT is honored regardless of how it
#      was set. Also: MRET back to S does NOT clear SDT (Priv 3.1.6.2: only
#      a return to U clears sstatus.SDT), so s_main clears it explicitly
#      with csrc before taking any further delegated trap.
#   5. mtval2 access from S-mode must raise illegal-instruction (M-level
#      CSR, privilege check) -- delegated to the S handler (scause=2).
#
#   Scratchpad layout (base 0x80000000):
#   0x00: menvcfgh & DTE at boot   (expect 0x08000000: resets to 1)
#   0x04: DTE after write-0        (expect 0)
#   0x08: DTE after write-1        (expect 0x08000000)
#   0x0C: SDT after SW set in S    (expect 0x01000000)
#   0x10: SDT after SW clear       (expect 0)
#   0x14: SDT after SW re-set      (expect 0x01000000)
#   0x18: m mcause                 (expect 16 = double trap)
#   0x1C: m mtval2                 (expect 2 = original cause)
#   0x20: m mepc                   (expect &illegal_dbl, compare with 0x24)
#   0x24: expected mepc            (&illegal_dbl)
#   0x28: SDT after MRET back to S (expect 0x01000000: MRET to S keeps SDT)
#   0x48: SDT after explicit csrc  (expect 0)
#   0x2C: scause for mtval2-from-S (expect 2: illegal instruction)
#   0x30: sepc                     (expect &mtval2_read, compare with 0x34)
#   0x34: expected sepc            (&mtval2_read)
#   0x38: m_trap_count             (expect 1: only the double trap)
#   0x3C: s_trap_count             (expect 1: only the mtval2-from-S trap)
#   0x40: m_trap_count after boot mtval2 read (expect 0: M read is legal)
#   0x44: final resume flag        (expect 0xAA)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # M-MODE HANDLER (direct mode)
    #=================================================================
    .align 2
    .option push
    .option norvc

m_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    csrr t0, mcause
    csrr t1, mepc

    # Increment m_trap_count
    lw   t2, 0x38(s1)
    addi t2, t2, 1
    sw   t2, 0x38(s1)

    sw   t0, 0x18(s1)          # m mcause (expect 16)

    # mtval2 (0x34B) readable from M; holds original cause after dbl trap
    csrr t2, 0x34B
    sw   t2, 0x1C(s1)          # expect 2

    sw   t1, 0x20(s1)          # m mepc (expect &illegal_dbl)

    # Recover: advance MEPC past the 4-byte faulting instruction
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret                        # MPP=S -> back to s_main, SDT stays 1


    #=================================================================
    # S-MODE HANDLER (direct mode)
    #=================================================================
    .align 2

s_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    # Re-entry guard: this handler must be entered exactly once
    # (the mtval2-from-S illegal-instruction trap).
    lw   t2, 0x3C(s1)
    addi t2, t2, 1
    sw   t2, 0x3C(s1)
    li   t0, 1
    bne  t2, t0, s_unexpected

    csrr t0, scause
    sw   t0, 0x2C(s1)          # expect 2 (illegal instruction)

    csrr t1, sepc
    sw   t1, 0x30(s1)          # expect &mtval2_read

    # Advance sepc past the 4-byte csrr and return
    addi t1, t1, 4
    csrw sepc, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    sret

s_unexpected:
    li   x31, 0x0BADBADB       # FAIL: unexpected S handler entry
s_unexpected_loop:
    j    s_unexpected_loop

    .option pop


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
    .align 4
_start:
    li   sp, 0x80010000
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   s1, 0x80000000

    # Zero scratchpad (no CSR writes yet -- reset-value check comes first)
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)
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
    sw   t0, 0x48(s1)

    # 1. menvcfgh.DTE reset value -- read BEFORE any menvcfgh write
    csrr t0, 0x31A
    li   t1, 0x08000000
    and  t2, t0, t1
    sw   t2, 0x00(s1)          # expect 0x08000000 (DTE resets to 1)

    # 2. DTE WARL: write-0-read-0
    csrc 0x31A, t1
    csrr t0, 0x31A
    and  t2, t0, t1
    sw   t2, 0x04(s1)          # expect 0

    #    DTE WARL: write-1-read-1 (and leave it at 1 for the rest)
    csrs 0x31A, t1
    csrr t0, 0x31A
    and  t2, t0, t1
    sw   t2, 0x08(s1)          # expect 0x08000000

    # 3. mtval2 readable from M-mode: must not trap
    csrr t0, 0x34B
    lw   t0, 0x38(s1)          # m_trap_count so far
    sw   t0, 0x40(s1)          # expect 0 (the read did not trap)

    # Install M and S handlers (direct mode)
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0

    # Delegate illegal-instruction (cause 2) to S-mode
    li   t0, 0x4
    csrs medeleg, t0

    li   x31, 0x11111111

    # MPP=01 (S-mode), mret into s_main
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0
    la   t0, s_main
    csrw mepc, t0
    mret

    .align 2
s_main:
    # 4. sstatus.SDT software-writable both ways (DTE=1), from S-mode,
    #    OUTSIDE any trap handler
    li   t1, 0x01000000
    csrs sstatus, t1
    csrr t0, sstatus
    and  t0, t0, t1
    sw   t0, 0x0C(s1)          # expect 0x01000000 (SW set works)

    csrc sstatus, t1
    csrr t0, sstatus
    and  t0, t0, t1
    sw   t0, 0x10(s1)          # expect 0 (SW clear works)

    csrs sstatus, t1
    csrr t0, sstatus
    and  t0, t0, t1
    sw   t0, 0x14(s1)          # expect 0x01000000 (re-armed)
    lw   t0, 0x14(s1)          # drain

    # Record the expected MEPC of the double trap
    la   t0, illegal_dbl
    sw   t0, 0x24(s1)

    li   x31, 0x22222222

    # SDT=1 (set purely by software, no first trap ever occurred):
    # a delegated illegal must be redirected as a double trap to M
illegal_dbl:
    .word 0xFFFFFFFF

    # M handler advanced MEPC and MRETed back here (MPP=S) -- SDT must
    # still be 1: only an MRET to U clears it (Priv 3.1.6.2)
    csrr t0, sstatus
    li   t1, 0x01000000
    and  t0, t0, t1
    sw   t0, 0x28(s1)          # expect 0x01000000 (MRET to S keeps SDT)

    # Clear SDT explicitly so the next delegated trap is taken in S
    csrc sstatus, t1
    csrr t0, sstatus
    and  t0, t0, t1
    sw   t0, 0x48(s1)          # expect 0
    lw   t0, 0x48(s1)          # drain

    li   x31, 0x33333333

    # 5. mtval2 access from S-mode must raise illegal-instruction
    #    (delegated to the S handler; SDT cleared above, so taken
    #    horizontally in S)
    la   t0, mtval2_read
    sw   t0, 0x34(s1)          # expected sepc
mtval2_read:
    csrr t0, 0x34B             # M-level CSR from S -> illegal instruction

    # S handler advanced sepc past the csrr; resume here
    li   t0, 0xAA
    sw   t0, 0x44(s1)
    lw   t0, 0x44(s1)          # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
