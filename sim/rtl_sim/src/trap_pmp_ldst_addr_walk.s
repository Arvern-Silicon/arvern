#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_ldst_addr_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP load/store address walk over the whole 32-bit space
#
#   Priv 3.7.1: "The lowest-numbered PMP entry that matches any byte of an
#   access determines whether that access succeeds or fails." "When the L bit
#   is set, these permissions are enforced for all privilege modes."
#   "Failed accesses generate an instruction, load, or store access-fault
#   exception."
#   doc/traps_and_interrupts.md: cause 5 "A PMP rule denied read on the load
#   address", cause 7 "A PMP rule denied write on the store address"; mtval
#   for 1, 5, 7 is "The faulting (access-faulting) address".
#   doc/software_guide.md 12: "a load or store denied by PMP produces no bus
#   transfer at all" (checked by the bench monitor, see the .v).
#
#   Machine mode, four LOCKED entries (they bind M-mode):
#     0  NAPOT 64 KB @ 0x20000000 (ROM)      R X    -- the test's code
#     1  NAPOT 64 KB @ 0x80000000 (SRAM_X)   R W    -- scratch
#     2  NAPOT 64 KB @ 0x81000000 (SRAM_NX)  R W
#     3  NAPOT whole space (pmpaddr -1)      none   -- catch-all deny
#   so every data access outside the bench memories faults, and ROM is
#   read-only.
#
#   Addresses: walking ones 1<<k and walking zeros ~(1<<k) & ~3, k = 2..31
#   (60 addresses). Each gets an LW then an SW. Two addresses fall in a bench
#   memory: 0x80000000 (1<<31, SRAM_X) -- load returns the seeded 0x12345678,
#   store lands (0x5EED001F) -- and 0x20000000 (1<<29, ROM) -- load returns
#   the ROM word read before PMP was armed, store faults. Every other access
#   must trap with mcause 5/7, mtval = the address, the load's rd unchanged;
#   the handler resumes after the instruction.
#
#   Result registers:
#     s5 (x21) checks performed (expect 120)   s6 (x22) failures (expect 0)
#     s7 (x23) first failure code              s8 (x24) RNMIs (expect 0)
#     s10 (x26) unexpected trap causes (0)     s11 (x27) mtval mismatches (0)
#     a3 (x13) load faults (expect 58)         a4 (x14) store faults (expect 59)
#     a6 (x16) pmpcfg0 read-back               a7 (x17) pmpaddr3 read-back
#   Scratchpad: 0x80000000 probe word; 0x80000100 handler save area.
#
# Requires PMP_NR > 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.option norvc

.equ SAVE,        0x80000100
.equ PROBE_WORD,  0x80000000
.equ MARV_NMVEC,  0x7FD
.equ MARV_ESTAT,  0x7FE

.macro CHK reg, code
    addi s5, s5, 1
    beqz \reg, .Lchk_ok\@
    addi s6, s6, 1
    bnez s7, .Lchk_ok\@
    li   s7, \code
    slli t0, a5, 8
    or   s7, s7, t0
    or   s7, s7, s2
.Lchk_ok\@:
.endm

main:
    j _start

    #=================================================================
    # M trap handler: record the fault kind in s9, count mtval
    # mismatches in s11, unexpected causes in s10, skip the access.
    #=================================================================
    .align 2
m_handler:
    csrw mscratch, t0
    li   t0, SAVE
    sw   t1, 0(t0)
    sw   t2, 4(t0)
    csrr t1, mcause
    li   t2, 5
    beq  t1, t2, h_load
    li   t2, 7
    beq  t1, t2, h_store
    addi s10, s10, 1
    sw   t1, 8(t0)                  # last unexpected cause
    j    h_skip
h_load:
    ori  s9, s9, 1
    addi a3, a3, 1
    j    h_tval
h_store:
    ori  s9, s9, 2
    addi a4, a4, 1
h_tval:
    csrr t1, mtval
    beq  t1, a0, h_skip
    addi s11, s11, 1
h_skip:
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    lw   t2, 4(t0)
    lw   t1, 0(t0)
    csrr t0, mscratch
    mret

    #=================================================================
    # RNMI handler: an allowed access hit an unmapped address. Count it.
    #=================================================================
    .align 2
nmi_handler:
    csrw 0x740, t0                  # mnscratch
    li   t0, 5
    csrw MARV_ESTAT, t0             # W1C valid|overrun
    addi s8, s8, 1
    csrr t0, 0x740
    .word 0x70200073                # mnret

_start:
    li   sp, 0x80010000
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, nmi_handler
    csrw MARV_NMVEC, t0
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw mstatush, x0               # mstatus.MDT = 0
    csrci mstatus, 8                # MIE = 0

    li   s5, 0
    li   s6, 0
    li   s7, 0
    li   s8, 0
    li   s9, 0
    li   s10, 0
    li   s11, 0
    li   a3, 0
    li   a4, 0

    li   t0, PROBE_WORD
    li   t1, 0x12345678
    sw   t1, 0(t0)
    li   t0, 0x20000000
    lw   s1, 0(t0)                  # ROM word at 1<<29, read while PMP is off

    # Addresses first, then all four cfg bytes (locked) in one write.
    li   t0, (0x20000000 >> 2) | 0x1FFF
    csrw pmpaddr0, t0
    li   t0, (0x80000000 >> 2) | 0x1FFF
    csrw pmpaddr1, t0
    li   t0, (0x81000000 >> 2) | 0x1FFF
    csrw pmpaddr2, t0
    li   t0, -1
    csrw pmpaddr3, t0
    li   t0, 0x989B9B9D             # 3: L|NAPOT  2,1: L|NAPOT|RW  0: L|NAPOT|RX
    csrw pmpcfg0, t0
    csrr a6, pmpcfg0
    csrr a7, pmpaddr3

    li   x31, 0x11111111            # Sync: walk starts (bus monitor armed)

    li   s4, 1
    li   a5, 0                      # 0 = walking ones, 1 = walking zeros
phase:
    li   s2, 2
    li   s3, 32
walk:
    sll  a0, s4, s2
    beqz a5, 1f
    not  a0, a0
    andi a0, a0, -4
1:
    li   a1, 3                      # expected fault mask: load | store
    li   a2, 0x0BAD0BAD             # expected rd of the load
    li   t0, PROBE_WORD
    bne  a0, t0, 2f
    li   a1, 0
    li   a2, 0x12345678
    j    3f
2:  li   t0, 0x20000000
    bne  a0, t0, 3f
    li   a1, 2                      # ROM: load allowed, store denied
    mv   a2, s1
3:
    li   s9, 0
    li   t3, 0x0BAD0BAD
    li   t4, 0x5EED0000
    or   t4, t4, s2
    lw   t3, 0(a0)
    sw   t4, 0(a0)
    xor  t0, s9, a1
    CHK  t0, 0x10000
    xor  t0, t3, a2
    CHK  t0, 0x20000
    addi s2, s2, 1
    bne  s2, s3, walk
    bnez a5, walk_done
    li   a5, 1
    j    phase
walk_done:

    li   t0, PROBE_WORD
    lw   zero, 0(t0)                # the allowed store has landed
    li   x31, 0x22222222            # Sync: walk done (bus monitor disarmed)

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
