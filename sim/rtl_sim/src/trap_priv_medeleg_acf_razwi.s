#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_priv_medeleg_acf_razwi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: medeleg[5] / medeleg[7] follow whether causes 5/7 have a producer
#
#   Distinct from trap_priv_mideleg_razwi, which covers the SU_MODE_EN=0 case
#   where the WHOLE register is RAZ/WI. Here S-mode exists and medeleg is a
#   real register -- but the two access-fault bits still must not stick.
#
#   Causes 5 and 7 are RESERVED and are never raised: a
#   DATA-bus error is delivered as an RNMI (mncause=0x80000003), and RNMIs are
#   M-mode only by the Smrnmi definition, so they are not delegable at all.
#
#   Instruction-bus errors are unaffected -- cause 1 is still a synchronous
#   exception and medeleg[1] is still a normal, writable delegation bit.
#
#   Write all-ones, expect the implemented bits 0..9 back MINUS bits 5 and 7:
#     0x3FF & ~((1<<5)|(1<<7)) = 0x35F
#   The neighbours (4 = load misaligned, 6 = store misaligned) MUST still set,
#   which is what makes this a real check rather than "some bits read 0".
#
# Scratchpad (base 0x80000000):
#   0x00: trap_count (must remain 0)   0x04: last MCAUSE
#   0x20: medeleg readback after writing 0xFFFFFFFF (expect 0x35F)
#   0x24: medeleg readback after writing 0x00000000 (expect 0x000)
#----------------------------------------------------------------------------

main:
    j _start

    #=================================================================
    # TRAP HANDLER (defensive; not expected to fire)
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    csrr t0, mcause
    csrr t1, mepc

    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)
    sw   t0, 0x04(s1)

    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)

    la   t0, trap_handler
    csrw mtvec, t0

    li   x31, 0x11111111

    #=================================================================
    # PHASE 2: write all-ones, bits 5 and 7 must NOT stick
    #=================================================================
    li   t1, 0xFFFFFFFF
    csrw 0x302, t1              # medeleg
    csrr t0, 0x302
    sw   t0, 0x20(s1)
    lw   t0, 0x20(s1)           # load-back fence

    li   x31, 0x22222222

    #=================================================================
    # PHASE 3: write zero, everything clears
    #=================================================================
    li   t1, 0x00000000
    csrw 0x302, t1
    csrr t0, 0x302
    sw   t0, 0x24(s1)
    lw   t0, 0x24(s1)

    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
