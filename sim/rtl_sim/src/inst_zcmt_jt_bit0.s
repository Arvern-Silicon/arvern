#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmt_jt_bit0
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.JT / CM.JALT through a table entry with bit 0 set
#
#   Unpriv Zcmt (cm.jt operation):   "j target_address[XLEN-1:0]&~0x1;"
#   Unpriv Zcmt (cm.jalt operation): "jal ra, target_address[XLEN-1:0]&~0x1;"
#   Bit 0 of the table entry is discarded: the jump lands on the even address
#   below it, raises no instruction-address-misaligned exception and executes
#   the instruction there.
#
#   Unpriv Zcmt: "The memory pointed to by jvt.base is treated as instruction
#   memory for the purpose of executing table jump instructions" -- the table
#   is written with stores, so a FENCE.I separates the stores from the jumps.
#
#   Four jumps, each to a label L with the table entry = L | 1:
#     1  cm.jt   0   L 4-byte aligned
#     2  cm.jt   1   L 2-byte aligned only (follows a C.NOP)
#     3  cm.jalt 32  L 4-byte aligned; ra = address of the cm.jalt + 2
#     4  cm.jalt 33  L 2-byte aligned only; ra = address of the cm.jalt + 2
#   Each landing site starts with an instruction that records the step in s2
#   (bit per step); the instruction after each cm.* sets a canary that must
#   never be seen.
#
#   Result registers:
#     s2 (x18)  steps landed, expect 0xF
#     s3 (x19)  error count, expect 0
#     s4 (x20)  first error code (0 = none)
#
#   jvt base 0x80000040 (entries 0/1 at +0/+4, 32/33 at +128/+132).
#----------------------------------------------------------------------------

.section .text
.global main

.equ JVT_BASE, 0x80000040

.macro FAIL code
    addi s3, s3, 1
    bnez s4, 99f
    li   s4, \code
99:
.endm

main:
    jal  t0, _random_irq_init
    li   t0, 0

    li   s2, 0
    li   s3, 0
    li   s4, 0
    li   x31, 0x11111111            # Sync: start

    li   t0, JVT_BASE
    csrw 0x017, t0

    la   t1, land1
    ori  t1, t1, 1
    sw   t1, 0(t0)
    la   t1, land2
    ori  t1, t1, 1
    sw   t1, 4(t0)
    la   t1, land3
    ori  t1, t1, 1
    sw   t1, 128(t0)
    la   t1, land4
    ori  t1, t1, 1
    sw   t1, 132(t0)
    fence.i

    # The alignment of each landing label is part of the stimulus.
    la   t1, land1
    andi t1, t1, 3
    beqz t1, 1f
    FAIL 0x01
1:  la   t1, land2
    andi t1, t1, 3
    li   t2, 2
    beq  t1, t2, 1f
    FAIL 0x02
1:  la   t1, land3
    andi t1, t1, 3
    beqz t1, 1f
    FAIL 0x03
1:  la   t1, land4
    andi t1, t1, 3
    li   t2, 2
    beq  t1, t2, 1f
    FAIL 0x04
1:

    #-------------------------------------------------
    # 1: cm.jt 0 -> land1 (4-byte aligned)
    #-------------------------------------------------
    li   a5, 0xCAFECAFE
    cm.jt 0
    li   a5, 0xBAD0BAD0
    FAIL 0x11
    j    step2

    .balign 4
land1:
    ori  s2, s2, 1
    li   t1, 0xCAFECAFE
    beq  a5, t1, step2
    FAIL 0x12

    #-------------------------------------------------
    # 2: cm.jt 1 -> land2 (2-byte aligned)
    #-------------------------------------------------
step2:
    li   a5, 0xCAFECAFE
    cm.jt 1
    li   a5, 0xBAD0BAD0
    FAIL 0x21
    j    step3

    .balign 4
    c.nop
land2:
    ori  s2, s2, 2
    li   t1, 0xCAFECAFE
    beq  a5, t1, step3
    FAIL 0x22

    #-------------------------------------------------
    # 3: cm.jalt 32 -> land3 (4-byte aligned), ra = site + 2
    #-------------------------------------------------
step3:
    li   a5, 0xCAFECAFE
    li   ra, 0
site3:
    cm.jalt 32
    li   a5, 0xBAD0BAD0
    FAIL 0x31
    j    step4

    .balign 4
land3:
    ori  s2, s2, 4
    li   t1, 0xCAFECAFE
    beq  a5, t1, 1f
    FAIL 0x32
1:  la   t1, site3
    addi t1, t1, 2
    beq  ra, t1, step4
    FAIL 0x33

    #-------------------------------------------------
    # 4: cm.jalt 33 -> land4 (2-byte aligned), ra = site + 2
    #-------------------------------------------------
step4:
    li   a5, 0xCAFECAFE
    li   ra, 0
site4:
    cm.jalt 33
    li   a5, 0xBAD0BAD0
    FAIL 0x41
    j    done

    .balign 4
    c.nop
land4:
    ori  s2, s2, 8
    li   t1, 0xCAFECAFE
    beq  a5, t1, 1f
    FAIL 0x42
1:  la   t1, site4
    addi t1, t1, 2
    beq  ra, t1, done
    FAIL 0x43

done:
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
