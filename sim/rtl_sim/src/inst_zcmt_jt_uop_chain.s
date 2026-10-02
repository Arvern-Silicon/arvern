#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zcmt_jt_uop_chain
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Table jump landing directly on another micro-op instruction.
#
#   The UOP control register is held by ex_uop_ready_o, which pulses on jt_done.
#   ex_uop_enable_i therefore stays high past completion only when a NEW uop
#   dispatches in that same cycle -- and then jt_completed (set by jt_done) is
#   never cleared, because its clear term is ~ex_uop_enable_i. That is the
#   scenario the `if (!jt_completed)` guard in the JT_IDLE arm exists for, and
#   the only way to create it is a table jump whose TARGET BEGINS with a micro-op
#   instruction, so the two dispatches touch with no gap.
#
#   inst_zcmt_jt already chains cm.jt, but each of its targets starts with a
#   normal `li`, which leaves the redirect gap and never arms the guard.
#
#   Chains here: cm.jt -> cm.jt -> cm.jt -> cm.jt -> cm.push, then a cm.jalt pair,
#   every target's first instruction being the next micro-op.
#----------------------------------------------------------------------------

.section .text
.global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP
    #-------------------------------------------------
    li  x30, 0                    # error code
    li  x5,  0xCAFECAFE           # canary: must survive every redirect
    li  x18, 0                    # targets reached
    li  x19, 0                    # cm.jalt links taken

    li  sp,  0x80001000           # valid stack for cm.push / cm.pop

    #-------------------------------------------------
    # JVT setup: base 0x80000040, entry N at base + N*4
    #-------------------------------------------------
    li   t0, 0x80000040
    csrw 0x017, t0                # JVT.base

    la   t1, chain_a
    sw   t1, 0(t0)                # JVT[0]
    la   t1, chain_b
    sw   t1, 4(t0)                # JVT[1]
    la   t1, chain_c
    sw   t1, 8(t0)                # JVT[2]
    la   t1, chain_d
    sw   t1, 12(t0)               # JVT[3]
    la   t1, jalt_a
    sw   t1, 128(t0)              # JVT[32] -- cm.jalt range starts at 32
    la   t1, jalt_b
    sw   t1, 132(t0)              # JVT[33]

    li  x31, 0x11111111           # sync: setup done

    #=========================================================
    # Chain: every target's FIRST instruction is another micro-op
    #=========================================================
    cm.jt 0
    cm.push {ra}, -16             # uop in the branch shadow: must NOT execute
    j    test_fail

chain_a:
    cm.jt 1                       # target also begins with a uop
    cm.push {ra}, -16
    j    test_fail

chain_b:
    cm.jt 2
    cm.pop  {ra}, 16              # a second uop flavour in the shadow
    j    test_fail

chain_c:
    cm.jt 3
    cm.jt 0                       # table jump in the shadow of a table jump
    j    test_fail

chain_d:
    cm.push {ra}, -16             # a DIFFERENT uop type landing on the redirect
    li   x18, 4                   # all four cm.jt links were taken
    cm.pop  {ra}, 16

    #=========================================================
    # Same shape with cm.jalt (writes ra, so it also exercises the ALU state)
    #=========================================================
    li   x5, 0xCAFECAFE           # refresh canary
    cm.jalt 32
    cm.push {ra}, -16
    j    test_fail

jalt_a:
    cm.jalt 33                    # target also begins with a uop
    cm.jalt 32                    # table jump in the shadow of a table jump
    j    test_fail

jalt_b:
    li   x19, 2                   # both cm.jalt links were taken

    #-------------------------------------------------
    # CHECKS
    #-------------------------------------------------
    li   x30, 0x00000001
    li   x12, 0xCAFECAFE
    bne  x5,  x12, test_fail      # canary survived every redirect

    li   x30, 0x00000002
    li   x12, 4
    bne  x18, x12, test_fail

    li   x30, 0x00000003
    li   x12, 2
    bne  x19, x12, test_fail

    li   x30, 0x00000004
    li   x12, 0x80001000
    bne  sp,  x12, test_fail      # cm.push/cm.pop balanced

    #-------------------------------------------------
    # ALL TESTS PASSED
    #-------------------------------------------------
    li  x30, 0x00000000
    li  x31, 0xDEADBEEF
    j   end_of_test

test_fail:
    li  x31, 0xBADC0DE0
    j   end_of_test

end_of_test:
    nop
    j end_of_test                 # infinite loop
