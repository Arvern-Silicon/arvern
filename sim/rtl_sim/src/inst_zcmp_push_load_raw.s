#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmp_push_load_raw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Bug reproducer - RAW hazard from a LOAD into the FIRST-stored
#              register of an immediately following CM.PUSH.
#
# Suspected bug: a load writing register X, immediately followed (back-to-back,
# no gap instruction) by a CM.PUSH whose register list contains X, pushes the
# STALE (pre-load) value of X for the FIRST store of the push sequence.
#
# Zcmp CM.PUSH stack layout / store order (Zc spec v1.0, CM.PUSH operation):
#
#   addr = sp - bytes;
#   for (i in 27,26,25,24,23,22,21,20,19,18,9,8,1) {   // s11,s10,...,s1,s0,ra
#       if (xreg_list[i]) { mem[addr] = X(i); addr -= bytes; }
#   }
#   sp = sp - stack_adj;
#
# i.e. registers are stored at DESCENDING addresses starting at old_sp-4, in
# DESCENDING register order: the HIGHEST-numbered register of the list is the
# FIRST store, at old_sp-4; ra is stored LAST, at the lowest address of the
# register block. For {ra, s0-s1}, -16:
#     s1 at old_sp-4  = new_sp+12   <-- FIRST store of the sequence
#     s0 at old_sp-8  = new_sp+8
#     ra at old_sp-12 = new_sp+4
#     new_sp+0        = padding (stack_adj rounded to 16)
# For {ra, s0-s2}, -16 (4 regs, no padding):
#     s2 at new_sp+12 (FIRST store), s1 at +8, s0 at +4, ra at +0
#
# (The spec makes the LAYOUT architectural; this test therefore self-checks
# EVERY stacked word, so it fails if ANY store of the sequence used a stale
# value, whatever internal store order the implementation uses. The loaded
# register is deliberately the spec-order FIRST-stored one in each RAW case.)
#
# Cases (each with its own sync value, fresh sp, and dedicated stash register
# that is never rewritten afterwards so the testbench can check it race-free):
#   Case 1 (0x11111111): lw s1  ; cm.push {ra,s0-s1}, -16   (back-to-back, std lw)
#   Case 2 (0x22222222): lw s2  ; cm.push {ra,s0-s2}, -16   (back-to-back, std lw)
#   Case 3 (0x33333333): lw s1 ; NOP ; cm.push {ra,s0-s1}   (CONTROL: 1-inst gap,
#                        must PASS even on buggy RTL - documents the boundary)
#   Case 4 (0x44444444): c.lw s1 ; cm.push {ra,s0-s1}       (back-to-back, both
#                        16/32-bit fetch-word neighbours, compressed load)
#
# Fresh values 0x600D000x are planted in memory; stale values 0xBADBADxx are
# preloaded into the target register. On buggy RTL the stacked word at
# new_sp+12 reads back 0xBADBADxx instead of 0x600D000x.
#
# Error code (x30) = 0x0000CCNN : CC = case (01-04), NN = check within case.
# The expected FAIL signature on buggy RTL is x30 = 0x00000102
# (case 1, check 2: stacked s1 == fresh), x11 = 0xBADBAD01, x12 = 0x600D0001.
#
# Deterministic: no random IRQ injection (no _random_irq_init call) - an IRQ
# kill/replay of CM.PUSH would separate it from the load and hide the bug.
#----------------------------------------------------------------------------

.section .text
.global main

main:

    #-------------------------------------------------
    # CASE 1: lw s1 back-to-back with cm.push {ra, s0-s1}, -16
    #         s1 is the FIRST-stored register (old_sp-4)
    #-------------------------------------------------
    li   a0, 0x80000F00          # address of fresh-data word for case 1
    li   t1, 0x600D0001          # FRESH value
    sw   t1, 0(a0)               # plant fresh value in memory

    li   ra, 0xC1000011          # other pushed regs get known values
    li   s0, 0xC1000022
    li   s1, 0xBADBAD01          # STALE (pre-load) value in s1
    li   sp, 0x80001000          # stack top for this case

    .align 2                     # deterministic placement of the pair
.option push
.option norvc                    # force the 32-bit lw encoding
    lw   s1, 0(a0)               # load FRESH value into s1 ...
.option pop
    cm.push {ra, s0-s1}, -16     # ... IMMEDIATELY pushed; s1 = 1st store
                                 # new sp = 0x80000FF0

    lw   x11, 12(sp)             # read back stacked s1 (old_sp-4)
    mv   a3, x11                 # stash for testbench (x13, never reused)

    li   x30, 0x00000101         # Case 1, Check 1: live s1 got the fresh value
    li   x12, 0x600D0001
    bne  s1,  x12, test_fail

    li   x30, 0x00000102         # Case 1, Check 2: stacked s1 == FRESH  << BUG CHECK
    bne  x11, x12, test_fail     # buggy RTL: x11 = 0xBADBAD01 (stale)

    li   x30, 0x00000103         # Case 1, Check 3: stacked s0
    lw   x11, 8(sp)
    li   x12, 0xC1000022
    bne  x11, x12, test_fail

    li   x30, 0x00000104         # Case 1, Check 4: stacked ra
    lw   x11, 4(sp)
    li   x12, 0xC1000011
    bne  x11, x12, test_fail

    li   x30, 0x00000105         # Case 1, Check 5: sp decremented by 16
    li   x12, 0x80000FF0
    bne  sp,  x12, test_fail

    li   x31, 0x11111111         # Sync: case 1 done


    #-------------------------------------------------
    # CASE 2: lw s2 back-to-back with cm.push {ra, s0-s2}, -16
    #         different rlist; s2 is the FIRST-stored register
    #-------------------------------------------------
    li   a0, 0x80000F04          # address of fresh-data word for case 2
    li   t1, 0x600D0002          # FRESH value
    sw   t1, 0(a0)

    li   ra, 0xC2000011
    li   s0, 0xC2000022
    li   s1, 0xC2000033
    li   s2, 0xBADBAD02          # STALE value in s2
    li   sp, 0x80002000

    .align 2
.option push
.option norvc
    lw   s2, 0(a0)               # load FRESH value into s2 ...
.option pop
    cm.push {ra, s0-s2}, -16     # ... IMMEDIATELY pushed; s2 = 1st store
                                 # new sp = 0x80001FF0

    lw   x11, 12(sp)             # read back stacked s2 (old_sp-4)
    mv   a4, x11                 # stash for testbench (x14, never reused)

    li   x30, 0x00000201         # Case 2, Check 1: live s2 got the fresh value
    li   x12, 0x600D0002
    bne  s2,  x12, test_fail

    li   x30, 0x00000202         # Case 2, Check 2: stacked s2 == FRESH  << BUG CHECK
    bne  x11, x12, test_fail

    li   x30, 0x00000203         # Case 2, Check 3: stacked s1
    lw   x11, 8(sp)
    li   x12, 0xC2000033
    bne  x11, x12, test_fail

    li   x30, 0x00000204         # Case 2, Check 4: stacked s0
    lw   x11, 4(sp)
    li   x12, 0xC2000022
    bne  x11, x12, test_fail

    li   x30, 0x00000205         # Case 2, Check 5: stacked ra
    lw   x11, 0(sp)
    li   x12, 0xC2000011
    bne  x11, x12, test_fail

    li   x30, 0x00000206         # Case 2, Check 6: sp decremented by 16
    li   x12, 0x80001FF0
    bne  sp,  x12, test_fail

    li   x31, 0x22222222         # Sync: case 2 done


    #-------------------------------------------------
    # CASE 3 (CONTROL): lw s1, ONE NOP, then cm.push {ra, s0-s1}, -16
    #         Must PASS even on buggy RTL (documents the
    #         one-instruction-gap boundary of the hazard)
    #-------------------------------------------------
    li   a0, 0x80000F08          # address of fresh-data word for case 3
    li   t1, 0x600D0003          # FRESH value
    sw   t1, 0(a0)

    li   ra, 0xC3000011
    li   s0, 0xC3000022
    li   s1, 0xBADBAD03          # STALE value in s1
    li   sp, 0x80003000

    .align 2
.option push
.option norvc
    lw   s1, 0(a0)               # load FRESH value into s1
    nop                          # ONE instruction gap (32-bit nop)
.option pop
    cm.push {ra, s0-s1}, -16     # new sp = 0x80002FF0

    lw   x11, 12(sp)             # read back stacked s1
    mv   a5, x11                 # stash for testbench (x15, never reused)

    li   x30, 0x00000301         # Case 3, Check 1: live s1
    li   x12, 0x600D0003
    bne  s1,  x12, test_fail

    li   x30, 0x00000302         # Case 3, Check 2: stacked s1 == FRESH (control)
    bne  x11, x12, test_fail

    li   x30, 0x00000303         # Case 3, Check 3: stacked s0
    lw   x11, 8(sp)
    li   x12, 0xC3000022
    bne  x11, x12, test_fail

    li   x30, 0x00000304         # Case 3, Check 4: stacked ra
    lw   x11, 4(sp)
    li   x12, 0xC3000011
    bne  x11, x12, test_fail

    li   x30, 0x00000305         # Case 3, Check 5: sp decremented by 16
    li   x12, 0x80002FF0
    bne  sp,  x12, test_fail

    li   x31, 0x33333333         # Sync: case 3 done


    #-------------------------------------------------
    # CASE 4: c.lw s1 back-to-back with cm.push {ra, s0-s1}, -16
    #         Compressed load variant - the two 16-bit
    #         instructions share one 32-bit fetch word
    #-------------------------------------------------
    li   a0, 0x80000F0C          # address of fresh-data word for case 4
    li   t1, 0x600D0004          # FRESH value
    sw   t1, 0(a0)

    li   ra, 0xC4000011
    li   s0, 0xC4000022
    li   s1, 0xBADBAD04          # STALE value in s1
    li   sp, 0x80004000

    .align 2                     # c.lw at +0, cm.push at +2 (same fetch word)
    c.lw s1, 0(a0)               # load FRESH value into s1 ...
    cm.push {ra, s0-s1}, -16     # ... IMMEDIATELY pushed; s1 = 1st store
                                 # new sp = 0x80003FF0

    lw   x11, 12(sp)             # read back stacked s1
    mv   a6, x11                 # stash for testbench (x16, never reused)

    li   x30, 0x00000401         # Case 4, Check 1: live s1
    li   x12, 0x600D0004
    bne  s1,  x12, test_fail

    li   x30, 0x00000402         # Case 4, Check 2: stacked s1 == FRESH  << BUG CHECK
    bne  x11, x12, test_fail

    li   x30, 0x00000403         # Case 4, Check 3: stacked s0
    lw   x11, 8(sp)
    li   x12, 0xC4000022
    bne  x11, x12, test_fail

    li   x30, 0x00000404         # Case 4, Check 4: stacked ra
    lw   x11, 4(sp)
    li   x12, 0xC4000011
    bne  x11, x12, test_fail

    li   x30, 0x00000405         # Case 4, Check 5: sp decremented by 16
    li   x12, 0x80003FF0
    bne  sp,  x12, test_fail

    li   x31, 0x44444444         # Sync: case 4 done


    #-------------------------------------------------
    # ALL CASES PASSED
    #-------------------------------------------------
    li   x30, 0x00000000         # Clear error code
    li   x31, 0xDEADBEEF         # Success marker
    j    end_of_test


test_fail:
    #-------------------------------------------------
    # TEST FAILED
    # x30 = error code 0x0000CCNN (CC = case, NN = check)
    # x11 = actual value, x12 = expected value
    #-------------------------------------------------
    li   x31, 0xBADC0DE0         # Failure marker
    j    end_of_test


end_of_test:
    nop
    j    end_of_test             # Infinite loop (testbench ends simulation)
