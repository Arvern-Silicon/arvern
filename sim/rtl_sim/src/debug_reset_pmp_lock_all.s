#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_reset_pmp_lock_all
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: every implemented PMP entry locked, every pmpcfg / pmpaddr
#   write ignored, then an ndmreset clears all of them
#   Priv 3.7.1: "If PMP entry i is locked, writes to pmpicfg and pmpaddri
#   are ignored. Additionally, if PMP entry i is locked and pmpicfg.A is set
#   to TOR, writes to pmpaddri-1 are ignored." Locked entries are enforced
#   for M-mode. Priv 6.2: "PMP reset: A reset process where all PMP settings
#   of the hart, including locked rules/settings, are re-initialized to a
#   set of safe defaults".
#
#   N = CFG_PMP_NR (4, 8 or 16). mseccfg is never written (no MML/MMWP).
#
#   FIRST BOOT (SRAM boot flag != magic):
#     pmpaddr0..N-2 = 0, pmpaddrN-1 = 0x20800000, written before any cfg.
#     Every implemented cfg byte = L|TOR|X|W|R (0x8F): entries 0..N-2 match
#     nothing (pmpaddr(i-1) >= pmpaddr(i), entry 0 bounded below by 0), entry
#     N-1 = [0, 0x82000000) RWX covers the ROM, both SRAMs and the
#     peripherals. Every rule is RWX and MMWP is off, so no rewrite that
#     wrongly lands can deny an access: a broken lock shows as a mismatch.
#     All 4 pmpcfg and all 16 pmpaddr are read after locking, then:
#       csrw pmpcfgK, x0 / csrc pmpcfgK, 0x80808080 (each read back)
#       csrw pmpaddrI, 0x00ABC000+I (read back)
#     x31 = 11111111, spin; the testbench pulses dmcontrol.ndmreset.
#   SECOND BOOT (flag == magic, SRAM survives the ndmreset):
#     all 4 pmpcfg and 16 pmpaddr read 0; entry N-1 (formerly locked) and
#     pmpaddrN-2 (formerly TOR-locked) are writable: pmpaddrN-1 = 0x1234,
#     pmpaddrN-2 = 0x456, cfg byte N-1 = TOR|R (0x09, unlocked, M-mode not
#     affected), read back, then cleared and read back.
#     x31 = 22222222 then deadbeef.
#
#   SRAM (0x80000000):
#     0x000 boot flag         0x008 trap count      0x00C last mcause
#     0x040 pmpcfg0..3 after locking
#     0x050 pmpcfg0..3 after csrw x0
#     0x060 pmpcfg0..3 after csrc L bits
#     0x080 pmpaddr0..15 after locking
#     0x0C0 pmpaddr0..15 after the rewrite attempts
#     0x100 pmpcfg0..3 second boot
#     0x140 pmpaddr0..15 second boot
#     0x180 pmpcfg(N-1)/4 after write   0x184 pmpaddrN-1   0x188 pmpaddrN-2
#     0x18C pmpcfg(N-1)/4 after clear   0x190 pmpaddrN-1   0x194 pmpaddrN-2
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.option norvc

.equ SBASE,        0x80000000
.equ BOOT_MAGIC,   0x5EC0B00F
.equ TOP_ADDR,     0x20800000          # 0x82000000 >> 2

.equ O_CFG_LOCK,   0x040
.equ O_CFG_W0,     0x050
.equ O_CFG_CL,     0x060
.equ O_ADDR_LOCK,  0x080
.equ O_ADDR_RW,    0x0C0
.equ O_CFG_B2,     0x100
.equ O_ADDR_B2,    0x140
.equ O_PAIR,       0x180

# Entry N-1: its cfg register and the two pmpaddr it locks
.macro PAIR_WRITE cfg, atop, alow
    li   t0, 0x00001234
    csrw \atop, t0
    li   t0, 0x00000456
    csrw \alow, t0
    li   t0, 0x09000000            # byte 3 = TOR | R, unlocked
    csrw \cfg, t0
    csrr t0, \cfg
    sw   t0, O_PAIR+0x00(s1)       # expect 0x09000000
    csrr t0, \atop
    sw   t0, O_PAIR+0x04(s1)       # expect 0x00001234
    csrr t0, \alow
    sw   t0, O_PAIR+0x08(s1)       # expect 0x00000456
    csrw \cfg, x0
    csrw \atop, x0
    csrw \alow, x0
    csrr t0, \cfg
    sw   t0, O_PAIR+0x0C(s1)       # expect 0
    csrr t0, \atop
    sw   t0, O_PAIR+0x10(s1)       # expect 0
    csrr t0, \alow
    sw   t0, O_PAIR+0x14(s1)       # expect 0
.endm

main:
    j    _start

    #---------------------------------------------------------------
    # M trap handler: must never run. Stackless; counts and skips.
    #---------------------------------------------------------------
    .align 2
m_trap_handler:
    lw   t5, 0x08(s1)
    addi t5, t5, 1
    sw   t5, 0x08(s1)
    csrr t6, mcause
    sw   t6, 0x0C(s1)
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret

_start:
    li   s1, SBASE
    la   t0, m_trap_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0

    li   t1, BOOT_MAGIC
    lw   t0, 0x00(s1)
    beq  t0, t1, second_boot

    #=================================================================
    # FIRST BOOT
    #=================================================================
    sw   t1, 0x00(s1)              # boot flag (survives the ndmreset)
    sw   x0, 0x08(s1)
    sw   x0, 0x0C(s1)
    lw   t0, 0x00(s1)              # the flag store has landed

    # pmpaddr first: once a TOR entry is locked its lower pmpaddr is too
    li   t1, TOP_ADDR
    .irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    .if \i == (CFG_PMP_NR-1)
    csrw pmpaddr\i, t1
    .elseif \i < (CFG_PMP_NR-1)
    csrw pmpaddr\i, x0
    .endif
    .endr

    # then every implemented cfg byte = L | TOR | X | W | R
    li   t1, 0x8F8F8F8F
    .irp k, 0,1,2,3
    .if (4*\k) < CFG_PMP_NR
    csrw pmpcfg\k, t1
    .endif
    .endr

    .irp k, 0,1,2,3
    csrr t0, pmpcfg\k
    sw   t0, O_CFG_LOCK+4*\k(s1)
    .endr
    .irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    csrr t0, pmpaddr\i
    sw   t0, O_ADDR_LOCK+4*\i(s1)
    .endr

    # Every write below must be ignored.
    .irp k, 0,1,2,3
    csrw pmpcfg\k, x0
    csrr t0, pmpcfg\k
    sw   t0, O_CFG_W0+4*\k(s1)
    .endr

    li   t1, 0x80808080
    .irp k, 0,1,2,3
    csrc pmpcfg\k, t1
    csrr t0, pmpcfg\k
    sw   t0, O_CFG_CL+4*\k(s1)
    .endr

    .irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    li   t1, 0x00ABC000+\i
    csrw pmpaddr\i, t1
    csrr t0, pmpaddr\i
    sw   t0, O_ADDR_RW+4*\i(s1)
    .endr

    lw   t0, 0x08(s1)              # last store has landed

    li   x31, 0x11111111           # sync: testbench pulses ndmreset
spin:
    j    spin

    #=================================================================
    # SECOND BOOT (after the ndmreset)
    #=================================================================
second_boot:
    .irp k, 0,1,2,3
    csrr t0, pmpcfg\k
    sw   t0, O_CFG_B2+4*\k(s1)
    .endr
    .irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    csrr t0, pmpaddr\i
    sw   t0, O_ADDR_B2+4*\i(s1)
    .endr

.if CFG_PMP_NR >= 16
    PAIR_WRITE pmpcfg3, pmpaddr15, pmpaddr14
.elseif CFG_PMP_NR >= 8
    PAIR_WRITE pmpcfg1, pmpaddr7, pmpaddr6
.else
    PAIR_WRITE pmpcfg0, pmpaddr3, pmpaddr2
.endif

    lw   t0, 0x08(s1)              # last store has landed

    li   x31, 0x22222222
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
