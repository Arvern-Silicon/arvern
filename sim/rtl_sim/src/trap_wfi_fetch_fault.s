#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_wfi_fetch_fault
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: WFI whose next instruction cannot be fetched
#   PMP_NR > 0. Entry 0 = LOCKED NAPOT (32 bytes) R=W=1 X=0 over block D, which
#   starts right after the wfi. The testbench raises the machine software
#   interrupt line well after the hart went to sleep. The hart must not hang:
#   the interrupt is taken once, and the instruction access fault at &D is
#   taken once (mepc = mtval = &D), in either order.
#
#   Scratchpad (base 0x80000000): 0x00 irq count, 0x04 fault count,
#   0x08 fault mepc, 0x0C &D
#----------------------------------------------------------------------------

.equ SBASE,          0x80000000

.include "firmware_config.inc"

.section .text
.global main

.option norvc

main:
    j _start

    .align 4
m_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x10(t0)
    csrr t1, mcause
    bltz t1, 1f
    lw   t1, 0x04(t0)               # synchronous: count, record mepc, resume at done
    addi t1, t1, 1
    sw   t1, 0x04(t0)
    csrr t1, mepc
    sw   t1, 0x08(t0)
    la   t1, done
    csrw mepc, t1
    j    2f
1:
    lw   t1, 0x00(t0)               # interrupt (the testbench drops the line on the take)
    addi t1, t1, 1
    sw   t1, 0x00(t0)
2:
    lw   zero, 0x00(t0)
    lw   t1, 0x10(t0)
    csrr t0, mscratch
    mret

_start:
    li   sp, 0x80010000
    li   s1, SBASE
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8              # Smdbltrp boot: NMIE=1 first...
    csrw  mstatush, x0          # ...then MDT=0
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    li   t0, 0xFFFFFFFF
    sw   t0, 0x08(s1)
    la   t0, D
    sw   t0, 0x0C(s1)
    lw   zero, 0x0C(s1)

    la   t1, D
    srli t1, t1, 2
    ori  t1, t1, 3              # NAPOT, 32 bytes
    csrw pmpaddr0, t1
    li   t0, 0x9B               # entry 0: L | NAPOT | R | W, X=0
    csrw pmpcfg0, t0
    li   t0, 0x8
    csrs mie, t0                # MSIE
    csrsi mstatus, 8            # MIE

    li   x31, 0x11111111        # sync: going to sleep
    .balign 32
    .rept 7
    nop
    .endr
    wfi
D:
    .rept 8
    nop                         # X=0: fetching here faults
    .endr
done:
    li   t2, 2000                   # the fault may be taken first: wait for the interrupt too
3:
    lw   t1, 0x00(s1)
    bnez t1, 4f
    addi t2, t2, -1
    bnez t2, 3b
4:
    csrci mstatus, 8
    lw   zero, 0x08(s1)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
