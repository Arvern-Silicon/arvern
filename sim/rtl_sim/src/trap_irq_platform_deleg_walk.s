#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_platform_deleg_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: every irq_platform_i line, delegated to S vs not delegated
#
#   traps_and_interrupts.md §4: "Each platform IRQ has its own enable bit in
#   mie[31:16] and can be delegated to S-mode via mideleg[31:16]. Trap cause
#   is mcause = 16 + bit_index." ... "The pending bits are latched, not
#   level: a pulse or level on irq_platform_i sets the bit, and it stays set
#   until software writes it to 0 via mip (or sip for a delegated bit)."
#   traps_and_interrupts.md §5: "a delegated S-mode IRQ fires when the core is
#   in U-mode, or in S-mode with sstatus.SIE = 1"; "an M-mode IRQ fires
#   whenever the core is running below M-mode"; "M-mode never takes a
#   delegated IRQ from S-mode unless mideleg undelegates it."
#   Priv §3.1.8: "Delegated interrupts result in the interrupt being masked at
#   the delegator privilege level."
#
#   For each line N = 0..15 (bit b = 16+N), scenario s:
#     s=0  mideleg[b]=1, running S with SIE=1   -> S handler, scause 0x80000010+N, SPP=S
#     s=1  mideleg[b]=1, running U (SIE=0)      -> S handler, SPP=U
#     s=2  mideleg[b]=0, running S (MIE=0)      -> M handler, mcause 0x80000010+N, MPP=S
#     s=3  mideleg[b]=0, running U              -> M handler, MPP=U
#     s=4  mideleg[b]=1, running M with MIE=1   -> NOT taken in M (bit stays
#          pending), then taken in S as soon as M drops to S with SIE=1
#   Handshake: x31 = 0x60000000 | s<<8 | N asks the bench to pulse
#   irq_platform_i[N]; the handler clears the latched bit (retrying until the
#   pin is low) and bumps the case count.
#
#   Slot (s*16+N) at 0x80000100 + 32*(s*16+N):
#     +0 handler id (1 = M, 2 = S)  +4 cause  +8 previous privilege
#     +12 (s=4) trap count while still in M   +16 (s=4) pending bit seen in M
#     +20 trap count   +24 mideleg & bit read back
#   0x80000000: unexpected-trap count
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSTATUS,  0x744
.equ MSTATUSH,  0x310
.equ SLOTS,     0x80000100
.equ PLAT_MASK, 0xFFFF0000

.section .text
.global main

main:
    j    _start

#=========================================================================
# M handler: platform interrupt -> record; ECALL from U/S -> back to M at s10
#=========================================================================
    .align 2
m_handler:
    csrr t0, mcause
    bltz t0, m_irq
    li   t1, 8
    beq  t0, t1, m_to_m
    li   t1, 9
    beq  t0, t1, m_to_m
    lw   t1, 0(s1)                  # unexpected exception: count, skip
    addi t1, t1, 1
    sw   t1, 0(s1)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    mret
m_to_m:
    li   t1, 0x1800
    csrs mstatus, t1
    csrw mepc, s10
    mret
m_irq:
1:  csrc mip, a4                    # a pin still high keeps the bit: retry
    csrr t1, mip
    and  t1, t1, a4
    bnez t1, 1b
    li   t1, 1
    sw   t1, 0(s9)
    sw   t0, 4(s9)
    csrr t1, mstatus
    srli t1, t1, 11
    andi t1, t1, 3
    sw   t1, 8(s9)
    lw   t1, 20(s9)
    addi t1, t1, 1
    sw   t1, 20(s9)
    mret

#=========================================================================
# S handler
#=========================================================================
    .align 2
s_handler:
    csrr t0, scause
    bgez t0, s_unexpected
1:  csrc sip, a4
    csrr t1, sip
    and  t1, t1, a4
    bnez t1, 1b
    li   t1, 2
    sw   t1, 0(s9)
    sw   t0, 4(s9)
    csrr t1, sstatus
    srli t1, t1, 8
    andi t1, t1, 1
    sw   t1, 8(s9)
    lw   t1, 20(s9)
    addi t1, t1, 1
    sw   t1, 20(s9)
    sret
s_unexpected:
    lw   t1, 0(s1)
    addi t1, t1, 1
    sw   t1, 0(s1)
    csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    sret

#=========================================================================
# Lower-mode bodies (entered by MRET)
#=========================================================================
    .align 2
lower_signal:                       # ask for the pulse, wait for the trap
    mv   x31, a3
lower_wait:                         # wait for the trap only
1:  lw   t0, 20(s9)
    beqz t0, 1b
    ecall                           # back to M at s10

# a0 = 0 (U) / 1 (S), a1 = entry point
    .align 2
enter_lower:
    li   t0, 0x1800
    csrc mstatus, t0
    slli t0, a0, 11
    csrs mstatus, t0
    csrw mepc, a1
    mret

#=========================================================================
_start:
    csrsi MNSTATUS, 8               # Smdbltrp boot: NMIE = 1 first
    csrw MSTATUSH, x0               # then MDT = 0

    li   sp, 0x80010000
    li   s1, 0x80000000
    PMP_ALLOW_ALL
    mv   t0, s1
    li   t1, 0x80000C00
1:  sw   x0, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b

    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0
    csrw medeleg, x0
    csrw mideleg, x0
    li   t0, PLAT_MASK
    csrc mie, t0
    csrc mip, t0

    li   x31, 0x11111111            # sync: init done

    li   s2, 0                      # scenario
scen_loop:
    li   s3, 0                      # line
line_loop:
    # a4 = 1 << (16+N); s9 = slot; a3 = handshake value
    addi t0, s3, 16
    li   a4, 1
    sll  a4, a4, t0
    slli t0, s2, 4
    add  t0, t0, s3
    slli t0, t0, 5
    li   s9, SLOTS
    add  s9, s9, t0
    slli t0, s2, 8
    or   a3, s3, t0
    li   t0, 0x60000000
    or   a3, a3, t0

    # clean state for this case
    li   t0, PLAT_MASK
    csrc mideleg, t0
    csrc mie, t0
    csrc mip, t0
    li   t0, (1 << 24) | 0x2 | 0x8
    csrc mstatus, t0                # SDT = 0, SIE = 0, MIE = 0

    li   t0, 2
    beq  s2, t0, 2f                 # s=2,3: not delegated
    li   t0, 3
    beq  s2, t0, 2f
    csrs mideleg, a4
2:  csrr t0, mideleg
    and  t0, t0, a4
    sw   t0, 24(s9)
    csrs mie, a4

    la   s10, case_done
    li   t0, 4
    beq  s2, t0, scen4
    li   t0, 0
    bne  s2, t0, 3f
    li   t0, 0x2
    csrs mstatus, t0                # s=0: sstatus.SIE = 1
3:  andi a0, s2, 1                  # s=0,2 -> S ; s=1,3 -> U
    xori a0, a0, 1
    la   a1, lower_signal
    j    enter_lower

scen4:
    li   t0, 0x8
    csrs mstatus, t0                # M with MIE = 1
    mv   x31, a3                    # pulse
1:  lw   t0, 20(s9)
    bnez t0, 3f                     # wrongly taken in M: stop waiting
    csrr t0, mip
    and  t0, t0, a4
    beqz t0, 1b                     # wait for the latched pending bit
3:  li   t1, 64
2:  addi t1, t1, -1                 # give a masked-at-M interrupt time to fire
    bnez t1, 2b
    lw   t0, 20(s9)
    sw   t0, 12(s9)                 # count while in M (expect 0)
    csrr t0, mip
    and  t0, t0, a4
    snez t0, t0
    sw   t0, 16(s9)                 # still pending (expect 1)
    li   t0, 0x8
    csrc mstatus, t0
    li   t0, 0x2
    csrs mstatus, t0                # SIE = 1 for the S-mode delivery
    li   a0, 1
    la   a1, lower_wait
    j    enter_lower

case_done:
    addi s3, s3, 1
    li   t0, 16
    blt  s3, t0, line_loop
    addi s2, s2, 1
    li   t0, 5
    blt  s2, t0, scen_loop

    li   t0, PLAT_MASK
    csrc mideleg, t0
    csrc mie, t0
    csrc mip, t0

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
