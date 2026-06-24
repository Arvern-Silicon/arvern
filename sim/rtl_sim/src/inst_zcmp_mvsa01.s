#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmp_mvsa01
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.MVSA01
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIALIZE ALL REGISTERS TO KNOWN VALUES
    #-------------------------------------------------

    li  x1,  0x11111111   # ra
    li  x2,  0x22222222   # sp (will be set properly later)
    li  x3,  0x33333333   # gp
    li  x4,  0x44444444   # tp
    li  x5,  0x55555555   # t0
    li  x6,  0x66666666   # t1
    li  x7,  0x77777777   # t2
    li  x8,  0x88888888   # s0
    li  x9,  0x99999999   # s1
    li  x10, 0xAAAAAAAA   # a0
    li  x11, 0xBBBBBBBB   # a1
    li  x12, 0xCCCCCCCC   # a2
    li  x13, 0xDDDDDDDD   # a3
    li  x14, 0xEEEEEEEE   # a4
    li  x15, 0x0F0F0F0F   # a5
    li  x16, 0x10101010   # a6
    li  x17, 0x17171717   # a7
    li  x18, 0x18181818   # s2
    li  x19, 0x19191919   # s3
    li  x20, 0x20202020   # s4
    li  x21, 0x21212121   # s5
    li  x22, 0x22222222   # s6
    li  x23, 0x23232323   # s7
    li  x24, 0x24242424   # s8
    li  x25, 0x25252525   # s9
    li  x26, 0x26262626   # s10
    li  x27, 0x27272727   # s11
    li  x28, 0x28282828   # t3
    li  x29, 0x29292929   # t4
    li  x30, 0x30303030   # t5
    li  x31, 0x31313131   # t6


    #-------------------------------------------------
    # SET UP S-REGISTERS WITH DISTINCTIVE VALUES
    # These serve as the "non-target" expected values
    #-------------------------------------------------
    li  x2,  0x80001000   # SP = safe stack address
    li  x8,  0x80808080   # s0
    li  x9,  0x91919191   # s1
    li  x18, 0xA2A2A2A2   # s2
    li  x19, 0xB3B3B3B3   # s3
    li  x20, 0xC4C4C4C4   # s4
    li  x21, 0xD5D5D5D5   # s5
    li  x22, 0xE6E6E6E6   # s6
    li  x23, 0xF7F7F7F7   # s7


    #=========================================================
    # Tests 1-8: Full r1s'/r2s' coverage
    # Each s-register (s0-s7) appears as a destination
    # a0 = 0x10101010, a1 = 0x20202020 for all basic tests
    #=========================================================

    #-------------------------------------------------
    # Test 1: cm.mvsa01 s0, s1
    # s0 = a0 = 0x10101010, s1 = a1 = 0x20202020
    #-------------------------------------------------
    li   x8,  0xDEADDEAD              # Sentinel s0
    li   x9,  0xDEADDEAD              # Sentinel s1
    li   x10, 0x10101010              # a0
    li   x11, 0x20202020              # a1
    cm.mvsa01 s0, s1
    mv   x3, x11                      # Save a1 before checks overwrite it

    # Check s0 = a0
    li   x30, 0x00000101
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    # Check s1 = a1
    li   x30, 0x00000102
    mv   x11, x9
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    # Check a0 unchanged
    li   x30, 0x00000103
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    # Check a1 unchanged
    li   x30, 0x00000104
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    # Restore s0, s1
    li   x8,  0x80808080
    li   x9,  0x91919191


    #-------------------------------------------------
    # Test 2: cm.mvsa01 s1, s0
    # s1 = a0 = 0x10101010, s0 = a1 = 0x20202020
    #-------------------------------------------------
    li   x8,  0xDEADDEAD              # Sentinel s0
    li   x9,  0xDEADDEAD              # Sentinel s1
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s1, s0
    mv   x3, x11

    # Check s1 = a0
    li   x30, 0x00000201
    mv   x11, x9
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    # Check s0 = a1
    li   x30, 0x00000202
    mv   x11, x8
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    # Check a0 unchanged
    li   x30, 0x00000203
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    # Check a1 unchanged
    li   x30, 0x00000204
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


    #-------------------------------------------------
    # Test 3: cm.mvsa01 s2, s3
    # s2 = a0 = 0x10101010, s3 = a1 = 0x20202020
    #-------------------------------------------------
    li   x18, 0xDEADDEAD              # Sentinel s2
    li   x19, 0xDEADDEAD              # Sentinel s3
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s2, s3
    mv   x3, x11

    li   x30, 0x00000301
    mv   x11, x18
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000302
    mv   x11, x19
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000303
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000304
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x18, 0xA2A2A2A2
    li   x19, 0xB3B3B3B3


    #-------------------------------------------------
    # Test 4: cm.mvsa01 s3, s2
    # s3 = a0, s2 = a1
    #-------------------------------------------------
    li   x18, 0xDEADDEAD
    li   x19, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s3, s2
    mv   x3, x11

    li   x30, 0x00000401
    mv   x11, x19
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000402
    mv   x11, x18
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000403
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000404
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x18, 0xA2A2A2A2
    li   x19, 0xB3B3B3B3


    #-------------------------------------------------
    # Test 5: cm.mvsa01 s4, s5
    # s4 = a0, s5 = a1
    #-------------------------------------------------
    li   x20, 0xDEADDEAD
    li   x21, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s4, s5
    mv   x3, x11

    li   x30, 0x00000501
    mv   x11, x20
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000502
    mv   x11, x21
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000503
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000504
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x20, 0xC4C4C4C4
    li   x21, 0xD5D5D5D5


    #-------------------------------------------------
    # Test 6: cm.mvsa01 s5, s4
    # s5 = a0, s4 = a1
    #-------------------------------------------------
    li   x20, 0xDEADDEAD
    li   x21, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s5, s4
    mv   x3, x11

    li   x30, 0x00000601
    mv   x11, x21
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000602
    mv   x11, x20
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000603
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000604
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x20, 0xC4C4C4C4
    li   x21, 0xD5D5D5D5


    #-------------------------------------------------
    # Test 7: cm.mvsa01 s6, s7
    # s6 = a0, s7 = a1
    #-------------------------------------------------
    li   x22, 0xDEADDEAD
    li   x23, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s6, s7
    mv   x3, x11

    li   x30, 0x00000701
    mv   x11, x22
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000702
    mv   x11, x23
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000703
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000704
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x22, 0xE6E6E6E6
    li   x23, 0xF7F7F7F7


    #-------------------------------------------------
    # Test 8: cm.mvsa01 s7, s6
    # s7 = a0, s6 = a1
    #-------------------------------------------------
    li   x22, 0xDEADDEAD
    li   x23, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s7, s6
    mv   x3, x11

    li   x30, 0x00000801
    mv   x11, x23
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000802
    mv   x11, x22
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000803
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000804
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x22, 0xE6E6E6E6
    li   x23, 0xF7F7F7F7


    #=========================================================
    # Tests 9-14: Remaining r2s' coverage
    # s2-s7 as r2s' (s0/s1 already covered in tests 1-2)
    #=========================================================

    #-------------------------------------------------
    # Test 9: cm.mvsa01 s0, s2
    # s0 = a0, s2 = a1
    #-------------------------------------------------
    li   x8,  0xDEADDEAD
    li   x18, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s0, s2
    mv   x3, x11

    li   x30, 0x00000901
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000902
    mv   x11, x18
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000903
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000904
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x18, 0xA2A2A2A2


    #-------------------------------------------------
    # Test 10: cm.mvsa01 s0, s3
    # s0 = a0, s3 = a1
    #-------------------------------------------------
    li   x8,  0xDEADDEAD
    li   x19, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s0, s3
    mv   x3, x11

    li   x30, 0x00000A01
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000A02
    mv   x11, x19
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000A03
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000A04
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x19, 0xB3B3B3B3


    #-------------------------------------------------
    # Test 11: cm.mvsa01 s0, s4
    # s0 = a0, s4 = a1
    #-------------------------------------------------
    li   x8,  0xDEADDEAD
    li   x20, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s0, s4
    mv   x3, x11

    li   x30, 0x00000B01
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000B02
    mv   x11, x20
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000B03
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000B04
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x20, 0xC4C4C4C4


    #-------------------------------------------------
    # Test 12: cm.mvsa01 s0, s5
    # s0 = a0, s5 = a1
    #-------------------------------------------------
    li   x8,  0xDEADDEAD
    li   x21, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s0, s5
    mv   x3, x11

    li   x30, 0x00000C01
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000C02
    mv   x11, x21
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000C03
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000C04
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x21, 0xD5D5D5D5


    #-------------------------------------------------
    # Test 13: cm.mvsa01 s0, s6
    # s0 = a0, s6 = a1
    #-------------------------------------------------
    li   x8,  0xDEADDEAD
    li   x22, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s0, s6
    mv   x3, x11

    li   x30, 0x00000D01
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000D02
    mv   x11, x22
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000D03
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000D04
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x22, 0xE6E6E6E6


    #-------------------------------------------------
    # Test 14: cm.mvsa01 s0, s7
    # s0 = a0, s7 = a1
    #-------------------------------------------------
    li   x8,  0xDEADDEAD
    li   x23, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s0, s7
    mv   x3, x11

    li   x30, 0x00000E01
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000E02
    mv   x11, x23
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x30, 0x00000E03
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00000E04
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x23, 0xF7F7F7F7


    #=========================================================
    # Tests 18-19: Cross patterns (non-adjacent registers)
    # Note: same-register (r1s'==r2s') is an illegal encoding
    #=========================================================

    #-------------------------------------------------
    # Test 18: cm.mvsa01 s2, s7
    # s2 = a0 = 0x12345678, s7 = a1 = 0x9ABCDEF0
    #-------------------------------------------------
    li   x18, 0xDEADDEAD
    li   x23, 0xDEADDEAD
    li   x10, 0x12345678
    li   x11, 0x9ABCDEF0
    cm.mvsa01 s2, s7
    mv   x3, x11

    li   x30, 0x00001201
    mv   x11, x18
    li   x12, 0x12345678
    bne  x11, x12, test_fail

    li   x30, 0x00001202
    mv   x11, x23
    li   x12, 0x9ABCDEF0
    bne  x11, x12, test_fail

    li   x30, 0x00001203
    mv   x11, x10
    li   x12, 0x12345678
    bne  x11, x12, test_fail

    li   x30, 0x00001204
    mv   x11, x3
    li   x12, 0x9ABCDEF0
    bne  x11, x12, test_fail

    li   x18, 0xA2A2A2A2
    li   x23, 0xF7F7F7F7


    #-------------------------------------------------
    # Test 19: cm.mvsa01 s6, s1
    # s6 = a0 = 0xFEDCBA98, s1 = a1 = 0x76543210
    #-------------------------------------------------
    li   x22, 0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x10, 0xFEDCBA98
    li   x11, 0x76543210
    cm.mvsa01 s6, s1
    mv   x3, x11

    li   x30, 0x00001301
    mv   x11, x22
    li   x12, 0xFEDCBA98
    bne  x11, x12, test_fail

    li   x30, 0x00001302
    mv   x11, x9
    li   x12, 0x76543210
    bne  x11, x12, test_fail

    li   x30, 0x00001303
    mv   x11, x10
    li   x12, 0xFEDCBA98
    bne  x11, x12, test_fail

    li   x30, 0x00001304
    mv   x11, x3
    li   x12, 0x76543210
    bne  x11, x12, test_fail

    li   x22, 0xE6E6E6E6
    li   x9,  0x91919191


    #=========================================================
    # Tests 20-21: RAW hazard on a0/a1
    #=========================================================

    #-------------------------------------------------
    # Test 20: RAW hazard on a0
    # li a0, new_val immediately before cm.mvsa01
    # s0 must use the new a0 value
    #-------------------------------------------------
    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x11, 0x20202020              # a1
    li   x10, 0x14141414              # a0 set RIGHT BEFORE instruction (RAW)
    cm.mvsa01 s0, s1
    mv   x3, x11

    li   x30, 0x00001401
    mv   x11, x8
    li   x12, 0x14141414              # Must be new a0 value
    bne  x11, x12, test_fail

    li   x30, 0x00001402
    mv   x11, x9
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


    #-------------------------------------------------
    # Test 21: RAW hazard on a1
    # li a1, new_val immediately before cm.mvsa01
    # s1 must use the new a1 value
    #-------------------------------------------------
    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x10, 0x10101010              # a0
    li   x11, 0x15151515              # a1 set RIGHT BEFORE instruction (RAW)
    cm.mvsa01 s0, s1
    mv   x3, x11

    li   x30, 0x00001501
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    li   x30, 0x00001502
    mv   x11, x9
    li   x12, 0x15151515              # Must be new a1 value
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


    #=========================================================
    # Test 22: Load-use hazard on a0
    # lw a0, addr immediately before cm.mvsa01
    #=========================================================
    li   x3,  0x80001000              # Memory address
    li   x4,  0x16161616              # Value to store
    sw   x4,  0(x3)                   # Store to memory

    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x11, 0x20202020              # a1
    lw   x10, 0(x3)                   # Load a0 from memory (load-use hazard)
    cm.mvsa01 s0, s1
    mv   x3, x11

    li   x30, 0x00001601
    mv   x11, x8
    li   x12, 0x16161616              # Must be loaded value
    bne  x11, x12, test_fail

    li   x30, 0x00001602
    mv   x11, x9
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


    #=========================================================
    # Test 23: Back-to-back cm.mvsa01
    # First writes s0,s1; then change a0/a1; second writes s2,s3
    #=========================================================
    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x18, 0xDEADDEAD
    li   x19, 0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s0, s1                  # s0=0x10101010, s1=0x20202020
    li   x10, 0x30303030              # Change a0
    li   x11, 0x40404040              # Change a1
    cm.mvsa01 s2, s3                  # s2=0x30303030, s3=0x40404040
    mv   x3, x11

    # Check s0 from first instruction
    li   x30, 0x00001701
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    # Check s1 from first instruction
    li   x30, 0x00001702
    mv   x11, x9
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    # Check s2 from second instruction
    li   x30, 0x00001703
    mv   x11, x18
    li   x12, 0x30303030
    bne  x11, x12, test_fail

    # Check s3 from second instruction
    li   x30, 0x00001704
    mv   x11, x19
    li   x12, 0x40404040
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191
    li   x18, 0xA2A2A2A2
    li   x19, 0xB3B3B3B3


    #=========================================================
    # Test 24: Result forwarding
    # Use written s-register immediately after cm.mvsa01
    #=========================================================
    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s0, s1                  # s0=0x10101010, s1=0x20202020
    add  x3, x8, x9                   # x3 = s0 + s1 (use results immediately)

    li   x30, 0x00001801
    mv   x11, x3
    li   x12, 0x30303030              # 0x10101010 + 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


    #=========================================================
    # Test 25: Zero source (a0 = 0)
    #=========================================================
    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x10, 0x00000000              # a0 = zero
    li   x11, 0x20202020              # a1
    cm.mvsa01 s0, s1
    mv   x3, x11

    # Check s0 = 0
    li   x30, 0x00001901
    mv   x11, x8
    li   x12, 0x00000000
    bne  x11, x12, test_fail

    # Check s1 = a1
    li   x30, 0x00001902
    mv   x11, x9
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


    #=========================================================
    # Test 26: All-ones source (a0 = 0xFFFFFFFF)
    #=========================================================
    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x10, 0xFFFFFFFF              # a0 = all-ones
    li   x11, 0x00000000              # a1 = zero
    cm.mvsa01 s0, s1
    mv   x3, x11

    # Check s0 = 0xFFFFFFFF
    li   x30, 0x00001A01
    mv   x11, x8
    li   x12, 0xFFFFFFFF
    bne  x11, x12, test_fail

    # Check s1 = 0
    li   x30, 0x00001A02
    mv   x11, x9
    li   x12, 0x00000000
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


    #=========================================================
    # Test 27: Non-target register preservation
    # cm.mvsa01 s0, s1 must NOT clobber other registers
    #=========================================================
    # Set identifiable values in registers we'll check
    li   x1,  0xD1D1D1D1              # ra
    li   x4,  0xD4D4D4D4              # tp
    li   x5,  0xD5D5D5D5              # t0
    li   x13, 0xDDDDDDDD              # a3
    li   x14, 0xDEDEDEDE              # a4
    li   x28, 0xD8D8D8D8              # t3
    # s2-s7 already at distinctive values

    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x10, 0x10101010
    li   x11, 0x20202020
    cm.mvsa01 s0, s1
    mv   x3, x11

    # Check s0 = a0
    li   x30, 0x00001B01
    mv   x11, x8
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    # Check s1 = a1
    li   x30, 0x00001B02
    mv   x11, x9
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    # Check a0 unchanged
    li   x30, 0x00001B03
    mv   x11, x10
    li   x12, 0x10101010
    bne  x11, x12, test_fail

    # Check a1 unchanged
    li   x30, 0x00001B04
    mv   x11, x3
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    # Check SP unchanged
    li   x30, 0x00001B05
    mv   x11, x2
    li   x12, 0x80001000
    bne  x11, x12, test_fail

    # Check ra unchanged
    li   x30, 0x00001B06
    mv   x11, x1
    li   x12, 0xD1D1D1D1
    bne  x11, x12, test_fail

    # Check s2 unchanged (non-target s-register)
    li   x30, 0x00001B07
    mv   x11, x18
    li   x12, 0xA2A2A2A2
    bne  x11, x12, test_fail

    # Check s3 unchanged
    li   x30, 0x00001B08
    mv   x11, x19
    li   x12, 0xB3B3B3B3
    bne  x11, x12, test_fail

    # Check s7 unchanged
    li   x30, 0x00001B09
    mv   x11, x23
    li   x12, 0xF7F7F7F7
    bne  x11, x12, test_fail

    # Check t0 unchanged
    li   x30, 0x00001B0A
    mv   x11, x5
    li   x12, 0xD5D5D5D5
    bne  x11, x12, test_fail

    # Check a3 unchanged
    li   x30, 0x00001B0B
    mv   x11, x13
    li   x12, 0xDDDDDDDD
    bne  x11, x12, test_fail

    # Check a4 unchanged
    li   x30, 0x00001B0C
    mv   x11, x14
    li   x12, 0xDEDEDEDE
    bne  x11, x12, test_fail

    # Check tp unchanged
    li   x30, 0x00001B0D
    mv   x11, x4
    li   x12, 0xD4D4D4D4
    bne  x11, x12, test_fail

    # Check t3 unchanged
    li   x30, 0x00001B0E
    mv   x11, x28
    li   x12, 0xD8D8D8D8
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


    #=========================================================
    # Test 28: MVA01S / MVSA01 roundtrip
    # Set s-regs -> cm.mva01s -> clear s-regs -> cm.mvsa01
    # Verify s-regs restored to original values
    #=========================================================
    li   x8,  0xAAAA1111              # s0 original value
    li   x9,  0xBBBB2222              # s1 original value

    cm.mva01s s0, s1                  # a0 = 0xAAAA1111, a1 = 0xBBBB2222

    # Clear s0, s1 to sentinel
    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD

    cm.mvsa01 s0, s1                  # s0 = a0 = 0xAAAA1111, s1 = a1 = 0xBBBB2222
    mv   x3, x11

    # Check s0 roundtripped
    li   x30, 0x00001C01
    mv   x11, x8
    li   x12, 0xAAAA1111
    bne  x11, x12, test_fail

    # Check s1 roundtripped
    li   x30, 0x00001C02
    mv   x11, x9
    li   x12, 0xBBBB2222
    bne  x11, x12, test_fail

    # Check a0 = 0xAAAA1111 (preserved through both instructions)
    li   x30, 0x00001C03
    mv   x11, x10
    li   x12, 0xAAAA1111
    bne  x11, x12, test_fail

    # Check a1 = 0xBBBB2222
    li   x30, 0x00001C04
    mv   x11, x3
    li   x12, 0xBBBB2222
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


    #=========================================================
    # Test 29: RAW hazard with high s-register destination
    # li a0, val; cm.mvsa01 s5, s0
    #=========================================================
    li   x21, 0xDEADDEAD              # Sentinel s5
    li   x8,  0xDEADDEAD              # Sentinel s0
    li   x11, 0x20202020              # a1
    li   x10, 0x1D1D1D1D              # a0 set RIGHT BEFORE (RAW)
    cm.mvsa01 s5, s0
    mv   x3, x11

    # Check s5 = a0
    li   x30, 0x00001D01
    mv   x11, x21
    li   x12, 0x1D1D1D1D
    bne  x11, x12, test_fail

    # Check s0 = a1
    li   x30, 0x00001D02
    mv   x11, x8
    li   x12, 0x20202020
    bne  x11, x12, test_fail

    li   x21, 0xD5D5D5D5
    li   x8,  0x80808080


    #=========================================================
    # Test 30: Load-use hazard on a1
    # lw a1, addr immediately before cm.mvsa01
    #=========================================================
    li   x3,  0x80001000              # Memory address
    li   x4,  0x1E1E1E1E              # Value to store
    sw   x4,  8(x3)                   # Store to memory at offset 8

    li   x8,  0xDEADDEAD
    li   x9,  0xDEADDEAD
    li   x10, 0x10101010              # a0
    lw   x11, 8(x3)                   # Load a1 from memory (load-use hazard)
    cm.mvsa01 s0, s1
    mv   x3, x11

    li   x30, 0x00001E01
    mv   x11, x8
    li   x12, 0x10101010              # s0 must be a0 value
    bne  x11, x12, test_fail

    li   x30, 0x00001E02
    mv   x11, x9
    li   x12, 0x1E1E1E1E              # s1 must be loaded a1 value
    bne  x11, x12, test_fail

    li   x8,  0x80808080
    li   x9,  0x91919191


	#-------------------------------------------------
	# ALL TESTS PASSED
	#-------------------------------------------------
	li  x30, 0x00000000              # Clear error code
	li  x31, 0xDEADBEEF              # Success marker
	j   end_of_test


test_fail:
	#-------------------------------------------------
	# TEST FAILED
	#-------------------------------------------------
	# x30 contains error code: 0x00TTCC
	#   TT = Test number (01-1D)
	#   CC = Check number
	#        01 = r1s' destination, 02 = r2s' destination,
	#        03 = a0 source preserved, 04 = a1 source preserved,
	#        05+ = other preservation checks
	# x31 = 0xBADC0DE0 (failure marker)
	# x11 = Actual value read
	# x12 = Expected value
	#-------------------------------------------------
	li  x31, 0xBADC0DE0              # Failure marker
	j   end_of_test


end_of_test:
	nop
    j end_of_test                     # Infinite loop
