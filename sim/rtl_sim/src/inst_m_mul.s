#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_m_mul
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MUL/MULH/MULHSU/MULHU
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0
   # Registers used:
   # s0 -> base address of test_values
   # s1 -> base address of results array (0x81000000)
   # s2 -> N (number of test values)
   # t0 -> outer index i (Operand 1 index)
   # t1 -> inner index j (Operand 2 index)
   # t2 -> temporary for loaded Operand 1 (A)
   # t3 -> temporary for loaded Operand 2 (B)
   # t4 -> pointer arithmetic / word count temp
   # t5 -> temporary for storing results address
   # a0..a3 -> temporary for multiplication results (not preserved across calls)
   # Note: we use only integer instructions; assembler pseudo-instructions (la/li) allowed.
   
   la   s0, test_values        # base of test values
   la   s1, 0x81000000         # base of results array
   li   s2, 24                 # number of test values (N)
   
   li   t0, 0                  # outer index i = 0
   
outer_loop:
   bge  t0, s2, done_outer
   slli t4, t0, 2
   add  t4, s0, t4
   lw   t2, 0(t4)              # Load Operand 1 (A)
   
   li   t1, 0

inner_loop:
   bge  t1, s2, next_outer
   slli t4, t1, 2
   add  t4, s0, t4
   lw   t3, 0(t4)              # Load Operand 2 (B)

   # -----------------------------------------------------------------
   # Compute result record address (6 words per test, 24 bytes)
   # Index = (i * N) + j
   # Offset = Index * 6 * 4
   # -----------------------------------------------------------------
   mul  t5, t0, s2             # t5 = i * N
   add  t5, t5, t1             # t5 = Index
   li   t4, 6                  # t4 = 6 words per record
   mul  t5, t5, t4             # t5 = Index * 6 (word offset)
   slli t5, t5, 2              # t5 = Index * 24 (byte offset)
   add  t5, s1, t5             # t5 = Address of result record
   
   # Store Operand 1 (A) and Operand 2 (B)
   sw   t2, 0(t5)              # [0]: Operand 1
   sw   t3, 4(t5)              # [4]: Operand 2
   
   # MUL (Low 32 bits of Signed * Signed product)
   mul  a0, t2, t3
   sw   a0, 8(t5)              # [8]: MUL (Result[31:0])
   
   # MULH (High 32 bits of Signed * Signed product)
   mulh a1, t2, t3
   sw   a1, 12(t5)             # [12]: MULH (Result[63:32])
   
   # MULHSU (High 32 bits of Signed * Unsigned product)
   mulhsu a2, t2, t3
   sw   a2, 16(t5)             # [16]: MULHSU (Result[63:32])
   
   # MULHU (High 32 bits of Unsigned * Unsigned product)
   mulhu a3, t2, t3
   sw   a3, 20(t5)             # [20]: MULHU (Result[63:32])

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
   # Expanded test set: edges + randoms (24 values total)
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