#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_csr_illegal_rd
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ILLEGAL CSR -> rd PRESERVE
#   Per RISC-V privileged spec: when a CSR access raises an illegal
#   instruction exception, neither the CSR nor the destination register
#   shall be written.
#
#   Phase 2: csrrw  t0, mvendorid, x0   (write to RO CSR, rd!=x0)
#   Phase 3: csrrs  t1, mvendorid, t6   (set on RO CSR with rs1!=x0)
#   Phase 4: csrrwi t2, mvendorid, 1    (immediate write to RO CSR)
#   Phase 5: csrrw  t3, 0x3A0, x0       (write to unimplemented CSR bank)
#
#   In each case the destination register must retain its pre-instruction
#   value after the illegal-instruction trap is taken and skipped.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#
# Phase 2: csrrw rd, mvendorid, x0
#   0x20: t0 value AFTER trap (expect pre-load 0xCAFEBABE)
#   0x24: MCAUSE (expect 2)
#
# Phase 3: csrrs rd, mvendorid, t6
#   0x30: t1 value AFTER trap (expect 0xC0FFEEEE)
#   0x34: MCAUSE (expect 2)
#
# Phase 4: csrrwi rd, mvendorid, 1
#   0x40: t2 value AFTER trap (expect 0xBADC0DE5)
#   0x44: MCAUSE (expect 2)
#
# Phase 5: csrrw rd, 0x3A0, x0
#   0x50: t3 value AFTER trap (expect 0xDEFACED0)
#   0x54: MCAUSE (expect 2)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    addi sp, sp, -16
    sw   t4, 12(sp)
    sw   t5,  8(sp)
    sw   t6,  4(sp)

    csrr t4, mcause
    csrr t5, mepc

    # Increment trap_count
    lw   t6, 0x00(s1)
    addi t6, t6, 1
    sw   t6, 0x00(s1)

    # Save MCAUSE / MEPC into working area
    sw   t4, 0x04(s1)
    sw   t5, 0x08(s1)

    # All faulting instructions in this test are 32-bit CSR ops, so
    # advance MEPC by 4 unconditionally.
    addi t5, t5, 4
    csrw mepc, t5

    lw   t6,  4(sp)
    lw   t5,  8(sp)
    lw   t4, 12(sp)
    addi sp, sp, 16
    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)

    #=================================================================
    # PHASE 1: Install trap handler, init callee-saved markers
    #=================================================================

    la   t0, trap_handler
    csrw mtvec, t0

    # Initialize callee-saved registers (must survive every trap)
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: csrrw rd, mvendorid, x0   (RO CSR + actual write)
    #          rd must retain its pre-instruction value.
    #=================================================================

    li   t0, 0xCAFEBABE
    # csrrw t0, mvendorid (0xF11), x0
    csrrw t0, 0xF11, x0

    # Capture t0 immediately into memory before any other use
    sw   t0, 0x20(s1)
    # Capture MCAUSE recorded by handler
    lw   t6, 0x04(s1)
    sw   t6, 0x24(s1)
    # Load-back forces the SW to drain on AHB before signalling the testbench
    lw   t6, 0x24(s1)

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: csrrs rd, mvendorid, t6   (RO CSR + non-zero rs1 -> write)
    #=================================================================

    li   t1, 0xC0FFEEEE
    li   t6, 0xFFFFFFFF             # non-zero rs1 -> a real write attempt
    # csrrs t1, mvendorid, t6
    csrrs t1, 0xF11, t6

    sw   t1, 0x30(s1)
    lw   t6, 0x04(s1)
    sw   t6, 0x34(s1)
    lw   t6, 0x34(s1)         # load-back to drain SW under wait states

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: csrrwi rd, mvendorid, 1   (immediate write to RO CSR)
    #=================================================================

    li   t2, 0xBADC0DE5
    # csrrwi t2, mvendorid, 1
    csrrwi t2, 0xF11, 1

    sw   t2, 0x40(s1)
    lw   t6, 0x04(s1)
    sw   t6, 0x44(s1)
    lw   t6, 0x44(s1)         # load-back to drain SW under wait states

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: csrrw rd, 0x3A0, x0       (unimplemented CSR bank)
    #          addr[11:6]=6'b001110 is not decoded by any bank -> trap.
    #=================================================================

    li   t3, 0xDEFACED0
    # csrrw t3, 0x3A0, x0
    csrrw t3, 0x3A0, x0

    sw   t3, 0x50(s1)
    lw   t6, 0x04(s1)
    sw   t6, 0x54(s1)
    lw   t6, 0x54(s1)         # load-back to drain SW under wait states

    li   x31, 0xdeadbeef


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test
