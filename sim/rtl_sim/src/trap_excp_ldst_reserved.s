#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ldst_reserved
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: RESERVED LOAD/STORE FUNCT3 -> ILLEGAL
#   RISC-V Unprivileged ISA reserves several LOAD/STORE funct3 encodings on
#   RV32 (those are RV64-only or fully reserved). Each must raise an illegal-
#   instruction trap (MCAUSE=2). Pre-fix, id_std_opcode_error does not filter
#   funct3 inside LOAD/STORE opcodes, so the LSU consumes the raw bits and
#   emits AHB transactions with HSIZE=3'b011 (8-byte transfer on a 32-bit
#   master -- AMBA AHB protocol violation) or silently zero-extends LWU as
#   LW. No trap is taken.
#
#   The reproducer issues three reserved encodings in sequence; the trap
#   handler counts entries and advances MEPC by 4 to step over each one. The
#   testbench checks trap_count == 3 and each captured MCAUSE == 2.
#
#   Phase 2: LOAD funct3=011 (LD on RV64).         enc = 0x00053583 (lw-like)
#   Phase 3: LOAD funct3=110 (LWU on RV64).        enc = 0x00056583
#   Phase 4: STORE funct3=011 (SD on RV64).        enc = 0x00b53023
#
#   Pre-fix: trap_count = 0, AHB transactions emitted with illegal HSIZE.
#   Post-fix: trap_count = 3, MCAUSE = 2 each time, no AHB transaction.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    # Records mcause/mepc, increments trap_count, advances MEPC by 4 to
    # skip past the offending .word, returns.
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  8(sp)
    sw   t1,  4(sp)
    sw   t2,  0(sp)

    csrr t0, mcause
    csrr t1, mepc

    # Increment trap_count
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    # Save latest mcause / mepc
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)

    # Advance MEPC by 4 (each illegal encoding is a 32-bit .word)
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  0(sp)
    lw   t1,  4(sp)
    lw   t0,  8(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x8000F000           # safe SP inside 64KB SRAM
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Use x10 as the load/store base (point into SRAM scratchpad)
    li   x10, 0x80000020          # safe SRAM address

    li   x31, 0x11111111          # init done


    #=================================================================
    # PHASE 2: LOAD funct3=011 (RV64 LD encoding, reserved on RV32)
    #   Pre-fix: emits AHB read with HSIZE=011 (protocol violation), no trap.
    #   Post-fix: illegal-instruction trap.
    #=================================================================
    .word 0x00053583              # ld x11, 0(x10) -- reserved on RV32

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: LOAD funct3=110 (RV64 LWU encoding, reserved on RV32)
    #   Pre-fix: ex_size=010 (word), zero-extend -- silent RV64 behavior.
    #   Post-fix: illegal-instruction trap.
    #=================================================================
    .word 0x00056583              # lwu x11, 0(x10) -- reserved on RV32

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: STORE funct3=011 (RV64 SD encoding, reserved on RV32)
    #   Pre-fix: emits AHB write with HSIZE=011 (protocol violation), no trap.
    #   Post-fix: illegal-instruction trap.
    #=================================================================
    .word 0x00b53023              # sd x11, 0(x10) -- reserved on RV32

    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
