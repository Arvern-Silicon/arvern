#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmp_popret
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.POPRET
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
    # ra@[SP+12] = return address
    #-------------------------------------------------
    li   x2,  0x80001000              # Set SP
    la   x3,  check_test1             # Return address
    sw   x3,  12(x2)                  # Store return address at ra position

    li   x1,  0                       # Clear ra
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra}, 16                # Pop ra and return

    # Fall-through: return didn't happen
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000100
    j    test_fail

check_test1:
    # Check delay-slot canary
    li   x30, 0x00000101
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00000102
    mv   x11, x2
    li   x12, 0x80001010
    bne  x11, x12, test_fail

    # Check ra = check_test1 address
    li   x30, 0x00000103
    la   x12, check_test1
    bne  x1, x12, test_fail


    #-------------------------------------------------
    # Test 2: rlist=5 {ra,s0}, stack_adj=32 (spimm=1)
    # SP=0x80002000, new_SP=0x80002020
    # ra@[SP+24], s0@[SP+28]
    #-------------------------------------------------
    li   x2,  0x80002000              # Set SP
    la   x3,  check_test2             # Return address
    sw   x3,  24(x2)                  # Store return address at ra position
    li   x3,  0x02000002              # s0 value
    sw   x3,  28(x2)                  # Store s0 at [SP+28]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0}, 32            # Pop ra,s0 and return

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000200
    j    test_fail

check_test2:
    # Check delay-slot canary
    li   x30, 0x00000201
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00000202
    mv   x11, x2
    li   x12, 0x80002020
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000203
    la   x12, check_test2
    bne  x1, x12, test_fail

    # Check s0
    li   x30, 0x00000204
    mv   x11, x8
    li   x12, 0x02000002
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 3: rlist=6 {ra,s0-s1}, stack_adj=16 (spimm=0)
    # SP=0x80003000, new_SP=0x80003010
    # ra@[SP+4], s0@[SP+8], s1@[SP+12]
    #-------------------------------------------------
    li   x2,  0x80003000              # Set SP
    la   x3,  check_test3
    sw   x3,  4(x2)                   # Store ra at [SP+4]
    li   x3,  0x03000002              # s0 value
    sw   x3,  8(x2)
    li   x3,  0x03000003              # s1 value
    sw   x3,  12(x2)

    li   x1,  0
    li   x8,  0
    li   x9,  0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s1}, 16

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000300
    j    test_fail

check_test3:
    # Check delay-slot canary
    li   x30, 0x00000301
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000302
    mv   x11, x2
    li   x12, 0x80003010
    bne  x11, x12, test_fail

    li   x30, 0x00000303
    la   x12, check_test3
    bne  x1, x12, test_fail

    li   x30, 0x00000304
    mv   x11, x8
    li   x12, 0x03000002
    bne  x11, x12, test_fail

    li   x30, 0x00000305
    mv   x11, x9
    li   x12, 0x03000003
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 4: rlist=7 {ra,s0-s2}, stack_adj=48 (spimm=2)
    # SP=0x80004000, new_SP=0x80004030
    # ra@[SP+32], s0@[SP+36], s1@[SP+40], s2@[SP+44]
    #-------------------------------------------------
    li   x2,  0x80004000              # Set SP
    la   x3,  check_test4
    sw   x3,  32(x2)
    li   x3,  0x04000002
    sw   x3,  36(x2)
    li   x3,  0x04000003
    sw   x3,  40(x2)
    li   x3,  0x04000004
    sw   x3,  44(x2)

    li   x1,  0
    li   x8,  0
    li   x9,  0
    li   x18, 0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s2}, 48

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000400
    j    test_fail

check_test4:
    # Check delay-slot canary
    li   x30, 0x00000401
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000402
    mv   x11, x2
    li   x12, 0x80004030
    bne  x11, x12, test_fail

    li   x30, 0x00000403
    la   x12, check_test4
    bne  x1, x12, test_fail

    li   x30, 0x00000404
    mv   x11, x8
    li   x12, 0x04000002
    bne  x11, x12, test_fail

    li   x30, 0x00000405
    mv   x11, x9
    li   x12, 0x04000003
    bne  x11, x12, test_fail

    li   x30, 0x00000406
    mv   x11, x18
    li   x12, 0x04000004
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 5: rlist=8 {ra,s0-s3}, stack_adj=48 (spimm=1)
    # SP=0x80005000, new_SP=0x80005030
    # ra@[SP+28], s0@[SP+32], s1@[SP+36], s2@[SP+40], s3@[SP+44]
    #-------------------------------------------------
    li   x2,  0x80005000
    la   x3,  check_test5
    sw   x3,  28(x2)
    li   x3,  0x05000002
    sw   x3,  32(x2)
    li   x3,  0x05000003
    sw   x3,  36(x2)
    li   x3,  0x05000004
    sw   x3,  40(x2)
    li   x3,  0x05000005
    sw   x3,  44(x2)

    li   x1,  0
    li   x8,  0
    li   x9,  0
    li   x18, 0
    li   x19, 0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s3}, 48

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000500
    j    test_fail

check_test5:
    # Check delay-slot canary
    li   x30, 0x00000501
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000502
    mv   x11, x2
    li   x12, 0x80005030
    bne  x11, x12, test_fail

    li   x30, 0x00000503
    la   x12, check_test5
    bne  x1, x12, test_fail

    li   x30, 0x00000504
    mv   x11, x8
    li   x12, 0x05000002
    bne  x11, x12, test_fail

    li   x30, 0x00000505
    mv   x11, x9
    li   x12, 0x05000003
    bne  x11, x12, test_fail

    li   x30, 0x00000506
    mv   x11, x18
    li   x12, 0x05000004
    bne  x11, x12, test_fail

    li   x30, 0x00000507
    mv   x11, x19
    li   x12, 0x05000005
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 6: rlist=9 {ra,s0-s4}, stack_adj=48 (spimm=1)
    # SP=0x80006000, new_SP=0x80006030
    # ra@[SP+24], s0@[SP+28], s1@[SP+32], s2@[SP+36], s3@[SP+40], s4@[SP+44]
    #-------------------------------------------------
    li   x2,  0x80006000
    la   x3,  check_test6
    sw   x3,  24(x2)
    li   x3,  0x06000002
    sw   x3,  28(x2)
    li   x3,  0x06000003
    sw   x3,  32(x2)
    li   x3,  0x06000004
    sw   x3,  36(x2)
    li   x3,  0x06000005
    sw   x3,  40(x2)
    li   x3,  0x06000006
    sw   x3,  44(x2)

    li   x1,  0
    li   x8,  0
    li   x9,  0
    li   x18, 0
    li   x19, 0
    li   x20, 0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s4}, 48

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000600
    j    test_fail

check_test6:
    # Check delay-slot canary
    li   x30, 0x00000601
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000602
    mv   x11, x2
    li   x12, 0x80006030
    bne  x11, x12, test_fail

    li   x30, 0x00000603
    la   x12, check_test6
    bne  x1, x12, test_fail

    li   x30, 0x00000604
    mv   x11, x8
    li   x12, 0x06000002
    bne  x11, x12, test_fail

    li   x30, 0x00000605
    mv   x11, x9
    li   x12, 0x06000003
    bne  x11, x12, test_fail

    li   x30, 0x00000606
    mv   x11, x18
    li   x12, 0x06000004
    bne  x11, x12, test_fail

    li   x30, 0x00000607
    mv   x11, x19
    li   x12, 0x06000005
    bne  x11, x12, test_fail

    li   x30, 0x00000608
    mv   x11, x20
    li   x12, 0x06000006
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 7: rlist=10 {ra,s0-s5}, stack_adj=80 (spimm=3)
    # SP=0x80007000, new_SP=0x80007050
    # ra@[SP+52], s0@[SP+56], s1@[SP+60], s2@[SP+64], s3@[SP+68], s4@[SP+72], s5@[SP+76]
    #-------------------------------------------------
    li   x2,  0x80007000
    la   x3,  check_test7
    sw   x3,  52(x2)
    li   x3,  0x07000002
    sw   x3,  56(x2)
    li   x3,  0x07000003
    sw   x3,  60(x2)
    li   x3,  0x07000004
    sw   x3,  64(x2)
    li   x3,  0x07000005
    sw   x3,  68(x2)
    li   x3,  0x07000006
    sw   x3,  72(x2)
    li   x3,  0x07000007
    sw   x3,  76(x2)

    li   x1,  0
    li   x8,  0
    li   x9,  0
    li   x18, 0
    li   x19, 0
    li   x20, 0
    li   x21, 0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s5}, 80

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000700
    j    test_fail

check_test7:
    # Check delay-slot canary
    li   x30, 0x00000701
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000702
    mv   x11, x2
    li   x12, 0x80007050
    bne  x11, x12, test_fail

    li   x30, 0x00000703
    la   x12, check_test7
    bne  x1, x12, test_fail

    li   x30, 0x00000704
    mv   x11, x8
    li   x12, 0x07000002
    bne  x11, x12, test_fail

    li   x30, 0x00000705
    mv   x11, x9
    li   x12, 0x07000003
    bne  x11, x12, test_fail

    li   x30, 0x00000706
    mv   x11, x18
    li   x12, 0x07000004
    bne  x11, x12, test_fail

    li   x30, 0x00000707
    mv   x11, x19
    li   x12, 0x07000005
    bne  x11, x12, test_fail

    li   x30, 0x00000708
    mv   x11, x20
    li   x12, 0x07000006
    bne  x11, x12, test_fail

    li   x30, 0x00000709
    mv   x11, x21
    li   x12, 0x07000007
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 8: rlist=11 {ra,s0-s6}, stack_adj=32 (spimm=0)
    # SP=0x80008000, new_SP=0x80008020
    # ra@[SP+0], s0@[SP+4], s1@[SP+8], s2@[SP+12], s3@[SP+16], s4@[SP+20], s5@[SP+24], s6@[SP+28]
    #-------------------------------------------------
    li   x2,  0x80008000
    la   x3,  check_test8
    sw   x3,  0(x2)
    li   x3,  0x08000002
    sw   x3,  4(x2)
    li   x3,  0x08000003
    sw   x3,  8(x2)
    li   x3,  0x08000004
    sw   x3,  12(x2)
    li   x3,  0x08000005
    sw   x3,  16(x2)
    li   x3,  0x08000006
    sw   x3,  20(x2)
    li   x3,  0x08000007
    sw   x3,  24(x2)
    li   x3,  0x08000008
    sw   x3,  28(x2)

    li   x1,  0
    li   x8,  0
    li   x9,  0
    li   x18, 0
    li   x19, 0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s6}, 32

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000800
    j    test_fail

check_test8:
    # Check delay-slot canary
    li   x30, 0x00000801
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000802
    mv   x11, x2
    li   x12, 0x80008020
    bne  x11, x12, test_fail

    li   x30, 0x00000803
    la   x12, check_test8
    bne  x1, x12, test_fail

    li   x30, 0x00000804
    mv   x11, x8
    li   x12, 0x08000002
    bne  x11, x12, test_fail

    li   x30, 0x00000805
    mv   x11, x9
    li   x12, 0x08000003
    bne  x11, x12, test_fail

    li   x30, 0x00000806
    mv   x11, x18
    li   x12, 0x08000004
    bne  x11, x12, test_fail

    li   x30, 0x00000807
    mv   x11, x19
    li   x12, 0x08000005
    bne  x11, x12, test_fail

    li   x30, 0x00000808
    mv   x11, x20
    li   x12, 0x08000006
    bne  x11, x12, test_fail

    li   x30, 0x00000809
    mv   x11, x21
    li   x12, 0x08000007
    bne  x11, x12, test_fail

    li   x30, 0x0000080A
    mv   x11, x22
    li   x12, 0x08000008
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 9: rlist=12 {ra,s0-s7}, stack_adj=80 (spimm=2)
    # SP=0x80009000, new_SP=0x80009050
    # ra@[SP+44], s0@[SP+48], s1@[SP+52], s2@[SP+56], s3@[SP+60],
    # s4@[SP+64], s5@[SP+68], s6@[SP+72], s7@[SP+76]
    #-------------------------------------------------
    li   x2,  0x80009000
    la   x3,  check_test9
    sw   x3,  44(x2)
    li   x3,  0x09000002
    sw   x3,  48(x2)
    li   x3,  0x09000003
    sw   x3,  52(x2)
    li   x3,  0x09000004
    sw   x3,  56(x2)
    li   x3,  0x09000005
    sw   x3,  60(x2)
    li   x3,  0x09000006
    sw   x3,  64(x2)
    li   x3,  0x09000007
    sw   x3,  68(x2)
    li   x3,  0x09000008
    sw   x3,  72(x2)
    li   x3,  0x09000009
    sw   x3,  76(x2)

    li   x1,  0
    li   x8,  0
    li   x9,  0
    li   x18, 0
    li   x19, 0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s7}, 80

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000900
    j    test_fail

check_test9:
    # Check delay-slot canary
    li   x30, 0x00000901
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000902
    mv   x11, x2
    li   x12, 0x80009050
    bne  x11, x12, test_fail

    li   x30, 0x00000903
    la   x12, check_test9
    bne  x1, x12, test_fail

    li   x30, 0x00000904
    mv   x11, x8
    li   x12, 0x09000002
    bne  x11, x12, test_fail

    li   x30, 0x00000905
    mv   x11, x9
    li   x12, 0x09000003
    bne  x11, x12, test_fail

    li   x30, 0x00000906
    mv   x11, x18
    li   x12, 0x09000004
    bne  x11, x12, test_fail

    li   x30, 0x00000907
    mv   x11, x19
    li   x12, 0x09000005
    bne  x11, x12, test_fail

    li   x30, 0x00000908
    mv   x11, x20
    li   x12, 0x09000006
    bne  x11, x12, test_fail

    li   x30, 0x00000909
    mv   x11, x21
    li   x12, 0x09000007
    bne  x11, x12, test_fail

    li   x30, 0x0000090A
    mv   x11, x22
    li   x12, 0x09000008
    bne  x11, x12, test_fail

    li   x30, 0x0000090B
    mv   x11, x23
    li   x12, 0x09000009
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 10: rlist=13 {ra,s0-s8}, stack_adj=64 (spimm=1)
    # SP=0x8000A000, new_SP=0x8000A040
    # ra@[SP+24], s0@[SP+28], s1@[SP+32], s2@[SP+36], s3@[SP+40],
    # s4@[SP+44], s5@[SP+48], s6@[SP+52], s7@[SP+56], s8@[SP+60]
    #-------------------------------------------------
    li   x2,  0x8000A000
    la   x3,  check_test10
    sw   x3,  24(x2)
    li   x3,  0x0A000002
    sw   x3,  28(x2)
    li   x3,  0x0A000003
    sw   x3,  32(x2)
    li   x3,  0x0A000004
    sw   x3,  36(x2)
    li   x3,  0x0A000005
    sw   x3,  40(x2)
    li   x3,  0x0A000006
    sw   x3,  44(x2)
    li   x3,  0x0A000007
    sw   x3,  48(x2)
    li   x3,  0x0A000008
    sw   x3,  52(x2)
    li   x3,  0x0A000009
    sw   x3,  56(x2)
    li   x3,  0x0A00000A
    sw   x3,  60(x2)

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
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s8}, 64

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000A00
    j    test_fail

check_test10:
    # Check delay-slot canary
    li   x30, 0x00000A01
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000A02
    mv   x11, x2
    li   x12, 0x8000A040
    bne  x11, x12, test_fail

    li   x30, 0x00000A03
    la   x12, check_test10
    bne  x1, x12, test_fail

    li   x30, 0x00000A04
    mv   x11, x8
    li   x12, 0x0A000002
    bne  x11, x12, test_fail

    li   x30, 0x00000A05
    mv   x11, x9
    li   x12, 0x0A000003
    bne  x11, x12, test_fail

    li   x30, 0x00000A06
    mv   x11, x18
    li   x12, 0x0A000004
    bne  x11, x12, test_fail

    li   x30, 0x00000A07
    mv   x11, x19
    li   x12, 0x0A000005
    bne  x11, x12, test_fail

    li   x30, 0x00000A08
    mv   x11, x20
    li   x12, 0x0A000006
    bne  x11, x12, test_fail

    li   x30, 0x00000A09
    mv   x11, x21
    li   x12, 0x0A000007
    bne  x11, x12, test_fail

    li   x30, 0x00000A0A
    mv   x11, x22
    li   x12, 0x0A000008
    bne  x11, x12, test_fail

    li   x30, 0x00000A0B
    mv   x11, x23
    li   x12, 0x0A000009
    bne  x11, x12, test_fail

    li   x30, 0x00000A0C
    mv   x11, x24
    li   x12, 0x0A00000A
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 11: rlist=14 {ra,s0-s9}, stack_adj=96 (spimm=3)
    # SP=0x8000B000, new_SP=0x8000B060
    # ra@[SP+52], s0@[SP+56], s1@[SP+60], s2@[SP+64], s3@[SP+68],
    # s4@[SP+72], s5@[SP+76], s6@[SP+80], s7@[SP+84], s8@[SP+88], s9@[SP+92]
    #-------------------------------------------------
    li   x2,  0x8000B000
    la   x3,  check_test11
    sw   x3,  52(x2)
    li   x3,  0x0B000002
    sw   x3,  56(x2)
    li   x3,  0x0B000003
    sw   x3,  60(x2)
    li   x3,  0x0B000004
    sw   x3,  64(x2)
    li   x3,  0x0B000005
    sw   x3,  68(x2)
    li   x3,  0x0B000006
    sw   x3,  72(x2)
    li   x3,  0x0B000007
    sw   x3,  76(x2)
    li   x3,  0x0B000008
    sw   x3,  80(x2)
    li   x3,  0x0B000009
    sw   x3,  84(x2)
    li   x3,  0x0B00000A
    sw   x3,  88(x2)
    li   x3,  0x0B00000B
    sw   x3,  92(x2)

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
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s9}, 96

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000B00
    j    test_fail

check_test11:
    # Check delay-slot canary
    li   x30, 0x00000B01
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000B02
    mv   x11, x2
    li   x12, 0x8000B060
    bne  x11, x12, test_fail

    li   x30, 0x00000B03
    la   x12, check_test11
    bne  x1, x12, test_fail

    li   x30, 0x00000B04
    mv   x11, x8
    li   x12, 0x0B000002
    bne  x11, x12, test_fail

    li   x30, 0x00000B05
    mv   x11, x9
    li   x12, 0x0B000003
    bne  x11, x12, test_fail

    li   x30, 0x00000B06
    mv   x11, x18
    li   x12, 0x0B000004
    bne  x11, x12, test_fail

    li   x30, 0x00000B07
    mv   x11, x19
    li   x12, 0x0B000005
    bne  x11, x12, test_fail

    li   x30, 0x00000B08
    mv   x11, x20
    li   x12, 0x0B000006
    bne  x11, x12, test_fail

    li   x30, 0x00000B09
    mv   x11, x21
    li   x12, 0x0B000007
    bne  x11, x12, test_fail

    li   x30, 0x00000B0A
    mv   x11, x22
    li   x12, 0x0B000008
    bne  x11, x12, test_fail

    li   x30, 0x00000B0B
    mv   x11, x23
    li   x12, 0x0B000009
    bne  x11, x12, test_fail

    li   x30, 0x00000B0C
    mv   x11, x24
    li   x12, 0x0B00000A
    bne  x11, x12, test_fail

    li   x30, 0x00000B0D
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
    li   x2,  0x8000C000
    la   x3,  check_test12
    sw   x3,  12(x2)
    li   x3,  0x0C000002
    sw   x3,  16(x2)
    li   x3,  0x0C000003
    sw   x3,  20(x2)
    li   x3,  0x0C000004
    sw   x3,  24(x2)
    li   x3,  0x0C000005
    sw   x3,  28(x2)
    li   x3,  0x0C000006
    sw   x3,  32(x2)
    li   x3,  0x0C000007
    sw   x3,  36(x2)
    li   x3,  0x0C000008
    sw   x3,  40(x2)
    li   x3,  0x0C000009
    sw   x3,  44(x2)
    li   x3,  0x0C00000A
    sw   x3,  48(x2)
    li   x3,  0x0C00000B
    sw   x3,  52(x2)
    li   x3,  0x0C00000C
    sw   x3,  56(x2)
    li   x3,  0x0C00000D
    sw   x3,  60(x2)

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
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s11}, 64

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000C00
    j    test_fail

check_test12:
    # Check delay-slot canary
    li   x30, 0x00000C01
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000C02
    mv   x11, x2
    li   x12, 0x8000C040
    bne  x11, x12, test_fail

    li   x30, 0x00000C03
    la   x12, check_test12
    bne  x1, x12, test_fail

    li   x30, 0x00000C04
    mv   x11, x8
    li   x12, 0x0C000002
    bne  x11, x12, test_fail

    li   x30, 0x00000C05
    mv   x11, x9
    li   x12, 0x0C000003
    bne  x11, x12, test_fail

    li   x30, 0x00000C06
    mv   x11, x18
    li   x12, 0x0C000004
    bne  x11, x12, test_fail

    li   x30, 0x00000C07
    mv   x11, x19
    li   x12, 0x0C000005
    bne  x11, x12, test_fail

    li   x30, 0x00000C08
    mv   x11, x20
    li   x12, 0x0C000006
    bne  x11, x12, test_fail

    li   x30, 0x00000C09
    mv   x11, x21
    li   x12, 0x0C000007
    bne  x11, x12, test_fail

    li   x30, 0x00000C0A
    mv   x11, x22
    li   x12, 0x0C000008
    bne  x11, x12, test_fail

    li   x30, 0x00000C0B
    mv   x11, x23
    li   x12, 0x0C000009
    bne  x11, x12, test_fail

    li   x30, 0x00000C0C
    mv   x11, x24
    li   x12, 0x0C00000A
    bne  x11, x12, test_fail

    li   x30, 0x00000C0D
    mv   x11, x25
    li   x12, 0x0C00000B
    bne  x11, x12, test_fail

    li   x30, 0x00000C0E
    mv   x11, x26
    li   x12, 0x0C00000C
    bne  x11, x12, test_fail

    li   x30, 0x00000C0F
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
    li   x2,  0x8000D000
    la   x3,  check_test13
    sw   x3,  44(x2)
    li   x3,  0x0D000002
    sw   x3,  48(x2)
    li   x3,  0x0D000003
    sw   x3,  52(x2)
    li   x3,  0x0D000004
    sw   x3,  56(x2)
    li   x3,  0x0D000005
    sw   x3,  60(x2)
    li   x3,  0x0D000006
    sw   x3,  64(x2)
    li   x3,  0x0D000007
    sw   x3,  68(x2)
    li   x3,  0x0D000008
    sw   x3,  72(x2)
    li   x3,  0x0D000009
    sw   x3,  76(x2)
    li   x3,  0x0D00000A
    sw   x3,  80(x2)
    li   x3,  0x0D00000B
    sw   x3,  84(x2)
    li   x3,  0x0D00000C
    sw   x3,  88(x2)
    li   x3,  0x0D00000D
    sw   x3,  92(x2)

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
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s11}, 96

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000D00
    j    test_fail

check_test13:
    # Check delay-slot canary
    li   x30, 0x00000D01
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    li   x30, 0x00000D02
    mv   x11, x2
    li   x12, 0x8000D060
    bne  x11, x12, test_fail

    li   x30, 0x00000D03
    la   x12, check_test13
    bne  x1, x12, test_fail

    li   x30, 0x00000D04
    mv   x11, x8
    li   x12, 0x0D000002
    bne  x11, x12, test_fail

    li   x30, 0x00000D05
    mv   x11, x9
    li   x12, 0x0D000003
    bne  x11, x12, test_fail

    li   x30, 0x00000D06
    mv   x11, x18
    li   x12, 0x0D000004
    bne  x11, x12, test_fail

    li   x30, 0x00000D07
    mv   x11, x19
    li   x12, 0x0D000005
    bne  x11, x12, test_fail

    li   x30, 0x00000D08
    mv   x11, x20
    li   x12, 0x0D000006
    bne  x11, x12, test_fail

    li   x30, 0x00000D09
    mv   x11, x21
    li   x12, 0x0D000007
    bne  x11, x12, test_fail

    li   x30, 0x00000D0A
    mv   x11, x22
    li   x12, 0x0D000008
    bne  x11, x12, test_fail

    li   x30, 0x00000D0B
    mv   x11, x23
    li   x12, 0x0D000009
    bne  x11, x12, test_fail

    li   x30, 0x00000D0C
    mv   x11, x24
    li   x12, 0x0D00000A
    bne  x11, x12, test_fail

    li   x30, 0x00000D0D
    mv   x11, x25
    li   x12, 0x0D00000B
    bne  x11, x12, test_fail

    li   x30, 0x00000D0E
    mv   x11, x26
    li   x12, 0x0D00000C
    bne  x11, x12, test_fail

    li   x30, 0x00000D0F
    mv   x11, x27
    li   x12, 0x0D00000D
    bne  x11, x12, test_fail


    #=========================================================
    # Test 14: Special tests
    #=========================================================

    #-------------------------------------------------
    # Test 14a: Push-popret roundtrip
    # SP=0x8000E000
    # Set ra=check_test14a, s0=test_val, s1=test_val
    # cm.push {ra, s0-s1}, -48 -> SP=0x8000DFD0
    # Clear regs
    # cm.popret {ra, s0-s1}, 48 -> SP=0x8000E000, return to check_test14a
    #-------------------------------------------------
    li   x2,  0x8000E000              # Set SP
    la   x1,  check_test14a           # Return address = check label
    li   x8,  0x0E100002              # s0 test value
    li   x9,  0x0E100003              # s1 test value

    cm.push {ra, s0-s1}, -48          # Push: SP -> 0x8000DFD0

    # Clear registers
    li   x1,  0
    li   x8,  0
    li   x9,  0

    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s1}, 48         # Pop and return to check_test14a

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000E00
    j    test_fail

check_test14a:
    # Check delay-slot canary
    li   x30, 0x00000E01
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP restored
    li   x30, 0x00000E02
    mv   x11, x2
    li   x12, 0x8000E000
    bne  x11, x12, test_fail

    # Check ra = check_test14a
    li   x30, 0x00000E03
    la   x12, check_test14a
    bne  x1, x12, test_fail

    # Check s0 restored
    li   x30, 0x00000E04
    mv   x11, x8
    li   x12, 0x0E100002
    bne  x11, x12, test_fail

    # Check s1 restored
    li   x30, 0x00000E05
    mv   x11, x9
    li   x12, 0x0E100003
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 14b: cm.pop followed by cm.popret
    # SP=0x8000E100
    # 1st: cm.pop {ra,s0}, 32 -> SP=0x8000E120
    # 2nd: cm.popret {ra}, 16 -> SP=0x8000E130, return
    #
    # Pre-store at original SP:
    # - ra for cm.pop at [SP+24]=0x8000E118 (arbitrary value)
    # - s0 for cm.pop at [SP+28]=0x8000E11C
    # - ra for cm.popret at [0x8000E120+12]=[SP+44] (return address)
    #-------------------------------------------------
    li   x3,  0x8000E100              # Use x3 to set up memory
    li   x4,  0x0E200001              # ra for 1st pop (arbitrary)
    sw   x4,  24(x3)
    li   x4,  0x0E200002              # s0 for 1st pop
    sw   x4,  28(x3)
    la   x4,  check_test14b           # ra for popret = check label
    sw   x4,  44(x3)                  # At [0x8000E120+12] = offset 44

    li   x1,  0
    li   x8,  0
    li   x2,  0x8000E100              # Set SP

    cm.pop {ra, s0}, 32              # Pop ra,s0, SP: 0x8000E100 -> 0x8000E120

    # Save ra from pop (it's an arbitrary value, not a valid address)
    mv   x4,  x1                      # Save 1st pop ra in x4

    # Clear ra for popret
    li   x1,  0

    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra}, 16               # Pop ra and return, SP: 0x8000E120 -> 0x8000E130

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000E10
    j    test_fail

check_test14b:
    # Check delay-slot canary
    li   x30, 0x00000E11
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check final SP
    li   x30, 0x00000E12
    mv   x11, x2
    li   x12, 0x8000E130
    bne  x11, x12, test_fail

    # Check ra from 1st pop (saved in x4)
    li   x30, 0x00000E13
    mv   x11, x4
    li   x12, 0x0E200001
    bne  x11, x12, test_fail

    # Check s0 from 1st pop
    li   x30, 0x00000E14
    mv   x11, x8
    li   x12, 0x0E200002
    bne  x11, x12, test_fail

    # Check ra = check_test14b
    li   x30, 0x00000E15
    la   x12, check_test14b
    bne  x1, x12, test_fail


    #=========================================================
    # Test 15: Pipeline hazard tests
    #=========================================================

    #-------------------------------------------------
    # Test 15a: RAW on SP input - li x2, addr; cm.popret
    # SP=0x8000F000, {ra}, 16
    #-------------------------------------------------
    li   x3,  0x8000F000              # Use x3 to set up memory
    la   x4,  check_test15a
    sw   x4,  12(x3)                  # Store return address at [0x8000F000+12]

    li   x1,  0                       # Clear ra
    li   x5,  0xCAFECAFE              # Delay-slot canary
    li   x2,  0x8000F000              # Set SP immediately before popret
    cm.popret {ra}, 16                # Must use SP=0x8000F000

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000F00
    j    test_fail

check_test15a:
    # Check delay-slot canary
    li   x30, 0x00000F01
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00000F02
    mv   x11, x2
    li   x12, 0x8000F010
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000F03
    la   x12, check_test15a
    bne  x1, x12, test_fail

    #-------------------------------------------------
    # Test 15b: Load-use on SP - lw x2, 0(x3); cm.popret
    # SP=0x8000F100, {ra}, 16
    #-------------------------------------------------
    li   x3,  0x8000F100
    sw   x3,  0(x3)                   # Store 0x8000F100 at address 0x8000F100
    la   x4,  check_test15b
    sw   x4,  12(x3)                  # Store return address at [0x8000F100+12]

    li   x1,  0                       # Clear ra
    li   x5,  0xCAFECAFE              # Delay-slot canary
    lw   x2,  0(x3)                   # Load SP from memory (SP=0x8000F100)
    cm.popret {ra}, 16                # Pop ra and return

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000F10
    j    test_fail

check_test15b:
    # Check delay-slot canary
    li   x30, 0x00000F11
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00000F12
    mv   x11, x2
    li   x12, 0x8000F110
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000F13
    la   x12, check_test15b
    bne  x1, x12, test_fail

    #-------------------------------------------------
    # Test 15c: Store then cm.popret to overlapping address
    # (cm.popret must read the value just written by sw)
    # SP=0x8000F200
    #-------------------------------------------------
    li   x3,  0x8000F200
    li   x4,  0xBAAAAAAD              # Decoy value
    sw   x4,  12(x3)                  # Pre-write decoy to ra position

    la   x4,  check_test15c           # Real return address
    li   x2,  0x8000F200              # Set SP
    sw   x4,  12(x2)                  # Store real ra RIGHT BEFORE cm.popret
    li   x1,  0                       # Clear ra
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra}, 16                # Must load the just-stored value

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000F20
    j    test_fail

check_test15c:
    # Check delay-slot canary
    li   x30, 0x00000F21
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00000F22
    mv   x11, x2
    li   x12, 0x8000F210
    bne  x11, x12, test_fail

    # Check ra = check_test15c (not the decoy)
    li   x30, 0x00000F23
    la   x12, check_test15c
    bne  x1, x12, test_fail

    #-------------------------------------------------
    # Test 15d: Non-target register preservation
    # cm.popret {ra, s0} must NOT clobber s1-s11
    # SP=0x8000F300
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

    li   x2,  0x8000F300              # Set SP
    la   x3,  check_test15d
    sw   x3,  24(x2)                  # Store ra at [SP+24]
    li   x3,  0xFF300002              # s0 value
    sw   x3,  28(x2)                  # Store s0 at [SP+28]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0}, 32            # Pop ra,s0 and return

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000F30
    j    test_fail

check_test15d:
    # Check delay-slot canary
    li   x30, 0x00000F31
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00000F32
    mv   x11, x2
    li   x12, 0x8000F320
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000F33
    la   x12, check_test15d
    bne  x1, x12, test_fail

    # Check s0
    li   x30, 0x00000F34
    mv   x11, x8
    li   x12, 0xFF300002
    bne  x11, x12, test_fail

    # Verify non-target registers were NOT clobbered
    li   x30, 0x00000F35
    mv   x11, x9
    li   x12, 0xA1A1A1A1
    bne  x11, x12, test_fail

    li   x30, 0x00000F36
    mv   x11, x18
    li   x12, 0xA2A2A2A2
    bne  x11, x12, test_fail

    li   x30, 0x00000F37
    mv   x11, x19
    li   x12, 0xA3A3A3A3
    bne  x11, x12, test_fail

    li   x30, 0x00000F38
    mv   x11, x20
    li   x12, 0xA4A4A4A4
    bne  x11, x12, test_fail

    li   x30, 0x00000F39
    mv   x11, x21
    li   x12, 0xA5A5A5A5
    bne  x11, x12, test_fail

    li   x30, 0x00000F3A
    mv   x11, x22
    li   x12, 0xA6A6A6A6
    bne  x11, x12, test_fail

    li   x30, 0x00000F3B
    mv   x11, x23
    li   x12, 0xA7A7A7A7
    bne  x11, x12, test_fail

    li   x30, 0x00000F3C
    mv   x11, x24
    li   x12, 0xA8A8A8A8
    bne  x11, x12, test_fail

    li   x30, 0x00000F3D
    mv   x11, x25
    li   x12, 0xA9A9A9A9
    bne  x11, x12, test_fail

    li   x30, 0x00000F3E
    mv   x11, x26
    li   x12, 0xAAAAAAAA
    bne  x11, x12, test_fail

    li   x30, 0x00000F3F
    mv   x11, x27
    li   x12, 0xABABABAB
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15e: Push-popret roundtrip with full rlist
    # SP=0x8000F400
    # Push {ra, s0-s1}, -48 -> SP=0x8000F3D0
    # Clear regs
    # Popret {ra, s0-s1}, 48 -> SP=0x8000F400 (restored), return
    #-------------------------------------------------
    li   x2,  0x8000F400              # Set SP
    la   x1,  check_test15e           # Return address = check label
    li   x8,  0xFF000002              # s0 test value
    li   x9,  0xFF000003              # s1 test value

    cm.push {ra, s0-s1}, -48          # Push: SP -> 0x8000F3D0

    # Clear registers
    li   x1,  0
    li   x8,  0
    li   x9,  0

    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s1}, 48         # Pop and return to check_test15e

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00000F40
    j    test_fail

check_test15e:
    # Check delay-slot canary
    li   x30, 0x00000F41
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP restored
    li   x30, 0x00000F42
    mv   x11, x2
    li   x12, 0x8000F400
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00000F43
    la   x12, check_test15e
    bne  x1, x12, test_fail

    # Check s0 restored
    li   x30, 0x00000F44
    mv   x11, x8
    li   x12, 0xFF000002
    bne  x11, x12, test_fail

    # Check s1 restored
    li   x30, 0x00000F45
    mv   x11, x9
    li   x12, 0xFF000003
    bne  x11, x12, test_fail


    #=========================================================
    # Test 16: Non-aligned return address with 32-bit instruction
    # cm.popret returns to addr where addr%4==2, and the
    # instruction at that address is 32-bit (spans word boundary)
    #=========================================================

    #-------------------------------------------------
    # Test 16a: Simple non-aligned return, rlist=4 {ra}, stack_adj=16
    # SP=0x8000F500
    # Return address is 2-byte aligned but NOT 4-byte aligned
    # First instruction at return address is 32-bit
    #-------------------------------------------------
    li   x2,  0x8000F500              # Set SP
    la   x3,  check_test16a           # Return address (non-aligned)
    sw   x3,  12(x2)                  # Store return address at ra position

    li   x1,  0                       # Clear ra
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra}, 16                # Pop ra and return

    # Fall-through: return didn't happen
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00001000
    j    test_fail

    .balign 4
    c.nop                             # Pad to make label at addr%4==2
check_test16a:
    .option push
    .option norvc                     # Force 32-bit instructions at return point
    # Check delay-slot canary
    li   x30, 0x00001001
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP (first instruction is 32-bit, spanning word boundary)
    li   x30, 0x00001002
    mv   x11, x2
    li   x12, 0x8000F510
    bne  x11, x12, test_fail

    # Check ra = check_test16a
    li   x30, 0x00001003
    la   x12, check_test16a
    bne  x1, x12, test_fail
    .option pop


    #-------------------------------------------------
    # Test 16b: Non-aligned return, rlist=5 {ra,s0}, stack_adj=32
    # SP=0x8000F600
    # Return address is 2-byte aligned but NOT 4-byte aligned
    #-------------------------------------------------
    li   x2,  0x8000F600              # Set SP
    la   x3,  check_test16b           # Return address (non-aligned)
    sw   x3,  24(x2)                  # Store ra at [SP+24]
    li   x3,  0x16B00002              # s0 value
    sw   x3,  28(x2)                  # Store s0 at [SP+28]

    li   x1,  0                       # Clear ra
    li   x8,  0                       # Clear s0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0}, 32            # Pop ra,s0 and return

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00001010
    j    test_fail

    .balign 4
    c.nop                             # Pad to make label at addr%4==2
check_test16b:
    .option push
    .option norvc                     # Force 32-bit instructions at return point
    # Check delay-slot canary
    li   x30, 0x00001011
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00001012
    mv   x11, x2
    li   x12, 0x8000F620
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00001013
    la   x12, check_test16b
    bne  x1, x12, test_fail

    # Check s0
    li   x30, 0x00001014
    mv   x11, x8
    li   x12, 0x16B00002
    bne  x11, x12, test_fail
    .option pop


    #-------------------------------------------------
    # Test 16c: Non-aligned return, rlist=6 {ra,s0-s1}, stack_adj=16
    # SP=0x8000F700
    # Return address is 2-byte aligned but NOT 4-byte aligned
    #-------------------------------------------------
    li   x2,  0x8000F700              # Set SP
    la   x3,  check_test16c           # Return address (non-aligned)
    sw   x3,  4(x2)                   # Store ra at [SP+4]
    li   x3,  0x16C00002              # s0 value
    sw   x3,  8(x2)
    li   x3,  0x16C00003              # s1 value
    sw   x3,  12(x2)

    li   x1,  0
    li   x8,  0
    li   x9,  0
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0-s1}, 16

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00001020
    j    test_fail

    .balign 4
    c.nop                             # Pad to make label at addr%4==2
check_test16c:
    .option push
    .option norvc                     # Force 32-bit instructions at return point
    # Check delay-slot canary
    li   x30, 0x00001021
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00001022
    mv   x11, x2
    li   x12, 0x8000F710
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00001023
    la   x12, check_test16c
    bne  x1, x12, test_fail

    # Check s0
    li   x30, 0x00001024
    mv   x11, x8
    li   x12, 0x16C00002
    bne  x11, x12, test_fail

    # Check s1
    li   x30, 0x00001025
    mv   x11, x9
    li   x12, 0x16C00003
    bne  x11, x12, test_fail
    .option pop


    #-------------------------------------------------
    # Test 16d: Push-popret roundtrip with non-aligned return
    # SP=0x8000F800
    # Set ra to non-aligned check label, push, clear, popret
    #-------------------------------------------------
    li   x2,  0x8000F800              # Set SP
    la   x1,  check_test16d           # Return address (non-aligned)
    li   x8,  0x16D00002              # s0 test value

    cm.push {ra, s0}, -32             # Push: SP -> 0x8000F7E0

    # Clear registers
    li   x1,  0
    li   x8,  0

    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.popret {ra, s0}, 32            # Pop and return to non-aligned address

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00001030
    j    test_fail

    .balign 4
    c.nop                             # Pad to make label at addr%4==2
check_test16d:
    .option push
    .option norvc                     # Force 32-bit instructions at return point
    # Check delay-slot canary
    li   x30, 0x00001031
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP restored
    li   x30, 0x00001032
    mv   x11, x2
    li   x12, 0x8000F800
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00001033
    la   x12, check_test16d
    bne  x1, x12, test_fail

    # Check s0 restored
    li   x30, 0x00001034
    mv   x11, x8
    li   x12, 0x16D00002
    bne  x11, x12, test_fail
    .option pop


    #-------------------------------------------------
    # Test 16e: RAW on SP + non-aligned return
    # li x2, addr; cm.popret returns to non-aligned addr
    # SP=0x8000F900, {ra}, 16
    #-------------------------------------------------
    li   x3,  0x8000F900              # Use x3 to set up memory
    la   x4,  check_test16e
    sw   x4,  12(x3)                  # Store return address at [0x8000F900+12]

    li   x1,  0                       # Clear ra
    li   x5,  0xCAFECAFE              # Delay-slot canary
    li   x2,  0x8000F900              # Set SP immediately before popret
    cm.popret {ra}, 16                # Must use SP=0x8000F900

    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    li   x30, 0x00001040
    j    test_fail

    .balign 4
    c.nop                             # Pad to make label at addr%4==2
check_test16e:
    .option push
    .option norvc                     # Force 32-bit instructions at return point
    # Check delay-slot canary
    li   x30, 0x00001041
    mv   x11, x5
    li   x12, 0xCAFECAFE
    bne  x11, x12, test_fail

    # Check SP
    li   x30, 0x00001042
    mv   x11, x2
    li   x12, 0x8000F910
    bne  x11, x12, test_fail

    # Check ra
    li   x30, 0x00001043
    la   x12, check_test16e
    bne  x1, x12, test_fail
    .option pop


    #-------------------------------------------------
    # Test 17: IRQ stress test - 20 iterations of
    # cm.popret {ra, s0-s11}, 64 (13 regs, max kill window)
    # Each iteration: push known values to stack (with
    # ra = check label), clear regs, popret them back
    # and verify all 13 registers + return jump.
    # Stack at 0x8000FE00 (below trap handler region).
    #-------------------------------------------------

    li  x28, 0                        # Loop counter (t3)

test17_loop:
    li  x30, 0x00110000              # Error code base: Test 17

    # Set all registers to known values based on iteration
    slli x29, x28, 4                  # x29 = iter << 4
    lui  x5, 0x17000                  # x5 = 0x17000000 (base)
    or   x5, x5, x29                 # x5 = 0x17000000 | (iter << 4)

    la   x1,  test17_check            # ra  = return address (check label)
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

    # Push all 13 registers to stack (ra = check label gets stored)
    li   x2,  0x8000FE00
    cm.push {ra, s0-s11}, -64        # SP -> 0x8000FDC0

    # Clear all s-registers and ra
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

    # Execute longest popret: 13 registers, maximum IRQ kill window
    # Loads regs from stack, SP -> 0x8000FE00, jumps to ra (test17_check)
    cm.popret {ra, s0-s11}, 64

    # Should NOT reach here — popret jumps to test17_check
    li  x30, 0x00110000
    j   test_fail

    .balign 4
test17_check:
    .option push
    .option norvc

    # ---- Verify SP ----
    slli x6, x28, 12                 # x6 = iter << 12
    lui  x7, 0x00110
    ori  x7, x7, 0x001
    or   x30, x7, x6

    li   x10, 0x8000FE00             # Expected SP
    bne  x2,  x10, test_fail

    # ---- Rebuild expected base ----
    slli x29, x28, 4
    lui  x5, 0x17000
    or   x5, x5, x29                 # x5 = 0x17000000 | (iter << 4)

    # ---- Verify ra points to check label ----
    lui  x7, 0x00110
    ori  x7, x7, 0x002
    or   x30, x7, x6
    la   x12, test17_check
    bne  x1,  x12, test_fail

    # ---- Verify all 12 s-registers ----

    # Check s0
    lui  x7, 0x00110
    ori  x7, x7, 0x003
    or   x30, x7, x6
    mv   x11, x8
    ori  x12, x5, 0x002
    bne  x11, x12, test_fail

    # Check s1
    lui  x7, 0x00110
    ori  x7, x7, 0x004
    or   x30, x7, x6
    mv   x11, x9
    ori  x12, x5, 0x003
    bne  x11, x12, test_fail

    # Check s2
    lui  x7, 0x00110
    ori  x7, x7, 0x005
    or   x30, x7, x6
    mv   x11, x18
    ori  x12, x5, 0x004
    bne  x11, x12, test_fail

    # Check s3
    lui  x7, 0x00110
    ori  x7, x7, 0x006
    or   x30, x7, x6
    mv   x11, x19
    ori  x12, x5, 0x005
    bne  x11, x12, test_fail

    # Check s4
    lui  x7, 0x00110
    ori  x7, x7, 0x007
    or   x30, x7, x6
    mv   x11, x20
    ori  x12, x5, 0x006
    bne  x11, x12, test_fail

    # Check s5
    lui  x7, 0x00110
    ori  x7, x7, 0x008
    or   x30, x7, x6
    mv   x11, x21
    ori  x12, x5, 0x007
    bne  x11, x12, test_fail

    # Check s6
    lui  x7, 0x00110
    ori  x7, x7, 0x009
    or   x30, x7, x6
    mv   x11, x22
    ori  x12, x5, 0x008
    bne  x11, x12, test_fail

    # Check s7
    lui  x7, 0x00110
    ori  x7, x7, 0x00A
    or   x30, x7, x6
    mv   x11, x23
    ori  x12, x5, 0x009
    bne  x11, x12, test_fail

    # Check s8
    lui  x7, 0x00110
    ori  x7, x7, 0x00B
    or   x30, x7, x6
    mv   x11, x24
    ori  x12, x5, 0x00A
    bne  x11, x12, test_fail

    # Check s9
    lui  x7, 0x00110
    ori  x7, x7, 0x00C
    or   x30, x7, x6
    mv   x11, x25
    ori  x12, x5, 0x00B
    bne  x11, x12, test_fail

    # Check s10
    lui  x7, 0x00110
    ori  x7, x7, 0x00D
    or   x30, x7, x6
    mv   x11, x26
    ori  x12, x5, 0x00C
    bne  x11, x12, test_fail

    # Check s11
    lui  x7, 0x00110
    ori  x7, x7, 0x00E
    or   x30, x7, x6
    mv   x11, x27
    ori  x12, x5, 0x00D
    bne  x11, x12, test_fail

    # Increment loop counter and check if done
    addi x28, x28, 1
    li   x29, 20
    bne  x28, x29, test17_loop
    .option pop


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
	#   TT = Test number (01-0F, 10)
	#   CC = Check number within test (00 = return didn't happen)
	#        01 = delay-slot canary, 02+ = SP/ra/register checks
	# x31 = 0xBADC0DE0 (failure marker)
	# x11 = Actual value read
	# x12 = Expected value
	#-------------------------------------------------
	li  x31, 0xBADC0DE0              # Failure marker
	j   end_of_test


end_of_test:
	nop
    j end_of_test                     # Infinite loop
