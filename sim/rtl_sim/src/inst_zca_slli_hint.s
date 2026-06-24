#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_slli_hint
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.SLLI rd=0  (RVC HINT space)
#   Per RISC-V Unprivileged ISA, all C.SLLI encodings with rd=0 are reserved
#   as HINTs that MUST execute as NOPs (not raise illegal-instruction).
#   Tests three rd=0 variants with shamt = 0, 1, 16:
#
#   C.SLLI x0, 0   = 0x0002
#   C.SLLI x0, 1   = 0x0006
#   C.SLLI x0, 16  = 0x0042
#
#   Any illegal-instruction trap on these is a spec violation.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count (must remain 0)
#   0x04: last MCAUSE (must remain 0)
#   0x08: progress marker advanced after each HINT
#=========================================================================

main:
    j _start

    .align 2
trap_handler:
    # Should never run. If it does, record MCAUSE and bail.
    addi sp, sp, -16
    sw   s10,12(sp)
    sw   s11, 8(sp)

    lw   s10, 0x00(s1)
    addi s10, s10, 1
    sw   s10, 0x00(s1)

    csrr s10, mcause
    sw   s10, 0x04(s1)

    # Advance MEPC past the 16-bit faulting compressed instruction.
    csrr s11, mepc
    addi s11, s11, 2
    csrw mepc, s11

    lw   s11, 8(sp)
    lw   s10,12(sp)
    addi sp, sp, 16
    mret


 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)

    la   t0, trap_handler
    csrw mtvec, t0

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: C.SLLI x0, 0  (the canonical SLLI HINT)
    #=================================================================
    .hword 0x0002                   # c.slli x0, 0
    li   t0, 1
    sw   t0, 0x08(s1)
    lw   t0, 0x08(s1)              # load-back drains SW under random SRAM wait states
    li   x31,0x22222222


    #=================================================================
    # PHASE 3: C.SLLI x0, 1  (non-zero shamt, rd still x0)
    #=================================================================
    .hword 0x0006                   # c.slli x0, 1
    li   t0, 2
    sw   t0, 0x08(s1)
    lw   t0, 0x08(s1)              # load-back drains SW under random SRAM wait states
    li   x31,0x33333333


    #=================================================================
    # PHASE 4: C.SLLI x0, 16 (shamt with bit[4] set)
    #=================================================================
    .hword 0x0042                   # c.slli x0, 16
    li   t0, 3
    sw   t0, 0x08(s1)
    lw   t0, 0x08(s1)              # load-back drains SW under random SRAM wait states
    li   x31,0xdeadbeef


end_of_test:
    j    end_of_test
