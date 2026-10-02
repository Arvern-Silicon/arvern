#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_zcb_illegal_nozbb
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZCB WITHOUT ZBB -> C.SEXT.B / C.ZEXT.H / C.SEXT.H ILLEGAL
#   Requires C_EXTENSION>=2 and B_EXTENSION==0. Unpriv §28.8: "c.sext.b is
#   only implemented if Zbb is implemented" (likewise c.zext.h, c.sext.h).
#   Without Zbb the three encodings must raise illegal-instruction and rd
#   must keep its prior value, while c.zext.b and c.not (Zcb-only) execute.
#   Encoded as .half because the assembler refuses the three without 'zbb'.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000, base register s2)
#
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x20: s0 after C.SEXT.B   (expect preserved)
#   0x30: s1 after C.ZEXT.H   (expect preserved)
#   0x40: a0 after C.SEXT.H   (expect preserved)
#   0x50: a1 after C.ZEXT.B   (expect executed)
#   0x60: a2 after C.NOT      (expect executed)
#=========================================================================

main:
    j _start

    .align 2
trap_handler:
    addi sp, sp, -16
    sw   s10,12(sp)
    sw   s11, 8(sp)

    # Increment trap_count
    lw   s10, 0x00(s2)
    addi s10, s10, 1
    sw   s10, 0x00(s2)

    # Save MCAUSE
    csrr s10, mcause
    sw   s10, 0x04(s2)

    # Advance MEPC past the faulting 16-bit instruction
    csrr s11, mepc
    addi s11, s11, 2
    csrw mepc, s11

    lw   s11, 8(sp)
    lw   s10,12(sp)
    addi sp, sp, 16
    mret


 _start:
    li   sp, 0x80010000
    li   s2, 0x80000000

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s2)
    sw   t0, 0x04(s2)
    sw   t0, 0x20(s2)
    sw   t0, 0x30(s2)
    sw   t0, 0x40(s2)
    sw   t0, 0x50(s2)
    sw   t0, 0x60(s2)

    # Install handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Smdbltrp boot rule: arm NMIE, then clear MDT.
    csrsi 0x744, 8
    csrw  mstatush, x0

    # rd seeds (rd' must be x8-x15)
    li   s0, 0xAAAAAA81        # C.SEXT.B seed (must be preserved)
    li   s1, 0xBBBB8002        # C.ZEXT.H seed (must be preserved)
    li   a0, 0xCCCC8003        # C.SEXT.H seed (must be preserved)
    li   a1, 0x123456F8        # C.ZEXT.B seed -> 0x000000F8
    li   a2, 0x0F0F0F0F        # C.NOT seed    -> 0xF0F0F0F0

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: C.SEXT.B s0   (0x9C65) -> ILLEGAL, s0 preserved
    #=================================================================
    .half 0x9C65                  # c.sext.b s0
    sw   s0, 0x20(s2)
    lw   s0, 0x20(s2)             # load-back to drain SW
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: C.ZEXT.H s1   (0x9CE9) -> ILLEGAL, s1 preserved
    #=================================================================
    .half 0x9CE9                  # c.zext.h s1
    sw   s1, 0x30(s2)
    lw   s1, 0x30(s2)
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: C.SEXT.H a0   (0x9D6D) -> ILLEGAL, a0 preserved
    #=================================================================
    .half 0x9D6D                  # c.sext.h a0
    sw   a0, 0x40(s2)
    lw   a0, 0x40(s2)
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: C.ZEXT.B a1   (0x9DE1) -> executes (Zcb only), no trap
    #=================================================================
    .half 0x9DE1                  # c.zext.b a1
    sw   a1, 0x50(s2)
    lw   a1, 0x50(s2)
    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: C.NOT a2      (0x9E75) -> executes (Zcb only), no trap
    #=================================================================
    .half 0x9E75                  # c.not a2
    sw   a2, 0x60(s2)
    lw   a2, 0x60(s2)

    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
