#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_rv32i_waw_load_alu
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: write-after-write between a slow load and a younger writer
#   A load to x5 is followed (0, 1 or 2 NOPs later) by a younger instruction
#   that also writes x5. The older load's data phase may still be running
#   (wait states from -rwsram/-wssram/-rwsrom/-wsrom/-gahb/-fahb) when the
#   younger writer completes; the architectural result must nevertheless be
#   the younger value, and every consumer of x5 after the younger writer must
#   see the younger value.
#
#   Spec (Unpriv, RVWMO): "code running on a single hart appears to execute
#   in order from the perspective of other memory instructions in the same
#   hart" -- and the ISA defines each instruction's rd write in program order,
#   so the younger write to x5 is the one that survives.
#
#   63 rounds = 3 sources x 7 kinds x {0,1,2} NOPs, id = src*21 + kind*3 + nops
#     src 0: executable SRAM   0x80000800+id*4   (seeded K = 0x5A5A0000+id)
#     src 1: non-exec SRAM     0x81000000+id*4   (seeded K = 0x5A5A0000+id)
#     src 2: ROM word rom_k                      (K = 0xA5A5C3C3)
#
#     kind  younger sequence right behind  lw x5,0(a2) [+nops]
#     ----  ------------------------------------------------------------
#       0   addi x5,x0,1                                  x5=1
#       1   addi x5,x0,1 ; sw x5,0(a3)                    x5=1, DST=1
#       2   addi x5,x0,1 ; addi x6,x5,0x10               x5=1, x6=0x11
#       3   addi x5,x0,1 ; addi x5,x5,1                   x5=2
#       4   addi x5,x0,1 ; lw x7,0(a2) ; sw x5,0(a3)      x5=1, x7=K, DST=1
#       5   lui x5,%hi(DST) ; sw x6,%lo(DST)(x5) ;
#           lw x7,%lo(DST)(x5)                            x5=0x80000000,
#                                                         DST=x7=0x66600000+id
#       6   csrr x5, mscratch                             x5=0x8000FF00
#           (mscratch holds 0x8000FF00 outside the random-IRQ handler,
#            which _random_irq_init installs)
#
#   Before each round: x5=0xBAD50000+id, x6=0x66600000+id, x7=0x77700000+id,
#   DST[id]=0xDEAD0000+id. After a settle loop that does not touch x5..x7
#   (so the final reads are "later reads" of the registers):
#     0x80000100+id*4  RESA[id] = x5
#     0x80000200+id*4  RESB[id] = x6
#     0x80000300+id*4  RESC[id] = x7
#     0x80000400+id*4  DST[id]
#
#   Mode BOTH: in the COMP build the addi/nop encode as c.li/c.addi/c.nop,
#   which changes the dispatch spacing -- both spacings are wanted.
#----------------------------------------------------------------------------

.section .text
.global main

.equ SBASE,   0x80000000
.equ SRCX,    0x80000800
.equ SRCNX,   0x81000000
.equ DSTB,    0x80000400

main:
    jal  t0, _random_irq_init
    li   s0, SBASE
    j    _start

    .align 2
rom_k:
    .word 0xA5A5C3C3

.macro ROUND id, src, kind, nops
    #--- source address + seed ------------------------------------------
    .if \src == 0
    li   a2, SRCX + (\id)*4
    .elseif \src == 1
    li   a2, SRCNX + (\id)*4
    .else
    la   a2, rom_k
    .endif
    .if \src != 2
    li   t0, 0x5A5A0000 + (\id)
    sw   t0, 0(a2)
    lw   zero, 0(a2)                 # drain the seed store
    .endif
    li   a3, DSTB + (\id)*4
    li   t0, 0xDEAD0000 + (\id)
    sw   t0, 0(a3)
    lw   zero, 0(a3)                 # drain the DST sentinel
    li   x5, 0xBAD50000 + (\id)
    li   x6, 0x66600000 + (\id)
    li   x7, 0x77700000 + (\id)

    #--- the window under test ------------------------------------------
    lw   x5, 0(a2)                   # older, slow writer of x5
    .rept \nops
    nop
    .endr
    .if \kind == 0
    addi x5, x0, 1
    .elseif \kind == 1
    addi x5, x0, 1
    sw   x5, 0(a3)                   # must store 1
    .elseif \kind == 2
    addi x5, x0, 1
    addi x6, x5, 0x10                # must read 1
    .elseif \kind == 3
    addi x5, x0, 1
    addi x5, x5, 1                   # RAW on the younger value -> 2
    .elseif \kind == 4
    addi x5, x0, 1
    lw   x7, 0(a2)                   # keep the LSU busy behind it
    sw   x5, 0(a3)                   # must store 1
    .elseif \kind == 5
    lui  x5, %hi(DSTB + (\id)*4)     # x5 as an address base
    sw   x6, %lo(DSTB + (\id)*4)(x5)
    lw   x7, %lo(DSTB + (\id)*4)(x5)
    .else
    csrr x5, mscratch
    .endif

    #--- settle, then the later reads -----------------------------------
    li   a4, 20
1:  addi a4, a4, -1
    bnez a4, 1b
    sw   x5, 0x100 + (\id)*4(s0)
    sw   x6, 0x200 + (\id)*4(s0)
    sw   x7, 0x300 + (\id)*4(s0)
.endm

_start:
    li   x31, 0x11111111

    .irp s, 0, 1, 2
    .irp k, 0, 1, 2, 3, 4, 5, 6
    .irp n, 0, 1, 2
    ROUND (\s*21+\k*3+\n), \s, \k, \n
    .endr
    .endr
    .endr

    lw   zero, 0x100(s0)             # drain the last result stores
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
