#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_m_dbltrp_divert_causes
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Smdbltrp divert to the RNMI handler, one case per cause
#
#   Priv §8.3 (Smrnmi mncause): "If the reason is an exception within M-mode
#   that results in a double trap as specified in the Smdbltrp extension, bit
#   MXLEN-1 is set to 0 and the least-significant bits are set to the cause
#   code corresponding to the exception that precipitated the double trap."
#   traps_and_interrupts.md §10 "Where a double trap goes", NMIE=1: "Diverted
#   to the RNMI handler. mnepc and mncause take the values mepc/mcause would
#   have taken, mnstatus.MNPP reads M and NMIE clears. ... The M trap stack is
#   left untouched".
#   traps_and_interrupts.md §10: "A write that sets MDT clears mstatus.MIE" --
#   MDT is software-settable, so a trap after `csrs mstatush, MDT` is a
#   double trap exactly like one taken inside a handler.
#   traps_and_interrupts.md §6: "A locked rule (pmpcfg.L) binds M-mode too,
#   so M-mode can fault on its own rules."
#
#   Precipitating causes: 11 (ecall), 2 (illegal), 3 (ebreak), and with
#   PMP_NR > 0: 5 (load) and 7 (store) against locked entry 0 (NAPOT 64 B at
#   0x80004000, L=1, no R/W/X).
#
#   Path A (cases 0-4): MDT set by `csrs mstatush` in main code. mepc/mcause/
#     mtval are seeded with sentinels first and must still hold them.
#   Path B (cases 5-9): MDT set by the hardware entry of an ordinary ECALL
#     trap; handler_b runs the faulting instruction. The M stack must still
#     describe the ECALL (mepc = its PC, mcause 11, mtval 0).
#
#   Slot k at 0x80000100 + 32*k, written by the RNMI handler:
#     +0 mncause  +4 mnepc  +8 mnstatus at entry  +12 mepc  +16 mcause
#     +20 mtval   +24 RNMI entries for this case  +28 expected mnepc
#   0x80000000: entries of the path-A mtvec (0 expected)
#   0x80000004: entries of handler_b (expected: number of path-B cases)
#   0x8000000C: entries of final_handler (1)   0x80000010: its mcause (11)
#   0x80000040+4j: PC of the first ECALL of path-B case 5+j
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNEPC,     0x741
.equ MNCAUSE,   0x742
.equ MNSTATUS,  0x744
.equ MSTATUSH,  0x310
.equ MARV_NMVEC, 0x7FD
.equ SLOTS,     0x80000100
.equ SENT_EPC,  0x20000F00
.equ SENT_TVAL, 0x5A5A5A5A
.equ LOCKED,    0x80004000

.section .text
.global main

main:
    j    _start

#=========================================================================
# Path-A mtvec: must never be reached (every trap there is a double trap)
#=========================================================================
    .align 2
m_bad_handler:
    lw   t0, 0(s1)
    addi t0, t0, 1
    sw   t0, 0(s1)
    csrw MSTATUSH, x0
    csrw mepc, s11
    mret

#=========================================================================
# Path-B mtvec: entered by the ECALL, MDT is now 1; run the fault snippet
#=========================================================================
    .align 2
handler_b:
    lw   t0, 4(s1)
    addi t0, t0, 1
    sw   t0, 4(s1)
    jr   s10

#=========================================================================
# RNMI handler (marv_nmvec)
#=========================================================================
    .align 2
rnmi_handler:
    csrr t0, MNCAUSE
    sw   t0, 0(s9)
    csrr t0, MNEPC
    sw   t0, 4(s9)
    csrr t0, MNSTATUS
    sw   t0, 8(s9)
    csrr t0, mepc
    sw   t0, 12(s9)
    csrr t0, mcause
    sw   t0, 16(s9)
    csrr t0, mtval
    sw   t0, 20(s9)
    lw   t0, 24(s9)
    addi t0, t0, 1
    sw   t0, 24(s9)
    csrw MSTATUSH, x0              # MNPP = M: MNRET leaves MDT set, clear it
    csrw MNEPC, s11
    .word 0x70200073               # mnret

#=========================================================================
# Final ordinary trap
#=========================================================================
    .align 2
final_handler:
    lw   t0, 0x0C(s1)
    addi t0, t0, 1
    sw   t0, 0x0C(s1)
    csrr t0, mcause
    sw   t0, 0x10(s1)
    csrw mepc, s11
    mret

#=========================================================================
# Fault snippets (entered with a jump; never fall through)
#=========================================================================
    .align 2
f_ecall:
    ecall
    j    f_stuck
f_illegal:
    .word 0xFFFFFFFF
    j    f_stuck
f_ebreak:
    .word 0x00100073               # 32-bit ebreak
    j    f_stuck
f_load:
    lw   t0, 0(a5)
    j    f_stuck
f_store:
    sw   t0, 0(a5)
    j    f_stuck
f_stuck:
    li   x31, 0xBADBAD00
    j    f_stuck

#=========================================================================
# Seed the M trap stack with sentinels
#=========================================================================
    .align 2
seed_mstack:
    li   t0, SENT_EPC
    csrw mepc, t0
    li   t0, 6
    csrw mcause, t0
    li   t0, SENT_TVAL
    csrw mtval, t0
    ret

#=========================================================================
# Path A: s9 = slot, s10 = snippet
#=========================================================================
    .align 2
run_path_a:
    mv   s8, ra
    call seed_mstack
    sw   s10, 28(s9)
    la   s11, 1f
    li   a5, LOCKED
    li   t1, (1 << 10)
    csrs MSTATUSH, t1              # MDT = 1
    jr   s10                       # fault -> double trap -> RNMI handler
1:  mv   ra, s8
    ret

#=========================================================================
# Path B: s9 = slot, s10 = snippet, a4 = first-ECALL record address
#=========================================================================
    .align 2
run_path_b:
    mv   s8, ra
    la   t0, handler_b
    csrw mtvec, t0
    sw   s10, 28(s9)
    la   s11, 1f
    li   a5, LOCKED
    la   t0, 2f
    sw   t0, 0(a4)
2:  ecall                          # MDT 0 -> 1, then handler_b faults
1:  la   t0, m_bad_handler
    csrw mtvec, t0
    mv   ra, s8
    ret

#=========================================================================
_start:
    csrsi MNSTATUS, 8              # Smdbltrp boot: NMIE = 1 first
    csrw MSTATUSH, x0              # then MDT = 0

    li   sp, 0x80010000
    li   s1, 0x80000000
    mv   t0, s1
    li   t1, 0x80000300
1:  sw   x0, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b

    la   t0, rnmi_handler
    csrw MARV_NMVEC, t0
    la   t0, m_bad_handler
    csrw mtvec, t0

.if CFG_PMP_NR > 0
    li   t0, (LOCKED >> 2) | 0x7   # NAPOT 64 bytes
    csrw pmpaddr0, t0
    li   t0, 0x98                  # L | NAPOT, no R/W/X: binds M-mode
    csrw pmpcfg0, t0
.endif

    li   x31, 0x11111111           # sync: init done

    #--- Path A
    li   s9, SLOTS + 0*32
    la   s10, f_ecall
    call run_path_a
    li   s9, SLOTS + 1*32
    la   s10, f_illegal
    call run_path_a
    li   s9, SLOTS + 2*32
    la   s10, f_ebreak
    call run_path_a
.if CFG_PMP_NR > 0
    li   s9, SLOTS + 3*32
    la   s10, f_load
    call run_path_a
    li   s9, SLOTS + 4*32
    la   s10, f_store
    call run_path_a
.endif
    li   x31, 0x22222222           # sync: path A done

    #--- Path B
    li   s9, SLOTS + 5*32
    la   s10, f_ecall
    li   a4, 0x80000040 + 0*4
    call run_path_b
    li   s9, SLOTS + 6*32
    la   s10, f_illegal
    li   a4, 0x80000040 + 1*4
    call run_path_b
    li   s9, SLOTS + 7*32
    la   s10, f_ebreak
    li   a4, 0x80000040 + 2*4
    call run_path_b
.if CFG_PMP_NR > 0
    li   s9, SLOTS + 8*32
    la   s10, f_load
    li   a4, 0x80000040 + 3*4
    call run_path_b
    li   s9, SLOTS + 9*32
    la   s10, f_store
    li   a4, 0x80000040 + 4*4
    call run_path_b
.endif
    li   x31, 0x33333333           # sync: path B done

    # the hart still takes ordinary traps through mtvec after all the diverts
    la   t0, final_handler
    csrw mtvec, t0
    la   s11, 1f
    ecall
1:  li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test
