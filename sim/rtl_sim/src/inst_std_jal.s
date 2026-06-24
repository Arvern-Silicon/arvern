#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_jal
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: JAL
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0
    li    x1,  0x12345678

    # JAL 1: forward jump to label2, link in x11
    jal   x11, label2
jal1_ra:                           # rd expected value = address of this label
    jal   x0, test_fail                # never reached (label2 jumps to label3)


    # ------------------------------------------------------------------
    # label3 is physically before label2 → jal x14,label3 is backward
    # ------------------------------------------------------------------

label3:
    li    x2,  0xdeadbeef
    # Check JAL 2: x14 must equal address of jal2_ra
    la    x28, jal2_ra
    li    x30, 0x00000201
    bne   x14, x28, test_fail
    # JAL 3: forward jump to label4, link in x12
    jal   x12, label4
jal3_ra:
    jal   x0, test_fail


label7:
    li    x3,  0x10000010
    # Check JAL 6: x15 must equal address of jal6_ra
    la    x28, jal6_ra
    li    x30, 0x00000601
    bne   x15, x28, test_fail
    # JAL 7: forward jump to label8, link in x13
    jal   x13, label8
jal7_ra:
    jal   x0, test_fail


label2:
    li    x4,  0xabcd1234
    # Check JAL 1: x11 must equal address of jal1_ra
    la    x28, jal1_ra
    li    x30, 0x00000101
    bne   x11, x28, test_fail
    # JAL 2: backward jump to label3, link in x14
    jal   x14, label3
jal2_ra:
    jal   x0, test_fail


label6:
    li    x5,  0x0bad0c0d
    # Check JAL 5: x16 must equal address of jal5_ra
    la    x28, jal5_ra
    li    x30, 0x00000501
    bne   x16, x28, test_fail
    # JAL 6: backward jump to label7, link in x15
    jal   x15, label7
jal6_ra:
    jal   x0, test_fail


label5:
    li    x6,  0x0000ffff
    # Check JAL 4: x17 must equal address of jal4_ra
    la    x28, jal4_ra
    li    x30, 0x00000401
    bne   x17, x28, test_fail
    # JAL 5: backward jump to label6, link in x16
    jal   x16, label6
jal5_ra:
    jal   x0, test_fail


label4:
    li    x7,  0xffff0000
    # Check JAL 3: x12 must equal address of jal3_ra
    la    x28, jal3_ra
    li    x30, 0x00000301
    bne   x12, x28, test_fail
    # JAL 4: backward jump to label5, link in x17
    jal   x17, label5
jal4_ra:
    jal   x0, test_fail


label8:
    li    x8,  0x11111222
    # Check JAL 7: x13 must equal address of jal7_ra
    la    x28, jal7_ra
    li    x30, 0x00000701
    bne   x13, x28, test_fail

    # Sanity: x11 (JAL 1 link) must still be intact
    la    x28, jal1_ra
    li    x30, 0x00000702
    bne   x11, x28, test_fail

    # JAL 8: forward jump to end, link discarded (x0 always 0)
    jal   x0,  end_of_test_ok
jal8_ra:
    jal   x0, test_fail


    #-------------------------------------------------
    # ALL TESTS PASSED
    #-------------------------------------------------
end_of_test_ok:
    # JAL 8 check: jal x0 must not write x0 (hardwired to 0)
    li    x28, 0x00000000
    li    x30, 0x00000801
    bne   x0,  x28, test_fail
    li    x30, 0x00000000              # Clear error code
    li    x31, 0xDEADBEEF              # Success marker
    jal   x0, end_of_test


test_fail:
    #-------------------------------------------------
    # TEST FAILED
    #-------------------------------------------------
    # x30 = error code 0x00TTCC
    # x28 = expected link address
    li    x31, 0xBADC0DE0              # Failure marker
    jal   x0, end_of_test


end_of_test:
    nop
    jal   x0, end_of_test                  # Infinite loop
