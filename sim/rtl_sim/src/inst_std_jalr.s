#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_jalr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: JALR
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0
    li    x8,  0x12345678

    #=========================================================
    # Test 1: JALR zero offset, link in ra
    # la t0, func1 ; jalr ra, 0(t0)  →  PC=func1, ra=jalr1_ra
    #=========================================================
    la    t0,  func1
    jalr  ra,  0(t0)
jalr1_ra:                          # func1 returns here → fall through to Test 2

    #=========================================================
    # Test 2: JALR positive offset (+8), link in ra
    # Jumps to func2_mid, skipping func2_start (8-byte sentinel)
    # func2_mid verifies x11==0 to confirm func2_start was skipped
    #=========================================================
    li    x11, 0x00000000          # baseline: must be 0 when func2_mid is entered correctly
    la    t0,  func2_mid
    addi  t0,  t0,  -8             # t0 = func2_mid - 8 (= func2_start)
    jalr  ra,  8(t0)               # PC = (func2_mid-8)+8 = func2_mid, ra=jalr2_ra
jalr2_ra:                          # func2 returns here → fall through to Test 3

    #=========================================================
    # Test 3: JALR negative offset (-8), link in ra
    # la t0, func3_base+8 ; jalr ra, -8(t0)  →  PC=func3_base
    #=========================================================
    la    t0,  func3_base
    addi  t0,  t0,  8              # t0 = func3_base + 8
    jalr  ra,  -8(t0)              # PC = (func3_base+8)-8 = func3_base, ra=jalr3_ra
jalr3_ra:                          # func3 returns here → fall through to Test 4

    #=========================================================
    # Test 4: JALR rs1 == rd (same register)
    # The implementation must read rs1 (old value) BEFORE writing rd.
    # If rd is written first, rs1 gets the return address instead of
    # func4's address, and execution lands at the wrong location.
    # func4 sets x16=0xF5F5F5F5 so func5 can detect if it was skipped.
    #=========================================================
    la    ra,  func4               # ra = func4 address
    jalr  ra,  0(ra)               # PC = (old_ra) & ~1 = func4, ra = jalr4_ra
jalr4_ra:                          # func4 returns here → fall through to Test 5

    #=========================================================
    # Test 5: JALR link discarded (rd=x0)
    # func5 verifies x0==0 and all registers from previous funcs
    #=========================================================
    la    t0,  func5
    jalr  x0,  0(t0)               # PC=func5, x0 unchanged (hardwired 0)
    jal   x0,  test_fail           # never reached

    #=========================================================
    # Test 6: Shadow write tracking via ALU
    # JALR via t0 (shadow now tracks t0), then modify t0 with
    # ALU operations, then JALR via t0 again. The shadow must
    # have tracked the ALU write to produce the correct target.
    #=========================================================
test6_entry:
    la    t0,  func6a
    jalr  ra,  0(t0)               # shadow starts tracking t0
jalr6a_ra:
    # t0 is now stale (points to func6a). Update it via ALU.
    la    t0,  func6b              # ALU write to t0 → shadow must track this
    jalr  ra,  0(t0)               # shadow hit: must use updated t0 value
jalr6b_ra:

    #=========================================================
    # Test 7: Shadow miss then hit
    # JALR via t0, JALR via t1 (shadow miss → switch to t1),
    # JALR via t1 again (shadow hit → no stall)
    #=========================================================
    la    t0,  func7a
    jalr  ra,  0(t0)               # shadow now tracks t0
jalr7a_ra:
    la    t1,  func7b
    jalr  ra,  0(t1)               # shadow miss → switch to t1
jalr7b_ra:
    la    t1,  func7c
    jalr  ra,  0(t1)               # shadow hit on t1 (t1 updated via ALU, shadow tracked)
jalr7c_ra:

    #=========================================================
    # Test 8: Rapid shadow switching (4 different RS1 registers)
    # Each JALR forces a shadow miss and 1-cycle stall
    #=========================================================
    la    x6,  func8a
    jalr  ra,  0(x6)               # shadow switches to x6
jalr8a_ra:
    la    x7,  func8b
    jalr  ra,  0(x7)               # shadow miss → switch to x7
jalr8b_ra:
    la    x8,  func8c
    jalr  ra,  0(x8)               # shadow miss → switch to x8
jalr8c_ra:
    la    x9,  func8d
    jalr  ra,  0(x9)               # shadow miss → switch to x9
jalr8d_ra:

    #=========================================================
    # Test 9: Back-to-back shadow hits with ALU write tracking
    # 3 consecutive JALRs via same register (t0), with ALU
    # modifications to t0 between each. Shadow must track all
    # writes correctly.
    #=========================================================
    la    t0,  func9a
    jalr  ra,  0(t0)               # shadow tracks t0 (possible miss on first)
jalr9a_ra:
    la    t0,  func9b              # ALU write → shadow tracks
    jalr  ra,  0(t0)               # shadow hit
jalr9b_ra:
    la    t0,  func9c              # ALU write → shadow tracks
    jalr  ra,  0(t0)               # shadow hit
jalr9c_ra:

    #-------------------------------------------------
    # ALL TESTS PASSED
    #-------------------------------------------------
end_of_test_ok:
    li    x30, 0x00000000          # Clear error code
    li    x31, 0xDEADBEEF          # Success marker
    jal   x0,  end_of_test

test_fail:
    #-------------------------------------------------
    # TEST FAILED
    #-------------------------------------------------
    # x30 = error code 0x00TTCC
    # x11 = actual value, x28 = expected value
    li    x31, 0xBADC0DE0          # Failure marker
    jal   x0,  end_of_test

end_of_test:
    nop
    jal   x0,  end_of_test         # Infinite loop


    #=========================================================
    # func1: Test 1 target (zero offset)
    # Sets x9, x10 for func5 verification.
    #=========================================================
func1:
    li    x9,  0x5A5A5A5A
    li    x10, 0xA5A5A5A5
    # Check: ra (link) must equal jalr1_ra
    mv    x11, ra
    la    x28, jalr1_ra
    li    x30, 0x00000101
    bne   x11, x28, test_fail
    # Return to caller
    jalr  x0,  0(ra)
    jal   x0,  test_fail           # never reached


    #=========================================================
    # func2: Test 2 target (positive offset +8)
    #
    # func2_start is the 8-byte sentinel BEFORE func2_mid.
    # It must be exactly 8 bytes in both STD and COMP modes:
    #   li x11, 0xBAD11111 = lui x11,0xBAD11 + addi x11,x11,0x111
    #   addi imm = 0x111 = 273 > 31  →  never compresses to c.addi
    #   Total: 4 + 4 = 8 bytes always ✓
    # Sets x12 for func5 verification.
    #=========================================================
func2_start:
    li    x11, 0xBAD11111          # sentinel: x11≠0 if func2_start was entered (8 bytes, never compressed)

func2_mid:
    # Verify func2_start was skipped: x11 must still be 0
    li    x28, 0x00000000
    li    x30, 0x00000211
    bne   x11, x28, test_fail
    # Check: ra (link) must equal jalr2_ra
    li    x12, 0x0bad0c0d
    mv    x11, ra
    la    x28, jalr2_ra
    li    x30, 0x00000201
    bne   x11, x28, test_fail
    # Return to caller
    jalr  x0,  0(ra)
    jal   x0,  test_fail


    #=========================================================
    # func3: Test 3 target (negative offset -8)
    # Sets x13, x14 for func5 verification.
    #=========================================================
func3_base:
    li    x13, 0x0000ffff
    li    x14, 0xffff0000
    # Check: ra (link) must equal jalr3_ra
    mv    x11, ra
    la    x28, jalr3_ra
    li    x30, 0x00000301
    bne   x11, x28, test_fail
    # Return to caller
    jalr  x0,  0(ra)
    jal   x0,  test_fail


    #=========================================================
    # func4: Test 4 target (rs1 == rd same register)
    # ra must contain the RETURN address (jalr4_ra), not func4's address.
    # This verifies rs1 was read BEFORE rd was written.
    # Sets x16=0xF5F5F5F5 so func5 can verify func4 was actually entered.
    # (If the rs1==rd bug exists, execution skips func4 entirely and
    #  func5's check of x16 will catch it.)
    #=========================================================
func4:
    li    x16, 0xF5F5F5F5          # unique marker: proves func4 was entered
    # Check: ra (rd) must equal jalr4_ra, NOT func4's address
    mv    x11, ra
    la    x28, jalr4_ra
    li    x30, 0x00000401
    bne   x11, x28, test_fail
    # Return to caller
    jalr  x0,  0(ra)
    jal   x0,  test_fail


    #=========================================================
    # func5: Test 5 target (link discarded, rd=x0)
    # Verifies x0==0 (link not written) and all registers from
    # previous functions.  Jumps to end_of_test_ok on success.
    #=========================================================
func5:
    li    x15, 0xabcd1234
    # Verify x0 is still 0 (rd=x0, link must not be written)
    li    x28, 0x00000000
    li    x30, 0x00000501
    bne   x0,  x28, test_fail
    # Check x9 = 0x5A5A5A5A (set in func1)
    mv    x11, x9
    li    x28, 0x5A5A5A5A
    li    x30, 0x00000502
    bne   x11, x28, test_fail
    # Check x10 = 0xA5A5A5A5 (set in func1)
    mv    x11, x10
    li    x28, 0xA5A5A5A5
    li    x30, 0x00000503
    bne   x11, x28, test_fail
    # Check x12 = 0x0bad0c0d (set in func2)
    mv    x11, x12
    li    x28, 0x0bad0c0d
    li    x30, 0x00000504
    bne   x11, x28, test_fail
    # Check x13 = 0x0000ffff (set in func3)
    mv    x11, x13
    li    x28, 0x0000ffff
    li    x30, 0x00000505
    bne   x11, x28, test_fail
    # Check x14 = 0xffff0000 (set in func3)
    mv    x11, x14
    li    x28, 0xffff0000
    li    x30, 0x00000506
    bne   x11, x28, test_fail
    # Check x16 = 0xF5F5F5F5 (set in func4 — proves func4 was entered)
    mv    x11, x16
    li    x28, 0xF5F5F5F5
    li    x30, 0x00000507
    bne   x11, x28, test_fail
    # All checks passed → continue to shadow tests
    jal   x0,  test6_entry


    #=========================================================
    # func6a: Test 6 first target (shadow starts tracking t0)
    #=========================================================
func6a:
    mv    x11, ra
    la    x28, jalr6a_ra
    li    x30, 0x00000601
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

    #=========================================================
    # func6b: Test 6 second target (shadow must have tracked
    #         ALU write to t0)
    #=========================================================
func6b:
    mv    x11, ra
    la    x28, jalr6b_ra
    li    x30, 0x00000602
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

    #=========================================================
    # func7a: Test 7 first target (via t0)
    #=========================================================
func7a:
    mv    x11, ra
    la    x28, jalr7a_ra
    li    x30, 0x00000701
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

    #=========================================================
    # func7b: Test 7 second target (via t1, shadow miss)
    #=========================================================
func7b:
    mv    x11, ra
    la    x28, jalr7b_ra
    li    x30, 0x00000702
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

    #=========================================================
    # func7c: Test 7 third target (via t1 again, shadow hit)
    #=========================================================
func7c:
    mv    x11, ra
    la    x28, jalr7c_ra
    li    x30, 0x00000703
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

    #=========================================================
    # func8a-d: Test 8 targets (rapid shadow switching)
    #=========================================================
func8a:
    mv    x11, ra
    la    x28, jalr8a_ra
    li    x30, 0x00000801
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

func8b:
    mv    x11, ra
    la    x28, jalr8b_ra
    li    x30, 0x00000802
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

func8c:
    mv    x11, ra
    la    x28, jalr8c_ra
    li    x30, 0x00000803
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

func8d:
    mv    x11, ra
    la    x28, jalr8d_ra
    li    x30, 0x00000804
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

    #=========================================================
    # func9a-c: Test 9 targets (back-to-back hits with write tracking)
    #=========================================================
func9a:
    mv    x11, ra
    la    x28, jalr9a_ra
    li    x30, 0x00000901
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

func9b:
    mv    x11, ra
    la    x28, jalr9b_ra
    li    x30, 0x00000902
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail

func9c:
    mv    x11, ra
    la    x28, jalr9c_ra
    li    x30, 0x00000903
    bne   x11, x28, test_fail
    jalr  x0,  0(ra)
    jal   x0,  test_fail
