#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_bus_err_estat_w1c_race
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: marv_estat.valid W1C IN THE CYCLE OF A SECOND DATA-BUS ERROR
#   Each trial: a store to unmapped address 0 raises RNMI #1. Its handler
#   issues a second faulting store (address 8), k nops (k = 0..7), then
#   clears marv_estat (csrw 0x7FE, 5) and mnrets. The second error's RNMI #2
#   records marv_estat and marv_eaddr.
#   Depending on k the second error lands before, with or after the clear:
#     - before: it is an overrun of the first fault, and the clear removes
#       both flags (valid = 0, overrun = 0);
#     - with or after: it is captured as a new first fault (valid = 1,
#       marv_eaddr = 8).
#   An RNMI must never see overrun = 1 with valid = 0 (evidence lost).
#   Scratchpad (base 0x80000000), trial k at 0x40 + 8*k:
#     +0 marv_estat at RNMI #2, +4 marv_eaddr at RNMI #2
#----------------------------------------------------------------------------

.equ MARV_ESTAT, 0x7FE
.equ MARV_EADDR, 0xFFD
.equ MARV_NMVEC, 0x7FD

# RNMI handler for trial \k: first entry faults again and clears, second records
.macro HANDLER k
    .align 2
nmi_h\k:
    bnez  s1, 1f
    li    s1, 1
    li    t1, 8
    li    t2, 5
    sw    x0, 0(t1)                 # second data-bus error
    .rept \k
    nop
    .endr
    csrw  MARV_ESTAT, t2
    .word 0x70200073                # mnret
1:  csrr  t0, MARV_ESTAT
    sw    t0, 0(a0)
    csrr  t0, MARV_EADDR
    sw    t0, 4(a0)
    li    t2, 5
    csrw  MARV_ESTAT, t2
    li    s1, 2
    .word 0x70200073                # mnret
.endm

.macro TRIAL k
    la    t0, nmi_h\k
    csrw  MARV_NMVEC, t0
    li    s1, 0
    sw    x0, 0(zero)               # first data-bus error
    li    a1, 2
1:  bne   s1, a1, 1b
    addi  a0, a0, 8
.endm

.section .text
.global main
main:
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw  mstatush, x0              # mstatus.MDT   = 0
    la    t0, trap_handler
    csrw  mtvec, t0
    li    a0, 0x80000040
    li    x31, 0x11111111

    TRIAL 0
    TRIAL 1
    TRIAL 2
    TRIAL 3
    TRIAL 4
    TRIAL 5
    TRIAL 6
    TRIAL 7

    li    x31, 0xdeadbeef
end_of_test:
    j     end_of_test

    .align 2
trap_handler:
    li    x31, 0xbadbad00
park:
    j     park

    HANDLER 0
    HANDLER 1
    HANDLER 2
    HANDLER 3
    HANDLER 4
    HANDLER 5
    HANDLER 6
    HANDLER 7
