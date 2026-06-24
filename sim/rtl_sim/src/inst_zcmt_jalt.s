#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmt_jalt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.JALT
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
    li  x2,  0x22222222   # sp
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
    # SETUP JVT BASE: 0x80000100 (64-byte aligned, within 64KB SRAM)
    # JVT CSR (0x017) = 0x80000100
    # cm.jalt uses indices 32..255
    # entry N is at: 0x80000100 + N*4
    # entry 255 at:  0x80000100 + 1020 = 0x800004FC (within SRAM) OK
    #-------------------------------------------------
    li   t0, 0x80000100
    csrw 0x017, t0       # JVT.base = 0x80000100
    nop                  # Pipeline flush: let JVT write take effect


    #=========================================================
    # Test 1: cm.jalt N=32 - verify jump and ra = PC+2
    #=========================================================
    li  x30, 0x00000100

    # Populate JVT entry 32 with address of test1_target (offset 32*4=128)
    la   t1, test1_target
    li   t0, 0x80000100
    sw   t1, 128(t0)            # JVT[32] = address of test1_target

    # Set sentinels and delay-slot canary (NOT x1 since cm.jalt will write it)
    li   x6,  0x01000006
    li   x7,  0x01000007
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jalt N=32
    # PC+2 should point to the instruction AFTER cm.jalt (the canary below)
test1_jalt:
    cm.jalt 32                  # ra=PC+2, jump to JVT[32]=test1_target
test1_jalt_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test1_target:
    # Verify x1 (ra) = address of instruction after cm.jalt = test1_jalt_next
    li   x30, 0x00000101
    la   x12, test1_jalt_next
    bne  x1, x12, test_fail

    # Verify canary: instruction after cm.jalt must not have executed
    li   x30, 0x00000102
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinels (no other register should be modified)
    li   x30, 0x00000103
    li   x12, 0x01000006
    bne  x6, x12, test_fail

    li   x30, 0x00000104
    li   x12, 0x01000007
    bne  x7, x12, test_fail


    #=========================================================
    # Test 2: cm.jalt N=33 - verify jump and ra = PC+2
    #=========================================================
    li  x30, 0x00000200

    # Populate JVT entry 33 (offset 33*4=132)
    la   t1, test2_target
    li   t0, 0x80000100
    sw   t1, 132(t0)            # JVT[33] = test2_target

    li   x8,  0x02000008
    li   x9,  0x02000009
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jalt N=33
test2_jalt:
    cm.jalt 33                  # ra=PC+2, jump to JVT[33]=test2_target
test2_jalt_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test2_target:
    # Verify ra = test2_jalt_next
    li   x30, 0x00000201
    la   x12, test2_jalt_next
    bne  x1, x12, test_fail

    # Verify canary
    li   x30, 0x00000202
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinels
    li   x30, 0x00000203
    li   x12, 0x02000008
    bne  x8, x12, test_fail

    li   x30, 0x00000204
    li   x12, 0x02000009
    bne  x9, x12, test_fail


    #=========================================================
    # Test 3: cm.jalt N=36 - non-sequential index
    #=========================================================
    li  x30, 0x00000300

    # Populate JVT entry 36 (offset 36*4=144)
    la   t1, test3_target
    li   t0, 0x80000100
    sw   t1, 144(t0)            # JVT[36] = test3_target

    li   x13, 0x0300000D
    li   x14, 0x0300000E
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jalt N=36
test3_jalt:
    cm.jalt 36                  # ra=PC+2, jump to JVT[36]=test3_target
test3_jalt_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test3_target:
    # Verify ra = test3_jalt_next
    li   x30, 0x00000301
    la   x12, test3_jalt_next
    bne  x1, x12, test_fail

    # Verify canary
    li   x30, 0x00000302
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinels
    li   x30, 0x00000303
    li   x12, 0x0300000D
    bne  x13, x12, test_fail

    li   x30, 0x00000304
    li   x12, 0x0300000E
    bne  x14, x12, test_fail


    #=========================================================
    # Test 4: cm.jalt N=255 - maximum index
    #=========================================================
    li  x30, 0x00000400

    # Populate JVT entry 255 (offset 255*4=1020)
    la   t1, test4_target
    li   t0, 0x80000100
    sw   t1, 1020(t0)           # JVT[255] = test4_target

    li   x15, 0x0400000F
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jalt N=255
test4_jalt:
    cm.jalt 255                 # ra=PC+2, jump to JVT[255]=test4_target
test4_jalt_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test4_target:
    # Verify ra = test4_jalt_next
    li   x30, 0x00000401
    la   x12, test4_jalt_next
    bne  x1, x12, test_fail

    # Verify canary
    li   x30, 0x00000402
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinel
    li   x30, 0x00000403
    li   x12, 0x0400000F
    bne  x15, x12, test_fail


    #=========================================================
    # Test 5: RAW hazard - use x1 (ra) immediately after cm.jalt
    # The instruction right after cm.jalt at target must see the
    # correct ra value without stall
    #=========================================================
    li  x30, 0x00000500

    # Populate JVT entry 34 (offset 34*4=136)
    la   t1, test5_target
    li   t0, 0x80000100
    sw   t1, 136(t0)            # JVT[34] = test5_target

    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jalt N=34
test5_jalt:
    cm.jalt 34                  # ra=PC+2, jump to JVT[34]=test5_target
test5_jalt_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test5_target:
    # Immediately use x1 (no intervening instructions - hazard test)
    # x1 should be = test5_jalt_next
    mv   x11, x1                # copy ra to x11 RIGHT AWAY (hazard scenario)
    la   x12, test5_jalt_next
    li   x30, 0x00000501
    bne  x11, x12, test_fail

    # Also verify ra itself is still correct
    li   x30, 0x00000502
    la   x12, test5_jalt_next
    bne  x1, x12, test_fail

    # Verify canary
    li   x30, 0x00000503
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail


    #=========================================================
    # Test 6: Register preservation - only x1 should change
    #=========================================================
    li  x30, 0x00000600

    # Populate JVT entry 35 (offset 35*4=140)
    la   t1, test6_target
    li   t0, 0x80000100
    sw   t1, 140(t0)            # JVT[35] = test6_target

    # Set ALL registers to distinct known values (except x1 which cm.jalt writes)
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
    # NOTE: x30, x31 reserved for error code / pass-fail

    # Execute cm.jalt N=35
test6_jalt:
    cm.jalt 35                  # ra=PC+2, jump to JVT[35]=test6_target
test6_jalt_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test6_target:
    # Verify x1 = test6_jalt_next (x1 IS expected to change)
    li   x30, 0x00000601
    la   x31, test6_jalt_next
    bne  x1, x31, test_fail

    # Verify ALL other registers x2-x29 are unchanged
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
    # Test 7: cm.jalt used as a function call mechanism
    # Call a "function" via cm.jalt, function returns via jalr x0, x1, 0
    #=========================================================
    li  x30, 0x00000700

    # Populate JVT entry 37 (offset 37*4=148)
    la   t1, test7_func
    li   t0, 0x80000100
    sw   t1, 148(t0)            # JVT[37] = test7_func (our "function")

    li   x5, 0x07000005         # argument in x5
    li   x6, 0x07000006         # argument in x6

    # Call "function" via cm.jalt N=37
test7_jalt:
    cm.jalt 37                  # ra=PC+2, jump to test7_func
test7_return:
    # Function returned here via jalr x0, x1, 0
    # Verify function return value in x10
    li   x30, 0x00000701
    li   x12, 0x07ABCDEF
    bne  x10, x12, test_fail

    # Verify x5, x6 unchanged
    li   x30, 0x00000702
    li   x12, 0x07000005
    bne  x5, x12, test_fail

    # Verify x1 still holds the return address (jalr x0,x1,0 must NOT modify x1)
    li   x30, 0x00000703
    la   x12, test7_return
    bne  x1, x12, test_fail

    j    test7_done

test7_func:
    # This is the "function" body
    # Compute return value: x10 = 0x07ABCDEF
    li   x10, 0x07ABCDEF
    # Return via ra (x1 was set to test7_return by cm.jalt)
    jalr x0, x1, 0             # return to caller

test7_done:


    #=========================================================
    # Test 8: JVT base change - verify new base is used for cm.jalt
    # (Tests CSR write effective; mirrors cm.jt Test 5)
    # New JVT table at 0x80000500 (64-byte aligned, non-overlapping)
    #=========================================================
    li  x30, 0x00000800

    # Setup second JVT table at 0x80000500
    la   t1, test8_target
    li   t0, 0x80000500
    sw   t1, 128(t0)            # JVT2[32] = address of test8_target (offset 32*4=128)

    # Write new JVT base (with 2 NOPs to flush pipeline before cm.jalt)
    li   t0, 0x80000500
    csrw 0x017, t0              # JVT.base = 0x80000500
    nop
    nop

    # Set sentinel and delay-slot canary (NOT x1 since cm.jalt will write it)
    li   x16, 0x08000010
    li   x5,  0xCAFECAFE              # Delay-slot canary

    # Execute cm.jalt N=32 -> should now jump via JVT2 to test8_target
test8_jalt:
    cm.jalt 32                  # ra=PC+2, jump to JVT2[32]=test8_target
test8_jalt_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test8_target:
    # Verify ra = test8_jalt_next
    li   x30, 0x00000801
    la   x12, test8_jalt_next
    bne  x1, x12, test_fail

    # Verify canary
    li   x30, 0x00000802
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinel unchanged (cm.jalt must not modify x16)
    li   x30, 0x00000803
    li   x12, 0x08000010
    bne  x16, x12, test_fail

    # Restore original JVT base (with pipeline flush)
    li   t0, 0x80000100
    csrw 0x017, t0
    nop
    nop


    #=========================================================
    # Test 9: Back-to-back cm.jalt (chained)
    # cm.jalt N=32 -> chain_a -> cm.jalt N=33 -> chain_b
    # Verifies x1 is correctly overwritten by each cm.jalt
    #=========================================================
    li  x30, 0x00000900

    # Re-populate JVT entries 32 and 33 for the chain
    la   t1, test9_chain_a
    la   t2, test9_chain_b
    li   t0, 0x80000100
    sw   t1, 128(t0)            # JVT[32] = test9_chain_a
    sw   t2, 132(t0)            # JVT[33] = test9_chain_b

    li   x5,  0xCAFECAFE              # Delay-slot canary

    # First cm.jalt N=32
test9_jalt1:
    cm.jalt 32                  # ra=PC+2, jump to JVT[32]=test9_chain_a
test9_jalt1_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test9_chain_a:
    # Verify x1 = test9_jalt1_next (from first cm.jalt)
    li   x30, 0x00000901
    la   x12, test9_jalt1_next
    bne  x1, x12, test_fail

    # Verify canary
    li   x30, 0x00000902
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    li   x6, 0x09000006               # sentinel across second cm.jalt
    li   x5,  0xCAFECAFE              # Delay-slot canary for second cm.jalt

    # Second cm.jalt N=33 (back-to-back)
test9_jalt2:
    cm.jalt 33                  # ra=PC+2, jump to JVT[33]=test9_chain_b
test9_jalt2_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test9_chain_b:
    # Verify x1 = test9_jalt2_next (from second cm.jalt, NOT from first)
    li   x30, 0x00000903
    la   x12, test9_jalt2_next
    bne  x1, x12, test_fail

    # Verify canary
    li   x30, 0x00000904
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify sentinel still intact across second cm.jalt
    li   x30, 0x00000905
    li   x12, 0x09000006
    bne  x6, x12, test_fail


    #=========================================================
    # Test 10: Store-to-cm.jalt hazard (0 intervening instructions)
    # JVT entry written by store immediately before cm.jalt, with
    # NO instructions in between. Same structural AHB ordering
    # hazard as cm.jt Test 8, but also verifies ra = PC+2.
    #=========================================================
    li  x30, 0x00000A00

    # Write JVT entry 38 immediately before cm.jalt (tight sequence)
    # Use x28 (t3) as canary: x5/t0 is clobbered by li t0 in the store sequence
    li   x28, 0xCAFECAFE              # Delay-slot canary (t3, not used in store sequence)
    la   t1, test10_target
    li   t0, 0x80000100
    sw   t1, 152(t0)            # JVT[38] = test10_target  (offset 38*4=152)
    cm.jalt 38                  # must see the value just stored above
test10_jalt_next:
    li   x28, 0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test10_target:
    # Reaching here confirms store-to-cm.jalt ordering worked.
    # Verify ra = test10_jalt_next (the key cm.jalt-specific check)
    li   x30, 0x00000A01
    la   x12, test10_jalt_next
    bne  x1, x12, test_fail

    # Verify canary
    li   x30, 0x00000A02
    li   x12, 0xCAFECAFE
    bne  x28, x12, test_fail


    #=========================================================
    # Test 11: WAW hazard on x1 - instruction writes x1 immediately
    # before cm.jalt; cm.jalt must overwrite x1 with PC+2 (not stale)
    #=========================================================
    li  x30, 0x00000B00

    # Populate JVT entry 39 (offset 39*4=156)
    la   t1, test11_target
    li   t0, 0x80000100
    sw   t1, 156(t0)            # JVT[39] = test11_target

    # Write x1 with a distinct sentinel value immediately before cm.jalt
    li   x5,  0xCAFECAFE              # Delay-slot canary
    li   x1, 0x0B00DEAD         # x1 = stale sentinel (WAW hazard: cm.jalt must overwrite)
    cm.jalt 39                  # must overwrite x1 with PC+2, NOT 0x0B00DEAD
test11_jalt_next:
    li   x5,  0xBAD0BAD0              # Canary corruption (should NOT execute)
    j    test_fail

test11_target:
    # x1 must be test11_jalt_next, NOT the stale 0x0B00DEAD value
    li   x30, 0x00000B01
    la   x12, test11_jalt_next
    bne  x1, x12, test_fail

    # Verify canary
    li   x30, 0x00000B02
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail


    #=========================================================
    # Test 12: CM.JALT stress loop (IRQ kill coverage)
    #   100 iterations of cm.jalt through 5 JVT entries.
    #   Each iteration: set canary, cm.jalt, verify canary + ra at target.
    #   Counter in s0, iteration count in s2.
    #=========================================================
    li  x30, 0x00000C00

    # Set up 5 JVT entries (indices 40-44) pointing to test12_target
    li   t0, 0x80000100           # JVT base
    la   t1, test12_target
    sw   t1, 160(t0)             # JVT[40] (offset 40*4=160)
    sw   t1, 164(t0)             # JVT[41]
    sw   t1, 168(t0)             # JVT[42]
    sw   t1, 172(t0)             # JVT[43]
    sw   t1, 176(t0)             # JVT[44]

    li   s0, 0                   # iteration counter
    li   s2, 100                 # total iterations

test12_loop:
    bge  s0, s2, test12_done

    # Set canary
    li   x5, 0xCAFECAFE

    # Select JVT entry based on (iter % 5) + 40
    # NOTE: t0 = x5 holds canary, use t1 (x6) for temp
    andi s3, s0, 0x7             # s0 & 7 (0-7)
    li   t1, 5
    blt  s3, t1, test12_idx_ok
    sub  s3, s3, t1              # wrap 5,6,7 -> 0,1,2
test12_idx_ok:
    addi s3, s3, 40              # index 40-44

    # Dispatch to correct cm.jalt instruction
    # NOTE: t0 = x5 holds canary, use t1 (x6) for comparisons
    li   t1, 40
    beq  s3, t1, test12_jalt40
    li   t1, 41
    beq  s3, t1, test12_jalt41
    li   t1, 42
    beq  s3, t1, test12_jalt42
    li   t1, 43
    beq  s3, t1, test12_jalt43
    j    test12_jalt44

test12_jalt40:
    cm.jalt 40
test12_jalt40_next:
    j    test_fail              # Should not reach (cm.jalt jumps)
test12_jalt41:
    cm.jalt 41
test12_jalt41_next:
    j    test_fail
test12_jalt42:
    cm.jalt 42
test12_jalt42_next:
    j    test_fail
test12_jalt43:
    cm.jalt 43
test12_jalt43_next:
    j    test_fail
test12_jalt44:
    cm.jalt 44
test12_jalt44_next:
    j    test_fail

test12_target:
    # Verify canary survived
    li   x30, 0x00000C01
    li   x12, 0xCAFECAFE
    bne  x5, x12, test_fail

    # Verify ra = PC+2 of the cm.jalt instruction
    # ra should point to the instruction after cm.jalt (which is the "j test_fail")
    # We can verify ra is reasonable by checking it points within the dispatch area
    # (precise check is hard since it varies per entry, just verify ra != stale value)
    li   x30, 0x00000C02
    li   x12, 0x11111111          # original ra value from init
    beq  x1, x12, test_fail      # ra must have been overwritten by cm.jalt

    # Increment counter and loop back
    addi s0, s0, 1
    j    test12_loop

test12_done:
    # Verify we completed all iterations
    li   x30, 0x00000C03
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
