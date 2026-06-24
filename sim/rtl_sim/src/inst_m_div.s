#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_m_div
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DIV, DIVU, REM, REMU
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0
    # Registers used:
    # s0 -> base address of test_values
    # s1 -> base address of results array
    # s2 -> N (number of test values)
    # t0 -> outer index i (dividend index)
    # t1 -> inner index j (divisor index)
    # t2 -> temporary for loaded dividend
    # t3 -> temporary for loaded divisor
    # t4 -> pointer arithmetic / temp
    # t5 -> temporary for storing results address
    # a0 -> temporary for quotient/remainder (not preserved across calls)
    # Note: we use only integer instructions; assembler pseudo-instructions (la/li) allowed.

    la   s0, test_values        # base of test values
    la   s1, 0x81000000         # base of results array
    li   s2, 24                 # number of test values

    li   t0, 0                  # outer index i = 0

outer_loop:
    bge  t0, s2, done_outer
    slli t4, t0, 2
    add  t4, s0, t4
    lw   t2, 0(t4)              # dividend

    li   t1, 0

inner_loop:
    bge  t1, s2, next_outer
    slli t4, t1, 2
    add  t4, s0, t4
    lw   t3, 0(t4)              # divisor

    # Compute result record address
    mul  t5, t0, s2
    add  t5, t5, t1
    li   t4, 6
    mul  t5, t5, t4
    slli t5, t5, 2
    add  t5, s1, t5

    # DIV
    div  a0, t2, t3
    sw   a0, 8(t5)
    # DIVU
    divu a1, t2, t3
    sw   a1, 12(t5)
    # REM
    rem  a2, t2, t3
    sw   a2, 16(t5)
    # REMU
    remu a3, t2, t3
    sw   a3, 20(t5)

    # store dividend and divisor
    sw   t2, 0(t5)
    sw   t3, 4(t5)

    addi t1, t1, 1
    j inner_loop

next_outer:
    addi t0, t0, 1
    j outer_loop

#-------------------------------------------------
# END OF TEST 
#-------------------------------------------------
done_outer:

 	li     x31,  0xdeadbeef

end_of_test:
	nop
    j end_of_test   # infinite loop

    .align 4
test_values:
    # Expanded test set: edges + randoms
    .word 0x00000000   # 0
    .word 0x00000001   # 1
    .word 0xffffffff   # -1
    .word 0x00000002   # 2
    .word 0xfffffffe   # -2
    .word 0x7fffffff   # INT32_MAX
    .word 0x80000000   # INT32_MIN
    .word 0x80000001   # INT32_MIN+1
    .word 0x12345678   # random
    .word 0x87654321   # random large
    .word 0x0000ffff   # small
    .word 0xffff0000   # negative pattern
    .word 0x40000000   # large positive power-of-two
    .word 0xc0000000   # large negative power-of-two
    .word 0x7f7f7f7f   # pattern
    .word 0x80808080   # pattern
    .word 0x13579bdf   # random odd pattern
    .word 0x2468ace0   # random even pattern
    .word 0x00007fff   # near 32k
    .word 0xffff8000   # near -32k
    .word 0x01010101   # small repetitive pattern
    .word 0xf0f0f0f0   # alternating pattern
    .word 0xdeadbeef   # classic test value
    .word 0xcafebabe   # classic test value

