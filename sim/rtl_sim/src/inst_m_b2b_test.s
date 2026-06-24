#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_m_b2b_test
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: back-to-back muldiv patterns
#   Exercises four back-to-back patterns through the shared MUL/DIV unit:
#   Phase 1: MUL → DIV → REM   (DIV-after-MUL is the suspect pattern)
#   Phase 2: MUL → REM         (REM-after-MUL with no DIV between)
#   Phase 3: DIV → DIV         (control — should always work)
#   Phase 4: MUL → MUL         (control — should always work)
#
#   No non-muldiv instructions are scheduled between the back-to-back ops in
#   each phase, so the shared FSM's idle-cycle reset path is NOT exercised —
#   this isolates the inter-op handoff. Sync sentinels in x31 separate the
#   phases for the testbench's per-phase result checks.
#----------------------------------------------------------------------------

.section .text
.global main
main:
    jal  t0, _random_irq_init

    li   x31, 0xFFFFFFFF       # start-of-test sync

    /* ------------------------------------------------------------------- */
    /* Phase 1: MUL → DIV → REM                                            */
    /* ------------------------------------------------------------------- */
    li   t0, 0x00000007        # 7
    li   t1, 0x00000003        # 3

    mul  t2, t0, t1            # t2 = 7 * 3 = 21 = 0x15
    div  t3, t0, t1            # t3 = 7 / 3 = 2  = 0x2
    rem  t4, t0, t1            # t4 = 7 % 3 = 1  = 0x1

    li   x31, 0x11111111       # phase-1 sync

    /* ------------------------------------------------------------------- */
    /* Phase 2: MUL → REM (no DIV between)                                 */
    /* ------------------------------------------------------------------- */
    li   t0, 0x0000000D        # 13
    li   t1, 0x00000004        # 4

    mul  t2, t0, t1            # t2 = 13 * 4 = 52 = 0x34
    rem  t3, t0, t1            # t3 = 13 % 4 = 1  = 0x1

    li   x31, 0x22222222       # phase-2 sync

    /* ------------------------------------------------------------------- */
    /* Phase 3: DIV → DIV (control)                                        */
    /* NB: do NOT use t6 (=x31) as an operand register — that would       */
    /* clobber the sync sentinel. Phase-1's t4 result is already checked   */
    /* and free to reuse from phase 3 onward.                              */
    /* ------------------------------------------------------------------- */
    li   t0, 0x00000064        # 100
    li   t1, 0x00000005        # 5
    li   t5, 0x0000003C        # 60
    li   t4, 0x00000004        # 4

    div  t2, t0, t1            # t2 = 100 / 5 = 20 = 0x14
    div  t3, t5, t4            # t3 = 60  / 4 = 15 = 0xF

    li   x31, 0x33333333       # phase-3 sync

    /* ------------------------------------------------------------------- */
    /* Phase 4: MUL → MUL (control)                                        */
    /* ------------------------------------------------------------------- */
    li   t0, 0x00000007        # 7
    li   t1, 0x0000000B        # 11
    li   t5, 0x0000000D        # 13
    li   t4, 0x00000011        # 17

    mul  t2, t0, t1            # t2 = 7 * 11 = 77  = 0x4D
    mul  t3, t5, t4            # t3 = 13 * 17 = 221 = 0xDD

    li   x31, 0x44444444       # phase-4 sync

    li   x31, 0xdeadbeef       # end-of-test sync

end_of_test:
    nop
    j end_of_test
