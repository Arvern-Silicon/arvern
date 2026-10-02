#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_late_fault_irq
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Late load fault (load-use hazard) racing an M-mode IRQ
#
#   Priv 3.1.11 / Unpriv 1.6: a synchronous exception of an instruction is
#   always reported precisely; an interrupt may be taken before or after that
#   instruction but never INSTEAD of it.
#
#   The critical pair is a load whose base register is the destination of the
#   immediately preceding load (load-use hazard), so its address -- and thus
#   its misalignment -- becomes known only once the first load's data returns:
#
#       crit_lw0: lw a0, 0(a1)     # a1 -> word holding 0x80000101 (misaligned)
#       crit_lw:  lw a2, 0(a0)     # base forwarded from crit_lw0 -> mcause 4
#
#   The testbench sweeps a level machine-timer interrupt across the pair over
#   40 cycle offsets.  Whatever the IRQ ordering, every iteration must see
#   EXACTLY ONE synchronous exception (mcause=4, mtval=0x80000101,
#   mepc=&crit_lw) and a2 must keep its sentinel (a faulting load never
#   writes rd).
#
#   Per iteration (MIE=1, MTIE=1, timer line low):
#     s5=0, a2=sentinel, sync 0x51000000+i, 8 NOPs, crit_lw0, crit_lw,
#     a3++ (after-pair), wait until this iteration's IRQ was taken,
#     classify (s5==1 ? a2==sentinel ? a0==0x80000101 ?), sync 0x52000000+i.
#
#   Register conventions (handler uses the stack only for t0/t1):
#     s1  (x9)  iterations where a0 != 0x80000101 after the pair   expect 0
#     s2  (x18) iteration counter                                  expect 40
#     s3  (x19) total M IRQs taken                                 expect 40
#     s4  (x20) total synchronous exceptions                       expect 40
#     s5  (x21) per-iteration synchronous exceptions               expect 1
#     s6  (x22) per-iteration "IRQ taken" flag (1 = still waiting)
#     s7  (x23) last mcause seen by the handler
#     s8  (x24) last mtval seen by a synchronous exception
#     s9  (x25) synchronous exceptions with mcause != 4            expect 0
#     s10 (x26) &crit_lw (the faulting load)
#     s11 (x27) synchronous exceptions with mepc != &crit_lw       expect 0
#     t3  (x28) IRQs taken with mepc <  &crit_lw (before)  diagnostic
#     t4  (x29) IRQs taken with mepc == &crit_lw (at)      diagnostic
#     t5  (x30) IRQs taken with mepc >  &crit_lw (after)   diagnostic
#     a3  (x13) after-pair counter                                 expect 40
#     a4  (x14) iterations where s5 != 1 (exception lost/doubled) expect 0
#     a5  (x15) iterations where a2 != sentinel (rd written)      expect 0
#     a6  (x16) expected mtval (0x80000101)
#     a7  (x17) sentinel (0xDEAD0000)
#     x31       testbench sync
#----------------------------------------------------------------------------

.equ MSTATUSH,  0x310
.equ MNSTATUS,  0x744
.equ MIE_MASK,  0x00000008
.equ MTIE_MASK, 0x00000080
.equ MISALIGNED_ADDR, 0x80000101
.equ ADDR_WORD,       0x80000200
.equ SENTINEL,        0xDEAD0000
.equ ITERATIONS,      40

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # M TRAP HANDLER
    #=================================================================
    .align 2
m_handler:
    addi sp, sp, -8
    sw   t0, 4(sp)
    sw   t1, 0(sp)

    csrr s7, mcause
    bgez s7, m_exception

    # ---- interrupt: classify by mepc against the faulting load ----
    csrr t0, mepc
    bltu t0, s10, m_before
    beq  t0, s10, m_at
    addi t5, t5, 1
    j    m_taken
m_before:
    addi t3, t3, 1
    j    m_taken
m_at:
    addi t4, t4, 1
m_taken:
    addi s3, s3, 1              # testbench drops the timer line on this
    li   s6, 0
m_spin:                         # level IRQ: wait for the line to drop
    csrr t0, mip
    andi t0, t0, MTIE_MASK
    bnez t0, m_spin
    j    m_done

    # ---- synchronous exception: must be mcause 4 at &crit_lw ----
m_exception:
    addi s4, s4, 1
    addi s5, s5, 1
    csrr s8, mtval
    li   t0, 4
    beq  s7, t0, 1f
    addi s9, s9, 1
1:  csrr t0, mepc
    beq  t0, s10, 2f
    addi s11, s11, 1
2:  addi t0, t0, 4              # crit_lw is a 32-bit lw (norvc)
    csrw mepc, t0

m_done:
    lw   t1, 0(sp)
    lw   t0, 4(sp)
    addi sp, sp, 8
    mret

    #=================================================================
    # MAIN
    #=================================================================
_start:
    li   sp, 0x80010000

    li   s1, 0
    li   s2, 0
    li   s3, 0
    li   s4, 0
    li   s5, 0
    li   s6, 0
    li   s7, 0
    li   s8, 0
    li   s9, 0
    li   s11, 0
    li   t3, 0
    li   t4, 0
    li   t5, 0
    li   a3, 0
    li   a4, 0
    li   a5, 0
    li   a6, MISALIGNED_ADDR
    li   a7, SENTINEL

    la   t0, m_handler
    csrw mtvec, t0
    la   s10, crit_lw

    # a1 -> SRAM word holding the misaligned address
    li   a1, ADDR_WORD
    sw   a6, 0(a1)

    csrsi MNSTATUS, 8           # mnstatus.NMIE = 1 first ...
    csrw  MSTATUSH, x0          # ... then MDT = 0 (boot order per Smdbltrp)

    li   t0, MTIE_MASK
    csrs mie, t0
    csrsi mstatus, MIE_MASK

    li   x31, 0x11111111

main_loop:
    li   s5, 0                  # per-iteration exception count
    li   s6, 1                  # waiting for this iteration's IRQ
    mv   a2, a7                 # rd sentinel
    li   a0, 0
    li   t0, 0x51000000
    add  x31, t0, s2            # per-iteration sync: tb asserts MTIP at +i cycles

    .rept 8
    nop
    .endr
.option push
.option norvc
crit_lw0:
    lw   a0, 0(a1)              # a0 = 0x80000101
crit_lw:
    lw   a2, 0(a0)              # load-use hazard; misaligned -> mcause 4
.option pop
    addi a3, a3, 1              # after-pair counter

wait_irq:
    bnez s6, wait_irq

    # ---- per-iteration classification ----
    li   t0, 1
    beq  s5, t0, 3f
    addi a4, a4, 1              # exception lost (or doubled)
3:  beq  a2, a7, 4f
    addi a5, a5, 1              # faulting load wrote rd
4:  beq  a0, a6, 5f
    addi s1, s1, 1              # first load did not deliver its data
5:
    li   t0, 0x52000000
    add  x31, t0, s2            # end-of-iteration sync: tb reads the verdict

    addi s2, s2, 1
    li   t0, ITERATIONS
    blt  s2, t0, main_loop

    li   x31, 0xdeadbeef
1:  j 1b
