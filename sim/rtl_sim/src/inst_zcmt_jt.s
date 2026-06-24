#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmt_jt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.JT
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
    li  x31, 0x31313131   # t6 -- Testbench synchronization point

    #-------------------------------------------------
    # SETUP JVT BASE: 0x80000040 (64-byte aligned, within 64KB SRAM)
    # JVT CSR (0x017) = 0x80000040
    # entry N is at: 0x80000040 + N*4
    # entry 31 at:   0x80000040 + 124  = 0x800000BC (within SRAM) OK
    #-------------------------------------------------
    li   t0, 0x80000040
    csrw 0x017, t0       # JVT.base = 0x80000040


    #=========================================================
    # Test 1: cm.jt N=0 - basic jump to entry 0
    #=========================================================

    # Populate JVT entry 0 with address of test1_target
    la   t1, test1_target
    li   t0, 0x80000040
    sw   t1, 0(t0)              # JVT[0] = address of test1_target

    # Set sentinel values; canary last (overwrites x5 sentinel intentionally)
    li   x6,  0x01000006
    li   x7,  0x01000007
    li   x8,  0x01000008
    li   x9,  0x01000009
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jt N=0 (encoding: 0xA002)
    cm.jt 0                     # jump to JVT[0] = test1_target
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail
    #nop

test1_target:
    # Verify canary: instruction after cm.jt must not have executed
    li   x30, 0x00000101
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    li   x30, 0x00000102
    li   x12, 0x01000006
    bne  x6, x12, test_fail

    li   x30, 0x00000103
    li   x12, 0x01000007
    bne  x7, x12, test_fail

    li   x30, 0x00000104
    li   x12, 0x01000008
    bne  x8, x12, test_fail

    li   x30, 0x00000105
    li   x12, 0x01000009
    bne  x9, x12, test_fail


    #=========================================================
    # Test 2: cm.jt N=1 - jump to entry 1
    #=========================================================

    # Populate JVT entry 1 with address of test2_target
    la   t1, test2_target
    li   t0, 0x80000040
    sw   t1, 4(t0)              # JVT[1] = address of test2_target

    # Set sentinel values and delay-slot canary
    li   x13, 0x02000013
    li   x14, 0x02000014
    li   x15, 0x02000015
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jt N=1 (encoding: 0xA006)
    cm.jt 1                     # jump to JVT[1] = test2_target
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test2_target:
    # Verify canary
    li   x30, 0x00000201
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinels
    li   x30, 0x00000202
    li   x12, 0x02000013
    bne  x13, x12, test_fail

    li   x30, 0x00000203
    li   x12, 0x02000014
    bne  x14, x12, test_fail

    li   x30, 0x00000204
    li   x12, 0x02000015
    bne  x15, x12, test_fail


    #=========================================================
    # Test 3: cm.jt N=4 - non-sequential index
    #=========================================================

    # Populate JVT entry 4 with address of test3_target
    la   t1, test3_target
    li   t0, 0x80000040
    sw   t1, 16(t0)             # JVT[4] = address of test3_target (offset=4*4=16)

    # Set sentinel values and delay-slot canary
    li   x16, 0x03000016
    li   x17, 0x03000017
    li   x18, 0x03000018
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jt N=4 (encoding: 0xA012)
    cm.jt 4                     # jump to JVT[4] = test3_target
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test3_target:
    # Verify canary
    li   x30, 0x00000301
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinels
    li   x30, 0x00000302
    li   x12, 0x03000016
    bne  x16, x12, test_fail

    li   x30, 0x00000303
    li   x12, 0x03000017
    bne  x17, x12, test_fail

    li   x30, 0x00000304
    li   x12, 0x03000018
    bne  x18, x12, test_fail


    #=========================================================
    # Test 4: cm.jt N=31 - maximum index for cm.jt
    #=========================================================

    # Populate JVT entry 31 with address of test4_target
    # Entry 31 is at offset 31*4 = 124 from base
    la   t1, test4_target
    li   t0, 0x80000040
    sw   t1, 124(t0)            # JVT[31] = address of test4_target

    # Set sentinel values and delay-slot canary
    li   x19, 0x04000019
    li   x20, 0x0400001A
    li   x21, 0x0400001B
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jt N=31 (encoding: 0xA07E)
    cm.jt 31                    # jump to JVT[31] = test4_target
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test4_target:
    # Verify canary
    li   x30, 0x00000401
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinels
    li   x30, 0x00000402
    li   x12, 0x04000019
    bne  x19, x12, test_fail

    li   x30, 0x00000403
    li   x12, 0x0400001A
    bne  x20, x12, test_fail

    li   x30, 0x00000404
    li   x12, 0x0400001B
    bne  x21, x12, test_fail


    #=========================================================
    # Test 5: Update JVT base and verify new target used
    # (Tests that CSR write is effective after pipeline drains)
    # New JVT table at 0x80000080 (next 64-byte aligned addr)
    #=========================================================

    # Setup second JVT table at 0x80000080
    la   t1, test5_target
    li   t0, 0x80000080
    sw   t1, 0(t0)              # JVT2[0] = address of test5_target

    # Write new JVT base (with 2 NOPs to flush pipeline before cm.jt)
    li   t0, 0x80000080
    csrw 0x017, t0              # JVT.base = 0x80000080
    nop
    nop

    # Set sentinel values and delay-slot canary
    li   x22, 0x05000016
    li   x23, 0x05000017
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jt N=0 -> should now jump via JVT2 to test5_target
    cm.jt 0                     # jump to JVT2[0] = test5_target
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test5_target:
    # Verify canary
    li   x30, 0x00000501
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinels
    li   x30, 0x00000502
    li   x12, 0x05000016
    bne  x22, x12, test_fail

    li   x30, 0x00000503
    li   x12, 0x05000017
    bne  x23, x12, test_fail

    # Restore original JVT base (with pipeline flush)
    li   t0, 0x80000040
    csrw 0x017, t0
    nop
    nop


    #=========================================================
    # Test 6: Full register preservation test
    # cm.jt must not modify ANY register (x1-x29)
    #=========================================================

    # Populate JVT entry 2 for this test (offset 2*4=8)
    la   t1, test6_target
    li   t0, 0x80000040
    sw   t1, 8(t0)              # JVT[2] = test6_target

    # Set ALL registers to distinct known values
    li   x1,  0x06000001
    li   x2,  0x06000002
    li   x3,  0x06000003
    li   x4,  0x06000004
    li   x5,  0x06000005
    li   x6,  0x06000006
    li   x7,  0x06000007
    li   x8,  0x06000008
    li   x9,  0x06000009
    li   x10, 0x0600000A
    li   x11, 0x0600000B
    li   x12, 0x0600000C
    li   x13, 0x0600000D
    li   x14, 0x0600000E
    li   x15, 0x0600000F
    li   x16, 0x06000010
    li   x17, 0x06000011
    li   x18, 0x06000012
    li   x19, 0x06000013
    li   x20, 0x06000014
    li   x21, 0x06000015
    li   x22, 0x06000016
    li   x23, 0x06000017
    li   x24, 0x06000018
    li   x25, 0x06000019
    li   x26, 0x0600001A
    li   x27, 0x0600001B
    li   x28, 0x0600001C
    li   x29, 0x0600001D
    # NOTE: x30 and x31 are reserved for error code / pass-fail

    # Execute cm.jt N=2 (encoding: 0xA00A)
    cm.jt 2                     # jump to JVT[2] = test6_target
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test6_target:
    # Check ALL registers x1-x29 are unchanged
    li   x30, 0x00000601
    li   x31, 0x06000001
    bne  x1,  x31, test_fail

    li   x30, 0x00000602
    li   x31, 0x06000002
    bne  x2,  x31, test_fail

    li   x30, 0x00000603
    li   x31, 0x06000003
    bne  x3,  x31, test_fail

    li   x30, 0x00000604
    li   x31, 0x06000004
    bne  x4,  x31, test_fail

    li   x30, 0x00000605
    li   x31, 0x06000005
    bne  x5,  x31, test_fail

    li   x30, 0x00000606
    li   x31, 0x06000006
    bne  x6,  x31, test_fail

    li   x30, 0x00000607
    li   x31, 0x06000007
    bne  x7,  x31, test_fail

    li   x30, 0x00000608
    li   x31, 0x06000008
    bne  x8,  x31, test_fail

    li   x30, 0x00000609
    li   x31, 0x06000009
    bne  x9,  x31, test_fail

    li   x30, 0x0000060A
    li   x31, 0x0600000A
    bne  x10, x31, test_fail

    li   x30, 0x0000060B
    li   x31, 0x0600000B
    bne  x11, x31, test_fail

    li   x30, 0x0000060C
    li   x31, 0x0600000C
    bne  x12, x31, test_fail

    li   x30, 0x0000060D
    li   x31, 0x0600000D
    bne  x13, x31, test_fail

    li   x30, 0x0000060E
    li   x31, 0x0600000E
    bne  x14, x31, test_fail

    li   x30, 0x0000060F
    li   x31, 0x0600000F
    bne  x15, x31, test_fail

    li   x30, 0x00000610
    li   x31, 0x06000010
    bne  x16, x31, test_fail

    li   x30, 0x00000611
    li   x31, 0x06000011
    bne  x17, x31, test_fail

    li   x30, 0x00000612
    li   x31, 0x06000012
    bne  x18, x31, test_fail

    li   x30, 0x00000613
    li   x31, 0x06000013
    bne  x19, x31, test_fail

    li   x30, 0x00000614
    li   x31, 0x06000014
    bne  x20, x31, test_fail

    li   x30, 0x00000615
    li   x31, 0x06000015
    bne  x21, x31, test_fail

    li   x30, 0x00000616
    li   x31, 0x06000016
    bne  x22, x31, test_fail

    li   x30, 0x00000617
    li   x31, 0x06000017
    bne  x23, x31, test_fail

    li   x30, 0x00000618
    li   x31, 0x06000018
    bne  x24, x31, test_fail

    li   x30, 0x00000619
    li   x31, 0x06000019
    bne  x25, x31, test_fail

    li   x30, 0x0000061A
    li   x31, 0x0600001A
    bne  x26, x31, test_fail

    li   x30, 0x0000061B
    li   x31, 0x0600001B
    bne  x27, x31, test_fail

    li   x30, 0x0000061C
    li   x31, 0x0600001C
    bne  x28, x31, test_fail

    li   x30, 0x0000061D
    li   x31, 0x0600001D
    bne  x29, x31, test_fail


    #=========================================================
    # Test 7: Back-to-back cm.jt (chained jumps)
    # cm.jt N=0 -> target -> cm.jt N=1 -> final target
    #=========================================================

    # Populate JVT entry 0 -> chain_a, entry 1 -> chain_b
    la   t1, test7_chain_a
    la   t2, test7_chain_b
    li   t0, 0x80000040
    sw   t1, 0(t0)              # JVT[0] = test7_chain_a
    sw   t2, 4(t0)              # JVT[1] = test7_chain_b

    li   x5,  0xCAFECAFE              # Delay-slot canary

    # First cm.jt N=0
    cm.jt 0                     # test7_chain_a
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test7_chain_a:
    # Verify canary
    li   x30, 0x00000701
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    li   x6, 0x07000006         # set sentinel for second jump
    li   x5,  0xCAFECAFE              # Delay-slot canary for second cm.jt

    # Second cm.jt N=1 (chained)
    cm.jt 1                     # test7_chain_b
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test7_chain_b:
    # Verify canary
    li   x30, 0x00000702
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinel unchanged across second cm.jt
    li   x30, 0x00000703
    li   x12, 0x07000006
    bne  x6, x12, test_fail


    #=========================================================
    # Test 8: Store-to-cm.jt hazard (0 intervening instructions)
    # The JVT entry is written by a store immediately before cm.jt,
    # with NO instructions in between. The AHB store may still be
    # in-flight when the sequencer tries to issue the JVT load.
    # The processor must correctly order the store before the load.
    #=========================================================

    # Write JVT entry 3 immediately before cm.jt (tight sequence)
    # Use x28 (t3) as canary: x5/t0 is clobbered by li t0 in the store sequence
    li   x28, 0xCAFECAFE              # Delay-slot canary (t3, not used in store sequence)
    la   t1, test8_target
    li   t0, 0x80000040
    sw   t1, 12(t0)             # JVT[3] = test8_target  -- NO instructions follow before cm.jt
    cm.jt 3                     # must see the value just stored above
    li   x28, 0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test8_target:
    # Verify canary: instruction after cm.jt must not have executed
    li   x30, 0x00000801
    li   x12, 0xCAFECAFE
    bne  x28, x12, test_fail


    #=========================================================
    # Test 9: JVT CSR read/write correctness
    #   9.1  Write 0 -> read back 0
    #   9.2  Write 0xFFFFFFFF -> read back 0xFFFFFFC0 (bits[5:0] forced to 0)
    #   9.3  Write misaligned base (0x80000043) -> read back 0x80000040
    #   9.4  Restore JVT base and confirm jump still works
    #=========================================================

    # 9.1  Zero write
    li   x30, 0x00000901
    csrw 0x017, zero
    csrr t0,    0x017
    bne  t0, zero, test_fail

    # 9.2  All-ones write
    li   x30, 0x00000902
    li   t1, 0xFFFFFFFF
    csrw 0x017, t1
    csrr t0,    0x017
    li   t1,   0xFFFFFFC0
    bne  t0, t1, test_fail

    # 9.3  Misaligned base: bits[5:0] must be stripped
    li   x30, 0x00000903
    li   t1, 0x80000043
    csrw 0x017, t1
    csrr t0,    0x017
    li   t1,   0x80000040
    bne  t0, t1, test_fail

    # 9.4  Restore JVT base and verify jump still works via CSR-set base
    li   x30, 0x00000904
    la   t1, test9_target
    li   t0, 0x80000040
    sw   t1, 0(t0)              # JVT[0] = test9_target
    csrw 0x017, t0              # restore JVT base = 0x80000040
    nop
    nop
    li   x5,  0xCAFECAFE              # Delay-slot canary
    cm.jt 0
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test9_target:
    # Verify canary
    li   x30, 0x00000905
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    #=========================================================
    # Test 10: CM.JT stress loop (IRQ kill coverage)
    #   100 iterations of cm.jt through 5 JVT entries.
    #   Each iteration: set canary, cm.jt, verify canary at target.
    #   Counter in s0, iteration count in s2.
    #=========================================================
    li  x30, 0x00000A00

    # Set up 5 JVT entries (indices 5-9) pointing to test10_target
    li   t0, 0x80000040           # JVT base
    la   t1, test10_target
    sw   t1, 20(t0)              # JVT[5]
    sw   t1, 24(t0)              # JVT[6]
    sw   t1, 28(t0)              # JVT[7]
    sw   t1, 32(t0)              # JVT[8]
    sw   t1, 36(t0)              # JVT[9]

    li   s0, 0                   # iteration counter
    li   s2, 100                 # total iterations

test10_loop:
    bge  s0, s2, test10_done

    # Set canary
    li   x5, 0xCAFECAFE

    # Select JVT entry based on (iter % 5) + 5
    # Use remainder: s3 = s0 % 5
    # NOTE: t0 = x5 holds canary, use t1 (x6) for temp
    andi s3, s0, 0x7             # s0 & 7 (0-7)
    li   t1, 5
    blt  s3, t1, test10_idx_ok
    sub  s3, s3, t1              # wrap 5,6,7 -> 0,1,2
test10_idx_ok:
    addi s3, s3, 5               # index 5-9

    # Dispatch to the correct cm.jt based on computed index
    # NOTE: t0 = x5, which holds the canary -- use t1 (x6) for comparisons
    li   t1, 5
    beq  s3, t1, test10_jt5
    li   t1, 6
    beq  s3, t1, test10_jt6
    li   t1, 7
    beq  s3, t1, test10_jt7
    li   t1, 8
    beq  s3, t1, test10_jt8
    j    test10_jt9

test10_jt5:
    cm.jt 5
    j    test_fail
test10_jt6:
    cm.jt 6
    j    test_fail
test10_jt7:
    cm.jt 7
    j    test_fail
test10_jt8:
    cm.jt 8
    j    test_fail
test10_jt9:
    cm.jt 9
    j    test_fail

test10_target:
    # Verify canary survived (wasn't corrupted by partial execution)
    li   x30, 0x00000A01
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Increment counter and loop back
    addi s0, s0, 1
    j    test10_loop

test10_done:
    # Verify we completed all iterations
    li   x30, 0x00000A02
    li   x12, 100
    bne  s0, x12, test_fail


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
    #   TT = Test number (01-07)
    #   CC = Check number within test
    # x31 = 0xBADC0DE0 (failure marker)
    #-------------------------------------------------
    li  x31, 0xBADC0DE0              # Failure marker
    j   end_of_test


end_of_test:
    nop
    j end_of_test                    # Infinite loop
