#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_s_dbltrp_basic
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: TRAP S DBLTRP BASIC (Ssdbltrp happy path)
#   Requires SU_MODE_EN==1. Deterministic (sync exceptions only, no IRQs).
#
#   Ssdbltrp: sstatus.SDT (bit 24) is set by hardware when a trap is taken
#   into S-mode. While SDT=1, any trap that would be delivered to S-mode is
#   redirected to M-mode as a DOUBLE TRAP: mcause=16, mtval2 (0x34B) holds
#   the original cause, mepc/mstatus.MPP written as for a normal M trap.
#   menvcfgh.DTE (bit 27, i.e. menvcfg bit 59) resets to 1 on aRVern, so no
#   menvcfg setup is needed here.
#
#   Scenario:
#   1. M-mode: delegate illegal-instruction (medeleg[2]) to S, enter S.
#   2. S main: verify SDT reads 0 (no trap taken yet), execute illegal1
#      -> delegated trap into the S handler; hardware sets SDT=1.
#   3. S handler: record scause and sstatus.SDT (must be 1), advance sepc
#      past illegal1, then execute illegal2 WITHOUT clearing SDT
#      -> double trap to M: mcause=16, mtval2=2, mepc=&illegal2.
#   4. M handler: record mcause/mepc/mtval2, advance mepc past illegal2,
#      mret back into the S handler. Priv 3.1.6.2: MRET executed in M clears
#      MDT, and clears sstatus.SDT ONLY if the new privilege mode is U --
#      returning to S leaves SDT=1.
#   5. S handler resumes: verify SDT still reads 1, sret back to S main
#      (Priv 12.1.1.5: SRET sets SDT to 0 unconditionally), which verifies
#      SDT=0 and runs to completion.
#
#   Scratchpad layout (base 0x80000000):
#   0x00: m_trap_count       (expect 1: only the double trap)
#   0x04: m_last_mcause      (expect 16 = double trap)
#   0x08: m_last_mepc        (expect &illegal2, compare with 0x1C)
#   0x0C: m_mtval2           (expect 2 = original cause, illegal inst)
#   0x10: s_trap_count       (expect 1: only the first trap)
#   0x14: s_last_scause      (expect 2)
#   0x18: SDT in S handler   (expect 0x01000000: set by HW on trap entry)
#   0x1C: expected mepc      (&illegal2)
#   0x20: handler resumed    (expect 0xAA: M unwound past illegal2)
#   0x24: SDT after M return (expect 0x01000000: MRET to S keeps SDT)
#   0x28: SDT before 1st trap(expect 0)
#   0x2C: s_main resumed     (expect 0xBB: full clean unwind)
#   0x30: SDT after sret      (expect 0: SRET clears SDT)
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
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    sw   t0, 0x04(s1)          # m_last_mcause (expect 16)
    sw   t1, 0x08(s1)          # m_last_mepc   (expect &illegal2)

    # mtval2 (0x34B, M-level) holds the ORIGINAL cause of the double trap
    csrr t2, 0x34B
    sw   t2, 0x0C(s1)          # expect 2 (illegal instruction)

    # Recover: advance MEPC past the 4-byte faulting instruction
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret                        # MPP=S -> return to S handler, SDT stays 1


    #=================================================================
    # S-MODE HANDLER (direct mode)
    #=================================================================
    .align 2

s_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    # Re-entry guard: this handler must be entered exactly once.
    # (Pre-Ssdbltrp RTL would horizontally re-deliver illegal2 to S and
    # livelock here -- fail fast instead.)
    lw   t2, 0x10(s1)
    addi t2, t2, 1
    sw   t2, 0x10(s1)
    li   t0, 1
    bne  t2, t0, s_unexpected

    csrr t0, scause
    sw   t0, 0x14(s1)          # s_last_scause (expect 2)

    # sstatus.SDT (bit 24) must have been set by hardware on this trap entry
    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x18(s1)          # expect 0x01000000

    # Advance sepc past illegal1 now -- the double trap must NOT clobber
    # the S trap CSRs, so sepc survives the M round trip.
    csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1

    # Record the expected MEPC of the upcoming double trap
    la   t0, illegal2
    sw   t0, 0x1C(s1)

    # Second illegal WITHOUT clearing SDT -> double trap to M-mode
illegal2:
    .word 0xFFFFFFFF

    # The M handler advanced MEPC past illegal2 and MRETed back here
    li   t0, 0xAA
    sw   t0, 0x20(s1)          # resumed-in-S-handler flag

    # MRET to S (not U) must NOT clear SDT (Priv 3.1.6.2)
    csrr t2, sstatus
    li   t0, 0x01000000
    and  t2, t2, t0
    sw   t2, 0x24(s1)          # expect 0x01000000

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    sret

s_unexpected:
    li   x31, 0x0BADBADB       # FAIL: unexpected S handler re-entry
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

    # Zero scratchpad
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
    # SDT must read 0 before any trap has been taken into S
    csrr t0, sstatus
    li   t1, 0x01000000
    and  t0, t0, t1
    sw   t0, 0x28(s1)          # expect 0
    lw   t0, 0x28(s1)          # drain

    li   x31, 0x22222222

illegal1:
    .word 0xFFFFFFFF           # first trap: delegated to the S handler

    # Full unwind done (S handler -> double trap -> M -> S handler -> sret).
    # SRET sets SDT to 0 unconditionally (Priv 12.1.1.5).
    csrr t0, sstatus
    li   t1, 0x01000000
    and  t0, t0, t1
    sw   t0, 0x30(s1)          # expect 0
    li   t0, 0xBB
    sw   t0, 0x2C(s1)
    lw   t0, 0x2C(s1)          # drain
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
