#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_step_late_fault
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DEBUG single-step over a late-faulting load (load-use hazard)
#   Debug Spec 1.0 (Sdext, dcsr.step): stepping an instruction that raises a
#   synchronous exception must take the exception -- the hart enters the trap
#   handler and halts before its first instruction (dpc == mtvec,
#   dcsr.cause == 4). The exception is never skipped.
#
#   The stepped pair is a load whose base register is the destination of the
#   immediately preceding load; the second load is misaligned (mcause 4):
#
#       step_start+0 : lw a0, 0(a1)     # a1 -> word holding 0x80000101
#       step_start+4 : lw a2, 0(a0)     # misaligned -> trap, a2 keeps sentinel
#       step_start+8 : addi x5, x0, 0x11
#       step_start+12: addi x6, x0, 0x22
#
#   Parking trick (from debug_single_step): the hart spins on
#   `jalr x0,0(x12)` with x12=&spin_self; the testbench halts it there,
#   abstract-writes x12=&step_start (pre-loaded in x13) and single-steps.
#
#   The trap handler (norvc, +4 per step) records mcause/mtval/mepc, bumps
#   mepc by 4 and returns; the testbench steps its first two instructions
#   and then clears dcsr.step and free-runs to the end marker.
#
#   Registers:
#     x5,x6  : post-pair targets (pre-init 0; final 0x11/0x22)
#     x10 a0 : first-load destination (expect 0x80000101 after step 2)
#     x11 a1 : &word holding 0x80000101 (SRAM 0x80000200)
#     x12    : jalr spin base (&spin_self; TB rewrites it to &step_start)
#     x13    : &step_start (TB reads this to learn the redirect target)
#     x14 a4 : rd of the faulting load, pre-set to the sentinel 0xDEAD0000
#              (a2/x12 is the jalr spin base here, so the sentinel lives in a4)
#     x18    : sentinel marker, must survive untouched (0xA5A5A5A5)
#     x20    : mcause recorded by the handler (expect 4)
#     x21    : mtval  recorded by the handler (expect 0x80000101)
#     x22    : mepc   recorded by the handler (expect &crit_lw = step_start+4)
#     x23    : trap-handler entry count (expect 1)
#     x31    : sync (11111111=spinning/halt-me-here, deadbeef=done)
#
#     x9  s1 : handler scratch
#----------------------------------------------------------------------------

.equ MSTATUSH,        0x310
.equ MNSTATUS,        0x744
.equ MISALIGNED_ADDR, 0x80000101
.equ ADDR_WORD,       0x80000200
.equ SENTINEL,        0xDEAD0000

.include "firmware_config.inc"

.section .text
.global main
main:
    j    _start

    #=============================================================
    # M TRAP HANDLER (norvc: the debugger steps its first two instrs)
    #=============================================================
.option push
.option norvc
    .align 2
m_handler:
    csrr x20, mcause
    csrr x21, mtval
    csrr x22, mepc
    addi x23, x23, 1
    addi x9, x22, 4             # crit_lw is a 32-bit lw
    csrw mepc, x9
    mret
.option pop

_start:
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x5,  0
    li   x6,  0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0

    la   x10, m_handler
    csrw mtvec, x10
    csrsi MNSTATUS, 8           # mnstatus.NMIE = 1 first ...
    csrw  MSTATUSH, x0          # ... then MDT = 0 (boot order per Smdbltrp)

    li   a1, ADDR_WORD
    li   a0, MISALIGNED_ADDR
    sw   a0, 0(a1)              # word holding the misaligned address
    li   a0, 0
    li   a4, SENTINEL

    la   x13, step_start        # redirect target (testbench abstract-reads this)
    la   x12, spin_self         # jalr base = self -> infinite self-jump (spin)

    li   x31, 0x11111111        # sync: spinning (testbench halts us at spin_self)
spin_self:
    jalr x0, 0(x12)             # spin in place; TB rewrites x12 to &step_start

    #=============================================================
    # STEP RUN: straight-line 32-bit instructions (+4 each)
    #=============================================================
.option push
.option norvc
step_start:
    lw   a0, 0(a1)              # step 2: a0 = 0x80000101
crit_lw:
    lw   a4, 0(a0)              # step 3: load-use hazard, misaligned -> mcause 4
    addi x5,  x0, 0x11          # free-run after the handler returns
    addi x6,  x0, 0x22
.option pop

    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test
