#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_carry_race
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: COUNTER CARRY RACE (write coincides
#   with lo=0xFFFFFFFF + count event)
#----------------------------------------------------------------------------

.section .text
.global main

.equ MCYCLE,         0xB00
.equ MCYCLEH,        0xB80
.equ MINSTRET,       0xB02
.equ MINSTRETH,      0xB82
.equ MCOUNTINHIBIT,  0x320

main:
    li   sp, 0x80010000
    li   s1, 0x80000000
    # DO NOT call _random_irq_init (no_random_irq test)

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)              # minstret_hi after race
    sw   t0, 0x04(s1)              # mcycle_hi after race

    # Pre-load race-write data into callee-saved regs.
    # These will be used in csrw at the race-trigger cycle without any
    # intervening ALU/li instruction.
    li   s2, 0xCAFEBABE            # race write value for minstret
    li   s3, 0xDEADBEEF            # race write value for mcycle
    li   s4, 0xFFFFFFFE            # value to preset lo with
    li   s5, 4                     # IR (instret-inhibit) bit
    li   s6, 1                     # CY (cycle-inhibit) bit

    li   x31, 0x11111111


    #=========================================================================
    # PHASE 2: minstret race
    #
    # Sequence (minstret uses mcountinhibit_nxt -- WAR; no NOP needed):
    #   csrrs IR             <- inhibit
    #   csrw  minstret, 0xFFFFFFFE
    #   csrw  minstreth, 0
    #   csrrc IR             <- un-inhibit; at csrrc's EX cycle, mcountinhibit_nxt=0,
    #                            and the NEXT instr is decoded with inst_retired_i=1,
    #                            so lo ticks 0xFFFFFFFE -> 0xFFFFFFFF at posedge.
    #   csrw  minstret, s2   <- RACE: at this EX cycle lo = 0xFFFFFFFF and
    #                            minstret_wr=1 (write wins on lo); pre-fix hi += 1.
    #   csrrs IR             <- re-inhibit (freeze)
    #   csrr  minstreth, t1
    #=========================================================================

    csrrs x0, MCOUNTINHIBIT, s5    # inhibit IR
    csrw MINSTRET, s4              # lo = 0xFFFFFFFE
    csrw MINSTRETH, x0             # hi = 0
    csrrc x0, MCOUNTINHIBIT, s5    # un-inhibit IR
    csrw MINSTRET, s2              # RACE
    csrrs x0, MCOUNTINHIBIT, s5    # re-inhibit IR
    csrr t1, MINSTRETH
    sw   t1, 0x00(s1)
    lw   t0, 0x00(s1)              # drain

    li   x31, 0x22222222


    #=========================================================================
    # PHASE 3: mcycle race
    #
    # Sequence (mcycle uses mcountinhibit_reg; 1 NOP after csrrc so the
    # inhibit FF updates and lo ticks 0xFFFFFFFE -> 0xFFFFFFFF):
    #   csrrs CY             <- inhibit
    #   csrw  mcycle, 0xFFFFFFFE
    #   csrw  mcycleh, 0
    #   csrrc CY             <- un-inhibit (takes effect at next posedge)
    #   nop                  <- 1 cycle: lo ticks 0xFFFFFFFE -> 0xFFFFFFFF
    #   csrw  mcycle, s3     <- RACE: at this EX cycle lo = 0xFFFFFFFF and
    #                            mcycle_wr=1; pre-fix hi += 1.
    #   csrrs CY             <- re-inhibit
    #   csrr  mcycleh, t1
    #=========================================================================

    csrrs x0, MCOUNTINHIBIT, s6    # inhibit CY
    csrw MCYCLE, s4                # lo = 0xFFFFFFFE
    csrw MCYCLEH, x0               # hi = 0
    csrrc x0, MCOUNTINHIBIT, s6    # un-inhibit CY
    nop                            # 1 cycle to align race
    csrw MCYCLE, s3                # RACE
    csrrs x0, MCOUNTINHIBIT, s6    # re-inhibit CY
    csrr t1, MCYCLEH
    sw   t1, 0x04(s1)
    lw   t0, 0x04(s1)              # drain

    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test
