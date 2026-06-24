#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_mv_add_hint
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.MV / C.ADD rd=0  (RVC HINT space)
#   Per RISC-V Unprivileged ISA, all C.MV / C.ADD encodings with rd=0 and
#   rs2!=0 are reserved as HINTs that MUST execute as NOPs (not raise
#   illegal-instruction).
#
#   C.MV  x0, x10  = 0x802A
#   C.MV  x0, x11  = 0x802E
#   C.ADD x0, x10  = 0x902A
#   C.ADD x0, x11  = 0x902E
#
#   a0/a1 (x10/x11) carry distinctive sentinel values before each HINT; the
#   testbench verifies x0 remains 0 (hardwired) and no trap fires.
#   (Avoid using x2/sp as the rs2 source — that would clobber sp and the
#   trap handler would push to a bogus address if any HINT erroneously trapped.)
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
    # Should never run. Record MCAUSE and bail.
    addi sp, sp, -16
    sw   s10, 12(sp)
    sw   s11,  8(sp)

    lw   s10, 0x00(s1)
    addi s10, s10, 1
    sw   s10, 0x00(s1)

    csrr s10, mcause
    sw   s10, 0x04(s1)

    # Advance MEPC past the 16-bit faulting compressed instruction.
    csrr s11, mepc
    addi s11, s11, 2
    csrw mepc, s11

    lw   s11,  8(sp)
    lw   s10, 12(sp)
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

    # Seed source registers with distinctive sentinel values (a0=x10, a1=x11)
    li   a0, 0xCAFEBABE
    li   a1, 0xDEADC0DE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: C.MV x0, x10
    #=================================================================
    .hword 0x802A                   # c.mv x0, x10
    li   t0, 1
    sw   t0, 0x08(s1)
    lw   t0, 0x08(s1)               # drain SW under random SRAM wait states
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: C.MV x0, x11
    #=================================================================
    .hword 0x802E                   # c.mv x0, x11
    li   t0, 2
    sw   t0, 0x08(s1)
    lw   t0, 0x08(s1)
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: C.ADD x0, x10
    #=================================================================
    .hword 0x902A                   # c.add x0, x10
    li   t0, 3
    sw   t0, 0x08(s1)
    lw   t0, 0x08(s1)
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: C.ADD x0, x11
    #=================================================================
    .hword 0x902E                   # c.add x0, x11
    li   t0, 4
    sw   t0, 0x08(s1)
    lw   t0, 0x08(s1)
    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test
