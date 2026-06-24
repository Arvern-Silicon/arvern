#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmp_pop
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.POP
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
    # Test 1: rlist=4 {ra}, stack_adj=16 (spimm=0)
    # SP=0x80001000, new_SP=0x80001010
    # ra@[SP+12]
    #-------------------------------------------------
    li   x2,  0x80001000              # Set SP
    li   x3,  0x01000001              # ra value
    sw   x3,  12(x2)                  # Store ra at [SP+12]

    li   x1,  0                       # Clear ra
    cm.pop {ra}, 16                   # Pop ra, SP += 16

    # Check SP
    li   x30, 0x00000101              # Error code: Test 1, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x80001010              # Expected new SP
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000102              # Error code: Test 1, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x01000001
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 2: rlist=5 {ra,s0}, stack_adj=32 (spimm=1)
    # SP=0x80002000, new_SP=0x80002020
    # ra@[SP+24], s0@[SP+28]
    #-------------------------------------------------
    li   x2,  0x80002000              # Set SP
    li   x3,  0x02000001              # ra value
    sw   x3,  24(x2)                  # Store ra at [SP+24]
    li   x3,  0x02000002              # s0 value
    sw   x3,  28(x2)                  # Store s0 at [SP+28]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    cm.pop {ra, s0}, 32              # Pop ra,s0, SP += 32

    # Check SP
    li   x30, 0x00000201              # Error code: Test 2, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x80002020
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000202              # Error code: Test 2, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x02000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000203              # Error code: Test 2, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x02000002
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 3: rlist=6 {ra,s0-s1}, stack_adj=16 (spimm=0)
    # SP=0x80003000, new_SP=0x80003010
    # ra@[SP+4], s0@[SP+8], s1@[SP+12]
    #-------------------------------------------------
    li   x2,  0x80003000              # Set SP
    li   x3,  0x03000001              # ra value
    sw   x3,  4(x2)                   # Store ra at [SP+4]
    li   x3,  0x03000002              # s0 value
    sw   x3,  8(x2)                   # Store s0 at [SP+8]
    li   x3,  0x03000003              # s1 value
    sw   x3,  12(x2)                  # Store s1 at [SP+12]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    cm.pop {ra, s0-s1}, 16           # Pop ra,s0-s1, SP += 16

    # Check SP
    li   x30, 0x00000301              # Error code: Test 3, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x80003010
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000302              # Error code: Test 3, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x03000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000303              # Error code: Test 3, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x03000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000304              # Error code: Test 3, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x03000003
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 4: rlist=7 {ra,s0-s2}, stack_adj=48 (spimm=2)
    # SP=0x80004000, new_SP=0x80004030
    # ra@[SP+32], s0@[SP+36], s1@[SP+40], s2@[SP+44]
    #-------------------------------------------------
    li   x2,  0x80004000              # Set SP
    li   x3,  0x04000001              # ra value
    sw   x3,  32(x2)                  # Store ra at [SP+32]
    li   x3,  0x04000002              # s0 value
    sw   x3,  36(x2)                  # Store s0 at [SP+36]
    li   x3,  0x04000003              # s1 value
    sw   x3,  40(x2)                  # Store s1 at [SP+40]
    li   x3,  0x04000004              # s2 value
    sw   x3,  44(x2)                  # Store s2 at [SP+44]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    cm.pop {ra, s0-s2}, 48           # Pop ra,s0-s2, SP += 48

    # Check SP
    li   x30, 0x00000401              # Error code: Test 4, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x80004030
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000402              # Error code: Test 4, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x04000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000403              # Error code: Test 4, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x04000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000404              # Error code: Test 4, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x04000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000405              # Error code: Test 4, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x04000004
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 5: rlist=8 {ra,s0-s3}, stack_adj=48 (spimm=1)
    # SP=0x80005000, new_SP=0x80005030
    # ra@[SP+28], s0@[SP+32], s1@[SP+36], s2@[SP+40], s3@[SP+44]
    #-------------------------------------------------
    li   x2,  0x80005000              # Set SP
    li   x3,  0x05000001              # ra value
    sw   x3,  28(x2)                  # Store ra at [SP+28]
    li   x3,  0x05000002              # s0 value
    sw   x3,  32(x2)                  # Store s0 at [SP+32]
    li   x3,  0x05000003              # s1 value
    sw   x3,  36(x2)                  # Store s1 at [SP+36]
    li   x3,  0x05000004              # s2 value
    sw   x3,  40(x2)                  # Store s2 at [SP+40]
    li   x3,  0x05000005              # s3 value
    sw   x3,  44(x2)                  # Store s3 at [SP+44]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    li   x19, 0                       # Clear s3
    cm.pop {ra, s0-s3}, 48           # Pop ra,s0-s3, SP += 48

    # Check SP
    li   x30, 0x00000501              # Error code: Test 5, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x80005030
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000502              # Error code: Test 5, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x05000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000503              # Error code: Test 5, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x05000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000504              # Error code: Test 5, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x05000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000505              # Error code: Test 5, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x05000004
    bne  x11, x12, test_fail

    # Check s3
    li   x30, 0x00000506              # Error code: Test 5, Check 6 (s3)
    mv   x11, x19
    li   x12, 0x05000005
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 6: rlist=9 {ra,s0-s4}, stack_adj=48 (spimm=1)
    # SP=0x80006000, new_SP=0x80006030
    # ra@[SP+24], s0@[SP+28], s1@[SP+32], s2@[SP+36], s3@[SP+40], s4@[SP+44]
    #-------------------------------------------------
    li   x2,  0x80006000              # Set SP
    li   x3,  0x06000001              # ra value
    sw   x3,  24(x2)                  # Store ra at [SP+24]
    li   x3,  0x06000002              # s0 value
    sw   x3,  28(x2)                  # Store s0 at [SP+28]
    li   x3,  0x06000003              # s1 value
    sw   x3,  32(x2)                  # Store s1 at [SP+32]
    li   x3,  0x06000004              # s2 value
    sw   x3,  36(x2)                  # Store s2 at [SP+36]
    li   x3,  0x06000005              # s3 value
    sw   x3,  40(x2)                  # Store s3 at [SP+40]
    li   x3,  0x06000006              # s4 value
    sw   x3,  44(x2)                  # Store s4 at [SP+44]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    li   x19, 0                       # Clear s3
    li   x20, 0                       # Clear s4
    cm.pop {ra, s0-s4}, 48           # Pop ra,s0-s4, SP += 48

    # Check SP
    li   x30, 0x00000601              # Error code: Test 6, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x80006030
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000602              # Error code: Test 6, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x06000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000603              # Error code: Test 6, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x06000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000604              # Error code: Test 6, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x06000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000605              # Error code: Test 6, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x06000004
    bne  x11, x12, test_fail

    # Check s3
    li   x30, 0x00000606              # Error code: Test 6, Check 6 (s3)
    mv   x11, x19
    li   x12, 0x06000005
    bne  x11, x12, test_fail

    # Check s4
    li   x30, 0x00000607              # Error code: Test 6, Check 7 (s4)
    mv   x11, x20
    li   x12, 0x06000006
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 7: rlist=10 {ra,s0-s5}, stack_adj=80 (spimm=3)
    # SP=0x80007000, new_SP=0x80007050
    # ra@[SP+52], s0@[SP+56], s1@[SP+60], s2@[SP+64], s3@[SP+68], s4@[SP+72], s5@[SP+76]
    #-------------------------------------------------
    li   x2,  0x80007000              # Set SP
    li   x3,  0x07000001              # ra value
    sw   x3,  52(x2)                  # Store ra at [SP+52]
    li   x3,  0x07000002              # s0 value
    sw   x3,  56(x2)                  # Store s0 at [SP+56]
    li   x3,  0x07000003              # s1 value
    sw   x3,  60(x2)                  # Store s1 at [SP+60]
    li   x3,  0x07000004              # s2 value
    sw   x3,  64(x2)                  # Store s2 at [SP+64]
    li   x3,  0x07000005              # s3 value
    sw   x3,  68(x2)                  # Store s3 at [SP+68]
    li   x3,  0x07000006              # s4 value
    sw   x3,  72(x2)                  # Store s4 at [SP+72]
    li   x3,  0x07000007              # s5 value
    sw   x3,  76(x2)                  # Store s5 at [SP+76]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    li   x19, 0                       # Clear s3
    li   x20, 0                       # Clear s4
    li   x21, 0                       # Clear s5
    cm.pop {ra, s0-s5}, 80           # Pop ra,s0-s5, SP += 80

    # Check SP
    li   x30, 0x00000701              # Error code: Test 7, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x80007050
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000702              # Error code: Test 7, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x07000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000703              # Error code: Test 7, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x07000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000704              # Error code: Test 7, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x07000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000705              # Error code: Test 7, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x07000004
    bne  x11, x12, test_fail

    # Check s3
    li   x30, 0x00000706              # Error code: Test 7, Check 6 (s3)
    mv   x11, x19
    li   x12, 0x07000005
    bne  x11, x12, test_fail

    # Check s4
    li   x30, 0x00000707              # Error code: Test 7, Check 7 (s4)
    mv   x11, x20
    li   x12, 0x07000006
    bne  x11, x12, test_fail

    # Check s5
    li   x30, 0x00000708              # Error code: Test 7, Check 8 (s5)
    mv   x11, x21
    li   x12, 0x07000007
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 8: rlist=11 {ra,s0-s6}, stack_adj=32 (spimm=0)
    # SP=0x80008000, new_SP=0x80008020
    # ra@[SP+0], s0@[SP+4], s1@[SP+8], s2@[SP+12], s3@[SP+16], s4@[SP+20], s5@[SP+24], s6@[SP+28]
    #-------------------------------------------------
    li   x2,  0x80008000              # Set SP
    li   x3,  0x08000001              # ra value
    sw   x3,  0(x2)                   # Store ra at [SP+0]
    li   x3,  0x08000002              # s0 value
    sw   x3,  4(x2)                   # Store s0 at [SP+4]
    li   x3,  0x08000003              # s1 value
    sw   x3,  8(x2)                   # Store s1 at [SP+8]
    li   x3,  0x08000004              # s2 value
    sw   x3,  12(x2)                  # Store s2 at [SP+12]
    li   x3,  0x08000005              # s3 value
    sw   x3,  16(x2)                  # Store s3 at [SP+16]
    li   x3,  0x08000006              # s4 value
    sw   x3,  20(x2)                  # Store s4 at [SP+20]
    li   x3,  0x08000007              # s5 value
    sw   x3,  24(x2)                  # Store s5 at [SP+24]
    li   x3,  0x08000008              # s6 value
    sw   x3,  28(x2)                  # Store s6 at [SP+28]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    li   x19, 0                       # Clear s3
    li   x20, 0                       # Clear s4
    li   x21, 0                       # Clear s5
    li   x22, 0                       # Clear s6
    cm.pop {ra, s0-s6}, 32           # Pop ra,s0-s6, SP += 32

    # Check SP
    li   x30, 0x00000801              # Error code: Test 8, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x80008020
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000802              # Error code: Test 8, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x08000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000803              # Error code: Test 8, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x08000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000804              # Error code: Test 8, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x08000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000805              # Error code: Test 8, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x08000004
    bne  x11, x12, test_fail

    # Check s3
    li   x30, 0x00000806              # Error code: Test 8, Check 6 (s3)
    mv   x11, x19
    li   x12, 0x08000005
    bne  x11, x12, test_fail

    # Check s4
    li   x30, 0x00000807              # Error code: Test 8, Check 7 (s4)
    mv   x11, x20
    li   x12, 0x08000006
    bne  x11, x12, test_fail

    # Check s5
    li   x30, 0x00000808              # Error code: Test 8, Check 8 (s5)
    mv   x11, x21
    li   x12, 0x08000007
    bne  x11, x12, test_fail

    # Check s6
    li   x30, 0x00000809              # Error code: Test 8, Check 9 (s6)
    mv   x11, x22
    li   x12, 0x08000008
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 9: rlist=12 {ra,s0-s7}, stack_adj=80 (spimm=2)
    # SP=0x80009000, new_SP=0x80009050
    # ra@[SP+44], s0@[SP+48], s1@[SP+52], s2@[SP+56], s3@[SP+60],
    # s4@[SP+64], s5@[SP+68], s6@[SP+72], s7@[SP+76]
    #-------------------------------------------------
    li   x2,  0x80009000              # Set SP
    li   x3,  0x09000001              # ra value
    sw   x3,  44(x2)                  # Store ra at [SP+44]
    li   x3,  0x09000002              # s0 value
    sw   x3,  48(x2)                  # Store s0 at [SP+48]
    li   x3,  0x09000003              # s1 value
    sw   x3,  52(x2)                  # Store s1 at [SP+52]
    li   x3,  0x09000004              # s2 value
    sw   x3,  56(x2)                  # Store s2 at [SP+56]
    li   x3,  0x09000005              # s3 value
    sw   x3,  60(x2)                  # Store s3 at [SP+60]
    li   x3,  0x09000006              # s4 value
    sw   x3,  64(x2)                  # Store s4 at [SP+64]
    li   x3,  0x09000007              # s5 value
    sw   x3,  68(x2)                  # Store s5 at [SP+68]
    li   x3,  0x09000008              # s6 value
    sw   x3,  72(x2)                  # Store s6 at [SP+72]
    li   x3,  0x09000009              # s7 value
    sw   x3,  76(x2)                  # Store s7 at [SP+76]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    li   x19, 0                       # Clear s3
    li   x20, 0                       # Clear s4
    li   x21, 0                       # Clear s5
    li   x22, 0                       # Clear s6
    li   x23, 0                       # Clear s7
    cm.pop {ra, s0-s7}, 80           # Pop ra,s0-s7, SP += 80

    # Check SP
    li   x30, 0x00000901              # Error code: Test 9, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x80009050
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000902              # Error code: Test 9, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x09000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000903              # Error code: Test 9, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x09000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000904              # Error code: Test 9, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x09000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000905              # Error code: Test 9, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x09000004
    bne  x11, x12, test_fail

    # Check s3
    li   x30, 0x00000906              # Error code: Test 9, Check 6 (s3)
    mv   x11, x19
    li   x12, 0x09000005
    bne  x11, x12, test_fail

    # Check s4
    li   x30, 0x00000907              # Error code: Test 9, Check 7 (s4)
    mv   x11, x20
    li   x12, 0x09000006
    bne  x11, x12, test_fail

    # Check s5
    li   x30, 0x00000908              # Error code: Test 9, Check 8 (s5)
    mv   x11, x21
    li   x12, 0x09000007
    bne  x11, x12, test_fail

    # Check s6
    li   x30, 0x00000909              # Error code: Test 9, Check 9 (s6)
    mv   x11, x22
    li   x12, 0x09000008
    bne  x11, x12, test_fail

    # Check s7
    li   x30, 0x0000090A              # Error code: Test 9, Check 10 (s7)
    mv   x11, x23
    li   x12, 0x09000009
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 10: rlist=13 {ra,s0-s8}, stack_adj=64 (spimm=1)
    # SP=0x8000A000, new_SP=0x8000A040
    # ra@[SP+24], s0@[SP+28], s1@[SP+32], s2@[SP+36], s3@[SP+40],
    # s4@[SP+44], s5@[SP+48], s6@[SP+52], s7@[SP+56], s8@[SP+60]
    #-------------------------------------------------
    li   x2,  0x8000A000              # Set SP
    li   x3,  0x0A000001              # ra value
    sw   x3,  24(x2)                  # Store ra at [SP+24]
    li   x3,  0x0A000002              # s0 value
    sw   x3,  28(x2)                  # Store s0 at [SP+28]
    li   x3,  0x0A000003              # s1 value
    sw   x3,  32(x2)                  # Store s1 at [SP+32]
    li   x3,  0x0A000004              # s2 value
    sw   x3,  36(x2)                  # Store s2 at [SP+36]
    li   x3,  0x0A000005              # s3 value
    sw   x3,  40(x2)                  # Store s3 at [SP+40]
    li   x3,  0x0A000006              # s4 value
    sw   x3,  44(x2)                  # Store s4 at [SP+44]
    li   x3,  0x0A000007              # s5 value
    sw   x3,  48(x2)                  # Store s5 at [SP+48]
    li   x3,  0x0A000008              # s6 value
    sw   x3,  52(x2)                  # Store s6 at [SP+52]
    li   x3,  0x0A000009              # s7 value
    sw   x3,  56(x2)                  # Store s7 at [SP+56]
    li   x3,  0x0A00000A              # s8 value
    sw   x3,  60(x2)                  # Store s8 at [SP+60]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    li   x19, 0                       # Clear s3
    li   x20, 0                       # Clear s4
    li   x21, 0                       # Clear s5
    li   x22, 0                       # Clear s6
    li   x23, 0                       # Clear s7
    li   x24, 0                       # Clear s8
    cm.pop {ra, s0-s8}, 64           # Pop ra,s0-s8, SP += 64

    # Check SP
    li   x30, 0x00000A01              # Error code: Test 10, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x8000A040
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000A02              # Error code: Test 10, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x0A000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000A03              # Error code: Test 10, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x0A000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000A04              # Error code: Test 10, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x0A000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000A05              # Error code: Test 10, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x0A000004
    bne  x11, x12, test_fail

    # Check s3
    li   x30, 0x00000A06              # Error code: Test 10, Check 6 (s3)
    mv   x11, x19
    li   x12, 0x0A000005
    bne  x11, x12, test_fail

    # Check s4
    li   x30, 0x00000A07              # Error code: Test 10, Check 7 (s4)
    mv   x11, x20
    li   x12, 0x0A000006
    bne  x11, x12, test_fail

    # Check s5
    li   x30, 0x00000A08              # Error code: Test 10, Check 8 (s5)
    mv   x11, x21
    li   x12, 0x0A000007
    bne  x11, x12, test_fail

    # Check s6
    li   x30, 0x00000A09              # Error code: Test 10, Check 9 (s6)
    mv   x11, x22
    li   x12, 0x0A000008
    bne  x11, x12, test_fail

    # Check s7
    li   x30, 0x00000A0A              # Error code: Test 10, Check 10 (s7)
    mv   x11, x23
    li   x12, 0x0A000009
    bne  x11, x12, test_fail

    # Check s8
    li   x30, 0x00000A0B              # Error code: Test 10, Check 11 (s8)
    mv   x11, x24
    li   x12, 0x0A00000A
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 11: rlist=14 {ra,s0-s9}, stack_adj=96 (spimm=3)
    # SP=0x8000B000, new_SP=0x8000B060
    # ra@[SP+52], s0@[SP+56], s1@[SP+60], s2@[SP+64], s3@[SP+68],
    # s4@[SP+72], s5@[SP+76], s6@[SP+80], s7@[SP+84], s8@[SP+88], s9@[SP+92]
    #-------------------------------------------------
    li   x2,  0x8000B000              # Set SP
    li   x3,  0x0B000001              # ra value
    sw   x3,  52(x2)                  # Store ra at [SP+52]
    li   x3,  0x0B000002              # s0 value
    sw   x3,  56(x2)                  # Store s0 at [SP+56]
    li   x3,  0x0B000003              # s1 value
    sw   x3,  60(x2)                  # Store s1 at [SP+60]
    li   x3,  0x0B000004              # s2 value
    sw   x3,  64(x2)                  # Store s2 at [SP+64]
    li   x3,  0x0B000005              # s3 value
    sw   x3,  68(x2)                  # Store s3 at [SP+68]
    li   x3,  0x0B000006              # s4 value
    sw   x3,  72(x2)                  # Store s4 at [SP+72]
    li   x3,  0x0B000007              # s5 value
    sw   x3,  76(x2)                  # Store s5 at [SP+76]
    li   x3,  0x0B000008              # s6 value
    sw   x3,  80(x2)                  # Store s6 at [SP+80]
    li   x3,  0x0B000009              # s7 value
    sw   x3,  84(x2)                  # Store s7 at [SP+84]
    li   x3,  0x0B00000A              # s8 value
    sw   x3,  88(x2)                  # Store s8 at [SP+88]
    li   x3,  0x0B00000B              # s9 value
    sw   x3,  92(x2)                  # Store s9 at [SP+92]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    li   x19, 0                       # Clear s3
    li   x20, 0                       # Clear s4
    li   x21, 0                       # Clear s5
    li   x22, 0                       # Clear s6
    li   x23, 0                       # Clear s7
    li   x24, 0                       # Clear s8
    li   x25, 0                       # Clear s9
    cm.pop {ra, s0-s9}, 96           # Pop ra,s0-s9, SP += 96

    # Check SP
    li   x30, 0x00000B01              # Error code: Test 11, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x8000B060
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000B02              # Error code: Test 11, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x0B000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000B03              # Error code: Test 11, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x0B000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000B04              # Error code: Test 11, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x0B000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000B05              # Error code: Test 11, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x0B000004
    bne  x11, x12, test_fail

    # Check s3
    li   x30, 0x00000B06              # Error code: Test 11, Check 6 (s3)
    mv   x11, x19
    li   x12, 0x0B000005
    bne  x11, x12, test_fail

    # Check s4
    li   x30, 0x00000B07              # Error code: Test 11, Check 7 (s4)
    mv   x11, x20
    li   x12, 0x0B000006
    bne  x11, x12, test_fail

    # Check s5
    li   x30, 0x00000B08              # Error code: Test 11, Check 8 (s5)
    mv   x11, x21
    li   x12, 0x0B000007
    bne  x11, x12, test_fail

    # Check s6
    li   x30, 0x00000B09              # Error code: Test 11, Check 9 (s6)
    mv   x11, x22
    li   x12, 0x0B000008
    bne  x11, x12, test_fail

    # Check s7
    li   x30, 0x00000B0A              # Error code: Test 11, Check 10 (s7)
    mv   x11, x23
    li   x12, 0x0B000009
    bne  x11, x12, test_fail

    # Check s8
    li   x30, 0x00000B0B              # Error code: Test 11, Check 11 (s8)
    mv   x11, x24
    li   x12, 0x0B00000A
    bne  x11, x12, test_fail

    # Check s9
    li   x30, 0x00000B0C              # Error code: Test 11, Check 12 (s9)
    mv   x11, x25
    li   x12, 0x0B00000B
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 12: rlist=15 {ra,s0-s11}, stack_adj=64 (spimm=0)
    # SP=0x8000C000, new_SP=0x8000C040
    # ra@[SP+12], s0@[SP+16], s1@[SP+20], s2@[SP+24], s3@[SP+28],
    # s4@[SP+32], s5@[SP+36], s6@[SP+40], s7@[SP+44], s8@[SP+48],
    # s9@[SP+52], s10@[SP+56], s11@[SP+60]
    #-------------------------------------------------
    li   x2,  0x8000C000              # Set SP
    li   x3,  0x0C000001              # ra value
    sw   x3,  12(x2)                  # Store ra at [SP+12]
    li   x3,  0x0C000002              # s0 value
    sw   x3,  16(x2)                  # Store s0 at [SP+16]
    li   x3,  0x0C000003              # s1 value
    sw   x3,  20(x2)                  # Store s1 at [SP+20]
    li   x3,  0x0C000004              # s2 value
    sw   x3,  24(x2)                  # Store s2 at [SP+24]
    li   x3,  0x0C000005              # s3 value
    sw   x3,  28(x2)                  # Store s3 at [SP+28]
    li   x3,  0x0C000006              # s4 value
    sw   x3,  32(x2)                  # Store s4 at [SP+32]
    li   x3,  0x0C000007              # s5 value
    sw   x3,  36(x2)                  # Store s5 at [SP+36]
    li   x3,  0x0C000008              # s6 value
    sw   x3,  40(x2)                  # Store s6 at [SP+40]
    li   x3,  0x0C000009              # s7 value
    sw   x3,  44(x2)                  # Store s7 at [SP+44]
    li   x3,  0x0C00000A              # s8 value
    sw   x3,  48(x2)                  # Store s8 at [SP+48]
    li   x3,  0x0C00000B              # s9 value
    sw   x3,  52(x2)                  # Store s9 at [SP+52]
    li   x3,  0x0C00000C              # s10 value
    sw   x3,  56(x2)                  # Store s10 at [SP+56]
    li   x3,  0x0C00000D              # s11 value
    sw   x3,  60(x2)                  # Store s11 at [SP+60]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    li   x19, 0                       # Clear s3
    li   x20, 0                       # Clear s4
    li   x21, 0                       # Clear s5
    li   x22, 0                       # Clear s6
    li   x23, 0                       # Clear s7
    li   x24, 0                       # Clear s8
    li   x25, 0                       # Clear s9
    li   x26, 0                       # Clear s10
    li   x27, 0                       # Clear s11
    cm.pop {ra, s0-s11}, 64          # Pop ra,s0-s11, SP += 64

    # Check SP
    li   x30, 0x00000C01              # Error code: Test 12, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x8000C040
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000C02              # Error code: Test 12, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x0C000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000C03              # Error code: Test 12, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x0C000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000C04              # Error code: Test 12, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x0C000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000C05              # Error code: Test 12, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x0C000004
    bne  x11, x12, test_fail

    # Check s3
    li   x30, 0x00000C06              # Error code: Test 12, Check 6 (s3)
    mv   x11, x19
    li   x12, 0x0C000005
    bne  x11, x12, test_fail

    # Check s4
    li   x30, 0x00000C07              # Error code: Test 12, Check 7 (s4)
    mv   x11, x20
    li   x12, 0x0C000006
    bne  x11, x12, test_fail

    # Check s5
    li   x30, 0x00000C08              # Error code: Test 12, Check 8 (s5)
    mv   x11, x21
    li   x12, 0x0C000007
    bne  x11, x12, test_fail

    # Check s6
    li   x30, 0x00000C09              # Error code: Test 12, Check 9 (s6)
    mv   x11, x22
    li   x12, 0x0C000008
    bne  x11, x12, test_fail

    # Check s7
    li   x30, 0x00000C0A              # Error code: Test 12, Check 10 (s7)
    mv   x11, x23
    li   x12, 0x0C000009
    bne  x11, x12, test_fail

    # Check s8
    li   x30, 0x00000C0B              # Error code: Test 12, Check 11 (s8)
    mv   x11, x24
    li   x12, 0x0C00000A
    bne  x11, x12, test_fail

    # Check s9
    li   x30, 0x00000C0C              # Error code: Test 12, Check 12 (s9)
    mv   x11, x25
    li   x12, 0x0C00000B
    bne  x11, x12, test_fail

    # Check s10
    li   x30, 0x00000C0D              # Error code: Test 12, Check 13 (s10)
    mv   x11, x26
    li   x12, 0x0C00000C
    bne  x11, x12, test_fail

    # Check s11
    li   x30, 0x00000C0E              # Error code: Test 12, Check 14 (s11)
    mv   x11, x27
    li   x12, 0x0C00000D
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 13: rlist=15 {ra,s0-s11}, stack_adj=96 (spimm=2)
    # SP=0x8000D000, new_SP=0x8000D060
    # ra@[SP+44], s0@[SP+48], s1@[SP+52], s2@[SP+56], s3@[SP+60],
    # s4@[SP+64], s5@[SP+68], s6@[SP+72], s7@[SP+76], s8@[SP+80],
    # s9@[SP+84], s10@[SP+88], s11@[SP+92]
    #-------------------------------------------------
    li   x2,  0x8000D000              # Set SP
    li   x3,  0x0D000001              # ra value
    sw   x3,  44(x2)                  # Store ra at [SP+44]
    li   x3,  0x0D000002              # s0 value
    sw   x3,  48(x2)                  # Store s0 at [SP+48]
    li   x3,  0x0D000003              # s1 value
    sw   x3,  52(x2)                  # Store s1 at [SP+52]
    li   x3,  0x0D000004              # s2 value
    sw   x3,  56(x2)                  # Store s2 at [SP+56]
    li   x3,  0x0D000005              # s3 value
    sw   x3,  60(x2)                  # Store s3 at [SP+60]
    li   x3,  0x0D000006              # s4 value
    sw   x3,  64(x2)                  # Store s4 at [SP+64]
    li   x3,  0x0D000007              # s5 value
    sw   x3,  68(x2)                  # Store s5 at [SP+68]
    li   x3,  0x0D000008              # s6 value
    sw   x3,  72(x2)                  # Store s6 at [SP+72]
    li   x3,  0x0D000009              # s7 value
    sw   x3,  76(x2)                  # Store s7 at [SP+76]
    li   x3,  0x0D00000A              # s8 value
    sw   x3,  80(x2)                  # Store s8 at [SP+80]
    li   x3,  0x0D00000B              # s9 value
    sw   x3,  84(x2)                  # Store s9 at [SP+84]
    li   x3,  0x0D00000C              # s10 value
    sw   x3,  88(x2)                  # Store s10 at [SP+88]
    li   x3,  0x0D00000D              # s11 value
    sw   x3,  92(x2)                  # Store s11 at [SP+92]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x9,  0                       # Clear s1
    li   x18, 0                       # Clear s2
    li   x19, 0                       # Clear s3
    li   x20, 0                       # Clear s4
    li   x21, 0                       # Clear s5
    li   x22, 0                       # Clear s6
    li   x23, 0                       # Clear s7
    li   x24, 0                       # Clear s8
    li   x25, 0                       # Clear s9
    li   x26, 0                       # Clear s10
    li   x27, 0                       # Clear s11
    cm.pop {ra, s0-s11}, 96          # Pop ra,s0-s11, SP += 96

    # Check SP
    li   x30, 0x00000D01              # Error code: Test 13, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x8000D060
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000D02              # Error code: Test 13, Check 2 (ra)
    mv   x11, x1
    li   x12, 0x0D000001
    bne  x11, x12, test_fail

    # Check s0
    li   x30, 0x00000D03              # Error code: Test 13, Check 3 (s0)
    mv   x11, x8
    li   x12, 0x0D000002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00000D04              # Error code: Test 13, Check 4 (s1)
    mv   x11, x9
    li   x12, 0x0D000003
    bne  x11, x12, test_fail

    # Check s2
    li   x30, 0x00000D05              # Error code: Test 13, Check 5 (s2)
    mv   x11, x18
    li   x12, 0x0D000004
    bne  x11, x12, test_fail

    # Check s3
    li   x30, 0x00000D06              # Error code: Test 13, Check 6 (s3)
    mv   x11, x19
    li   x12, 0x0D000005
    bne  x11, x12, test_fail

    # Check s4
    li   x30, 0x00000D07              # Error code: Test 13, Check 7 (s4)
    mv   x11, x20
    li   x12, 0x0D000006
    bne  x11, x12, test_fail

    # Check s5
    li   x30, 0x00000D08              # Error code: Test 13, Check 8 (s5)
    mv   x11, x21
    li   x12, 0x0D000007
    bne  x11, x12, test_fail

    # Check s6
    li   x30, 0x00000D09              # Error code: Test 13, Check 9 (s6)
    mv   x11, x22
    li   x12, 0x0D000008
    bne  x11, x12, test_fail

    # Check s7
    li   x30, 0x00000D0A              # Error code: Test 13, Check 10 (s7)
    mv   x11, x23
    li   x12, 0x0D000009
    bne  x11, x12, test_fail

    # Check s8
    li   x30, 0x00000D0B              # Error code: Test 13, Check 11 (s8)
    mv   x11, x24
    li   x12, 0x0D00000A
    bne  x11, x12, test_fail

    # Check s9
    li   x30, 0x00000D0C              # Error code: Test 13, Check 12 (s9)
    mv   x11, x25
    li   x12, 0x0D00000B
    bne  x11, x12, test_fail

    # Check s10
    li   x30, 0x00000D0D              # Error code: Test 13, Check 13 (s10)
    mv   x11, x26
    li   x12, 0x0D00000C
    bne  x11, x12, test_fail

    # Check s11
    li   x30, 0x00000D0E              # Error code: Test 13, Check 14 (s11)
    mv   x11, x27
    li   x12, 0x0D00000D
    bne  x11, x12, test_fail


    #=========================================================
    # Test 14: Special tests
    #=========================================================

    #-------------------------------------------------
    # Test 14a: Consecutive pops
    # SP=0x8000E000
    # 1st pop {ra,s0}, 32: ra@[SP+24], s0@[SP+28] -> SP=0x8000E020
    # 2nd pop {ra}, 16: ra@[0x8000E020+12]=offset 44 from original SP -> SP=0x8000E030
    #-------------------------------------------------
    li   x2,  0x8000E000              # Set SP

    # Store values for 1st pop: ra@[SP+24], s0@[SP+28]
    li   x3,  0x0E100001              # ra for 1st pop
    sw   x3,  24(x2)                  # Store ra at [SP+24]
    li   x3,  0x0E100002              # s0 for 1st pop
    sw   x3,  28(x2)                  # Store s0 at [SP+28]

    # Store value for 2nd pop: ra@[0x8000E020+12] = [SP+44]
    li   x3,  0x0E200001              # ra for 2nd pop
    sw   x3,  44(x2)                  # Store ra at offset 44 from original SP

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0

    # 1st pop
    cm.pop {ra, s0}, 32              # Pop ra,s0, SP: 0x8000E000 -> 0x8000E020

    # Check SP after 1st pop
    li   x30, 0x00000E01              # Error code: Test 14a, Check 1 (SP after 1st pop)
    mv   x11, x2
    li   x12, 0x8000E020
    bne  x11, x12, test_fail

    # Check ra after 1st pop
    li   x30, 0x00000E02              # Error code: Test 14a, Check 2 (ra after 1st pop)
    mv   x11, x1
    li   x12, 0x0E100001
    bne  x11, x12, test_fail

    # Check s0 after 1st pop
    li   x30, 0x00000E03              # Error code: Test 14a, Check 3 (s0 after 1st pop)
    mv   x11, x8
    li   x12, 0x0E100002
    bne  x11, x12, test_fail

    # Clear ra for 2nd pop
    li   x1,  0

    # 2nd pop
    cm.pop {ra}, 16                  # Pop ra, SP: 0x8000E020 -> 0x8000E030

    # Check SP after 2nd pop
    li   x30, 0x00000E04              # Error code: Test 14a, Check 4 (SP after 2nd pop)
    mv   x11, x2
    li   x12, 0x8000E030
    bne  x11, x12, test_fail

    # Check ra after 2nd pop
    li   x30, 0x00000E05              # Error code: Test 14a, Check 5 (ra after 2nd pop)
    mv   x11, x1
    li   x12, 0x0E200001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 14b: Push-pop roundtrip
    # SP=0x8000E100
    # Set ra=0x0E300001, s0=0x0E300002, s1=0x0E300003
    # cm.push {ra, s0-s1}, -48 -> SP=0x8000E0D0
    # Clear ra, s0, s1 to 0
    # cm.pop {ra, s0-s1}, 48 -> SP=0x8000E100
    # Verify all restored
    #-------------------------------------------------
    li   x2,  0x8000E100              # Set SP
    li   x1,  0x0E300001              # ra
    li   x8,  0x0E300002              # s0
    li   x9,  0x0E300003              # s1

    cm.push {ra, s0-s1}, -48         # Push: SP -> 0x8000E0D0

    # Clear registers
    li   x1,  0
    li   x8,  0
    li   x9,  0

    cm.pop {ra, s0-s1}, 48           # Pop: SP -> 0x8000E100

    # Check SP restored
    li   x30, 0x00000E06              # Error code: Test 14b, Check 1 (SP restored)
    mv   x11, x2
    li   x12, 0x8000E100
    bne  x11, x12, test_fail

    # Check ra restored
    li   x30, 0x00000E07              # Error code: Test 14b, Check 2 (ra restored)
    mv   x11, x1
    li   x12, 0x0E300001
    bne  x11, x12, test_fail

    # Check s0 restored
    li   x30, 0x00000E08              # Error code: Test 14b, Check 3 (s0 restored)
    mv   x11, x8
    li   x12, 0x0E300002
    bne  x11, x12, test_fail

    # Check s1 restored
    li   x30, 0x00000E09              # Error code: Test 14b, Check 4 (s1 restored)
    mv   x11, x9
    li   x12, 0x0E300003
    bne  x11, x12, test_fail


    #=========================================================
    # Test 15: Pipeline hazard tests
    #=========================================================

    #-------------------------------------------------
    # Test 15a: RAW on SP input - li x2, addr; cm.pop
    # SP=0x8000F000, {ra}, 16
    # Pre-store ra at [0x8000F000+12] using x3 before setting x2
    #-------------------------------------------------
    li   x3,  0x8000F000              # Use x3 to set up memory before SP
    li   x4,  0xFA000001              # ra value
    sw   x4,  12(x3)                  # Store ra at [0x8000F000+12]

    li   x1,  0                       # Clear ra
    li   x2,  0x8000F000              # Set SP immediately before pop
    cm.pop {ra}, 16                  # Must use SP=0x8000F000

    # Check SP
    li   x30, 0x00000F01              # Error code: Test 15a, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x8000F010
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000F02              # Error code: Test 15a, Check 2 (ra)
    mv   x11, x1
    li   x12, 0xFA000001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15b: RAW on SP output - cm.pop; mv x11, x2
    # SP=0x8000F100, {ra}, 16
    #-------------------------------------------------
    li   x3,  0x8000F100              # Use x3 to set up memory
    li   x4,  0xFB000001              # ra value
    sw   x4,  12(x3)                  # Store ra at [0x8000F100+12]

    li   x1,  0                       # Clear ra
    li   x2,  0x8000F100              # Set SP
    cm.pop {ra}, 16                  # Pop ra, SP -> 0x8000F110
    mv   x11, x2                      # Read SP immediately after pop

    li   x30, 0x00000F03              # Error code: Test 15b, Check 1 (SP readback)
    li   x12, 0x8000F110
    bne  x11, x12, test_fail

    li   x30, 0x00000F04              # Error code: Test 15b, Check 2 (ra)
    mv   x11, x1
    li   x12, 0xFB000001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15c: Load-use on SP - lw x2, 0(x3); nop; cm.pop
    # SP=0x8000F200, {ra}, 16
    # Store 0x8000F200 at address 0x8000F200 first
    #-------------------------------------------------
    li   x3,  0x8000F200              # Address to load SP from
    sw   x3,  0(x3)                   # Store 0x8000F200 at address 0x8000F200
    li   x4,  0xFC000001              # ra value
    sw   x4,  12(x3)                  # Store ra at [0x8000F200+12]

    li   x1,  0                       # Clear ra
    lw   x2,  0(x3)                   # Load SP from memory (SP=0x8000F200)
    cm.pop {ra}, 16                  # Pop ra, SP -> 0x8000F210

    # Check SP
    li   x30, 0x00000F05              # Error code: Test 15c, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x8000F210
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000F06              # Error code: Test 15c, Check 2 (ra)
    mv   x11, x1
    li   x12, 0xFC000001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15d: Forwarding of popped register - cm.pop {ra}, 16; mv x11, x1
    # SP=0x8000F300
    #-------------------------------------------------
    li   x3,  0x8000F300              # Use x3 to set up memory
    li   x4,  0xFD000001              # ra value
    sw   x4,  12(x3)                  # Store ra at [0x8000F300+12]

    li   x1,  0                       # Clear ra
    li   x2,  0x8000F300              # Set SP
    cm.pop {ra}, 16                  # Pop ra, SP -> 0x8000F310
    mv   x11, x1                      # Read popped ra immediately

    li   x30, 0x00000F07              # Error code: Test 15d, Check 1 (ra forwarding)
    li   x12, 0xFD000001
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00000F08              # Error code: Test 15d, Check 2 (SP)
    mv   x11, x2
    li   x12, 0x8000F310
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15e: Back-to-back cm.pop
    # SP=0x8000F400
    # 1st pop {ra}, 16 -> SP=0x8000F410
    # 2nd pop {ra,s0}, 32 -> SP=0x8000F430
    # Pre-store: ra for 1st at [0x8000F400+12],
    #            ra for 2nd at [0x8000F410+24]=offset 40,
    #            s0 for 2nd at [0x8000F410+28]=offset 44
    #-------------------------------------------------
    li   x3,  0x8000F400              # Use x3 to set up memory
    li   x4,  0xFE000001              # ra for 1st pop
    sw   x4,  12(x3)                  # Store at [0x8000F400+12]
    li   x4,  0xFE000002              # ra for 2nd pop
    sw   x4,  40(x3)                  # Store at offset 40 from original SP
    li   x4,  0xFE000003              # s0 for 2nd pop
    sw   x4,  44(x3)                  # Store at offset 44 from original SP

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x2,  0x8000F400              # Set SP

    # 1st pop
    cm.pop {ra}, 16                  # Pop ra, SP: 0x8000F400 -> 0x8000F410

    # Save ra from 1st pop before it gets overwritten
    mv   x4,  x1                      # Save 1st pop ra in x4

    # Clear ra for 2nd pop
    li   x1,  0

    # 2nd pop
    cm.pop {ra, s0}, 32             # Pop ra,s0, SP: 0x8000F410 -> 0x8000F430

    # Check final SP
    li   x30, 0x00000F09              # Error code: Test 15e, Check 1 (final SP)
    mv   x11, x2
    li   x12, 0x8000F430
    bne  x11, x12, test_fail

    # Check ra from 1st pop (saved in x4)
    li   x30, 0x00000F0A              # Error code: Test 15e, Check 2 (1st pop ra)
    mv   x11, x4
    li   x12, 0xFE000001
    bne  x11, x12, test_fail

    # Check ra from 2nd pop
    li   x30, 0x00000F0B              # Error code: Test 15e, Check 3 (2nd pop ra)
    mv   x11, x1
    li   x12, 0xFE000002
    bne  x11, x12, test_fail

    # Check s0 from 2nd pop
    li   x30, 0x00000F0C              # Error code: Test 15e, Check 4 (2nd pop s0)
    mv   x11, x8
    li   x12, 0xFE000003
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15f: Store then cm.pop to overlapping address
    # (cm.pop must read the value just written by sw)
    # SP=0x8000F500
    #-------------------------------------------------
    li   x3,  0x8000F500              # Use x3 to set up memory
    li   x4,  0xBAAAAAAD              # Decoy value
    sw   x4,  12(x3)                  # Pre-write decoy to where ra will be loaded from

    li   x4,  0xFF500001              # Real ra value
    li   x2,  0x8000F500              # Set SP
    sw   x4,  12(x2)                  # Store real ra at [SP+12] RIGHT BEFORE cm.pop
    cm.pop {ra}, 16                   # Must load the just-stored value

    # Check SP
    li   x30, 0x00000F0D              # Error code: Test 15f, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x8000F510
    bne  x11, x12, test_fail

    # Check ra (must be the value we just stored, not the decoy)
    li   x30, 0x00000F0E              # Error code: Test 15f, Check 2 (ra)
    mv   x11, x1
    li   x12, 0xFF500001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15g: Non-target register preservation
    # cm.pop {ra, s0} must NOT clobber s1-s11
    # SP=0x8000F600
    #-------------------------------------------------
    # Set all s-registers to known values
    li   x9,  0xA1A1A1A1              # s1
    li   x18, 0xA2A2A2A2              # s2
    li   x19, 0xA3A3A3A3              # s3
    li   x20, 0xA4A4A4A4              # s4
    li   x21, 0xA5A5A5A5              # s5
    li   x22, 0xA6A6A6A6              # s6
    li   x23, 0xA7A7A7A7              # s7
    li   x24, 0xA8A8A8A8              # s8
    li   x25, 0xA9A9A9A9              # s9
    li   x26, 0xAAAAAAAA              # s10
    li   x27, 0xABABABAB              # s11

    li   x2,  0x8000F600              # Set SP
    li   x3,  0xFF600001              # ra value
    sw   x3,  24(x2)                  # Store ra at [SP+24]
    li   x3,  0xFF600002              # s0 value
    sw   x3,  28(x2)                  # Store s0 at [SP+28]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    cm.pop {ra, s0}, 32              # Pop only ra and s0, SP -> 0x8000F620

    # Check SP
    li   x30, 0x00000F0F              # Error code: Test 15g, Check 1 (SP)
    mv   x11, x2
    li   x12, 0x8000F620
    bne  x11, x12, test_fail

    # Check ra and s0 were loaded correctly
    li   x30, 0x00000F10              # Error code: Test 15g, Check 2 (ra)
    mv   x11, x1
    li   x12, 0xFF600001
    bne  x11, x12, test_fail

    li   x30, 0x00000F11              # Error code: Test 15g, Check 3 (s0)
    mv   x11, x8
    li   x12, 0xFF600002
    bne  x11, x12, test_fail

    # Verify non-target registers were NOT clobbered
    li   x30, 0x00000F12              # Error code: Test 15g, Check 4 (s1 preserved)
    mv   x11, x9
    li   x12, 0xA1A1A1A1
    bne  x11, x12, test_fail

    li   x30, 0x00000F13              # Error code: Test 15g, Check 5 (s2 preserved)
    mv   x11, x18
    li   x12, 0xA2A2A2A2
    bne  x11, x12, test_fail

    li   x30, 0x00000F14              # Error code: Test 15g, Check 6 (s3 preserved)
    mv   x11, x19
    li   x12, 0xA3A3A3A3
    bne  x11, x12, test_fail

    li   x30, 0x00000F15              # Error code: Test 15g, Check 7 (s4 preserved)
    mv   x11, x20
    li   x12, 0xA4A4A4A4
    bne  x11, x12, test_fail

    li   x30, 0x00000F16              # Error code: Test 15g, Check 8 (s5 preserved)
    mv   x11, x21
    li   x12, 0xA5A5A5A5
    bne  x11, x12, test_fail

    li   x30, 0x00000F17              # Error code: Test 15g, Check 9 (s6 preserved)
    mv   x11, x22
    li   x12, 0xA6A6A6A6
    bne  x11, x12, test_fail

    li   x30, 0x00000F18              # Error code: Test 15g, Check 10 (s7 preserved)
    mv   x11, x23
    li   x12, 0xA7A7A7A7
    bne  x11, x12, test_fail

    li   x30, 0x00000F19              # Error code: Test 15g, Check 11 (s8 preserved)
    mv   x11, x24
    li   x12, 0xA8A8A8A8
    bne  x11, x12, test_fail

    li   x30, 0x00000F1A              # Error code: Test 15g, Check 12 (s9 preserved)
    mv   x11, x25
    li   x12, 0xA9A9A9A9
    bne  x11, x12, test_fail

    li   x30, 0x00000F1B              # Error code: Test 15g, Check 13 (s10 preserved)
    mv   x11, x26
    li   x12, 0xAAAAAAAA
    bne  x11, x12, test_fail

    li   x30, 0x00000F1C              # Error code: Test 15g, Check 14 (s11 preserved)
    mv   x11, x27
    li   x12, 0xABABABAB
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15h: Push-pop roundtrip with immediate sequence
    # SP=0x8000F700
    # Push {ra, s0-s1}, -48 -> SP=0x8000F6D0
    # Clear regs
    # Pop {ra, s0-s1}, 48 -> SP=0x8000F700 (restored)
    #-------------------------------------------------
    li   x2,  0x8000F700              # Set SP
    li   x1,  0xFF000001              # ra
    li   x8,  0xFF000002              # s0
    li   x9,  0xFF000003              # s1

    cm.push {ra, s0-s1}, -48         # Push: SP -> 0x8000F6D0

    # Clear registers
    li   x1,  0
    li   x8,  0
    li   x9,  0

    cm.pop {ra, s0-s1}, 48           # Pop: SP -> 0x8000F700

    # Check SP restored
    li   x30, 0x00000F1D              # Error code: Test 15h, Check 1 (SP restored)
    mv   x11, x2
    li   x12, 0x8000F700
    bne  x11, x12, test_fail

    # Check ra restored
    li   x30, 0x00000F1E              # Error code: Test 15h, Check 2 (ra restored)
    mv   x11, x1
    li   x12, 0xFF000001
    bne  x11, x12, test_fail

    # Check s0 restored
    li   x30, 0x00000F1F              # Error code: Test 15h, Check 3 (s0 restored)
    mv   x11, x8
    li   x12, 0xFF000002
    bne  x11, x12, test_fail

    # Check s1 restored
    li   x30, 0x00000F20              # Error code: Test 15h, Check 4 (s1 restored)
    mv   x11, x9
    li   x12, 0xFF000003
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 16: IRQ stress test - 20 iterations of
    # cm.pop {ra, s0-s11}, 64 (13 regs, max kill window)
    # Each iteration: push known values, clear regs,
    # pop them back and verify all 13 registers.
    # Stack at 0x8000FE00 (below trap handler region).
    #-------------------------------------------------

    li  x28, 0                        # Loop counter (t3)

test16_loop:
    li  x30, 0x00100000              # Error code base: Test 16

    # Set all registers to known values based on iteration
    # ra = 0x16000000 | (iter << 4) | 1, s0 = ... | 2, etc.
    slli x29, x28, 4                  # x29 = iter << 4
    lui  x5, 0x16000                  # x5 = 0x16000000 (base)
    or   x5, x5, x29                 # x5 = 0x16000000 | (iter << 4)

    ori  x1,  x5, 0x001              # ra  = base | 1
    ori  x8,  x5, 0x002              # s0  = base | 2
    ori  x9,  x5, 0x003              # s1  = base | 3
    ori  x18, x5, 0x004              # s2  = base | 4
    ori  x19, x5, 0x005              # s3  = base | 5
    ori  x20, x5, 0x006              # s4  = base | 6
    ori  x21, x5, 0x007              # s5  = base | 7
    ori  x22, x5, 0x008              # s6  = base | 8
    ori  x23, x5, 0x009              # s7  = base | 9
    ori  x24, x5, 0x00A              # s8  = base | A
    ori  x25, x5, 0x00B              # s9  = base | B
    ori  x26, x5, 0x00C              # s10 = base | C
    ori  x27, x5, 0x00D              # s11 = base | D

    # Set SP and push all 13 registers to stack
    li   x2,  0x8000FE00
    cm.push {ra, s0-s11}, -64        # SP -> 0x8000FDC0

    # Clear all s-registers and ra to 0
    li   x1,  0
    li   x8,  0
    li   x9,  0
    li   x18, 0
    li   x19, 0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x24, 0
    li   x25, 0
    li   x26, 0
    li   x27, 0

    # Execute longest pop: 13 registers, maximum IRQ kill window
    cm.pop {ra, s0-s11}, 64          # SP -> 0x8000FE00

    # ---- Verify SP ----
    slli x6, x28, 12                 # x6 = iter << 12
    lui  x7, 0x00100
    ori  x7, x7, 0x001
    or   x30, x7, x6                # x30 = error code with iteration

    li   x10, 0x8000FE00             # Expected SP
    bne  x2,  x10, test_fail

    # ---- Rebuild expected base (x5 was clobbered by pop restoring s-regs) ----
    slli x29, x28, 4
    lui  x5, 0x16000
    or   x5, x5, x29                 # x5 = 0x16000000 | (iter << 4)

    # ---- Verify all 13 popped registers ----

    # Check ra
    lui  x7, 0x00100
    ori  x7, x7, 0x002
    or   x30, x7, x6
    mv   x11, x1
    ori  x12, x5, 0x001
    bne  x11, x12, test_fail

    # Check s0
    lui  x7, 0x00100
    ori  x7, x7, 0x003
    or   x30, x7, x6
    mv   x11, x8
    ori  x12, x5, 0x002
    bne  x11, x12, test_fail

    # Check s1
    lui  x7, 0x00100
    ori  x7, x7, 0x004
    or   x30, x7, x6
    mv   x11, x9
    ori  x12, x5, 0x003
    bne  x11, x12, test_fail

    # Check s2
    lui  x7, 0x00100
    ori  x7, x7, 0x005
    or   x30, x7, x6
    mv   x11, x18
    ori  x12, x5, 0x004
    bne  x11, x12, test_fail

    # Check s3
    lui  x7, 0x00100
    ori  x7, x7, 0x006
    or   x30, x7, x6
    mv   x11, x19
    ori  x12, x5, 0x005
    bne  x11, x12, test_fail

    # Check s4
    lui  x7, 0x00100
    ori  x7, x7, 0x007
    or   x30, x7, x6
    mv   x11, x20
    ori  x12, x5, 0x006
    bne  x11, x12, test_fail

    # Check s5
    lui  x7, 0x00100
    ori  x7, x7, 0x008
    or   x30, x7, x6
    mv   x11, x21
    ori  x12, x5, 0x007
    bne  x11, x12, test_fail

    # Check s6
    lui  x7, 0x00100
    ori  x7, x7, 0x009
    or   x30, x7, x6
    mv   x11, x22
    ori  x12, x5, 0x008
    bne  x11, x12, test_fail

    # Check s7
    lui  x7, 0x00100
    ori  x7, x7, 0x00A
    or   x30, x7, x6
    mv   x11, x23
    ori  x12, x5, 0x009
    bne  x11, x12, test_fail

    # Check s8
    lui  x7, 0x00100
    ori  x7, x7, 0x00B
    or   x30, x7, x6
    mv   x11, x24
    ori  x12, x5, 0x00A
    bne  x11, x12, test_fail

    # Check s9
    lui  x7, 0x00100
    ori  x7, x7, 0x00C
    or   x30, x7, x6
    mv   x11, x25
    ori  x12, x5, 0x00B
    bne  x11, x12, test_fail

    # Check s10
    lui  x7, 0x00100
    ori  x7, x7, 0x00D
    or   x30, x7, x6
    mv   x11, x26
    ori  x12, x5, 0x00C
    bne  x11, x12, test_fail

    # Check s11
    lui  x7, 0x00100
    ori  x7, x7, 0x00E
    or   x30, x7, x6
    mv   x11, x27
    ori  x12, x5, 0x00D
    bne  x11, x12, test_fail

    # Increment loop counter and check if done
    addi x28, x28, 1
    li   x29, 20
    bne  x28, x29, test16_loop


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
	#   TT = Test number (01-0F)
	#   CC = Check number within test
	# x31 = 0xBADC0DE0 (failure marker)
	# x11 = Actual value read
	# x12 = Expected value
	#-------------------------------------------------
	li  x31, 0xBADC0DE0              # Failure marker
	j   end_of_test


end_of_test:
	nop
    j end_of_test                     # Infinite loop
