#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_system_reserved
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: RESERVED SYSTEM ENCODINGS -> ILLEGAL
#   RISC-V Unprivileged/Privileged ISA: the SYSTEM major opcode (0b1110011)
#   only defines a small set of encodings (ECALL, EBREAK, xRET, WFI, the
#   CSR* funct3 1..7 family). All other SYSTEM encodings are RESERVED and
#   must raise an illegal-instruction exception (mcause = 2).
#
#   This test issues a sequence of reserved SYSTEM words via .word (the
#   assembler will not emit them) and verifies each one traps with mcause=2.
#   It interleaves a clean ECALL (mcause=11) and a clean CSR access as
#   positive controls: those legal control instructions must NOT raise an
#   illegal-instruction trap.
#
#   Reserved encodings under test (opcode=0b1110011):
#   P2: funct3=100, all-zero fields              .word 0x00004073
#   P3: funct3=100, with rs1/rd set              .word 0x001F4073
#   P4: funct3=000 ECALL-shaped but rd != 0      .word 0x00000F73
#   (= imm=0 rs1=0 f3=0 rd=x30 op=SYSTEM ; NOT a canonical ECALL)
#   P5: funct3=000 ECALL-shaped but rs1 != 0     .word 0x000F0073
#   (= imm=0 rs1=x30 f3=0 rd=0 op=SYSTEM ; NOT a canonical ECALL)
#   P6: funct3=000 imm=1 (between ECALL/EBREAK)  .word 0x00100073
#   (imm12=0x001 is neither ECALL(0x000) nor EBREAK(0x001 is EBREAK!))
#   --> see note: 0x00100073 IS EBREAK. We instead use imm12=0x002
#   .word 0x00200073  (reserved SYSTEM, not ECALL/EBREAK/xRET/WFI)
#
#   Positive controls (must NOT trap illegal):
#   - a real ECALL  -> mcause=11 (environment call from M-mode)
#   - a real CSRRW  -> no trap
#
#   The trap handler counts illegal (mcause=2) traps and ECALL (mcause=11)
#   traps separately, advancing MEPC by 4 to step over the offending word.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: illegal_count   (number of mcause=2 traps)
#   0x04: ecall_count     (number of mcause=11 traps)
#   0x08: other_count     (any other unexpected trap cause)
#   0x0C: last MCAUSE
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #   mcause=2  -> illegal_count++ , advance MEPC +4
    #   mcause=11 -> ecall_count++   , advance MEPC +4
    #   else      -> other_count++   , advance MEPC +4 (defensive)
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  8(sp)
    sw   t1,  4(sp)
    sw   t2,  0(sp)

    csrr t0, mcause
    csrr t1, mepc

    # Save latest mcause
    sw   t0, 0x0C(s1)

    li   t2, 2
    beq  t0, t2, h_illegal
    li   t2, 11
    beq  t0, t2, h_ecall
    j    h_other

h_illegal:
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)
    j    h_advance

h_ecall:
    lw   t2, 0x04(s1)
    addi t2, t2, 1
    sw   t2, 0x04(s1)
    j    h_advance

h_other:
    lw   t2, 0x08(s1)
    addi t2, t2, 1
    sw   t2, 0x08(s1)
    j    h_advance

h_advance:
    # Every offending instruction here is a 32-bit word -> MEPC + 4
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  0(sp)
    lw   t1,  4(sp)
    lw   t0,  8(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x8000F000           # safe SP inside SRAM
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    li   x31, 0x11111111          # init done


    #=================================================================
    # PHASE 2: SYSTEM funct3=100 (reserved), all-zero rs1/rd/imm
    #   enc = imm12=0 rs1=0 funct3=100 rd=0 op=1110011 = 0x00004073
    #=================================================================
    .word 0x00004073
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: SYSTEM funct3=100 (reserved) with non-zero rs1/rd
    #   enc = imm12=0 rs1=x31 funct3=100 rd=x0 op=1110011 = 0x001F4073
    #   (still funct3=100 -> reserved regardless of other fields)
    #=================================================================
    .word 0x001F4073
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: ECALL-shaped (funct3=000, imm=0, rs1=0) but rd=x30
    #   Canonical ECALL requires rd=0 & rs1=0. rd!=0 -> NOT ECALL,
    #   reserved SYSTEM -> illegal instruction.
    #   enc = imm12=0 rs1=0 funct3=000 rd=x30 op=1110011 = 0x00000F73
    #=================================================================
    .word 0x00000F73
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: ECALL-shaped (funct3=000, imm=0, rd=0) but rs1=x30
    #   Canonical ECALL requires rs1=0. rs1!=0 -> NOT ECALL,
    #   reserved SYSTEM -> illegal instruction.
    #   enc = imm12=0 rs1=x30 funct3=000 rd=0 op=1110011 = 0x000F0073
    #=================================================================
    .word 0x000F0073
    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: SYSTEM funct3=000, imm12=0x002 (reserved)
    #   imm12=0x000 is ECALL, 0x001 is EBREAK. 0x002 is in the
    #   reserved SYSTEM PRIV space (not ECALL/EBREAK/xRET/WFI)
    #   enc = imm12=0x002 rs1=0 funct3=000 rd=0 op=1110011 = 0x00200073
    #=================================================================
    .word 0x00200073
    li   x31, 0x66666666


    #=================================================================
    # PHASE 7: POSITIVE CONTROL -- a real ECALL
    #   Must trap with mcause=11 (env call from M-mode), NOT illegal.
    #=================================================================
    ecall
    li   x31, 0x77777777


    #=================================================================
    # PHASE 8: POSITIVE CONTROL -- a real CSR access (legal SYSTEM)
    #   csrr/csrw to mscratch must NOT raise illegal-instruction.
    #=================================================================
    li   t0, 0x0BADF00D
    csrw mscratch, t0
    csrr t1, mscratch             # t1 should read back 0x0BADF00D
    sw   t1, 0x10(s1)             # park readback for testbench (slot 0x10)

    # Drain the SPAD store before raising the completion sentinel.
    # arvern is a simple in-order AHB core: this load's address phase
    # cannot start until the prior store's data phase has completed, so
    # once this lw retires the store at 0x10 is guaranteed globally
    # visible -- robust regardless of how many wait states -rwsram injects.
    # t2 is dead here (only used inside the trap handler, save/restored on
    # the stack) and is read by nothing afterwards.
    lw   t2, 0x10(s1)             # fence the rwsram-stretched store

    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
