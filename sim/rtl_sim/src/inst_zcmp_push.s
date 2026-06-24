#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmp_push
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.PUSH
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
    # Test 1: Minimal push - {ra}, 16 bytes
    #-------------------------------------------------
    li   x2,  0x80001000              # Set SP to SRAM base + offset
    li   x1,  0xDEADBEEF              # Set ra to test value

    cm.push {ra}, -16                 # Push ra, decrement SP by 16

    # Verify SP decremented by 16 bytes
    li   x30, 0x00000101              # Error code: Test 1, Check 1 (SP value)
    li   x10, 0x80000FF0              # Expected SP = 0x80001000 - 16
    bne  x2,  x10, test_fail          # x2 (SP) should be decremented

    # Verify ra stored at [SP+12] (registers at top of stack frame)
    li   x30, 0x00000102              # Error code: Test 1, Check 2 (ra at [SP+12])
    lw   x11, 12(x2)                  # Load from [SP+12]
    li   x12, 0xDEADBEEF              # Expected value
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 2: Small push - {ra, s0}, 32 bytes
    #-------------------------------------------------
    li   x2,  0x80002000              # Set SP to new location
    li   x1,  0xABCD1234              # ra = 0xABCD1234
    li   x8,  0x5678CDEF              # s0 = 0x5678CDEF

    cm.push {ra, s0}, -32             # Push ra and s0, decrement SP by 32

    # Verify SP decremented by 32 bytes
    li   x30, 0x00000201              # Error code: Test 2, Check 1 (SP value)
    li   x10, 0x80001FE0              # Expected SP = 0x80002000 - 32
    bne  x2,  x10, test_fail

    # Verify ra stored at [SP+24]
    li   x30, 0x00000202              # Error code: Test 2, Check 2 (ra at [SP+24])
    lw   x11, 24(x2)
    li   x12, 0xABCD1234
    bne  x11, x12, test_fail

    # Verify s0 stored at [SP+28]
    li   x30, 0x00000203              # Error code: Test 2, Check 3 (s0 at [SP+28])
    lw   x11, 28(x2)
    li   x12, 0x5678CDEF
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 3: Medium push - {ra, s0-s3}, 48 bytes
    #-------------------------------------------------
    li   x2,  0x80003000              # Set SP
    li   x1,  0x00000001              # ra
    li   x8,  0x00000002              # s0
    li   x9,  0x00000003              # s1
    li   x18, 0x00000004              # s2
    li   x19, 0x00000005              # s3

    cm.push {ra, s0-s3}, -48          # Push ra, s0-s3, decrement SP by 48

    # Verify SP decremented by 48 bytes
    li   x30, 0x00000301              # Error code: Test 3, Check 1 (SP value)
    li   x10, 0x80002FD0              # Expected SP = 0x80003000 - 48
    bne  x2,  x10, test_fail

    # Verify all registers stored correctly
    li   x30, 0x00000302              # Error code: Test 3, Check 2 (ra at [SP+28])
    lw   x11, 28(x2)                  # ra at [SP+28]
    li   x12, 0x00000001
    bne  x11, x12, test_fail

    li   x30, 0x00000303              # Error code: Test 3, Check 3 (s0 at [SP+32])
    lw   x11, 32(x2)                  # s0 at [SP+32]
    li   x12, 0x00000002
    bne  x11, x12, test_fail

    li   x30, 0x00000304              # Error code: Test 3, Check 4 (s1 at [SP+36])
    lw   x11, 36(x2)                  # s1 at [SP+36]
    li   x12, 0x00000003
    bne  x11, x12, test_fail

    li   x30, 0x00000305              # Error code: Test 3, Check 5 (s2 at [SP+40])
    lw   x11, 40(x2)                  # s2 at [SP+40]
    li   x12, 0x00000004
    bne  x11, x12, test_fail

    li   x30, 0x00000306              # Error code: Test 3, Check 6 (s3 at [SP+44])
    lw   x11, 44(x2)                  # s3 at [SP+44]
    li   x12, 0x00000005
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 4: Maximum push - {ra, s0-s11}, 64 bytes
    #-------------------------------------------------
    li   x2,  0x80004000              # Set SP
    li   x1,  0xF0000001              # ra
    li   x8,  0xF0000002              # s0
    li   x9,  0xF0000003              # s1
    li   x18, 0xF0000004              # s2
    li   x19, 0xF0000005              # s3
    li   x20, 0xF0000006              # s4
    li   x21, 0xF0000007              # s5
    li   x22, 0xF0000008              # s6
    li   x23, 0xF0000009              # s7
    li   x24, 0xF000000A              # s8
    li   x25, 0xF000000B              # s9
    li   x26, 0xF000000C              # s10
    li   x27, 0xF000000D              # s11

    cm.push {ra, s0-s11}, -64         # Push all callee-saved registers

    # Verify SP decremented by 64 bytes
    li   x30, 0x00000401              # Error code: Test 4, Check 1 (SP value)
    li   x10, 0x80003FC0              # Expected SP = 0x80004000 - 64
    bne  x2,  x10, test_fail

    # Verify first few and last few registers
    li   x30, 0x00000402              # Error code: Test 4, Check 2 (ra at [SP+12])
    lw   x11, 12(x2)                  # ra at [SP+12]
    li   x12, 0xF0000001
    bne  x11, x12, test_fail

    li   x30, 0x00000403              # Error code: Test 4, Check 3 (s0 at [SP+16])
    lw   x11, 16(x2)                  # s0 at [SP+16]
    li   x12, 0xF0000002
    bne  x11, x12, test_fail

    li   x30, 0x00000404              # Error code: Test 4, Check 4 (s1 at [SP+20])
    lw   x11, 20(x2)                  # s1 at [SP+20]
    li   x12, 0xF0000003
    bne  x11, x12, test_fail

    li   x30, 0x00000407              # Error code: Test 4, Check 7 (s2 at [SP+24])
    lw   x11, 24(x2)                  # s2 at [SP+24]
    li   x12, 0xF0000004
    bne  x11, x12, test_fail

    li   x30, 0x00000408              # Error code: Test 4, Check 8 (s3 at [SP+28])
    lw   x11, 28(x2)                  # s3 at [SP+28]
    li   x12, 0xF0000005
    bne  x11, x12, test_fail

    li   x30, 0x00000409              # Error code: Test 4, Check 9 (s4 at [SP+32])
    lw   x11, 32(x2)                  # s4 at [SP+32]
    li   x12, 0xF0000006
    bne  x11, x12, test_fail

    li   x30, 0x0000040A              # Error code: Test 4, Check 10 (s5 at [SP+36])
    lw   x11, 36(x2)                  # s5 at [SP+36]
    li   x12, 0xF0000007
    bne  x11, x12, test_fail

    li   x30, 0x0000040B              # Error code: Test 4, Check 11 (s6 at [SP+40])
    lw   x11, 40(x2)                  # s6 at [SP+40]
    li   x12, 0xF0000008
    bne  x11, x12, test_fail

    li   x30, 0x0000040C              # Error code: Test 4, Check 12 (s7 at [SP+44])
    lw   x11, 44(x2)                  # s7 at [SP+44]
    li   x12, 0xF0000009
    bne  x11, x12, test_fail

    li   x30, 0x0000040D              # Error code: Test 4, Check 13 (s8 at [SP+48])
    lw   x11, 48(x2)                  # s8 at [SP+48]
    li   x12, 0xF000000A
    bne  x11, x12, test_fail

    li   x30, 0x0000040E              # Error code: Test 4, Check 14 (s9 at [SP+52])
    lw   x11, 52(x2)                  # s9 at [SP+52]
    li   x12, 0xF000000B
    bne  x11, x12, test_fail

    li   x30, 0x00000405              # Error code: Test 4, Check 5 (s10 at [SP+56])
    lw   x11, 56(x2)                  # s10 at [SP+56]
    li   x12, 0xF000000C
    bne  x11, x12, test_fail

    li   x30, 0x00000406              # Error code: Test 4, Check 6 (s11 at [SP+60])
    lw   x11, 60(x2)                  # s11 at [SP+60]
    li   x12, 0xF000000D
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 5: Push with different stack adjustments
    # Test {ra, s0-s1} with all stack adjustment values
    #-------------------------------------------------

    # Stack adjustment = 16 bytes (3 regs * 4 = 12 bytes, 4 bytes padding)
    li   x2,  0x80005000
    li   x1,  0xAAA00001
    li   x8,  0xAAA00002
    li   x9,  0xAAA00003
    cm.push {ra, s0-s1}, -16
    li   x30, 0x00000501              # Error code: Test 5, Check 1 (SP - 16)
    li   x10, 0x80004FF0              # Expected SP - 16
    bne  x2,  x10, test_fail

    # Verify registers: ra at [SP+4], s0 at [SP+8], s1 at [SP+12]
    li   x30, 0x00000502              # Error code: Test 5, Check 2 (ra at [SP+4])
    lw   x11, 4(x2)
    li   x12, 0xAAA00001
    bne  x11, x12, test_fail

    li   x30, 0x00000503              # Error code: Test 5, Check 3 (s0 at [SP+8])
    lw   x11, 8(x2)
    li   x12, 0xAAA00002
    bne  x11, x12, test_fail

    li   x30, 0x00000504              # Error code: Test 5, Check 4 (s1 at [SP+12])
    lw   x11, 12(x2)
    li   x12, 0xAAA00003
    bne  x11, x12, test_fail

    # Stack adjustment = 32 bytes (3 regs * 4 = 12 bytes, 20 bytes padding)
    li   x2,  0x80005100
    li   x1,  0xBBB00001
    li   x8,  0xBBB00002
    li   x9,  0xBBB00003
    cm.push {ra, s0-s1}, -32
    li   x30, 0x00000505              # Error code: Test 5, Check 5 (SP - 32)
    li   x10, 0x800050E0              # Expected SP - 32
    bne  x2,  x10, test_fail

    # Verify registers: ra at [SP+20], s0 at [SP+24], s1 at [SP+28]
    li   x30, 0x00000506              # Error code: Test 5, Check 6 (ra at [SP+20])
    lw   x11, 20(x2)
    li   x12, 0xBBB00001
    bne  x11, x12, test_fail

    li   x30, 0x00000507              # Error code: Test 5, Check 7 (s0 at [SP+24])
    lw   x11, 24(x2)
    li   x12, 0xBBB00002
    bne  x11, x12, test_fail

    li   x30, 0x00000508              # Error code: Test 5, Check 8 (s1 at [SP+28])
    lw   x11, 28(x2)
    li   x12, 0xBBB00003
    bne  x11, x12, test_fail

    # Stack adjustment = 48 bytes (3 regs * 4 = 12 bytes, 36 bytes padding)
    li   x2,  0x80005200
    li   x1,  0xCCC00001
    li   x8,  0xCCC00002
    li   x9,  0xCCC00003
    cm.push {ra, s0-s1}, -48
    li   x30, 0x00000509              # Error code: Test 5, Check 9 (SP - 48)
    li   x10, 0x800051D0              # Expected SP - 48
    bne  x2,  x10, test_fail

    # Verify registers: ra at [SP+36], s0 at [SP+40], s1 at [SP+44]
    li   x30, 0x0000050A              # Error code: Test 5, Check 10 (ra at [SP+36])
    lw   x11, 36(x2)
    li   x12, 0xCCC00001
    bne  x11, x12, test_fail

    li   x30, 0x0000050B              # Error code: Test 5, Check 11 (s0 at [SP+40])
    lw   x11, 40(x2)
    li   x12, 0xCCC00002
    bne  x11, x12, test_fail

    li   x30, 0x0000050C              # Error code: Test 5, Check 12 (s1 at [SP+44])
    lw   x11, 44(x2)
    li   x12, 0xCCC00003
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 6: Consecutive pushes (stack building)
    #-------------------------------------------------
    li   x2,  0x80006000              # Fresh stack
    li   x1,  0x12345678              # ra
    li   x8,  0x9ABCDEF0              # s0

    cm.push {ra, s0}, -32             # First push
    # SP should now be 0x80005FE0

    li   x1,  0xFEDCBA98              # New ra value
    li   x8,  0x76543210              # New s0 value

    cm.push {ra, s0}, -32             # Second push
    # SP should now be 0x80005FC0

    li   x30, 0x00000601              # Error code: Test 6, Check 1 (SP after 2 pushes)
    li   x10, 0x80005FC0
    bne  x2,  x10, test_fail

    # Verify second push data (2 regs, -32: ra at SP+24, s0 at SP+28)
    li   x30, 0x00000602              # Error code: Test 6, Check 2 (2nd push ra at [SP+24])
    lw   x11, 24(x2)
    li   x12, 0xFEDCBA98
    bne  x11, x12, test_fail

    li   x30, 0x00000603              # Error code: Test 6, Check 3 (2nd push s0 at [SP+28])
    lw   x11, 28(x2)
    li   x12, 0x76543210
    bne  x11, x12, test_fail

    # Verify first push data (1st push at SP+32, so ra at SP+32+24=SP+56)
    li   x30, 0x00000604              # Error code: Test 6, Check 4 (1st push ra at [SP+56])
    lw   x11, 56(x2)
    li   x12, 0x12345678
    bne  x11, x12, test_fail

    li   x30, 0x00000605              # Error code: Test 6, Check 5 (1st push s0 at [SP+60])
    lw   x11, 60(x2)
    li   x12, 0x9ABCDEF0
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 7: {ra, s0-s2} (rlist=7), spimm=2 -> -48
    #-------------------------------------------------
    li   x2,  0x80007000
    li   x1,  0x07000001              # ra
    li   x8,  0x07000002              # s0
    li   x9,  0x07000003              # s1
    li   x18, 0x07000004              # s2

    cm.push {ra, s0-s2}, -48

    li   x30, 0x00000701              # Error code: Test 7, Check 1 (SP)
    li   x10, 0x80006FD0              # Expected SP = 0x80007000 - 48
    bne  x2,  x10, test_fail

    # 4 regs, stack_adj=48: ra at [SP+32], s0 at [SP+36], s1 at [SP+40], s2 at [SP+44]
    li   x30, 0x00000702
    lw   x11, 32(x2)
    li   x12, 0x07000001
    bne  x11, x12, test_fail

    li   x30, 0x00000703
    lw   x11, 36(x2)
    li   x12, 0x07000002
    bne  x11, x12, test_fail

    li   x30, 0x00000704
    lw   x11, 40(x2)
    li   x12, 0x07000003
    bne  x11, x12, test_fail

    li   x30, 0x00000705
    lw   x11, 44(x2)
    li   x12, 0x07000004
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 8: {ra, s0-s4} (rlist=9), spimm=1 -> -48
    #-------------------------------------------------
    li   x2,  0x80008000
    li   x1,  0x08000001              # ra
    li   x8,  0x08000002              # s0
    li   x9,  0x08000003              # s1
    li   x18, 0x08000004              # s2
    li   x19, 0x08000005              # s3
    li   x20, 0x08000006              # s4

    cm.push {ra, s0-s4}, -48

    li   x30, 0x00000801              # Error code: Test 8, Check 1 (SP)
    li   x10, 0x80007FD0              # Expected SP = 0x80008000 - 48
    bne  x2,  x10, test_fail

    # 6 regs, stack_adj=48: ra at [SP+24], s0-s4 at [SP+28]..[SP+44]
    li   x30, 0x00000802
    lw   x11, 24(x2)
    li   x12, 0x08000001
    bne  x11, x12, test_fail

    li   x30, 0x00000803
    lw   x11, 28(x2)
    li   x12, 0x08000002
    bne  x11, x12, test_fail

    li   x30, 0x00000804
    lw   x11, 32(x2)
    li   x12, 0x08000003
    bne  x11, x12, test_fail

    li   x30, 0x00000805
    lw   x11, 36(x2)
    li   x12, 0x08000004
    bne  x11, x12, test_fail

    li   x30, 0x00000806
    lw   x11, 40(x2)
    li   x12, 0x08000005
    bne  x11, x12, test_fail

    li   x30, 0x00000807
    lw   x11, 44(x2)
    li   x12, 0x08000006
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 9: {ra, s0-s5} (rlist=10), spimm=3 -> -80
    #-------------------------------------------------
    li   x2,  0x80009000
    li   x1,  0x09000001              # ra
    li   x8,  0x09000002              # s0
    li   x9,  0x09000003              # s1
    li   x18, 0x09000004              # s2
    li   x19, 0x09000005              # s3
    li   x20, 0x09000006              # s4
    li   x21, 0x09000007              # s5

    cm.push {ra, s0-s5}, -80

    li   x30, 0x00000901              # Error code: Test 9, Check 1 (SP)
    li   x10, 0x80008FB0              # Expected SP = 0x80009000 - 80
    bne  x2,  x10, test_fail

    # 7 regs, stack_adj=80: ra at [SP+52], s0-s5 at [SP+56]..[SP+76]
    li   x30, 0x00000902
    lw   x11, 52(x2)
    li   x12, 0x09000001
    bne  x11, x12, test_fail

    li   x30, 0x00000903
    lw   x11, 56(x2)
    li   x12, 0x09000002
    bne  x11, x12, test_fail

    li   x30, 0x00000904
    lw   x11, 60(x2)
    li   x12, 0x09000003
    bne  x11, x12, test_fail

    li   x30, 0x00000905
    lw   x11, 64(x2)
    li   x12, 0x09000004
    bne  x11, x12, test_fail

    li   x30, 0x00000906
    lw   x11, 68(x2)
    li   x12, 0x09000005
    bne  x11, x12, test_fail

    li   x30, 0x00000907
    lw   x11, 72(x2)
    li   x12, 0x09000006
    bne  x11, x12, test_fail

    li   x30, 0x00000908
    lw   x11, 76(x2)
    li   x12, 0x09000007
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 10: {ra, s0-s6} (rlist=11), spimm=0 -> -32
    #-------------------------------------------------
    li   x2,  0x8000A000
    li   x1,  0x0A000001              # ra
    li   x8,  0x0A000002              # s0
    li   x9,  0x0A000003              # s1
    li   x18, 0x0A000004              # s2
    li   x19, 0x0A000005              # s3
    li   x20, 0x0A000006              # s4
    li   x21, 0x0A000007              # s5
    li   x22, 0x0A000008              # s6

    cm.push {ra, s0-s6}, -32

    li   x30, 0x00000A01              # Error code: Test 10, Check 1 (SP)
    li   x10, 0x80009FE0              # Expected SP = 0x8000A000 - 32
    bne  x2,  x10, test_fail

    # 8 regs, stack_adj=32: ra at [SP+0], s0-s6 at [SP+4]..[SP+28]
    li   x30, 0x00000A02
    lw   x11, 0(x2)
    li   x12, 0x0A000001
    bne  x11, x12, test_fail

    li   x30, 0x00000A03
    lw   x11, 4(x2)
    li   x12, 0x0A000002
    bne  x11, x12, test_fail

    li   x30, 0x00000A04
    lw   x11, 8(x2)
    li   x12, 0x0A000003
    bne  x11, x12, test_fail

    li   x30, 0x00000A05
    lw   x11, 12(x2)
    li   x12, 0x0A000004
    bne  x11, x12, test_fail

    li   x30, 0x00000A06
    lw   x11, 16(x2)
    li   x12, 0x0A000005
    bne  x11, x12, test_fail

    li   x30, 0x00000A07
    lw   x11, 20(x2)
    li   x12, 0x0A000006
    bne  x11, x12, test_fail

    li   x30, 0x00000A08
    lw   x11, 24(x2)
    li   x12, 0x0A000007
    bne  x11, x12, test_fail

    li   x30, 0x00000A09
    lw   x11, 28(x2)
    li   x12, 0x0A000008
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 11: {ra, s0-s7} (rlist=12), spimm=2 -> -80
    #-------------------------------------------------
    li   x2,  0x8000B000
    li   x1,  0x0B000001              # ra
    li   x8,  0x0B000002              # s0
    li   x9,  0x0B000003              # s1
    li   x18, 0x0B000004              # s2
    li   x19, 0x0B000005              # s3
    li   x20, 0x0B000006              # s4
    li   x21, 0x0B000007              # s5
    li   x22, 0x0B000008              # s6
    li   x23, 0x0B000009              # s7

    cm.push {ra, s0-s7}, -80

    li   x30, 0x00000B01              # Error code: Test 11, Check 1 (SP)
    li   x10, 0x8000AFB0              # Expected SP = 0x8000B000 - 80
    bne  x2,  x10, test_fail

    # 9 regs, stack_adj=80: ra at [SP+44], s0-s7 at [SP+48]..[SP+76]
    li   x30, 0x00000B02
    lw   x11, 44(x2)
    li   x12, 0x0B000001
    bne  x11, x12, test_fail

    li   x30, 0x00000B03
    lw   x11, 48(x2)
    li   x12, 0x0B000002
    bne  x11, x12, test_fail

    li   x30, 0x00000B04
    lw   x11, 52(x2)
    li   x12, 0x0B000003
    bne  x11, x12, test_fail

    li   x30, 0x00000B05
    lw   x11, 56(x2)
    li   x12, 0x0B000004
    bne  x11, x12, test_fail

    li   x30, 0x00000B06
    lw   x11, 60(x2)
    li   x12, 0x0B000005
    bne  x11, x12, test_fail

    li   x30, 0x00000B07
    lw   x11, 64(x2)
    li   x12, 0x0B000006
    bne  x11, x12, test_fail

    li   x30, 0x00000B08
    lw   x11, 68(x2)
    li   x12, 0x0B000007
    bne  x11, x12, test_fail

    li   x30, 0x00000B09
    lw   x11, 72(x2)
    li   x12, 0x0B000008
    bne  x11, x12, test_fail

    li   x30, 0x00000B0A
    lw   x11, 76(x2)
    li   x12, 0x0B000009
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 12: {ra, s0-s8} (rlist=13), spimm=1 -> -64
    #-------------------------------------------------
    li   x2,  0x8000C000
    li   x1,  0x0C000001              # ra
    li   x8,  0x0C000002              # s0
    li   x9,  0x0C000003              # s1
    li   x18, 0x0C000004              # s2
    li   x19, 0x0C000005              # s3
    li   x20, 0x0C000006              # s4
    li   x21, 0x0C000007              # s5
    li   x22, 0x0C000008              # s6
    li   x23, 0x0C000009              # s7
    li   x24, 0x0C00000A              # s8

    cm.push {ra, s0-s8}, -64

    li   x30, 0x00000C01              # Error code: Test 12, Check 1 (SP)
    li   x10, 0x8000BFC0              # Expected SP = 0x8000C000 - 64
    bne  x2,  x10, test_fail

    # 10 regs, stack_adj=64: ra at [SP+24], s0-s8 at [SP+28]..[SP+60]
    li   x30, 0x00000C02
    lw   x11, 24(x2)
    li   x12, 0x0C000001
    bne  x11, x12, test_fail

    li   x30, 0x00000C03
    lw   x11, 28(x2)
    li   x12, 0x0C000002
    bne  x11, x12, test_fail

    li   x30, 0x00000C04
    lw   x11, 32(x2)
    li   x12, 0x0C000003
    bne  x11, x12, test_fail

    li   x30, 0x00000C05
    lw   x11, 36(x2)
    li   x12, 0x0C000004
    bne  x11, x12, test_fail

    li   x30, 0x00000C06
    lw   x11, 40(x2)
    li   x12, 0x0C000005
    bne  x11, x12, test_fail

    li   x30, 0x00000C07
    lw   x11, 44(x2)
    li   x12, 0x0C000006
    bne  x11, x12, test_fail

    li   x30, 0x00000C08
    lw   x11, 48(x2)
    li   x12, 0x0C000007
    bne  x11, x12, test_fail

    li   x30, 0x00000C09
    lw   x11, 52(x2)
    li   x12, 0x0C000008
    bne  x11, x12, test_fail

    li   x30, 0x00000C0A
    lw   x11, 56(x2)
    li   x12, 0x0C000009
    bne  x11, x12, test_fail

    li   x30, 0x00000C0B
    lw   x11, 60(x2)
    li   x12, 0x0C00000A
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 13: {ra, s0-s9} (rlist=14), spimm=3 -> -96
    #-------------------------------------------------
    li   x2,  0x8000D000
    li   x1,  0x0D000001              # ra
    li   x8,  0x0D000002              # s0
    li   x9,  0x0D000003              # s1
    li   x18, 0x0D000004              # s2
    li   x19, 0x0D000005              # s3
    li   x20, 0x0D000006              # s4
    li   x21, 0x0D000007              # s5
    li   x22, 0x0D000008              # s6
    li   x23, 0x0D000009              # s7
    li   x24, 0x0D00000A              # s8
    li   x25, 0x0D00000B              # s9

    cm.push {ra, s0-s9}, -96

    li   x30, 0x00000D01              # Error code: Test 13, Check 1 (SP)
    li   x10, 0x8000CFA0              # Expected SP = 0x8000D000 - 96
    bne  x2,  x10, test_fail

    # 11 regs, stack_adj=96: ra at [SP+52], s0-s9 at [SP+56]..[SP+92]
    li   x30, 0x00000D02
    lw   x11, 52(x2)
    li   x12, 0x0D000001
    bne  x11, x12, test_fail

    li   x30, 0x00000D03
    lw   x11, 56(x2)
    li   x12, 0x0D000002
    bne  x11, x12, test_fail

    li   x30, 0x00000D04
    lw   x11, 60(x2)
    li   x12, 0x0D000003
    bne  x11, x12, test_fail

    li   x30, 0x00000D05
    lw   x11, 64(x2)
    li   x12, 0x0D000004
    bne  x11, x12, test_fail

    li   x30, 0x00000D06
    lw   x11, 68(x2)
    li   x12, 0x0D000005
    bne  x11, x12, test_fail

    li   x30, 0x00000D07
    lw   x11, 72(x2)
    li   x12, 0x0D000006
    bne  x11, x12, test_fail

    li   x30, 0x00000D08
    lw   x11, 76(x2)
    li   x12, 0x0D000007
    bne  x11, x12, test_fail

    li   x30, 0x00000D09
    lw   x11, 80(x2)
    li   x12, 0x0D000008
    bne  x11, x12, test_fail

    li   x30, 0x00000D0A
    lw   x11, 84(x2)
    li   x12, 0x0D000009
    bne  x11, x12, test_fail

    li   x30, 0x00000D0B
    lw   x11, 88(x2)
    li   x12, 0x0D00000A
    bne  x11, x12, test_fail

    li   x30, 0x00000D0C
    lw   x11, 92(x2)
    li   x12, 0x0D00000B
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 14: {ra, s0-s11} (rlist=15), spimm=2 -> -96
    # (Test 4 used spimm=0, this tests non-zero spimm with max rlist)
    #-------------------------------------------------
    li   x2,  0x8000E000
    li   x1,  0x0E000001              # ra
    li   x8,  0x0E000002              # s0
    li   x9,  0x0E000003              # s1
    li   x18, 0x0E000004              # s2
    li   x19, 0x0E000005              # s3
    li   x20, 0x0E000006              # s4
    li   x21, 0x0E000007              # s5
    li   x22, 0x0E000008              # s6
    li   x23, 0x0E000009              # s7
    li   x24, 0x0E00000A              # s8
    li   x25, 0x0E00000B              # s9
    li   x26, 0x0E00000C              # s10
    li   x27, 0x0E00000D              # s11

    cm.push {ra, s0-s11}, -96

    li   x30, 0x00000E01              # Error code: Test 14, Check 1 (SP)
    li   x10, 0x8000DFA0              # Expected SP = 0x8000E000 - 96
    bne  x2,  x10, test_fail

    # 13 regs, stack_adj=96: ra at [SP+44], s0-s11 at [SP+48]..[SP+92]
    li   x30, 0x00000E02
    lw   x11, 44(x2)
    li   x12, 0x0E000001
    bne  x11, x12, test_fail

    li   x30, 0x00000E03
    lw   x11, 48(x2)
    li   x12, 0x0E000002
    bne  x11, x12, test_fail

    li   x30, 0x00000E04
    lw   x11, 52(x2)
    li   x12, 0x0E000003
    bne  x11, x12, test_fail

    li   x30, 0x00000E05
    lw   x11, 56(x2)
    li   x12, 0x0E000004
    bne  x11, x12, test_fail

    li   x30, 0x00000E06
    lw   x11, 60(x2)
    li   x12, 0x0E000005
    bne  x11, x12, test_fail

    li   x30, 0x00000E07
    lw   x11, 64(x2)
    li   x12, 0x0E000006
    bne  x11, x12, test_fail

    li   x30, 0x00000E08
    lw   x11, 68(x2)
    li   x12, 0x0E000007
    bne  x11, x12, test_fail

    li   x30, 0x00000E09
    lw   x11, 72(x2)
    li   x12, 0x0E000008
    bne  x11, x12, test_fail

    li   x30, 0x00000E0A
    lw   x11, 76(x2)
    li   x12, 0x0E000009
    bne  x11, x12, test_fail

    li   x30, 0x00000E0B
    lw   x11, 80(x2)
    li   x12, 0x0E00000A
    bne  x11, x12, test_fail

    li   x30, 0x00000E0C
    lw   x11, 84(x2)
    li   x12, 0x0E00000B
    bne  x11, x12, test_fail

    li   x30, 0x00000E0D
    lw   x11, 88(x2)
    li   x12, 0x0E00000C
    bne  x11, x12, test_fail

    li   x30, 0x00000E0E
    lw   x11, 92(x2)
    li   x12, 0x0E00000D
    bne  x11, x12, test_fail


    #=========================================================
    # Test 15: Pipeline hazard and SP dependency tests
    #=========================================================

    #-------------------------------------------------
    # Test 15a: RAW hazard - write SP then CM.PUSH
    # (CM.PUSH must read the just-written SP value)
    #-------------------------------------------------
    li   x1,  0xFA000001              # ra
    li   x2,  0x8000F000              # write SP immediately before push
    cm.push {ra}, -16                 # must use SP=0x8000F000

    li   x30, 0x00000F01              # Error code: Test 15a, Check 1 (SP)
    li   x10, 0x8000EFF0              # Expected SP = 0x8000F000 - 16
    bne  x2,  x10, test_fail

    li   x30, 0x00000F02              # Error code: Test 15a, Check 2 (ra)
    lw   x11, 12(x2)                  # ra at [SP+12]
    li   x12, 0xFA000001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15b: RAW hazard - CM.PUSH then read SP
    # (next instruction must see the updated SP)
    #-------------------------------------------------
    li   x2,  0x8000F100
    li   x1,  0xFB000001              # ra
    cm.push {ra}, -16                 # SP -> 0x8000F0F0
    mv   x11, x2                      # read SP immediately after push

    li   x30, 0x00000F03              # Error code: Test 15b, Check 1 (SP readback)
    li   x12, 0x8000F0F0
    bne  x11, x12, test_fail

    li   x30, 0x00000F04              # Error code: Test 15b, Check 2 (ra)
    lw   x11, 12(x2)                  # ra at [SP+12]
    li   x12, 0xFB000001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15c: Load-use hazard - load into SP then CM.PUSH
    # (CM.PUSH must use the loaded SP value)
    #-------------------------------------------------
    li   x3,  0x8000F200              # target SP value
    sw   x3,  0(x3)                   # store target SP at address 0x8000F200
    li   x1,  0xFC000001              # ra
    lw   x2,  0(x3)                   # load SP from memory
    cm.push {ra}, -16                 # must use loaded SP=0x8000F200

    li   x30, 0x00000F05              # Error code: Test 15c, Check 1 (SP)
    li   x10, 0x8000F1F0              # Expected SP = 0x8000F200 - 16
    bne  x2,  x10, test_fail

    li   x30, 0x00000F06              # Error code: Test 15c, Check 2 (ra)
    lw   x11, 12(x2)                  # ra at [SP+12]
    li   x12, 0xFC000001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15d: RAW hazard - write pushed register then CM.PUSH
    # (CM.PUSH must store the just-written register value)
    #-------------------------------------------------
    li   x2,  0x8000F300
    li   x1,  0xDEADDEAD              # ra (decoy - will be overwritten)
    li   x8,  0xDEADDEAD              # s0 (decoy - will be overwritten)
    li   x1,  0xFD000001              # ra - written right before push
    li   x8,  0xFD000002              # s0 - written right before push
    cm.push {ra, s0}, -32

    li   x30, 0x00000F07              # Error code: Test 15d, Check 1 (SP)
    li   x10, 0x8000F2E0              # Expected SP = 0x8000F300 - 32
    bne  x2,  x10, test_fail

    li   x30, 0x00000F08              # Error code: Test 15d, Check 2 (ra)
    lw   x11, 24(x2)                  # ra at [SP+24]
    li   x12, 0xFD000001
    bne  x11, x12, test_fail

    li   x30, 0x00000F09              # Error code: Test 15d, Check 3 (s0)
    lw   x11, 28(x2)                  # s0 at [SP+28]
    li   x12, 0xFD000002
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15e: Back-to-back CM.PUSH (SP chaining)
    # (second CM.PUSH must use SP output of first CM.PUSH)
    #-------------------------------------------------
    li   x2,  0x8000F400
    li   x1,  0xFE000001              # ra
    li   x8,  0xFE000002              # s0
    cm.push {ra}, -16                 # 1st push: SP -> 0x8000F3F0
    cm.push {ra, s0}, -32             # 2nd push: SP -> 0x8000F3D0

    li   x30, 0x00000F0A              # Error code: Test 15e, Check 1 (final SP)
    li   x10, 0x8000F3D0
    bne  x2,  x10, test_fail

    # Verify 2nd push: {ra,s0} with stack_adj=32, ra at [SP+24], s0 at [SP+28]
    li   x30, 0x00000F0B              # Error code: Test 15e, Check 2 (2nd push ra)
    lw   x11, 24(x2)
    li   x12, 0xFE000001
    bne  x11, x12, test_fail

    li   x30, 0x00000F0C              # Error code: Test 15e, Check 3 (2nd push s0)
    lw   x11, 28(x2)
    li   x12, 0xFE000002
    bne  x11, x12, test_fail

    # Verify 1st push: {ra} at [0x8000F3F0+12]=0x8000F3FC, offset from current SP = 44
    li   x30, 0x00000F0D              # Error code: Test 15e, Check 4 (1st push ra)
    lw   x11, 44(x2)
    li   x12, 0xFE000001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15f: CM.PUSH then immediate load from stack
    # (load must use updated SP from CM.PUSH)
    #-------------------------------------------------
    li   x2,  0x8000F500
    li   x1,  0xFF000001              # ra
    cm.push {ra}, -16                 # SP -> 0x8000F4F0
    lw   x11, 12(x2)                  # immediately load pushed ra using new SP

    li   x30, 0x00000F0E              # Error code: Test 15f, Check 1 (loaded ra)
    li   x12, 0xFF000001
    bne  x11, x12, test_fail

    #-------------------------------------------------
    # Test 15g: Store then CM.PUSH to overlapping address
    # (CM.PUSH store must overwrite the earlier store)
    #-------------------------------------------------
    li   x2,  0x8000F600
    li   x1,  0xF1000001              # ra
    li   x8,  0xF1000002              # s0
    # Pre-write a known pattern to where CM.PUSH will store
    li   x3,  0xBAAAAAAD
    sw   x3,  -4(x2)                  # store to [orig_SP-4] (where s0 will land)
    sw   x3,  -8(x2)                  # store to [orig_SP-8] (where ra will land)
    cm.push {ra, s0}, -32             # SP -> 0x8000F5E0, overwrites -4 and -8

    li   x30, 0x00000F0F              # Error code: Test 15g, Check 1 (SP)
    li   x10, 0x8000F5E0
    bne  x2,  x10, test_fail

    # Verify CM.PUSH overwrote the pre-stored values
    li   x30, 0x00000F10              # Error code: Test 15g, Check 2 (ra)
    lw   x11, 24(x2)                  # ra at [SP+24]
    li   x12, 0xF1000001
    bne  x11, x12, test_fail

    li   x30, 0x00000F11              # Error code: Test 15g, Check 3 (s0)
    lw   x11, 28(x2)                  # s0 at [SP+28]
    li   x12, 0xF1000002
    bne  x11, x12, test_fail


    #-------------------------------------------------
    # Test 16: IRQ stress test - 20 iterations of
    # cm.push {ra, s0-s11}, -64 (13 regs, max window)
    # Each iteration resets SP and all regs, so IRQ
    # kills mid-push are tolerated (next iter is fresh)
    #-------------------------------------------------
    li  x31, 0xF0F0F0F0              # Sync: start of stress loop

    li  x28, 0                        # Loop counter (t3)

test16_loop:
    li  x30, 0x00100000              # Error code base: Test 16

    # Set all pushed registers to known values based on iteration
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

    # Set SP below trap handler region (0x8000FEE0-0x8000FFFF) and
    # above Test 15 addresses (up to 0x8000F5FC). Stores go to
    # 0x8000FDCC-0x8000FDFC, avoiding collision with trap counter
    # at 0x8000FFF0.
    li   x2,  0x8000FE00

    # Execute longest push: 13 registers, maximum IRQ kill window
    cm.push {ra, s0-s11}, -64        # SP -> 0x8000FDC0

    # ---- Verify SP ----
    # Encode iteration in error code upper bits: (iter << 12) | 0x001001
    slli x6, x28, 12                 # x6 = iter << 12
    lui  x7, 0x00100                 # x7 = 0x00100000
    ori  x7, x7, 0x001              # x7 = 0x00100001
    or   x30, x7, x6                # x30 = error code with iteration

    li   x10, 0x8000FDC0             # Expected SP = 0x8000FE00 - 64
    bne  x2,  x10, test_fail

    # ---- Verify all 13 pushed registers on the stack ----
    # For {ra, s0-s11} with stack_adj=64:
    #   ra  at [SP+12], s0 at [SP+16], s1 at [SP+20], ...
    #   s11 at [SP+60]

    # Rebuild expected base (x5 was clobbered by push saving s-regs,
    # but x28 loop counter uses t3 which is caller-saved, still valid)
    slli x29, x28, 4
    lui  x5, 0x16000
    or   x5, x5, x29                 # x5 = 0x16000000 | (iter << 4)

    # Check ra at [SP+12]
    ori  x7, x7, 0x002              # update check number (but recompute cleanly)
    slli x6, x28, 12
    lui  x7, 0x00100
    ori  x7, x7, 0x002
    or   x30, x7, x6
    lw   x11, 12(x2)
    ori  x12, x5, 0x001
    bne  x11, x12, test_fail

    # Check s0 at [SP+16]
    lui  x7, 0x00100
    ori  x7, x7, 0x003
    or   x30, x7, x6
    lw   x11, 16(x2)
    ori  x12, x5, 0x002
    bne  x11, x12, test_fail

    # Check s1 at [SP+20]
    lui  x7, 0x00100
    ori  x7, x7, 0x004
    or   x30, x7, x6
    lw   x11, 20(x2)
    ori  x12, x5, 0x003
    bne  x11, x12, test_fail

    # Check s2 at [SP+24]
    lui  x7, 0x00100
    ori  x7, x7, 0x005
    or   x30, x7, x6
    lw   x11, 24(x2)
    ori  x12, x5, 0x004
    bne  x11, x12, test_fail

    # Check s3 at [SP+28]
    lui  x7, 0x00100
    ori  x7, x7, 0x006
    or   x30, x7, x6
    lw   x11, 28(x2)
    ori  x12, x5, 0x005
    bne  x11, x12, test_fail

    # Check s4 at [SP+32]
    lui  x7, 0x00100
    ori  x7, x7, 0x007
    or   x30, x7, x6
    lw   x11, 32(x2)
    ori  x12, x5, 0x006
    bne  x11, x12, test_fail

    # Check s5 at [SP+36]
    lui  x7, 0x00100
    ori  x7, x7, 0x008
    or   x30, x7, x6
    lw   x11, 36(x2)
    ori  x12, x5, 0x007
    bne  x11, x12, test_fail

    # Check s6 at [SP+40]
    lui  x7, 0x00100
    ori  x7, x7, 0x009
    or   x30, x7, x6
    lw   x11, 40(x2)
    ori  x12, x5, 0x008
    bne  x11, x12, test_fail

    # Check s7 at [SP+44]
    lui  x7, 0x00100
    ori  x7, x7, 0x00A
    or   x30, x7, x6
    lw   x11, 44(x2)
    ori  x12, x5, 0x009
    bne  x11, x12, test_fail

    # Check s8 at [SP+48]
    lui  x7, 0x00100
    ori  x7, x7, 0x00B
    or   x30, x7, x6
    lw   x11, 48(x2)
    ori  x12, x5, 0x00A
    bne  x11, x12, test_fail

    # Check s9 at [SP+52]
    lui  x7, 0x00100
    ori  x7, x7, 0x00C
    or   x30, x7, x6
    lw   x11, 52(x2)
    ori  x12, x5, 0x00B
    bne  x11, x12, test_fail

    # Check s10 at [SP+56]
    lui  x7, 0x00100
    ori  x7, x7, 0x00D
    or   x30, x7, x6
    lw   x11, 56(x2)
    ori  x12, x5, 0x00C
    bne  x11, x12, test_fail

    # Check s11 at [SP+60]
    lui  x7, 0x00100
    ori  x7, x7, 0x00E
    or   x30, x7, x6
    lw   x11, 60(x2)
    ori  x12, x5, 0x00D
    bne  x11, x12, test_fail

    # Increment loop counter and check if done
    addi x28, x28, 1
    li   x29, 20
    bne  x28, x29, test16_loop

    li  x31, 0xF1F1F1F1              # Sync: stress loop completed


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

