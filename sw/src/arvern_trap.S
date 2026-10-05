#----------------------------------------------------------------------------
#          _    _           Family:    aRVern
#         / \__/ \          File:      arvern_trap.S
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Trap and RNMI entries: save the caller-saved registers, call the C
# dispatcher with the trap CSRs, write back the PC it returns, return.
# The RNMI entry switches to the private stack held in mnscratch.
#----------------------------------------------------------------------------

#ifdef __riscv_32e
#define FRAME 40
#define SAVE_EXTRA
#define LOAD_EXTRA
#else
#define FRAME 64
#define SAVE_EXTRA  sw a6, 40(sp); sw a7, 44(sp); sw t3, 48(sp); sw t4, 52(sp); sw t5, 56(sp); sw t6, 60(sp)
#define LOAD_EXTRA  lw a6, 40(sp); lw a7, 44(sp); lw t3, 48(sp); lw t4, 52(sp); lw t5, 56(sp); lw t6, 60(sp)
#endif

.macro SAVE_REGS
    addi sp, sp, -FRAME
    sw   ra,  0(sp)
    sw   t0,  4(sp)
    sw   t1,  8(sp)
    sw   t2, 12(sp)
    sw   a0, 16(sp)
    sw   a1, 20(sp)
    sw   a2, 24(sp)
    sw   a3, 28(sp)
    sw   a4, 32(sp)
    sw   a5, 36(sp)
    SAVE_EXTRA
.endm

.macro LOAD_REGS
    lw   ra,  0(sp)
    lw   t0,  4(sp)
    lw   t1,  8(sp)
    lw   t2, 12(sp)
    lw   a0, 16(sp)
    lw   a1, 20(sp)
    lw   a2, 24(sp)
    lw   a3, 28(sp)
    lw   a4, 32(sp)
    lw   a5, 36(sp)
    LOAD_EXTRA
    addi sp, sp, FRAME
.endm

    .section .text.arv_trap_entry, "ax"
    .balign 4
    .globl arv_trap_entry
arv_trap_entry:
    SAVE_REGS
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call arv_trap_dispatch          # a0 = PC to resume at
    csrw mepc, a0
    LOAD_REGS
    mret

    .section .text.arv_nmi_entry, "ax"
    .balign 4
    .globl arv_nmi_entry
arv_nmi_entry:
    csrrw sp, 0x740, sp             # sp <-> mnscratch: private RNMI stack
    SAVE_REGS
    csrr a0, 0x742                  # mncause
    csrr a1, 0x741                  # mnepc
    call arv_nmi_dispatch           # a0 = PC to resume at
    csrw 0x741, a0
    LOAD_REGS
    csrrw sp, 0x740, sp             # restore sp, mnscratch = RNMI stack again
    .word 0x70200073                # mnret
