#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_mml
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Smepmp Machine Mode Lockdown -- the full mseccfg.MML truth table
#
#   With MML set the meaning of pmpcfg.L changes: L=1 rules belong to M-mode,
#   L=0 rules to S/U-mode, and R=0,W=1 marks a Shared-Region (Priv 6.2, table
#   6.2.1). Every one of the 16 LRWX encodings gets its own 16-byte NAPOT
#   region, entry number = LRWX value, and is probed six ways:
#
#     0  M load     1  M store     2  M execute
#     3  U load     4  U store     5  U execute
#
#   U-mode data probes use mstatus.MPRV with MPP=U; U-mode execute probes
#   really enter U-mode with mret. Every region holds an ECALL at offset 0, so
#   an execute probe ends in a trap either way -- cause 1 if the fetch was
#   refused, cause 11 (from M) or 8 (from U) if it ran. Data probes use
#   offset 8 so a permitted store never clobbers the ECALL. A probe that traps
#   records its cause in its slot; one that does not leaves the slot at zero.
#
#   Row 1101 (M: read/execute) is placed over the ROM: MML refuses M-mode
#   execution from any address no rule covers, so the test itself needs that
#   rule, and it has to be installed before MML is set -- afterwards, adding
#   any locked rule with M-mode execute (LRWX 1001/1010/1011/1101) is ignored
#   unless RLB is set. Both of those rules are checked at the end, as is the
#   sticky-set of MML itself.
#
#   Last, every pmpcfg word gets the M-executable encodings 0x9C9A9E9D (LRWX
#   1001/1010/1011/1101 in bytes 3..0), then 0x19191919, 0x18181818,
#   0x9C199C19, then 0x18181818 again and 0x199C199C. Priv 6.2 Smepmp 4b: "Adding a rule with
#   executable privileges that either is M-mode-only or a locked
#   Shared-Region is not possible and such pmpcfg writes are ignored, leaving
#   pmpcfg unchanged" -- applied per entry (spec_compliance_notes.md).
#   pmpcfg0/1 (rows 0..7, unlocked, probes done) take the L=0 bytes only;
#   pmpcfg2/3 hold locked rows (incl. the ROM rule) and ignore everything.
#   Read-backs at 0x80000600 + 0x20*N + 4*step.
#
# Requires PMP_NR >= 16 and SU_MODE_EN == 1.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.equ SLOTS,    0x80000100       # 96 words: slot = SLOTS + (row*6 + probe)*4
.equ REGIONS,  0x80000400       # row i -> REGIONS + 16*i   (row 13 -> ROM)
.equ MPRV_U,   0x00020000       # MPRV=1, MPP=U
.equ MPP_U,    0x00000000       # MPP=U, MPRV=0
.equ MPP_M,    0x00001800

main:
    j _start

    .align 2
m_trap_handler:
    addi sp, sp, -8
    sw   t0, 4(sp)
    csrr t0, mcause
    sw   t0, 0(s11)             # this probe's slot
    li   t0, MPP_M
    csrs mstatus, t0            # always come back to M
    csrw mepc, s10
    lw   t0, 4(sp)
    addi sp, sp, 8
    mret

# Execute target for the ROM row: the same ECALL every other row carries.
    .align 2
rom_ecall:
    ecall
    nop
    nop

#-----------------------------------------------------------------------
# Probe macros. \base = region base register, \slot = slot address reg.
#-----------------------------------------------------------------------
# Write-and-read-back sequence for one pmpcfg word; \res = result address reg.
.macro CFG_SEQ csr, res
    li   t0, 0x9C9A9E9D
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 0(\res)
    li   t0, 0x19191919
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 4(\res)
    li   t0, 0x18181818
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 8(\res)
    li   t0, 0x9C199C19
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 12(\res)
    li   t0, 0x18181818              # reset every lane first
    csrw \csr, t0
    li   t0, 0x199C199C
    csrw \csr, t0
    csrr t3, \csr
    sw   t3, 16(\res)
    addi \res, \res, 0x20
.endm

.macro PROBE_M_LOAD base, slot
    la   s10, 1f
    mv   s11, \slot
    lw   t0, 8(\base)
1:
.endm

.macro PROBE_M_STORE base, slot
    la   s10, 1f
    mv   s11, \slot
    sw   t1, 8(\base)
1:
.endm

.macro PROBE_M_EXEC base, slot
    la   s10, 1f
    mv   s11, \slot
    jalr ra, 0(\base)           # ECALL (cause 11) or fetch refused (cause 1)
1:
.endm

.macro PROBE_U_LOAD base, slot
    la   s10, 1f
    mv   s11, \slot
    li   t0, MPRV_U
    csrw mstatus, t0
    lw   t0, 8(\base)
1:  csrw mstatus, x0
.endm

.macro PROBE_U_STORE base, slot
    la   s10, 1f
    mv   s11, \slot
    li   t0, MPRV_U
    csrw mstatus, t0
    sw   t1, 8(\base)
1:  csrw mstatus, x0
.endm

.macro PROBE_U_EXEC base, slot
    la   s10, 1f
    mv   s11, \slot
    li   t0, MPP_U
    csrw mstatus, t0
    csrw mepc, \base
    mret                        # enter U at the region: ECALL (8) or refused (1)
1:
.endm

# One full row: s5 = data/exec base, s6 = slot base for this row.
.macro PROBE_ROW
    PROBE_M_LOAD  s5, s6
    addi s6, s6, 4
    PROBE_M_STORE s5, s6
    addi s6, s6, 4
    PROBE_M_EXEC  s5, s6
    addi s6, s6, 4
    PROBE_U_LOAD  s5, s6
    addi s6, s6, 4
    PROBE_U_STORE s5, s6
    addi s6, s6, 4
    PROBE_U_EXEC  s5, s6
    addi s6, s6, 4
.endm

#=========================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    la   t0, m_trap_handler
    csrw mtvec, t0

    csrsi 0x744, 8              # mnstatus.NMIE = 1
    csrw  mstatush, x0          # Smdbltrp: MDT resets to 1
    csrci mstatus, 8            # MIE=0

    # Clear the 96 result slots.
    li   t0, SLOTS
    li   t1, 96
1:  sw   x0, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, 1b

    # Plant an ECALL at the base of the 15 SRAM regions.
    li   t0, REGIONS
    li   t1, 0x00000073
    li   t2, 16
2:  sw   t1, 0(t0)
    addi t0, t0, 16
    addi t2, t2, -1
    bnez t2, 2b
    fence.i

    li   t1, 0x5A5A5A5A         # store payload for every store probe

    #-----------------------------------------------------------------
    # Addresses first. Row i -> NAPOT 16 B at REGIONS + 16 i, except row
    # 13, which is a NAPOT 256 MB over the ROM.
    #-----------------------------------------------------------------
    li   t0, 0x20000101
    csrw pmpaddr0,  t0
    addi t0, t0, 4
    csrw pmpaddr1,  t0
    addi t0, t0, 4
    csrw pmpaddr2,  t0
    addi t0, t0, 4
    csrw pmpaddr3,  t0
    addi t0, t0, 4
    csrw pmpaddr4,  t0
    addi t0, t0, 4
    csrw pmpaddr5,  t0
    addi t0, t0, 4
    csrw pmpaddr6,  t0
    addi t0, t0, 4
    csrw pmpaddr7,  t0
    addi t0, t0, 4
    csrw pmpaddr8,  t0
    addi t0, t0, 4
    csrw pmpaddr9,  t0
    addi t0, t0, 4
    csrw pmpaddr10, t0
    addi t0, t0, 4
    csrw pmpaddr11, t0
    addi t0, t0, 4
    csrw pmpaddr12, t0
    li   t2, 0x09FFFFFF
    csrw pmpaddr13, t2          # ROM
    addi t0, t0, 8
    csrw pmpaddr14, t0
    addi t0, t0, 4
    csrw pmpaddr15, t0

    #-----------------------------------------------------------------
    # Then the configurations. pmpcfg packs {L,-,-,A,X,W,R}, so a row's LRWX
    # value maps to byte (L<<7) | NAPOT | (X<<2) | (W<<1) | R -- R and X swap
    # position relative to the LRWX digit order.
    # All 16 at once, before MML, so the locked M-execute rows are accepted.
    #-----------------------------------------------------------------
    li   t0, 0x1E1A1C18         # rows 0011 0010 0001 0000
    csrw pmpcfg0, t0
    li   t0, 0x1F1B1D19         # rows 0111 0110 0101 0100
    csrw pmpcfg1, t0
    li   t0, 0x9E9A9C98         # rows 1011 1010 1001 1000
    csrw pmpcfg2, t0
    li   t0, 0x9F9B9D99         # rows 1111 1110 1101 1100
    csrw pmpcfg3, t0

    #-----------------------------------------------------------------
    # MML on. From here M-mode may only execute where a rule allows it.
    #-----------------------------------------------------------------
    csrsi 0x747, 1
    csrr  a0, 0x747             # expect bit 0 set

    #=================================================================
    # Rows 0..12
    #=================================================================
    li   s5, REGIONS
    li   s6, SLOTS
    .rept 13
    PROBE_ROW
    addi s5, s5, 16
    .endr

    #=================================================================
    # Row 13 -- the ROM
    #=================================================================
    la   s5, rom_ecall
    PROBE_ROW

    #=================================================================
    # Rows 14, 15
    #=================================================================
    li   s5, REGIONS + 14*16
    PROBE_ROW
    addi s5, s5, 16
    PROBE_ROW

    #=================================================================
    # MML is sticky; and a locked M-execute rule cannot be added now.
    #=================================================================
    csrci 0x747, 1
    csrr  a1, 0x747             # expect bit 0 still set

    li   t0, 0x1E1A1C9C         # entry 0 -> LRWX 1001 (locked, M execute)
    csrw pmpcfg0, t0
    csrr a2, pmpcfg0            # expect 0x1E1A1C18: the write was ignored

    li   x31, 0x11111111

    #=================================================================
    # M-executable encodings refused per entry in every pmpcfg word.
    # a0..a2 stay untouched: the bench reads them after 0x11111111.
    #=================================================================
    li   s7, 0x80000600
    CFG_SEQ pmpcfg0, s7
    CFG_SEQ pmpcfg1, s7
.if CFG_PMP_NR >= 16
    CFG_SEQ pmpcfg2, s7
    CFG_SEQ pmpcfg3, s7
.endif
    lw   zero, -4(s7)

    li   x31, 0x22222222

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------
    li   x31, 0xdeadbeef
9:  j    9b
