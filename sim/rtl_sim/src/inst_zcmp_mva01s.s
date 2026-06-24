#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmp_mva01s
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.MVA01S
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
    # Each value is unique and encodes the source register
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
    # Tests 1-8: Full r1s' coverage
    # Each s-register (s0-s7) appears as r1s' (source for a0)
    #=========================================================

    #-------------------------------------------------
    # Test 1: cm.mva01s s0, s1
    # a0 = s0 = 0x80808080
    # a1 = s1 = 0x91919191
    #-------------------------------------------------
    li   x10, 0xDEADDEAD              # Sentinel a0
    li   x11, 0xDEADDEAD              # Sentinel a1
    cm.mva01s s0, s1
    mv   x3, x11                      # Save a1 before checks overwrite it

    # Check a0 = s0
    li   x30, 0x00000101
    mv   x11, x10
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    # Check a1 = s1
    li   x30, 0x00000102
    mv   x11, x3
    li   x12, 0x91919191
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 2: cm.mva01s s1, s0
    # a0 = s1 = 0x91919191
    # a1 = s0 = 0x80808080
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s1, s0
    mv   x3, x11

    li   x30, 0x00000201
    mv   x11, x10
    li   x12, 0x91919191
    bne  x11, x12, test_fail

    li   x30, 0x00000202
    mv   x11, x3
    li   x12, 0x80808080
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 3: cm.mva01s s2, s3
    # a0 = s2 = 0xA2A2A2A2
    # a1 = s3 = 0xB3B3B3B3
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s2, s3
    mv   x3, x11

    li   x30, 0x00000301
    mv   x11, x10
    li   x12, 0xA2A2A2A2
    bne  x11, x12, test_fail

    li   x30, 0x00000302
    mv   x11, x3
    li   x12, 0xB3B3B3B3
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 4: cm.mva01s s3, s2
    # a0 = s3 = 0xB3B3B3B3
    # a1 = s2 = 0xA2A2A2A2
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s3, s2
    mv   x3, x11

    li   x30, 0x00000401
    mv   x11, x10
    li   x12, 0xB3B3B3B3
    bne  x11, x12, test_fail

    li   x30, 0x00000402
    mv   x11, x3
    li   x12, 0xA2A2A2A2
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 5: cm.mva01s s4, s5
    # a0 = s4 = 0xC4C4C4C4
    # a1 = s5 = 0xD5D5D5D5
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s4, s5
    mv   x3, x11

    li   x30, 0x00000501
    mv   x11, x10
    li   x12, 0xC4C4C4C4
    bne  x11, x12, test_fail

    li   x30, 0x00000502
    mv   x11, x3
    li   x12, 0xD5D5D5D5
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 6: cm.mva01s s5, s4
    # a0 = s5 = 0xD5D5D5D5
    # a1 = s4 = 0xC4C4C4C4
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s5, s4
    mv   x3, x11

    li   x30, 0x00000601
    mv   x11, x10
    li   x12, 0xD5D5D5D5
    bne  x11, x12, test_fail

    li   x30, 0x00000602
    mv   x11, x3
    li   x12, 0xC4C4C4C4
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 7: cm.mva01s s6, s7
    # a0 = s6 = 0xE6E6E6E6
    # a1 = s7 = 0xF7F7F7F7
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s6, s7
    mv   x3, x11

    li   x30, 0x00000701
    mv   x11, x10
    li   x12, 0xE6E6E6E6
    bne  x11, x12, test_fail

    li   x30, 0x00000702
    mv   x11, x3
    li   x12, 0xF7F7F7F7
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 8: cm.mva01s s7, s6
    # a0 = s7 = 0xF7F7F7F7
    # a1 = s6 = 0xE6E6E6E6
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s7, s6
    mv   x3, x11

    li   x30, 0x00000801
    mv   x11, x10
    li   x12, 0xF7F7F7F7
    bne  x11, x12, test_fail

    li   x30, 0x00000802
    mv   x11, x3
    li   x12, 0xE6E6E6E6
    bne  x11, x12, test_fail


    #=========================================================
    # Tests 9-14: Remaining r2s' coverage
    # s2-s7 as r2s' (s0 and s1 already covered in tests 1-2)
    #=========================================================

    #-------------------------------------------------
    # Test 9: cm.mva01s s0, s2
    # a0 = s0 = 0x80808080, a1 = s2 = 0xA2A2A2A2
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s2
    mv   x3, x11

    li   x30, 0x00000901
    mv   x11, x10
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    li   x30, 0x00000902
    mv   x11, x3
    li   x12, 0xA2A2A2A2
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 10: cm.mva01s s0, s3
    # a0 = s0 = 0x80808080, a1 = s3 = 0xB3B3B3B3
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s3
    mv   x3, x11

    li   x30, 0x00000A01
    mv   x11, x10
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    li   x30, 0x00000A02
    mv   x11, x3
    li   x12, 0xB3B3B3B3
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 11: cm.mva01s s0, s4
    # a0 = s0 = 0x80808080, a1 = s4 = 0xC4C4C4C4
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s4
    mv   x3, x11

    li   x30, 0x00000B01
    mv   x11, x10
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    li   x30, 0x00000B02
    mv   x11, x3
    li   x12, 0xC4C4C4C4
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 12: cm.mva01s s0, s5
    # a0 = s0 = 0x80808080, a1 = s5 = 0xD5D5D5D5
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s5
    mv   x3, x11

    li   x30, 0x00000C01
    mv   x11, x10
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    li   x30, 0x00000C02
    mv   x11, x3
    li   x12, 0xD5D5D5D5
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 13: cm.mva01s s0, s6
    # a0 = s0 = 0x80808080, a1 = s6 = 0xE6E6E6E6
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s6
    mv   x3, x11

    li   x30, 0x00000D01
    mv   x11, x10
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    li   x30, 0x00000D02
    mv   x11, x3
    li   x12, 0xE6E6E6E6
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 14: cm.mva01s s0, s7
    # a0 = s0 = 0x80808080, a1 = s7 = 0xF7F7F7F7
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s7
    mv   x3, x11

    li   x30, 0x00000E01
    mv   x11, x10
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    li   x30, 0x00000E02
    mv   x11, x3
    li   x12, 0xF7F7F7F7
    bne  x11, x12, test_fail


    #=========================================================
    # Tests 15-17: Same register for both r1s' and r2s'
    # Both a0 and a1 should get the same value
    #=========================================================

    #-------------------------------------------------
    # Test 15: cm.mva01s s0, s0
    # a0 = a1 = s0 = 0x80808080
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s0
    mv   x3, x11

    li   x30, 0x00000F01
    mv   x11, x10
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    li   x30, 0x00000F02
    mv   x11, x3
    li   x12, 0x80808080
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 16: cm.mva01s s7, s7
    # a0 = a1 = s7 = 0xF7F7F7F7
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s7, s7
    mv   x3, x11

    li   x30, 0x00001001
    mv   x11, x10
    li   x12, 0xF7F7F7F7
    bne  x11, x12, test_fail

    li   x30, 0x00001002
    mv   x11, x3
    li   x12, 0xF7F7F7F7
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 17: cm.mva01s s3, s3
    # a0 = a1 = s3 = 0xB3B3B3B3
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s3, s3
    mv   x3, x11

    li   x30, 0x00001101
    mv   x11, x10
    li   x12, 0xB3B3B3B3
    bne  x11, x12, test_fail

    li   x30, 0x00001102
    mv   x11, x3
    li   x12, 0xB3B3B3B3
    bne  x11, x12, test_fail


    #=========================================================
    # Tests 18-19: Cross patterns (non-adjacent registers)
    #=========================================================

    #-------------------------------------------------
    # Test 18: cm.mva01s s2, s7
    # a0 = s2 = 0xA2A2A2A2, a1 = s7 = 0xF7F7F7F7
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s2, s7
    mv   x3, x11

    li   x30, 0x00001201
    mv   x11, x10
    li   x12, 0xA2A2A2A2
    bne  x11, x12, test_fail

    li   x30, 0x00001202
    mv   x11, x3
    li   x12, 0xF7F7F7F7
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 19: cm.mva01s s6, s1
    # a0 = s6 = 0xE6E6E6E6, a1 = s1 = 0x91919191
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s6, s1
    mv   x3, x11

    li   x30, 0x00001301
    mv   x11, x10
    li   x12, 0xE6E6E6E6
    bne  x11, x12, test_fail

    li   x30, 0x00001302
    mv   x11, x3
    li   x12, 0x91919191
    bne  x11, x12, test_fail


    #=========================================================
    # Tests 20-21: Pipeline hazard tests (RAW)
    #=========================================================

    #-------------------------------------------------
    # Test 20: RAW hazard on r1s'
    # li s0, new_val immediately before cm.mva01s s0, s1
    # a0 must use the new s0 value
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    li   x8,  0x20202020              # New s0 value (RAW hazard)
    cm.mva01s s0, s1
    mv   x3, x11

    li   x30, 0x00001401
    mv   x11, x10
    li   x12, 0x20202020              # Must be new s0 value
    bne  x11, x12, test_fail

    li   x30, 0x00001402
    mv   x11, x3
    li   x12, 0x91919191              # s1 unchanged
    bne  x11, x12, test_fail

    li   x8,  0x80808080              # Restore s0


    #-------------------------------------------------
    # Test 21: RAW hazard on r2s'
    # li s1, new_val immediately before cm.mva01s s0, s1
    # a1 must use the new s1 value
    #-------------------------------------------------
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    li   x9,  0x21212121              # New s1 value (RAW hazard)
    cm.mva01s s0, s1
    mv   x3, x11

    li   x30, 0x00001501
    mv   x11, x10
    li   x12, 0x80808080              # s0 unchanged
    bne  x11, x12, test_fail

    li   x30, 0x00001502
    mv   x11, x3
    li   x12, 0x21212121              # Must be new s1 value
    bne  x11, x12, test_fail

    li   x9,  0x91919191              # Restore s1


    #=========================================================
    # Test 22: Load-use hazard
    # lw s0, addr immediately before cm.mva01s s0, s1
    #=========================================================
    li   x3,  0x80001000              # Memory address
    li   x4,  0x22222222              # Value to store
    sw   x4,  0(x3)                   # Store to memory

    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    lw   x8,  0(x3)                   # Load s0 from memory (load-use hazard)
    cm.mva01s s0, s1
    mv   x3, x11

    li   x30, 0x00001601
    mv   x11, x10
    li   x12, 0x22222222              # Must be loaded value
    bne  x11, x12, test_fail

    li   x30, 0x00001602
    mv   x11, x3
    li   x12, 0x91919191              # s1 unchanged
    bne  x11, x12, test_fail

    li   x8,  0x80808080              # Restore s0


    #=========================================================
    # Test 23: Back-to-back cm.mva01s
    # Second instruction must override the first
    #=========================================================
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s1                  # First:  a0=s0, a1=s1
    cm.mva01s s2, s3                  # Second: a0=s2, a1=s3 (overrides)
    mv   x3, x11

    # a0 should be s2, NOT s0
    li   x30, 0x00001701
    mv   x11, x10
    li   x12, 0xA2A2A2A2
    bne  x11, x12, test_fail

    # a1 should be s3, NOT s1
    li   x30, 0x00001702
    mv   x11, x3
    li   x12, 0xB3B3B3B3
    bne  x11, x12, test_fail


    #=========================================================
    # Test 24: Result forwarding
    # Use a0 and a1 immediately after cm.mva01s
    #=========================================================
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s1                  # a0=0x80808080, a1=0x91919191
    add  x3, x10, x11                # x3 = a0 + a1 = 0x80808080 + 0x91919191

    li   x30, 0x00001801
    mv   x11, x3
    li   x12, 0x12121211              # 0x80808080 + 0x91919191 = 0x12121211 (with overflow)
    bne  x11, x12, test_fail


    #=========================================================
    # Test 25: Zero source value
    # s0 = 0, cm.mva01s s0, s1 -> a0 must be 0
    #=========================================================
    li   x8,  0                       # Set s0 to zero

    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s1
    mv   x3, x11

    li   x30, 0x00001901
    mv   x11, x10
    li   x12, 0x00000000              # a0 must be 0
    bne  x11, x12, test_fail

    li   x30, 0x00001902
    mv   x11, x3
    li   x12, 0x91919191              # a1 = s1 unchanged
    bne  x11, x12, test_fail

    li   x8,  0x80808080              # Restore s0


    #=========================================================
    # Test 26: All-ones source value
    # s0 = 0xFFFFFFFF, cm.mva01s s0, s1 -> a0 = 0xFFFFFFFF
    #=========================================================
    li   x8,  0xFFFFFFFF              # Set s0 to all-ones

    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s1
    mv   x3, x11

    li   x30, 0x00001A01
    mv   x11, x10
    li   x12, 0xFFFFFFFF
    bne  x11, x12, test_fail

    li   x30, 0x00001A02
    mv   x11, x3
    li   x12, 0x91919191
    bne  x11, x12, test_fail

    li   x8,  0x80808080              # Restore s0


    #=========================================================
    # Test 27: Non-target register preservation
    # Verify cm.mva01s only writes a0/a1, not source or other regs
    #=========================================================
    # Set identifiable values in registers we'll check
    li   x1,  0xD1D1D1D1              # ra
    li   x4,  0xD4D4D4D4              # tp
    li   x5,  0xD5D5D5D5              # t0
    li   x6,  0xD6D6D6D6              # t1
    li   x13, 0xDDDDDDDD              # a3
    li   x14, 0xDEDEDEDE              # a4
    li   x28, 0xD8D8D8D8              # t3
    # s0-s7 already at distinctive values

    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    cm.mva01s s0, s1
    mv   x3, x11                      # Save a1

    # Check a0 = s0
    li   x30, 0x00001B01
    mv   x11, x10
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    # Check a1 = s1
    li   x30, 0x00001B02
    mv   x11, x3
    li   x12, 0x91919191
    bne  x11, x12, test_fail

    # Check SP unchanged
    li   x30, 0x00001B03
    mv   x11, x2
    li   x12, 0x80001000
    bne  x11, x12, test_fail

    # Check ra unchanged
    li   x30, 0x00001B04
    mv   x11, x1
    li   x12, 0xD1D1D1D1
    bne  x11, x12, test_fail

    # Check s0 unchanged (source must not be modified)
    li   x30, 0x00001B05
    mv   x11, x8
    li   x12, 0x80808080
    bne  x11, x12, test_fail

    # Check s1 unchanged (source must not be modified)
    li   x30, 0x00001B06
    mv   x11, x9
    li   x12, 0x91919191
    bne  x11, x12, test_fail

    # Check s2 unchanged
    li   x30, 0x00001B07
    mv   x11, x18
    li   x12, 0xA2A2A2A2
    bne  x11, x12, test_fail

    # Check s7 unchanged
    li   x30, 0x00001B08
    mv   x11, x23
    li   x12, 0xF7F7F7F7
    bne  x11, x12, test_fail

    # Check t0 unchanged
    li   x30, 0x00001B09
    mv   x11, x5
    li   x12, 0xD5D5D5D5
    bne  x11, x12, test_fail

    # Check a3 unchanged
    li   x30, 0x00001B0A
    mv   x11, x13
    li   x12, 0xDDDDDDDD
    bne  x11, x12, test_fail

    # Check a4 unchanged
    li   x30, 0x00001B0B
    mv   x11, x14
    li   x12, 0xDEDEDEDE
    bne  x11, x12, test_fail

    # Check t3 unchanged
    li   x30, 0x00001B0C
    mv   x11, x28
    li   x12, 0xD8D8D8D8
    bne  x11, x12, test_fail

    # Check tp unchanged
    li   x30, 0x00001B0D
    mv   x11, x4
    li   x12, 0xD4D4D4D4
    bne  x11, x12, test_fail


    #=========================================================
    # Test 28: RAW hazard on high s-register (s5)
    # li s5, new_val; cm.mva01s s5, s0
    #=========================================================
    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    li   x21, 0x28282828              # New s5 value (RAW hazard)
    cm.mva01s s5, s0
    mv   x3, x11

    li   x30, 0x00001C01
    mv   x11, x10
    li   x12, 0x28282828              # Must be new s5 value
    bne  x11, x12, test_fail

    li   x30, 0x00001C02
    mv   x11, x3
    li   x12, 0x80808080              # s0 unchanged
    bne  x11, x12, test_fail

    li   x21, 0xD5D5D5D5              # Restore s5


    #=========================================================
    # Test 29: Load-use hazard on high s-register (s3)
    # lw s3, addr; cm.mva01s s3, s7
    #=========================================================
    li   x3,  0x80001000              # Memory address
    li   x4,  0x29292929              # Value to store
    sw   x4,  4(x3)                   # Store to memory at offset 4

    li   x10, 0xDEADDEAD
    li   x11, 0xDEADDEAD
    lw   x19, 4(x3)                   # Load s3 from memory (load-use hazard)
    cm.mva01s s3, s7
    mv   x3, x11

    li   x30, 0x00001D01
    mv   x11, x10
    li   x12, 0x29292929              # Must be loaded value
    bne  x11, x12, test_fail

    li   x30, 0x00001D02
    mv   x11, x3
    li   x12, 0xF7F7F7F7              # s7 unchanged
    bne  x11, x12, test_fail

    li   x19, 0xB3B3B3B3              # Restore s3


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
	#   CC = Check number (01 = a0 check, 02 = a1 check,
	#        03+ = preservation checks)
	# x31 = 0xBADC0DE0 (failure marker)
	# x11 = Actual value read
	# x12 = Expected value
	#-------------------------------------------------
	li  x31, 0xBADC0DE0              # Failure marker
	j   end_of_test


end_of_test:
	nop
    j end_of_test                     # Infinite loop
