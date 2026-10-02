#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_bus_err_next_ldst
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: the load/store right behind a data-bus error must still execute
#   A data-bus ERROR is reported as a resumable NMI (mncause=0x80000003) and
#   the documented resume contract (doc/spec_compliance_notes.md, data-bus
#   error entry) is that the faulting access AND every younger instruction that
#   retired before the RNMI really did execute, and mnret resumes past them.
#   This test puts an UNRELATED load or store immediately behind the faulting
#   access (0, 1 or 2 NOPs apart) so its address phase can coincide with the
#   two-cycle AHB ERROR response, and demands that it executed:
#     - younger lw : its rd must hold the loaded constant, not the sentinel
#     - younger sw : the SRAM word must hold the stored constant, not the sentinel
#   12 rounds = {faulting lw, faulting sw} x {younger lw, younger sw} x {0,1,2 NOPs}.
#   Every round must raise exactly one RNMI with marv_epc = the faulting access
#   and mnepc strictly after it (inside the round), and mtvec is never entered.
#
#   The faulting access targets FAULT_ADDR = 0x00000000, which is unmapped in
#   the testbench AHB decoder (SRAM_LO_X is only enabled for the arch-test
#   build), so both loads and stores to it receive an AHB ERROR response.
#
#   Scratchpad (base 0x80000000, s0):
#     0x000..0x008  RNMI handler register save area (t1,t2,t3)
#     0x010         nmi_count                   0x014  mtvec-entered count (expect 0)
#     0x018         nmi_handler address (published for the log)
#     0x020+id*4    FPC[id]  PC of the faulting access
#     0x060+id*4    END[id]  end-of-round label (mnepc must lie in (FPC, END])
#     0x0A0+id*4    RES[id]  younger-lw rd / younger-sw readback after settle (expect K(id))
#     0x0E0+id*4    CNT[id]  nmi_count after the round (expect id+1)
#     0x200+id*4    DAT[id]  the younger access' SRAM word
#     0x400+n*32    RNMI record n: +0 mncause +4 mnepc +8 marv_epc +12 marv_eaddr +16 marv_estat
#
#   K(id) = 0x5A5A0000 + id ; sentinel = 0xDEAD0000 + id
#   x31 sync: 11111111 = handler published, 22222222 = NMIE armed,
#             33333333 = all rounds done, deadbeef = done
#----------------------------------------------------------------------------

.equ MARV_ESTAT,     0x7FE
.equ MARV_EPC,       0xFFC
.equ MARV_EADDR,     0xFFD
.equ MNSTATUS,       0x744
.equ MNEPC,          0x741
.equ MNCAUSE,        0x742
.equ MARV_NMVEC,     0x7FD

.equ SBASE,          0x80000000
.equ FAULT_ADDR,     0x00000000      # unmapped in the tb AHB decoder -> AHB ERROR

.equ OFF_NMI_CNT,    0x010
.equ OFF_MTVEC_CNT,  0x014
.equ OFF_HANDLER,    0x018
.equ OFF_FPC,        0x020
.equ OFF_END,        0x060
.equ OFF_RES,        0x0A0
.equ OFF_CNT,        0x0E0
.equ OFF_DAT,        0x200
.equ OFF_REC,        0x400

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # RNMI handler -- saves t1..t3 (no stack), records the evidence in
    # record slot nmi_count, bumps nmi_count, restores, mnret.
    #=================================================================
    .align 2
nmi_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    sw   t2, 0x04(t0)
    sw   t3, 0x08(t0)

    lw   t1, OFF_NMI_CNT(t0)        # n
    slli t2, t1, 5                  # n*32
    addi t2, t2, OFF_REC
    add  t2, t2, t0                 # &record[n]
    csrr t3, MNCAUSE
    sw   t3, 0(t2)
    csrr t3, MNEPC
    sw   t3, 4(t2)
    csrr t3, MARV_EPC
    sw   t3, 8(t2)
    csrr t3, MARV_EADDR
    sw   t3, 12(t2)
    csrr t3, MARV_ESTAT
    sw   t3, 16(t2)
    addi t1, t1, 1
    sw   t1, OFF_NMI_CNT(t0)
    lw   zero, OFF_NMI_CNT(t0)      # read-back: force the stores to land

    lw   t1, 0x00(t0)
    lw   t2, 0x04(t0)
    lw   t3, 0x08(t0)
    csrr t0, mscratch
    .word 0x70200073                # mnret

    #=================================================================
    # mtvec handler -- must NEVER be entered. Counts and skips.
    #=================================================================
    .align 4
mtvec_handler:
    csrw mscratch, t0
    li   t0, SBASE
    sw   t1, 0x00(t0)
    lw   t1, OFF_MTVEC_CNT(t0)
    addi t1, t1, 1
    sw   t1, OFF_MTVEC_CNT(t0)
    lw   zero, OFF_MTVEC_CNT(t0)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    lw   t1, 0x00(t0)
    csrr t0, mscratch
    mret

    #=================================================================
    # ROUND macro
    #   id    : 0..11 (record / slot index)
    #   nops  : NOPs between the faulting access and the younger one
    #   fkind : 0 = faulting lw, 1 = faulting sw
    #   skind : 0 = younger lw (rd = t3), 1 = younger sw (from t2)
    #=================================================================
.macro ROUND id, nops, fkind, skind
    li   t0, 0x5
    csrw MARV_ESTAT, t0             # W1C valid|overrun: fresh evidence for this round
    li   s2, SBASE + OFF_DAT + \id*4
    li   t2, 0x5A5A0000 + \id       # K(id)
    li   t3, 0xDEAD0000 + \id       # sentinel
    .if \skind == 0
    sw   t2, 0(s2)                  # younger lw: DAT preloaded with K, rd (t3) holds the sentinel
    .else
    sw   t3, 0(s2)                  # younger sw: DAT preloaded with the sentinel
    .endif
    lw   zero, 0(s2)                # drain the setup store
    la   t1, fault_\id
    sw   t1, OFF_FPC + \id*4(s0)
    la   t1, end_\id
    sw   t1, OFF_END + \id*4(s0)
    lw   zero, OFF_END + \id*4(s0)  # drain
    li   t0, FAULT_ADDR
fault_\id:
    .if \fkind == 0
    lw   t1, 0(t0)                  # bus error -> RNMI (load)
    .else
    sw   zero, 0(t0)                # bus error -> RNMI (store)
    .endif
    .rept \nops
    nop
    .endr
    .if \skind == 0
    lw   t3, 0(s2)                  # MUST execute: t3 = K(id)
    .else
    sw   t2, 0(s2)                  # MUST land:    DAT[id] = K(id)
    .endif
    li   t0, 40
settle_\id:
    addi t0, t0, -1
    bnez t0, settle_\id
end_\id:
    .if \skind == 0
    sw   t3, OFF_RES + \id*4(s0)
    .else
    lw   t1, 0(s2)
    sw   t1, OFF_RES + \id*4(s0)
    .endif
    lw   t1, OFF_NMI_CNT(s0)
    sw   t1, OFF_CNT + \id*4(s0)
    lw   zero, OFF_CNT + \id*4(s0)  # drain
.endm

_start:
    li   sp, 0x80010000
    li   s0, SBASE

    # clear the counters
    sw   zero, OFF_NMI_CNT(s0)
    sw   zero, OFF_MTVEC_CNT(s0)

    la   t0, mtvec_handler
    csrw mtvec, t0

    la   t0, nmi_handler
    csrw MARV_NMVEC, t0             # RNMI vector
    sw   t0, OFF_HANDLER(s0)
    lw   zero, OFF_HANDLER(s0)

    li   x31, 0x11111111            # sync: handler published

    csrsi MNSTATUS, 8               # mnstatus.NMIE = 1
    csrw  mstatush, x0              # Smdbltrp: MDT resets to 1
    csrci mstatus, 8                # MIE=0

    li   x31, 0x22222222            # sync: NMIE armed

    #---------------------------------------------------------------
    # faulting lw, younger lw
    #---------------------------------------------------------------
    ROUND 0,  0, 0, 0
    ROUND 1,  1, 0, 0
    ROUND 2,  2, 0, 0
    #---------------------------------------------------------------
    # faulting lw, younger sw
    #---------------------------------------------------------------
    ROUND 3,  0, 0, 1
    ROUND 4,  1, 0, 1
    ROUND 5,  2, 0, 1
    #---------------------------------------------------------------
    # faulting sw, younger lw
    #---------------------------------------------------------------
    ROUND 6,  0, 1, 0
    ROUND 7,  1, 1, 0
    ROUND 8,  2, 1, 0
    #---------------------------------------------------------------
    # faulting sw, younger sw
    #---------------------------------------------------------------
    ROUND 9,  0, 1, 1
    ROUND 10, 1, 1, 1
    ROUND 11, 2, 1, 1

    li   x31, 0x33333333            # sync: all rounds done

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
