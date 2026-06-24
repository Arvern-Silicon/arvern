#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_rv32e_basic
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: RV32E BASIC (TEMPLATE)
#   RV32E SANITY TEST + REUSABLE TEMPLATE for all future RV32E tests.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000, 64 words total)
#   Load/store round-trip area lives at byte offsets 0x80..0x9C
#     0x80: word  scratch
#     0x84: byte  scratch
#     0x88: half  scratch
#     0x8C: word  scratch (sign tests)
#=========================================================================

main:
    jal  t0, _random_irq_init
    li   t0, 0

    #-------------------------------------------------
    # Initialize x1..x14 to a known value (x15=a5 is
    # the sync sentinel, x0 is hard zero -> not init'd)
    #-------------------------------------------------
    li   x1,  0xFFFFFFFF
    li   x2,  0xFFFFFFFF
    li   x3,  0xFFFFFFFF
    li   x4,  0xFFFFFFFF
    li   x5,  0xFFFFFFFF
    li   x6,  0xFFFFFFFF
    li   x7,  0xFFFFFFFF
    li   x8,  0xFFFFFFFF
    li   x9,  0xFFFFFFFF
    li   x10, 0xFFFFFFFF
    li   x11, 0xFFFFFFFF
    li   x12, 0xFFFFFFFF
    li   x13, 0xFFFFFFFF
    li   x14, 0xFFFFFFFF

    li   x15, 0xFFFFFFFF        # <-- SYNC 0: init done


    #=================================================================
    # CHECKPOINT 1: ALU reg-imm and reg-reg
    #=================================================================
    li    x1, 100
    addi  x2, x1, 23            # x2  = 123          (0x0000007B)
    li    x3, 0x000000F0
    li    x4, 0x0000000F
    add   x5, x3, x4            # x5  = 0x000000FF
    sub   x6, x3, x4            # x6  = 0x000000E1
    and   x7, x3, x4            # x7  = 0x00000000
    or    x8, x3, x4            # x8  = 0x000000FF
    xor   x9, x3, x4            # x9  = 0x000000FF
    li    x10, 1
    li    x11, 4
    sll   x12, x10, x11         # x12 = 16           (0x00000010)
    li    x13, 0x80000000
    srl   x14, x13, x11         # x14 = 0x08000000

    li    x15, 0x11111111       # <-- SYNC 1


    #=================================================================
    # CHECKPOINT 2: more ALU (sra, slt, sltu), lui, auipc
    #=================================================================
    li    x1, -16              # 0xFFFFFFF0
    li    x2, 2
    sra   x3, x1, x2           # x3  = 0xFFFFFFFC  (arith >>2 of -16 = -4)
    li    x4, -5
    li    x5, 3
    slt   x6, x4, x5           # x6  = 1   (signed: -5 < 3)
    sltu  x7, x4, x5           # x7  = 0   (unsigned: huge >= 3)
    slti  x8, x4, 0            # x8  = 1   (signed: -5 < 0)
    sltiu x9, x5, 10           # x9  = 1   (unsigned: 3 < 10)

    lui   x10, 0xABCDE         # x10 = 0xABCDE000

    # auipc: x11 = pc_of_this_auipc + 0  -> capture and verify it is
    # an even, in-ROM address by deriving a relative delta below.
1:  auipc x11, 0               # x11 = address of label 1 (PC-relative)
    la    x12, 1b              # x12 = same address via la
    sub   x13, x11, x12        # x13 = 0  if auipc base == label addr

    li    x15, 0x22222222      # <-- SYNC 2


    #=================================================================
    # CHECKPOINT 3: load/store round-trips (byte/half/word)
    #=================================================================
    li    s1, 0x80000000       # x9  = scratchpad base

    # word round-trip
    li    t0, 0xDEADBEEF
    sw    t0, 0x80(s1)
    lw    x1, 0x80(s1)         # x1 = 0xDEADBEEF

    # byte store + sign/zero extend loads
    li    t0, 0x000000F5       # store byte 0xF5
    sb    t0, 0x84(s1)
    lb    x2, 0x84(s1)         # x2 = 0xFFFFFFF5 (sign-extended)
    lbu   x3, 0x84(s1)         # x3 = 0x000000F5 (zero-extended)

    # half store + sign/zero extend loads
    li    t0, 0x00008123       # store half 0x8123
    sh    t0, 0x88(s1)
    lh    x4, 0x88(s1)         # x4 = 0xFFFF8123 (sign-extended)
    lhu   x5, 0x88(s1)         # x5 = 0x00008123 (zero-extended)

    # word store of a positive value, read back.
    # Use a4(x14) for the store data -- t0 is x5, which holds the
    # lhu result (0x8123) that SYNC 3 checks; must not clobber it.
    # a4 is only asserted by the .v at SYNC 0 / SYNC 1, free to reuse.
    li    a4, 0x01020304
    sw    a4, 0x8C(s1)
    lw    x6, 0x8C(s1)         # x6 = 0x01020304

    li    x15, 0x33333333      # <-- SYNC 3


    #=================================================================
    # CHECKPOINT 4 (misa): RV32E base-ISA identity bits in misa @0x301
    #
    # Spec (RISC-V Privileged, misa CSR, MRW, M-mode readable):
    #   misa[31:30] = MXL (machine XLEN); 2'b01 => 32-bit (RV32) hart.
    #   misa[8]     = I bit  ("RV32I base ISA present").
    #   misa[4]     = E bit  ("RV32E base ISA present").
    #   I and E are MUTUALLY EXCLUSIVE: an RV32E hart sets E=1, I=0.
    #
    # This build is RV32E (RV32E_EN=1), so the RV32E_EN-deterministic
    # bits are:  bit31=0, bit30=1 (MXL=01),  bit8=0 (I clear),
    #            bit4=1 (E set).  All OTHER misa bits (M/C/B/F/...) are
    # extension-param dependent and MUST NOT be asserted -- isolate
    # ONLY {31,30,8,4} with a mask so the test is config-stable.
    #
    # Derivation of the expected masked value:
    #   mask  = (1<<31)|(1<<30)|(1<<8)|(1<<4)
    #         = 0x80000000 | 0x40000000 | 0x00000100 | 0x00000010
    #         = 0xC0000110
    #   value = (misa & mask):
    #             bit31 = 0           -> 0x00000000
    #             bit30 = 1 (MXL=01)  -> 0x40000000
    #             bit8  = 0 (I clear) -> 0x00000000
    #             bit4  = 1 (E set)   -> 0x00000010
    #         => expected = 0x40000010
    #
    # WRITE-ONCE / NO-COLLISION:
    #   Result register = x11 (a1). x11 is sampled by the .v ONLY at
    #   SYNC 0 (init value 0xFFFFFFFF) -- it is NOT sampled at SYNC 1,
    #   2, 3, or FINAL. We give x11 exactly ONE write of its final
    #   checked value here (the AND result); the csrr lands in scratch
    #   x1, not in x11.  The post-checkpoint branch / jal / jalr
    #   section never writes x11 (it touches only x1,x2,x3,x4,x5,x6,
    #   x7,x10,x14), so x11 is stable from this write through the
    #   SYNC-4 sample.  Scratch reg x1 (ra) is intentionally
    #   clobberable -- the .v explicitly does NOT check x1 at FINAL
    #   (it is destroyed by the jal/jalr link path), and jal_target
    #   re-clobbers x1 shortly after this checkpoint.  x15 (a5) is
    #   never touched here.
    #=================================================================
    csrr  x1,  misa            # x1 (scratch) = raw misa
    li    x11, 0xC0000110      # mask = bits {31,30,8,4}
    and   x11, x11, x1         # x11 = misa & mask  (single write -> 0x40000010)

    li    x15, 0x44444444      # <-- SYNC 4: misa


    #=================================================================
    # CHECKPOINT 5: branches (taken + not-taken) and jal/jalr
    #
    # a0(x10) accumulates a distinct bit per branch that behaves
    # correctly. Bit values are loaded into a4 (x14) via li (avoids
    # the signed 12-bit immediate limit that would break
    # ori ...,0x800) and added into a0 -- all bits distinct so
    # add == or. a0 is used (not x1) so the jal/jalr sequence below
    # can exercise the canonical ra(x1) link without destroying it.
    # Final expected a0 = 0x00000FFF (12 checks: 6 conditions x
    # {taken, not-taken}). Compare operands t0=5,t1=7,t2=5 throughout.
    #=================================================================
    li    a0, 0                # result accumulator (x10)
    li    t0, 5
    li    t1, 7
    li    t2, 5

    # beq  (taken: t0==t2)
    beq   t0, t2, 1f
    j     2f
1:  li    a4, 0x001
    add   a0, a0, a4
2:
    # beq  (not-taken: t0!=t1)
    beq   t0, t1, 3f
    li    a4, 0x002
    add   a0, a0, a4
3:
    # bne  (taken: t0!=t1)
    bne   t0, t1, 4f
    j     5f
4:  li    a4, 0x004
    add   a0, a0, a4
5:
    # bne  (not-taken: t0==t2)
    bne   t0, t2, 6f
    li    a4, 0x008
    add   a0, a0, a4
6:
    # blt  (taken: 5 < 7 signed)
    blt   t0, t1, 7f
    j     8f
7:  li    a4, 0x010
    add   a0, a0, a4
8:
    # blt  (not-taken: 7 < 5 false)
    blt   t1, t0, 9f
    li    a4, 0x020
    add   a0, a0, a4
9:
    # bge  (taken: 7 >= 5 signed)
    bge   t1, t0, 10f
    j     11f
10: li    a4, 0x040
    add   a0, a0, a4
11:
    # bge  (not-taken: 5 >= 7 false)
    bge   t0, t1, 12f
    li    a4, 0x080
    add   a0, a0, a4
12:
    # bltu (taken: 5 < 7 unsigned)
    bltu  t0, t1, 13f
    j     14f
13: li    a4, 0x100
    add   a0, a0, a4
14:
    # bltu (not-taken: 7 < 5 unsigned false)
    bltu  t1, t0, 15f
    li    a4, 0x200
    add   a0, a0, a4
15:
    # bgeu (taken: 7 >= 5 unsigned)
    bgeu  t1, t0, 16f
    j     17f
16: li    a4, 0x400
    add   a0, a0, a4
17:
    # bgeu (not-taken: 5 >= 7 unsigned false)
    bgeu  t0, t1, 18f
    li    a4, 0x800
    add   a0, a0, a4
18:

    #-------------------------------------------------
    # jal / jalr control flow (uses ra(x1) link; a0
    # holds the branch result and must NOT be touched here)
    #-------------------------------------------------
    li    x2, 0                # will be set non-zero by the routine
    jal   x1, jal_target       # link in ra(x1); should skip "bad" code
    li    x2, 0xBADBAD         # MUST be skipped (jal_target jumps back)
    j     after_jal

jal_target:
    # ra (x1) holds return address of the instruction after the jal.
    # Set a marker, then jalr back through ra.
    li    x3, 0x600D600D       # x3 = good marker
    jalr  x0, x1, 0            # return to "li x2,0xBADBAD" (executes it)

after_jal:
    # x2 ended at 0xBADBAD (jalr returned into it), x3 = 0x600D600D.
    # Use jalr forward-jump to a clean landing that fixes x2.
    la    t0, jalr_land
    jalr  x4, t0, 0            # x4 = return addr (unused), jump to land
    li    x2, 0xDEADDEAD       # MUST be skipped

jalr_land:
    li    x2, 0x0000600D       # final clean value proving jalr landed here

    li    x15, 0xdeadbeef      # <-- FINAL SYNC


end_of_test:
    nop
    j end_of_test              # infinite loop (testbench ends simulation)
