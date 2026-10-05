#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_csr_next_inst
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: A TRIGGER CSR WRITE IS SEEN BY THE VERY NEXT INSTRUCTION
#   Unpriv "CSR Access Ordering": the side effects of a CSR access are
#   observable by the very next instruction. Execute trigger 0 (action = 0,
#   breakpoint exception, M-mode) and the instruction at its address directly
#   follow each write:
#     1. disarm   : csrw tdata1, x0       ; tgt1  -> no breakpoint
#     2. mte off  : csrci tcontrol, 8      ; tgt2  -> no breakpoint
#     3. retarget : csrw tdata2, &tgt3b    ; tgt3a (old address) -> none
#     4. arm      : csrw tdata1, armed     ; tgt4  -> one breakpoint, mepc = tgt4
#     5. mte on   : csrsi tcontrol, 8      ; tgt5  -> one breakpoint, mepc = tgt5
#   The handler records mepc in order and skips the instruction.
#   s0 (x8) = breakpoints taken (expected 2)
#   Scratchpad (base 0x80000000): 0x00/0x04 mepc of breakpoints 1/2
#----------------------------------------------------------------------------

.equ ARMED, 0x60000044              # mcontrol6: m, execute, action 0, match =

.section .text
.global main
main:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw  mstatush, x0              # mstatus.MDT   = 0
    la    t0, trap_handler
    csrw  mtvec, t0
    li    s0, 0
    li    s1, 0x80000000
    sw    x0, 0(s1)
    sw    x0, 4(s1)
    li    t1, ARMED
    csrw  0x7a0, x0                 # tselect = 0
    csrsi 0x7a5, 8                  # tcontrol.mte = 1
    li    x31, 0x11111111

    .option push
    .option norvc

    # 1. disarm
    la    t0, tgt1
    csrw  0x7a2, t0
    csrw  0x7a1, t1
    csrw  0x7a1, x0
tgt1:
    addi  a2, x0, 1

    # 2. mte off
    la    t0, tgt2
    csrw  0x7a2, t0
    csrw  0x7a1, t1
    csrci 0x7a5, 8
tgt2:
    addi  a2, x0, 2
    csrw  0x7a1, x0
    csrsi 0x7a5, 8

    # 3. retarget away
    la    t0, tgt3a
    csrw  0x7a2, t0
    la    t2, tgt3b
    csrw  0x7a1, t1
    csrw  0x7a2, t2
tgt3a:
    addi  a2, x0, 3
    csrw  0x7a1, x0
tgt3b:
    addi  a2, x0, 4

    # 4. arm
    la    t0, tgt4
    csrw  0x7a2, t0
    csrw  0x7a1, t1
tgt4:
    addi  a2, x0, 5
    csrw  0x7a1, x0

    # 5. mte on
    la    t0, tgt5
    csrw  0x7a2, t0
    csrci 0x7a5, 8
    csrw  0x7a1, t1
    csrsi 0x7a5, 8
tgt5:
    addi  a2, x0, 6
    csrw  0x7a1, x0

    .option pop

    la    a0, tgt4
    la    a1, tgt5
    li    x31, 0xdeadbeef
end_of_test:
    j     end_of_test

    .align 2
trap_handler:
    csrr  t0, mcause
    li    t2, 3
    bne   t0, t2, bad
    csrr  t0, mepc
    slli  t2, s0, 2
    add   t2, t2, s1
    sw    t0, 0(t2)
    addi  s0, s0, 1
    addi  t0, t0, 4
    csrw  mepc, t0
    mret
bad:
    li    x31, 0xbadbad00
park:
    j     park
