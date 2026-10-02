#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_sret_shadow
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: an IRQ taken in the shadow of SRET must record the RIGHT MPP
#
#   mstatus.MPP is captured from priv_mode_current_i at trap_taken. SRET's
#   privilege change is registered (1 cycle late) with a combinational bypass
#   in arv_csr_top, so an interrupt landing in that window can record the
#   pre-SRET privilege for a trap that was actually taken after it.
#
#   THE INVARIANT (timing-independent, which is why it is asserted rather than
#   an expected MPP value): MPP must agree with MEPC.
#     MEPC == the SRET PC   -> trap taken ON the SRET   -> MPP must be 01 (S)
#     MEPC == the U target  -> trap taken in U-mode     -> MPP must be 00 (U)
#   Getting this wrong means mret returns the interrupted code to S-mode when
#   it belongs in U-mode: a privilege escalation.
#
#   The testbench arms irq_m_software a swept number of cycles after the x31
#   marker, walking the interrupt across the SRET boundary. Driving it from the
#   bench rather than the ACLINT keeps the placement precise -- and an S-mode
#   MSIP write would AHB-ERROR anyway (the ACLINT filters S-mode, like the PLIC).
#
#   Found by riscv-arch-test InterruptsS-00, which hit exactly this window.
#
# Scratchpad (base 0x80000000):
#   0x00 irq_count   0x04 ecall_count
#   0x10 + 8*i : mepc for case i     0x14 + 8*i : mstatus for case i
#   0x40 + 4*i : SRET PC for case i  0x50 + 4*i : U-target PC for case i
#----------------------------------------------------------------------------

.equ ACLINT_MSIP0, 0x02000000
.equ MIE_MSIE,     0x00000008
.equ MSTATUS_MIE,  0x00000008
.equ MSTATUS_MPP,  0x00001800

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    .align 2
m_handler:
    csrrw sp, mscratch, sp
    addi  sp, sp, -16
    sw    t0, 12(sp)
    sw    t1,  8(sp)
    sw    t2,  4(sp)

    li    t2, 0x80000000
    csrr  t0, mcause
    li    t1, 8                       # ecall from U: the case-advance path
    beq   t0, t1, h_ecall

    # --- software interrupt: record (mepc, mstatus) for this case ---
    lw    t1, 0x04(t2)                # t1 = case index
    slli  t1, t1, 3
    addi  t1, t1, 0x10
    add   t1, t1, t2
    csrr  t0, mepc
    sw    t0, 0(t1)
    csrr  t0, mstatus
    sw    t0, 4(t1)

    lw    t0, 0x00(t2)
    addi  t0, t0, 1
    sw    t0, 0x00(t2)

    j     h_exit

h_ecall:
    # U-mode ecall: bump the case index and resume the NEXT case in M-mode
    lw    t0, 0x04(t2)
    addi  t0, t0, 1
    sw    t0, 0x04(t2)
    lw    t1, 0x60(t2)                # next-case address, stashed by the case
    csrw  mepc, t1
    li    t1, MSTATUS_MPP
    csrs  mstatus, t1                 # MPP = M so mret lands back in M-mode

h_exit:
    lw    t2,  4(sp)
    lw    t1,  8(sp)
    lw    t0, 12(sp)
    addi  sp, sp, 16
    csrrw sp, mscratch, sp
    mret

    .align 2
s_stub:                               # entered in S-mode; each case SRETs from here
    ret

_start:
    li   sp, 0x80010000
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   s1, 0x80000000
    csrw mscratch, sp

    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)

    la   t0, m_handler
    csrw mtvec, t0
    csrw mideleg, zero                # M handles the software interrupt
    csrw medeleg, zero

    li   t0, MIE_MSIE
    csrw mie, t0
    li   t0, MSTATUS_MIE
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0
    csrsi 0x744, 8                    # mnstatus.NMIE=1 -- NMIE=0 disables ALL interrupts

    li   x31, 0x11111111

# Each case: drop to S, arm MSIP, N nops, SRET to U, ecall back to M.
.macro SHADOW_CASE idx, nops, nextlbl
    la   t0, 1f
    sw   t0, 0x60(s1)                 # where the ecall handler resumes
    la   t0, 3f
    li   t1, 0x40
    addi t1, t1, \idx*4
    add  t1, t1, s1
    sw   t0, 0(t1)                    # publish the SRET PC
    la   t0, 4f
    li   t1, 0x50
    addi t1, t1, \idx*4
    add  t1, t1, s1
    sw   t0, 0(t1)                    # publish the U-target PC
    lw   zero, 0(t1)

    # M -> S
    li   t0, MSTATUS_MPP
    csrc mstatus, t0
    li   t0, 0x800
    csrs mstatus, t0                  # MPP = S
    la   t0, 2f
    csrw mepc, t0
    mret
2:  # ---- now in S-mode ----
    la   t0, 4f
    csrw sepc, t0
    li   t0, 0x100
    csrc sstatus, t0                  # SPP = 0 -> SRET returns to U

    li   x31, 0xA0000000 + \idx      # tb arms irq_m_software from here
    .rept \nops
    nop
    .endr
3:  sret
4:  # ---- now in U-mode ----
    ecall                             # back to M via the handler
1:
.endm

    SHADOW_CASE 0, 0, case1
    SHADOW_CASE 1, 1, case2
    SHADOW_CASE 2, 2, case3
    SHADOW_CASE 3, 3, done

    li   x31, 0x22222222
    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
