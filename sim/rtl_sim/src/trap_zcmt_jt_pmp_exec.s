#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_zcmt_jt_pmp_exec
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: the Zcmt jump-table read is an INSTRUCTION FETCH under PMP
#   Unpriv 28.14.2 (Table Jump Fault handling): "the execution of a table jump
#   instruction involves two instruction fetches ... Both instruction fetches
#   are implicit reads, and both require execute permission; read permission is
#   irrelevant. ... If an exception occurs on either instruction fetch, xEPC is
#   set to the PC of the table jump instruction, xCAUSE is set as expected for
#   the type of fault and xTVAL (if not set to zero) contains the fetch address."
#
#   Machine mode throughout, mseccfg.MML=0. With MML=0 an M-mode access is only
#   restricted by LOCKED entries (L=1), which is how trap_pmp_fetch.s builds its
#   denial; the same pattern is used here. Each phase owns a separate 16-byte
#   NAPOT table and a separate PMP entry (a locked entry cannot be rewritten),
#   and jvt is re-pointed between phases. Tables are populated BEFORE the
#   entries are locked (table B becomes unreadable once locked).
#
#     phase  table        entry            cm.jt outcome
#     ----------------------------------------------------------------------
#     (a)    0x80000400   L R=1 W=0 X=0    MCAUSE 1, MEPC=&jt_a, MTVAL=table+4
#                                          (cm.jt 1), NO jump; handler skips +2
#     (b)    0x80000500   L R=0 W=0 X=1    jumps (execute-only table is fine)
#     (c)    0x80000600   R=1 X=0 unlocked jumps under mstatus.MPRV=1/MPP=U:
#                         (U would be denied, M ignores an unlocked entry) the
#                         implicit fetch is checked at the CURRENT privilege
#
#   The handler clobbers t0-t2 (no stack: a trap under MPRV=1/U would fault on
#   the stack region), clears MPRV, records, and resumes at MEPC+2.
#
#   Scratchpad (base 0x80000000, s1):
#     0x00 trap count   0x04 MCAUSE   0x08 MEPC   0x0C MTVAL   0x10 &jt_a
#
#   Registers checked (after 0x33333333):
#     a0 MCAUSE(a)=1        a1 MEPC(a)-&jt_a=0   a2 MTVAL(a)=0x80000404
#     a3 trap count (a)=1   a4 phase-a landing = 0x0A0FA11 (fall-through only)
#     a5 phase-b landing = 0x0B0B0     a6 phase-c landing = 0x0C0C0
#     a7 final trap count = 1          s2 mstatus after (c) MPRV cleared = 0
#   x31 sync: 11111111 after (a), 22222222 after (b), 33333333 after (c),
#             deadbeef done
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ SBASE,   0x80000000
.equ TBL_A,   0x80000400
.equ TBL_B,   0x80000500
.equ TBL_C,   0x80000600
.equ MPRV_U,  0x00020000       # MPRV=1, MPP=U
.equ MPRV_BIT,0x00020000

main:
    j _start

    #=================================================================
    # M-MODE TRAP HANDLER (clobbers t0-t2, no stack)
    #=================================================================
    .align 2
m_trap_handler:
    li   t0, MPRV_BIT
    csrc mstatus, t0            # never let MPRV redirect the handler's own stores

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mtval
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)
    sw   t2, 0x0C(s1)
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)
    lw   zero, 0x00(s1)

    addi t1, t1, 2              # skip the 16-bit cm.jt
    csrw mepc, t1
    mret

#=========================================================================
_start:
    li   sp, 0x80010000
    li   s1, SBASE
    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    # Arm NMIE first, then clear MDT (else every M-mode trap is "unexpected").
    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw mstatush, x0           # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    # Populate the three tables while everything is still unprotected.
    li   t0, TBL_A
    la   t1, tgt_a
    sw   t1, 4(t0)              # TBL_A[1] = tgt_a  (cm.jt 1 -> fetch address TBL_A+4)
    li   t0, TBL_B
    la   t1, tgt_b
    sw   t1, 0(t0)              # TBL_B[0] = tgt_b
    li   t0, TBL_C
    la   t1, tgt_c
    sw   t1, 8(t0)              # TBL_C[2] = tgt_c
    lw   zero, 8(t0)            # drain
    fence.i

    la   t0, jt_a
    sw   t0, 0x10(s1)           # &jt_a for the MEPC compare

    # Entry 0: TBL_A, NAPOT 16 B, L | R      (locked, no X)   -> cfg 0x99
    # Entry 1: TBL_B, NAPOT 16 B, L | X      (locked, no R)   -> cfg 0x9C
    # Entry 2: TBL_C, NAPOT 16 B, R          (unlocked, no X) -> cfg 0x19
    li   t0, TBL_A
    srli t0, t0, 2
    ori  t0, t0, 1
    csrw pmpaddr0, t0
    li   t0, TBL_B
    srli t0, t0, 2
    ori  t0, t0, 1
    csrw pmpaddr1, t0
    li   t0, TBL_C
    srli t0, t0, 2
    ori  t0, t0, 1
    csrw pmpaddr2, t0
    li   t0, 0x00199C99         # pmp2cfg=0x19 | pmp1cfg=0x9C | pmp0cfg=0x99
    csrw pmpcfg0, t0

    #=================================================================
    # PHASE (a) -- table readable but not executable (locked):
    #   cm.jt 1 must trap MCAUSE=1, MEPC=&jt_a, MTVAL=TBL_A+4, and NOT jump.
    #=================================================================
    li   t0, TBL_A
    csrw 0x017, t0              # jvt = TBL_A
    nop
    nop
    li   a4, 0
jt_a:
    cm.jt 1                     # instruction access fault on the table fetch
    li   a4, 0x0A0FA11          # reached only via the handler's MEPC+2 skip
    j    a_done
tgt_a:
    li   a4, 0x0BAD0A           # must NOT be reached: the table was not executable
a_done:
    lw   a0, 0x04(s1)           # MCAUSE -- expect 1
    lw   a1, 0x08(s1)           # MEPC
    lw   t0, 0x10(s1)
    sub  a1, a1, t0             # MEPC - &jt_a -- expect 0
    lw   a2, 0x0C(s1)           # MTVAL -- expect TBL_A+4
    lw   a3, 0x00(s1)           # trap count -- expect 1
    addi t0, a3, 0              # consume the load: hold the sync until it retires

    li   x31, 0x11111111

    #=================================================================
    # PHASE (b) -- table executable but not readable (locked):
    #   cm.jt 0 must jump; no trap.
    #=================================================================
    li   t0, TBL_B
    csrw 0x017, t0              # jvt = TBL_B
    nop
    nop
    li   a5, 0
    cm.jt 0
    li   a5, 0x0BAD0B           # fell through: the jump did not happen (or trapped)
    j    b_done
tgt_b:
    li   a5, 0x0B0B0
b_done:

    li   x31, 0x22222222

    #=================================================================
    # PHASE (c) -- MPRV=1/MPP=U, table covered by an UNLOCKED no-X entry:
    #   checked as U the fetch would be denied; checked as M (current
    #   privilege, MPRV is not applied to instruction fetches) it succeeds.
    #=================================================================
    li   t0, TBL_C
    csrw 0x017, t0              # jvt = TBL_C
    nop
    nop
    li   a6, 0
    li   t0, MPRV_U
    csrw mstatus, t0
    cm.jt 2
    li   a6, 0x0BAD0C           # fell through: the jump did not happen (or trapped)
    j    c_done
tgt_c:
    li   a6, 0x0C0C0
c_done:
    csrw mstatus, x0
    csrr s2, mstatus
    li   t0, MPRV_BIT
    and  s2, s2, t0             # MPRV cleared -- expect 0
    lw   a7, 0x00(s1)           # trap count -- still 1
    addi t0, a7, 0              # consume the load

    li   x31, 0x33333333

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
1:  j    1b
