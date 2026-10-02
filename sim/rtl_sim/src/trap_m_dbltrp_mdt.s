#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_m_dbltrp_mdt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: mstatush.MDT hardware set/clear
#
#   MDT (mstatush bit 10) is set by hardware on every trap into M-mode and
#   cleared by MRET, by SRET executed in M-mode, and by MNRET/dret returning
#   below M. This test covers the paths reachable from M-mode firmware.
#
#   Phase A  clear MDT, take an ECALL -> the handler must observe MDT=1
#   Phase B  after the handler's MRET -> MDT must be 0 again
#   Phase C  set MDT, execute SRET from M-mode -> MDT must clear. This is NOT
#            the MPRV rule, which only clears when the return drops below M.
#            NOT observable from firmware: after the SRET we are below M and
#            cannot read mstatush, and re-entering M would set MDT again --
#            so the testbench samples the DUT flop at the two sync points.
#   Phase D  a second trap re-arms MDT, proving set is not one-shot
#
# Scratchpad (base 0x80000000):
#   0x00 trap_count   0x04 MDT seen inside handler (phase A)
#   0x08 MDT after MRET   0x10 MDT in handler (later traps)
#   Phase C is checked white-box by the testbench, not via scratchpad.
#----------------------------------------------------------------------------

.equ MSTATUSH, 0x310
.equ MDT_MASK, 0x00000400

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    .align 2
m_handler:
    addi sp, sp, -12
    sw   t0, 8(sp)
    sw   t1, 4(sp)
    sw   t2, 0(sp)

    # record MDT as the handler sees it -- slot depends on which phase
    csrr t0, MSTATUSH
    li   t2, MDT_MASK          # andi immediate is signed 12-bit; 0x800 needs a reg
    and  t0, t0, t2
    lw   t1, 0x00(s1)
    li   t2, 1
    bne  t1, t2, h_second
    sw   t0, 0x04(s1)          # phase A: first trap
    j    h_count
h_second:
    sw   t0, 0x10(s1)          # phase D: later trap
h_count:
    lw   t1, 0x00(s1)
    addi t1, t1, 1
    sw   t1, 0x00(s1)

    csrr t1, mepc              # skip the trapping instruction
    addi t1, t1, 4
    csrw mepc, t1

    li   t1, 0x1800            # MPP = M so every mret resumes in M-mode,
    csrs mstatus, t1           # including the S-mode ecall of phase C

    lw   t2, 0(sp)
    lw   t1, 4(sp)
    lw   t0, 8(sp)
    addi sp, sp, 12
    mret

_start:
    li   sp, 0x80010000
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   s1, 0x80000000

    li   t0, 1                 # trap_count starts at 1 so phase A is "first"
    sw   t0, 0x00(s1)
    li   t0, 0
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x10(s1)

    la   t0, m_handler
    csrw mtvec, t0

    li   x31, 0x11111111

    #---------------------------------------------------------------
    # PHASE A/B: MDT set on trap entry, cleared by MRET
    #---------------------------------------------------------------
    csrsi 0x744, 8            # Smdbltrp: a trap in M-mode with NMIE=0 is an unexpected trap
    csrw MSTATUSH, x0          # MDT = 0
    ecall                      # -> handler records MDT, then MRETs

    csrr t0, MSTATUSH          # after MRET
    li   t1, MDT_MASK
    and  t0, t0, t1
    sw   t0, 0x08(s1)
    lw   zero, 0x08(s1)

    li   x31, 0x22222222

    #---------------------------------------------------------------
    # PHASE C: SRET executed in M-mode clears MDT
    #---------------------------------------------------------------
    li   t0, MDT_MASK
    csrw MSTATUSH, t0          # MDT = 1
    la   t0, after_sret
    csrw sepc, t0
    li   t0, 0x100
    csrs sstatus, t0           # SPP = S

    li   x31, 0x33333333       # tb samples the MDT flop here: must be 1
    .rept 8                    # widen the sampling window: without this the
    nop                        # sret retires before the tb can look
    .endr
    sret
after_sret:                    # now in S-mode
    li   x31, 0x34343434       # tb samples again: SRET-from-M must have cleared it
    .rept 8                    # widen again: the ecall below would re-set MDT
    nop
    .endr
    ecall                      # back to M (handler forces MPP=M)

    #---------------------------------------------------------------
    # PHASE D: a later trap re-arms MDT
    #---------------------------------------------------------------
    csrw MSTATUSH, x0
    ecall

    li   x31, 0x44444444

    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
