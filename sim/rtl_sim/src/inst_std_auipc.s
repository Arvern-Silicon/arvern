#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_auipc
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: AUIPC
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    # Initialize some registers
    li    x1,  0x12345678
    li    x2,  0xdeadbeef
    li    x3,  0x10000010
    li    x4,  0xabcd1234
    li    x5,  0x0bad0c0d
    li    x6,  0x0000ffff
    li    x7,  0xffff0000
    li    x8,  0x11111222


    #=========================================================
    # Tests 1-5: Consecutive AUIPC instructions
    # Execute all five first, then check each result.
    # Expected value = label_address + (imm20 << 12)
    #=========================================================

t1: auipc x10, 0            # x10 = PC(t1) + 0
t2: auipc x11, 0xffff0      # x11 = PC(t2) + 0xffff0000
t3: auipc x12, 0x00100      # x12 = PC(t3) + 0x00100000
t4: auipc x13, 0x81234      # x13 = PC(t4) + 0x81234000
t5: auipc x14, 0x63456      # x14 = PC(t5) + 0x63456000
    nop
    nop
    nop

    # Save test 2 and test 3 results NOW, before check 1 clobbers x11 and x12.
    # Check 1 does: mv x11, x10 (overwrites x11 = test 2 result)
    #          and: la x12, t1  (overwrites x12 = test 3 result)
    mv    x5, x11           # save test 2 result (auipc x11, 0xffff0)
    mv    x6, x12           # save test 3 result (auipc x12, 0x00100)

    # Check 1: auipc x10, 0  →  x10 = PC(t1)
    mv    x11, x10          # x11 = actual
    la    x12, t1           # x12 = expected (imm=0, no add needed)
    li    x30, 0x00000101
    bne   x11, x12, test_fail

    # Check 2: auipc x11, 0xffff0  →  x11 = PC(t2) + 0xffff0000
    mv    x11, x5           # x11 = actual (restored from saved copy)
    la    x12, t2           # x12 = PC(t2)
    lui   x3,  0xffff0      # x3  = 0xffff0000
    add   x12, x12, x3     # x12 = expected
    li    x30, 0x00000201
    bne   x11, x12, test_fail

    # Check 3: auipc x12, 0x00100  →  x12 = PC(t3) + 0x00100000
    mv    x11, x6           # x11 = actual (restored from saved copy)
    la    x12, t3           # x12 = PC(t3)
    lui   x3,  0x00100      # x3  = 0x00100000
    add   x12, x12, x3     # x12 = expected
    li    x30, 0x00000301
    bne   x11, x12, test_fail

    # Check 4: auipc x13, 0x81234  →  x13 = PC(t4) + 0x81234000
    mv    x11, x13          # x11 = actual
    la    x12, t4           # x12 = PC(t4)
    lui   x3,  0x81234      # x3  = 0x81234000
    add   x12, x12, x3     # x12 = expected
    li    x30, 0x00000401
    bne   x11, x12, test_fail

    # Check 5: auipc x14, 0x63456  →  x14 = PC(t5) + 0x63456000
    mv    x11, x14          # x11 = actual
    la    x12, t5           # x12 = PC(t5)
    lui   x3,  0x63456      # x3  = 0x63456000
    add   x12, x12, x3     # x12 = expected
    li    x30, 0x00000501
    bne   x11, x12, test_fail


    #=========================================================
    # Tests 6-10: AUIPC with NOPs between instructions
    # Same immediates as tests 1-5, different PCs.
    #=========================================================

t6:  auipc x20, 0            # x20 = PC(t6)  + 0
    nop
    nop
t7:  auipc x21, 0xffff0      # x21 = PC(t7)  + 0xffff0000
    nop
    nop
t8:  auipc x22, 0x00100      # x22 = PC(t8)  + 0x00100000
    nop
    nop
t9:  auipc x23, 0x81234      # x23 = PC(t9)  + 0x81234000
    nop
    nop
t10: auipc x24, 0x63456      # x24 = PC(t10) + 0x63456000
    nop
    nop
    nop

    # Check 6: auipc x20, 0  →  x20 = PC(t6)
    mv    x11, x20          # x11 = actual
    la    x12, t6           # x12 = expected
    li    x30, 0x00000601
    bne   x11, x12, test_fail

    # Check 7: auipc x21, 0xffff0  →  x21 = PC(t7) + 0xffff0000
    mv    x11, x21          # x11 = actual
    la    x12, t7           # x12 = PC(t7)
    lui   x3,  0xffff0      # x3  = 0xffff0000
    add   x12, x12, x3     # x12 = expected
    li    x30, 0x00000701
    bne   x11, x12, test_fail

    # Check 8: auipc x22, 0x00100  →  x22 = PC(t8) + 0x00100000
    mv    x11, x22          # x11 = actual
    la    x12, t8           # x12 = PC(t8)
    lui   x3,  0x00100      # x3  = 0x00100000
    add   x12, x12, x3     # x12 = expected
    li    x30, 0x00000801
    bne   x11, x12, test_fail

    # Check 9: auipc x23, 0x81234  →  x23 = PC(t9) + 0x81234000
    mv    x11, x23          # x11 = actual
    la    x12, t9           # x12 = PC(t9)
    lui   x3,  0x81234      # x3  = 0x81234000
    add   x12, x12, x3     # x12 = expected
    li    x30, 0x00000901
    bne   x11, x12, test_fail

    # Check 10: auipc x24, 0x63456  →  x24 = PC(t10) + 0x63456000
    mv    x11, x24          # x11 = actual
    la    x12, t10          # x12 = PC(t10)
    lui   x3,  0x63456      # x3  = 0x63456000
    add   x12, x12, x3     # x12 = expected
    li    x30, 0x00000A01
    bne   x11, x12, test_fail


    #-------------------------------------------------
    # ALL TESTS PASSED
    #-------------------------------------------------
    li  x30, 0x00000000              # Clear error code
    li  x31, 0xDEADBEEF              # Success marker
    jal x0, end_of_test


test_fail:
    #-------------------------------------------------
    # TEST FAILED
    #-------------------------------------------------
    # x30 = error code 0x00TTCC  (TT=test, CC=check)
    # x11 = actual auipc result
    # x12 = expected (label address + shifted immediate)
    li  x31, 0xBADC0DE0              # Failure marker
    jal x0, end_of_test


end_of_test:
    nop
    jal x0, end_of_test              # Infinite loop
