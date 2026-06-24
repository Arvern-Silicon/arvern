#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_branch_reserved
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: RESERVED BRANCH FUNCT3 -> ILLEGAL
#   RISC-V Unprivileged ISA: the BRANCH major opcode (0b1100011) defines
#   funct3 = 000(BEQ) 001(BNE) 100(BLT) 101(BGE) 110(BLTU) 111(BGEU).
#   funct3 = 010 and 011 are RESERVED and must raise an illegal-instruction
#   exception (mcause = 2).
#
#   The two reserved encodings are emitted with .word because the assembler
#   will not produce them. A correctly-encoded BEQ (taken) and BNE (taken)
#   are executed in the same test as positive controls: they must execute
#   normally and must NOT trap.
#
#   Reserved encodings (BRANCH op=1100011, rs1=x0 rs2=x2 imm=2; the
#   register/immediate fields are irrelevant -- the reserved funct3 alone
#   makes the encoding illegal):
#   P2: funct3=010  -> .word 0x00202063
#   P3: funct3=011  -> .word 0x00203063
#
#   Positive controls:
#   P4: real BEQ taken      (x5==x5)  -> path proves no trap
#   P5: real BNE taken      (x5!=x6)  -> path proves no trap
#   P6: real BEQ not taken  (x5!=x6)  -> fallthrough proves correctness
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: illegal_count   (number of mcause=2 traps)
#   0x04: other_count     (any non-illegal trap cause - must stay 0)
#   0x08: last MCAUSE
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #   mcause=2 -> illegal_count++ ; advance MEPC +4 (32-bit .word)
    #   else     -> other_count++   ; advance MEPC +4 (defensive)
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  8(sp)
    sw   t1,  4(sp)
    sw   t2,  0(sp)

    csrr t0, mcause
    csrr t1, mepc
    sw   t0, 0x08(s1)             # last MCAUSE

    li   t2, 2
    beq  t0, t2, hb_illegal

    lw   t2, 0x04(s1)
    addi t2, t2, 1
    sw   t2, 0x04(s1)
    j    hb_advance

hb_illegal:
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

hb_advance:
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  0(sp)
    lw   t1,  4(sp)
    lw   t0,  8(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x8000F000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Markers used by the positive-control branches / proof registers.
    li   x18, 0x00000000          # P4 BEQ-taken proof   (1 = correct path)
    li   x19, 0x00000000          # P5 BNE-taken proof
    li   x20, 0x00000000          # P6 BEQ-not-taken proof

    li   x31, 0x11111111          # init done


    #=================================================================
    # PHASE 2: BRANCH funct3=010 (reserved) -> illegal (mcause=2)
    #   .word 0x00202063  (= beq x1,x2,+0 with funct3 forced to 010)
    #=================================================================
    .word 0x00202063
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: BRANCH funct3=011 (reserved) -> illegal (mcause=2)
    #   .word 0x00203063  (= beq x1,x2,+0 with funct3 forced to 011)
    #=================================================================
    .word 0x00203063
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: POSITIVE CONTROL -- real BEQ, taken (x5 == x5)
    #          Must take the branch normally, no trap.
    #=================================================================
    li   x5, 0x12345678
    beq  x5, x5, p4_taken
    li   x18, 0xBADBAD04          # must be skipped
    j    p4_done
p4_taken:
    li   x18, 0x00000001          # proof: branch was taken (correct)
p4_done:
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: POSITIVE CONTROL -- real BNE, taken (x5 != x6)
    #=================================================================
    li   x5, 0x00000005
    li   x6, 0x00000006
    bne  x5, x6, p5_taken
    li   x19, 0xBADBAD05          # must be skipped
    j    p5_done
p5_taken:
    li   x19, 0x00000001          # proof: branch was taken (correct)
p5_done:
    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: POSITIVE CONTROL -- real BEQ, NOT taken (x5 != x6)
    #          Fallthrough path must run; branch must NOT be taken.
    #=================================================================
    li   x5, 0x00000005
    li   x6, 0x00000006
    beq  x5, x6, p6_wrong         # must NOT be taken
    li   x20, 0x00000001          # proof: fallthrough taken (correct)
    j    p6_done
p6_wrong:
    li   x20, 0xBADBAD06          # branch erroneously taken
p6_done:

    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
