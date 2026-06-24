#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zbc_clmul
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CLMUL/CLMULH/CLMULR (Zbc)
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
   # a0..a2 -> temporary for multiplication results

   la   s0, test_values        # base of test values
   la   s1, 0x81000000         # base of results array
   li   s2, 16                 # number of test values (N)

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
   # Compute result record address (5 words per test, 20 bytes)
   # Index = (i * N) + j     ; Offset = Index * 5 * 4
   # No M-ext needed -- N=16 (line 52) ⇒ i*N == i<<4; *5 == (<<2)+self.
   # Keeps this Zbc test running across all M_EXTENSION configs.
   # -----------------------------------------------------------------
   slli t5, t0, 4              # t5 = i * 16  (N=16, hardcoded above)
   add  t5, t5, t1             # t5 = Index
   slli t4, t5, 2              # t4 = Index * 4
   add  t5, t5, t4             # t5 = Index*5  (shift-add: 5 = 4+1)
   slli t5, t5, 2              # t5 = Index * 20 (byte offset)
   add  t5, s1, t5             # t5 = Address of result record

   # Store Operand 1 (A) and Operand 2 (B)
   sw   t2, 0(t5)              # [0]: Operand 1
   sw   t3, 4(t5)              # [4]: Operand 2

   # CLMUL (Low 32 bits of carry-less product)
   clmul  a0, t2, t3
   sw   a0, 8(t5)              # [8]: CLMUL (bits [31:0])

   # CLMULH (High 32 bits of carry-less product)
   clmulh a1, t2, t3
   sw   a1, 12(t5)             # [12]: CLMULH (bits [63:32])

   # CLMULR (Reversed: bits [62:31] of carry-less product)
   clmulr a2, t2, t3
   sw   a2, 16(t5)             # [16]: CLMULR (bits [62:31])

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
   # Test values for carry-less multiplication
   .word 0x00000000   # 0
   .word 0x00000001   # 1
   .word 0xffffffff   # all ones
   .word 0x00000002   # 2
   .word 0x00000003   # 3
   .word 0x0000000f   # 15
   .word 0x80000000   # MSB set
   .word 0x12345678   # random pattern
   .word 0xaaaaaaaa   # alternating (10101010...)
   .word 0x55555555   # alternating (01010101...)
   .word 0xf0f0f0f0   # pattern
   .word 0x0f0f0f0f   # pattern (inverted)
   .word 0xdeadbeef   # mixed pattern
   .word 0x00000010   # 16
   .word 0x000000ff   # 255
   .word 0xabcdef01   # random
