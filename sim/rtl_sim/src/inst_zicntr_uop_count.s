#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_uop_count
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZICNTR + UOP RETIRE COUNT
#   Reproducer for RTL review #15: id_inst_retired_o over-counts on the UOP
#   branch shadow cycle (ex_uop_has_branch=1) for CM.POPRET / CM.POPRETZ.
#
#   The decoder mutes id_use_std_path / id_use_c_path during the UOP branch
#   cycle, but id_inst_retired_o was only gated by id_instruction_request_o
#   & id_instruction_valid_i -- both of which are 1 in that cycle since the
#   UOP-ready signal goes high (uop_done at counter=0). Result: each
#   CM.POPRET / CM.POPRETZ adds 1 extra count to minstret.
#
#   Window count (post-fix):
#   jal ra (1) + 4 instructions inside func (cm.push, li, add, cm.popret)
#   + 2 exit (li, csrrs) = 7
#
#   Pre-fix: cm.popret over-counts by 1 -> window = 8.
#   Post-fix: window = 7.
#
#   No random IRQ injection (no_random_irq test).
#----------------------------------------------------------------------------

.section .text
.global main

.equ MINSTRET,       0xB02
.equ MCOUNTINHIBIT,  0x320

main:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base
    # DO NOT call _random_irq_init (no_random_irq test)

    # Zero scratchpad
    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    sw   x0, 0x08(s1)
    sw   x0, 0x0C(s1)

    li   x31, 0x11111111       # init done


    #=========================================================================
    # Window: measure minstret across jal + CM.POPRET function
    #
    # Inhibit-gated window protocol:
    #   ENTER: set IR (counts), write minstret=0 (no count), clear IR (no count)
    #   WINDOW: instructions to measure
    #   EXIT:  li t0,4 (counts as n-1), csrrs IR (counts as n), csrr (no count)
    #=========================================================================

    # --- ENTER ---
    li   t0, 4
    csrrs x0, MCOUNTINHIBIT, t0    # set IR (inhibit minstret)
    csrw MINSTRET, x0              # minstret = 0 (not counted)
    csrrc x0, MCOUNTINHIBIT, t0    # clear IR (not counted, counting starts next inst)

    # --- WINDOW ---
    jal  ra, func_popret           # 1 (the call)
    # func_popret: cm.push, li, add, cm.popret = 4 instructions (post-fix)
    #              cm.popret over-counts by 1 in pre-fix => 5 instructions

    # --- EXIT ---
    li   t0, 4                     # counts as inst (n-1)
    csrrs x0, MCOUNTINHIBIT, t0    # counts as inst (n); inhibits from next
    csrr t1, MINSTRET              # reads frozen minstret (not counted)

    sw   t1, 0x00(s1)
    lw   t0, 0x00(s1)              # drain

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test


    #=========================================================================
    # CM.POPRET function: 4 instructions (post-fix), 5 instructions (pre-fix)
    #=========================================================================
    .align 2
func_popret:
    cm.push {ra, s0}, -16          # 1: push ra+s0, SP -= 16
    li   s0, 42                    # 2
    add  a0, s0, s0                # 3
    cm.popret {ra, s0}, 16         # 4: pop ra+s0, SP += 16, RET
