#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_lui_addi16sp_reserved
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.LUI / C.ADDI16SP RESERVED nzimm=0
#   Per RISC-V Unprivileged spec §27.5.1 / §16.5, the encoded Q1 funct3=011
#   space (C.LUI / C.ADDI16SP) has FOUR truth-table cells:
#
#   | rd       | nzimm | Required behavior          |
#   |----------|-------|----------------------------|
#   | x0       | 0     | illegal (reserved)          |
#   | x2       | 0     | illegal (reserved)          |
#   | other    | 0     | illegal (reserved)          |
#   | x0       | !=0   | HINT (no trap, NOP)         |
#   | x2       | !=0   | C.ADDI16SP                  |
#   | other    | !=0   | C.LUI                       |
#
#   Three of the nzimm=0 rows are RESERVED and MUST raise illegal-inst.
#   The pre-fix predicate `(inst[12:2] != 11'h000)` includes the rd field
#   in the nzimm check, defeating the reservation for:
#   - rd=x2 nzimm=0 (encoding 16'h6101) — silently NOP'ed as addi sp,sp,0
#   - rd∉{x0,x2} nzimm=0 (e.g. 16'h6081) — silently lui rd,0
#
#   The (rd=x0, nzimm=0) case (encoding 16'h6001) traps INCIDENTALLY because
#   both rd and nzimm zero make the broken predicate evaluate to false.
#
#   TEST DISCRIMINATOR: each broken-cell encoding must raise mcause=2 with
#   mtval == the 16-bit encoding (or 0 — implementation-defined).
#
#   Pre-fix : C.ADDI16SP imm=0 and C.LUI rd!={0,2} imm=0 do NOT trap → FAIL.
#   Post-fix: every nzimm=0 cell traps with mcause=2 → PASS.
#
#   Positive controls (must continue to work post-fix):
#   c.lui x1, 5         → x1 = 0x00005000
#   c.addi16sp sp, 32   → sp += 32
#   c.lui x0, 5         → HINT (no trap, no architectural write)
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count
#   0x04: Phase 2 mcause   (C.ADDI16SP imm=0,    encoding 0x6101)
#   0x08: Phase 3 mcause   (C.LUI x1, imm=0,     encoding 0x6081)
#   0x0C: Phase 4 mcause   (C.LUI x31, imm=0,    encoding 0x6F81)
#   0x10: Phase 4b mcause  (C.LUI x0, imm=0,     encoding 0x6001 — Cell A0)
#   0x14: Phase 5 result   (positive: C.LUI x1, 5 → expect 0x00005000)
#   0x18: Phase 6 result   (positive: C.ADDI16SP sp,32 → captured sp delta)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER (M-mode direct)
    # Each Phase puts an expected slot index in s2 BEFORE executing
    # the trapping encoding. The handler reads mcause and writes it
    # to s1[s2], then advances mepc by 2 (all faulting insts are 16-bit).
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)
    sw   t3,  0(sp)

    csrr t0, mcause                # t0 = mcause
    csrr t1, mepc                  # t1 = mepc

    # Record mcause to slot at s1+s2
    add  t2, s1, s2
    sw   t0, 0(t2)

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Advance mepc by 2 (compressed instruction)
    addi t1, t1, 2
    csrw mepc, t1

    lw   t3,  0(sp)
    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x8000F000
    li   s1, 0x80000000           # scratchpad base

    # Zero scratchpad slots (use lui+addi avoiding any C.LUI imm=0)
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    li   x31, 0x11111111          # init complete

    #=================================================================
    # PHASE 2: C.ADDI16SP imm=0 (encoding 0x6101) must trap illegal
    #=================================================================
    li   s2, 0x04                  # Phase 2 slot
    .hword 0x6101                  # c.addi16sp sp, 0 (reserved)
    # Handler advances mepc by 2 — returns here
    li   x31, 0x22222222

    #=================================================================
    # PHASE 3: C.LUI x1, imm=0 (encoding 0x6081) must trap illegal
    #=================================================================
    li   s2, 0x08                  # Phase 3 slot
    li   x1, 0xCAFEBABE             # canary: if trap is missed, x1 gets 0
    .hword 0x6081                  # c.lui x1, 0 (reserved)
    li   x31, 0x33333333

    #=================================================================
    # PHASE 4: C.LUI x31 ... wait, we use x31 as sentinel; pick x5 instead
    # PHASE 4: C.LUI x5, imm=0 (encoding 0x6281) must trap illegal
    #=================================================================
    li   s2, 0x0C                  # Phase 4 slot
    li   x5, 0xDEAD0000            # canary
    .hword 0x6281                  # c.lui x5, 0 (reserved)
    li   x31, 0x44444444

    #=================================================================
    # PHASE 4b: C.LUI x0, imm=0 (encoding 0x6001) — Cell A0 (always-trapped)
    #=================================================================
    li   s2, 0x10                  # Phase 4b slot
    .hword 0x6001                  # c.lui x0, 0 (reserved — Cell A0)
    li   x31, 0x55555555

    # Positive C.LUI / C.ADDI16SP execution (rd∈{x0,x2}∪rest, nzimm≠0) is
    # already covered by inst_zca_lui.{s,v} and inst_zca_addi16sp.{s,v} —
    # not duplicated here.

end_of_test:
    j    end_of_test
