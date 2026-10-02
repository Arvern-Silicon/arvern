#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_reset_sticky_state
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Smepmp sticky bits and locked PMP rules hold until a reset,
#   and an ndmreset clears them
#   Priv 6.2 (Smepmp): MMWP / MML "This is a sticky bit, meaning that once
#   set it cannot be unset until a PMP reset"; "PMP reset: A reset process
#   where all PMP settings of the hart, including locked rules/settings, are
#   re-initialized to a set of safe defaults". Priv 3.7.1: a locked entry
#   ignores writes to its pmpcfg and pmpaddr; a locked TOR entry also locks
#   the pmpaddr below it.
#
#   FIRST BOOT (SRAM boot flag != magic):
#     entry 0  pmpaddr0 = 0x08000000 (TOR lower bound), cfg OFF, unlocked
#     entry 1  TOR [0x20000000, 0x20010000) = the ROM, L|X|R  (0x8D)
#     entry 2  NAPOT 64 KB @ 0x80000000 = SRAM_X, L|W|R       (0x9B)
#     Then mseccfg = MML|MMWP (3). With MML an L=1 R-X rule is "Locked
#     Read/Execute region" (M only) and L=1 RW- "Locked Read/Write region",
#     so M keeps fetching the ROM and using the SRAM; with MMWP nothing else
#     is reachable (the firmware touches nothing else). time/minstret read.
#     Attempts that must all be ignored: mseccfg <- 0, csrc mseccfg 3,
#     pmpcfg0 <- 0, pmpaddr1 / pmpaddr2 rewritten (locked entries), pmpaddr0
#     rewritten (below a locked TOR entry). x31 = 11111111, spin; the
#     testbench pulses dmcontrol.ndmreset.
#   SECOND BOOT (flag == magic, SRAM survives the ndmreset):
#     mseccfg, pmpcfg0, pmpaddr0..2 read 0; minstret small; time completes;
#     a pmpcfg0 write on the formerly locked byte and a pmpaddr1 write land;
#     mseccfg.RLB can be set again (no rule locked) and cleared.
#     x31 = 22222222 then deadbeef.
#
#   Registers (first boot, checked at 11111111):
#     a0 pmpcfg0 after locking (0x009B8D00)   a1 mseccfg after the write (3)
#     a2 time (reported)                       a3 minstret (> 400)
#     a4 mseccfg after the clear attempts (3)  a5 pmpcfg0 after <- 0 (0x009B8D00)
#     a6 pmpaddr1 after rewrite (0x08004000)   a7 pmpaddr0 after rewrite (0x08000000)
#     s2 pmpaddr2 after rewrite (0x20001FFF)   s3 trap count (0)
#   Registers (second boot, checked at deadbeef):
#     s4 mseccfg (0)  s5 pmpcfg0 (0)  s6 pmpaddr0 (0)  s7 pmpaddr1 (0)
#     s8 pmpaddr2 (0) s9 minstret (< 100) s10 pmpcfg0 after write (0x900)
#     s11 pmpaddr1 after write (0x1234)  a0 mseccfg after RLB set (4)
#     a1 mseccfg after RLB clear (0)     a2 trap count (0)
#
#   SRAM (0x80000000): 0x00 boot flag, 0x08 trap count.
#   Requires PMP_NR >= 4 (entries 0..2).
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.option norvc

.equ SBASE,      0x80000000
.equ BOOT_MAGIC, 0x5EC0B007

main:
    j    _start

    #---------------------------------------------------------------
    # M trap handler: must never run. Stackless (only ROM and the
    # SRAM window are reachable under MMWP); counts and skips.
    #---------------------------------------------------------------
    .align 2
m_trap_handler:
    lw   t5, 0x08(s1)
    addi t5, t5, 1
    sw   t5, 0x08(s1)
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
    lw   t0, 0x00(s1)              # the flag store has landed

    li   t0, 200                   # retire a few hundred instructions
1:  addi t0, t0, -1
    bnez t0, 1b

    li   t0, 0x08000000            # entry 0: TOR bottom = 0x20000000
    csrw pmpaddr0, t0
    li   t0, 0x08004000            # entry 1: TOR top    = 0x20010000
    csrw pmpaddr1, t0
    li   t0, 0x20001FFF            # entry 2: NAPOT 64 KB @ 0x80000000
    csrw pmpaddr2, t0
    li   t0, 0x009B8D00            # e2 = L|NAPOT|W|R, e1 = L|TOR|X|R, e0 = OFF
    csrw pmpcfg0, t0
    csrr a0, pmpcfg0               # expect 0x009B8D00

    li   t0, 3
    csrw 0x747, t0                 # mseccfg = MML | MMWP
    csrr a1, 0x747                 # expect 3

.if CFG_ZICNTR_EN
    csrr a2, time
    csrr a3, minstret
.else
    li   a2, 0
    li   a3, 0
.endif

    # Every write below must be ignored.
    csrw 0x747, x0
    csrci 0x747, 3
    csrr a4, 0x747                 # expect 3

    csrw pmpcfg0, x0
    csrr a5, pmpcfg0               # expect 0x009B8D00

    li   t0, 0x08000010
    csrw pmpaddr1, t0              # locked entry
    csrr a6, pmpaddr1              # expect 0x08004000
    li   t0, 0x08000100
    csrw pmpaddr0, t0              # below a locked TOR entry
    csrr a7, pmpaddr0              # expect 0x08000000
    li   t0, 0x20000FFF
    csrw pmpaddr2, t0              # locked entry
    csrr s2, pmpaddr2              # expect 0x20001FFF

    lw   s3, 0x08(s1)              # trap count, expect 0
    addi s3, s3, 0

    li   x31, 0x11111111           # sync: testbench pulses ndmreset
spin:
    j    spin

    #=================================================================
    # SECOND BOOT (after the ndmreset)
    #=================================================================
second_boot:
    csrr s4, 0x747                 # expect 0
    csrr s5, pmpcfg0               # expect 0
    csrr s6, pmpaddr0              # expect 0
    csrr s7, pmpaddr1              # expect 0
    csrr s8, pmpaddr2              # expect 0

.if CFG_ZICNTR_EN
    csrr s9, minstret              # expect < 100
    csrr t0, time                  # must complete
.else
    li   s9, 0
.endif

    li   t0, 0x00000900            # entry 1 = TOR | R, unlocked
    csrw pmpcfg0, t0
    csrr s10, pmpcfg0              # expect 0x00000900
    li   t0, 0x00001234
    csrw pmpaddr1, t0
    csrr s11, pmpaddr1             # expect 0x00001234

    csrsi 0x747, 4                 # RLB: no rule is locked, so it is accepted
    csrr a0, 0x747                 # expect 4
    csrci 0x747, 4
    csrr a1, 0x747                 # expect 0

    csrw pmpcfg0, x0
    csrw pmpaddr1, x0

    lw   a2, 0x08(s1)              # trap count, expect 0
    addi a2, a2, 0

    li   x31, 0x22222222
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
