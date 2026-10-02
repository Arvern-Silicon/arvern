#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmp_mv_jalr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.MVSA01 / CM.MVA01S result used as the base of an
#              IMMEDIATELY following indirect jump (c.jr / jalr / c.jalr).
#
# Each case preloads the move destinations with the address of a per-case
# FAIL landing pad, executes the move, and jumps back-to-back through one of
# the freshly written registers. Every reachable landing pad writes a unique
# constant into that case's result register and continues to the next case,
# so a stale-value jump is reported rather than hanging.
#
# Result registers:
#   x24 = case 1  (cm.mvsa01 s0,s1 ; c.jr s0            -> c1_t1)
#   x25 = case 2  (cm.mvsa01 s0,s1 ; c.jr s1            -> c2_t2)
#   x26 = case 3  (cm.mva01s s0,s1 ; c.jr a0            -> c3_t1)
#   x27 = case 4  (cm.mva01s s0,s1 ; c.jr a1            -> c4_t2)
#   x28 = case 5  (cm.mvsa01 s0,s1 ; jalr ra,0(s0) [32b] -> c5_t1), x12 = ra check
#   x29 = case 6  (cm.mva01s s0,s1 ; c.jalr a0          -> c6_t1), x13 = ra check
#   x30 = case 7  (cm.mvsa01 s0,s1 ; addi ; c.jr s0     -> c7_t1)  control
#
# Result encodings (N = case number):
#   0x1111000N  intended target reached
#   0x2222000N  the OTHER move destination's target reached (swapped regs)
#   0xBAD0000N  FAIL pad reached (stale preload value used as jump base)
#   0xBAD0F00N  fell through: no jump happened
#   ra check:   0x600D000N = ra correct, 0xBADBAD0N = ra wrong
#
# Deterministic: no random IRQ injection - an IRQ taken between the move and
# the jump would separate them and hide a back-to-back hazard.
#----------------------------------------------------------------------------

.section .text
.global main

main:
    li  x2,  0x80001000           # sp = safe stack address
    li  x1,  0
    li  x5,  0
    li  x6,  0
    li  x12, 0
    li  x13, 0
    li  x24, 0
    li  x25, 0
    li  x26, 0
    li  x27, 0
    li  x28, 0
    li  x29, 0
    li  x30, 0
    li  x31, 0xFFFFFFFF           # Sync: init done

    #=========================================================
    # CASE 1: cm.mvsa01 s0, s1 ; c.jr s0  -> c1_t1
    #=========================================================
case1:
    la   x8,  c1_fail             # s0 preload = FAIL pad
    la   x9,  c1_fail             # s1 preload = FAIL pad
    la   x10, c1_t1               # a0 -> s0
    la   x11, c1_t2               # a1 -> s1
    nop
    nop
    cm.mvsa01 s0, s1
    c.jr x8
    li   x24, 0xBAD0F001          # fell through
    j    case2
.align 2
c1_t1:
    li   x24, 0x11110001
    j    case2
.align 2
c1_t2:
    li   x24, 0x22220001
    j    case2
.align 2
c1_fail:
    li   x24, 0xBAD00001
    j    case2

    #=========================================================
    # CASE 2: cm.mvsa01 s0, s1 ; c.jr s1  -> c2_t2
    #=========================================================
.align 2
case2:
    la   x8,  c2_fail
    la   x9,  c2_fail
    la   x10, c2_t1
    la   x11, c2_t2
    nop
    nop
    cm.mvsa01 s0, s1
    c.jr x9
    li   x25, 0xBAD0F002
    j    case3
.align 2
c2_t1:
    li   x25, 0x22220002          # wrong destination (s0's target)
    j    case3
.align 2
c2_t2:
    li   x25, 0x11110002
    j    case3
.align 2
c2_fail:
    li   x25, 0xBAD00002
    j    case3

    #=========================================================
    # CASE 3: cm.mva01s s0, s1 ; c.jr a0  -> c3_t1
    #=========================================================
.align 2
case3:
    la   x10, c3_fail             # a0 preload = FAIL pad
    la   x11, c3_fail             # a1 preload = FAIL pad
    la   x8,  c3_t1               # s0 -> a0
    la   x9,  c3_t2               # s1 -> a1
    nop
    nop
    cm.mva01s s0, s1
    c.jr x10
    li   x26, 0xBAD0F003
    j    case4
.align 2
c3_t1:
    li   x26, 0x11110003
    j    case4
.align 2
c3_t2:
    li   x26, 0x22220003
    j    case4
.align 2
c3_fail:
    li   x26, 0xBAD00003
    j    case4

    #=========================================================
    # CASE 4: cm.mva01s s0, s1 ; c.jr a1  -> c4_t2
    #=========================================================
.align 2
case4:
    la   x10, c4_fail
    la   x11, c4_fail
    la   x8,  c4_t1
    la   x9,  c4_t2
    nop
    nop
    cm.mva01s s0, s1
    c.jr x11
    li   x27, 0xBAD0F004
    j    case5
.align 2
c4_t1:
    li   x27, 0x22220004
    j    case5
.align 2
c4_t2:
    li   x27, 0x11110004
    j    case5
.align 2
c4_fail:
    li   x27, 0xBAD00004
    j    case5

    #=========================================================
    # CASE 5: cm.mvsa01 s0, s1 ; jalr ra, 0(s0) [32-bit] -> c5_t1
    #         ra must equal address of c5_after
    #=========================================================
.align 2
case5:
    la   x8,  c5_fail
    la   x9,  c5_fail
    la   x10, c5_t1
    la   x11, c5_t2
    li   x1,  0
    nop
    nop
    cm.mvsa01 s0, s1
.option push
.option norvc
    jalr x1, 0(x8)
.option pop
c5_after:
    li   x28, 0xBAD0F005
    j    case6
.align 2
c5_t1:
    li   x28, 0x11110005
    la   x6,  c5_after
    bne  x1,  x6, c5_ra_bad
    li   x12, 0x600D0005
    j    case6
c5_ra_bad:
    li   x12, 0xBADBAD05
    j    case6
.align 2
c5_t2:
    li   x28, 0x22220005
    j    case6
.align 2
c5_fail:
    li   x28, 0xBAD00005
    j    case6

    #=========================================================
    # CASE 6: cm.mva01s s0, s1 ; c.jalr a0 -> c6_t1
    #         ra must equal address of c6_after
    #=========================================================
.align 2
case6:
    la   x10, c6_fail
    la   x11, c6_fail
    la   x8,  c6_t1
    la   x9,  c6_t2
    li   x1,  0
    nop
    nop
    cm.mva01s s0, s1
    c.jalr x10
c6_after:
    li   x29, 0xBAD0F006
    j    case7
.align 2
c6_t1:
    li   x29, 0x11110006
    la   x6,  c6_after
    bne  x1,  x6, c6_ra_bad
    li   x13, 0x600D0006
    j    case7
c6_ra_bad:
    li   x13, 0xBADBAD06
    j    case7
.align 2
c6_t2:
    li   x29, 0x22220006
    j    case7
.align 2
c6_fail:
    li   x29, 0xBAD00006
    j    case7

    #=========================================================
    # CASE 7 (control): cm.mvsa01 s0, s1 ; addi ; c.jr s0 -> c7_t1
    #         One unrelated instruction between move and jump
    #=========================================================
.align 2
case7:
    la   x8,  c7_fail
    la   x9,  c7_fail
    la   x10, c7_t1
    la   x11, c7_t2
    nop
    nop
    cm.mvsa01 s0, s1
    addi x5, x5, 1
    c.jr x8
    li   x30, 0xBAD0F007
    j    test_done
.align 2
c7_t1:
    li   x30, 0x11110007
    j    test_done
.align 2
c7_t2:
    li   x30, 0x22220007
    j    test_done
.align 2
c7_fail:
    li   x30, 0xBAD00007
    j    test_done

    #=========================================================
    # DONE
    #=========================================================
.align 2
test_done:
    li  x31, 0xDEADBEEF           # Sync: test done

end_of_test:
    nop
    j end_of_test
