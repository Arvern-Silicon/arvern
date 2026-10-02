#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmt_jvt_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: jvt base walk -- CM.JT through tables at many 64-byte bases
#
#   Unpriv Zcmt (jvt): "The value in the BASE field must always be aligned on
#   a 64-byte boundary. [...] the lower six bits of base are filled with
#   zeroes to obtain an XLEN-bit jump-table base address jvt.base".
#   Unpriv Zcmt (cm.jt): "table_address[XLEN-1:0] = jvt.base + (index<<2);
#   target_address = InstMemory[table_address]; j target_address&~0x1".
#   doc/arvern_instructions.md (jvt): "BASE[31:6] writable (64-byte aligned),
#   MODE[5:0] read-only 0".
#
#   Bases walk the address bits of executable SRAM (0x8000_0000, 64 KB):
#     walking ones   0x80000000 | (1<<k),        k = 6..15, index = k
#     walking zeros  0x80007FC0 & ~(1<<k),       k = 6..14, index = k + 16
#   (the 0x8000_FF00+ handler area and the 0x8000A000 result area are never a
#   table slot). Per step:
#     - jvt written with base | 0x3F, read back: expect base (MODE is 0)
#     - one table entry at base + 4*index written with the step's landing
#       label, FENCE.I (the table is instruction memory), cm.jt index
#     - the landing site checks the canary and counts the step
#
#   Result registers:
#     s2 (x18)  steps landed, expect 19
#     s3 (x19)  error count, expect 0
#     s4 (x20)  first error code (0 = none)
#   Scratchpad 0x8000A000 + 4*step: jvt read-back per step
#----------------------------------------------------------------------------

.section .text
.global main

.equ RES_BASE, 0x8000A000

.macro FAIL code
    addi s3, s3, 1
    bnez s4, 99f
    li   s4, \code
99:
.endm

.macro JVT_STEP step, base, idx
    li   t0, (\base) | 0x3F
    csrw 0x017, t0
    csrr t1, 0x017
    sw   t1, (\step) * 4(s5)
    li   t2, \base
    beq  t1, t2, 1f
    FAIL (0x100 | \step)
1:  la   t1, 2f
    li   t0, (\base) + (\idx) * 4
    sw   t1, 0(t0)
    fence.i
    li   a5, 0xCAFECAFE
    cm.jt \idx
    li   a5, 0xBAD0BAD0
    FAIL (0x200 | \step)
    j    3f
    .balign 4
2:  addi s2, s2, 1
    li   t1, 0xCAFECAFE
    beq  a5, t1, 3f
    FAIL (0x300 | \step)
3:
.endm

main:
    jal  t0, _random_irq_init
    li   t0, 0

    li   s2, 0
    li   s3, 0
    li   s4, 0
    li   s5, RES_BASE
    li   x31, 0x11111111            # Sync: start

    # Walking ones
    JVT_STEP  0, 0x80000040,  6
    JVT_STEP  1, 0x80000080,  7
    JVT_STEP  2, 0x80000100,  8
    JVT_STEP  3, 0x80000200,  9
    JVT_STEP  4, 0x80000400, 10
    JVT_STEP  5, 0x80000800, 11
    JVT_STEP  6, 0x80001000, 12
    JVT_STEP  7, 0x80002000, 13
    JVT_STEP  8, 0x80004000, 14
    JVT_STEP  9, 0x80008000, 15
    # Walking zeros below 0x80007FC0
    JVT_STEP 10, 0x80007F80, 22
    JVT_STEP 11, 0x80007F40, 23
    JVT_STEP 12, 0x80007EC0, 24
    JVT_STEP 13, 0x80007DC0, 25
    JVT_STEP 14, 0x80007BC0, 26
    JVT_STEP 15, 0x800077C0, 27
    JVT_STEP 16, 0x80006FC0, 28
    JVT_STEP 17, 0x80005FC0, 29
    JVT_STEP 18, 0x80003FC0, 30

    lw   zero, 18 * 4(s5)
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
