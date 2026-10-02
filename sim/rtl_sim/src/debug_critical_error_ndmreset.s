#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_critical_error_ndmreset
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: recovery from the Smdbltrp critical-error state by an ndmreset
#   The critical-error state (lockup_o) is left by a reset only. The debugger
#   pulses dmcontrol.ndmreset; the hart boots again from the reset vector.
#
#   A boot counter in SRAM (survives the ndmreset, 0 at power-on) tells the
#   two boots apart:
#     boot 1: mnstatus.NMIE left at its reset value 0, so the ECALL is an
#             unexpected trap -> critical error. x31 = 11111111 first.
#     boot 2: normal Smdbltrp boot sequence, M handler installed, an ECALL
#             is taken and handled normally, x31 = deadbeef.
#
#   SRAM (0x80000000): 0x00 boot counter (2 at the end), 0x04 M handler
#   entries (1: boot 2's ecall only), 0x0C written only if boot 1 ran past
#   its ecall (must stay 0).
#----------------------------------------------------------------------------

.section .text
.global main

.option norvc

main:
    j    _start

    .align 2
m_handler:
    lw   t0, 0x04(s1)
    addi t0, t0, 1
    sw   t0, 0x04(s1)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

_start:
    li   s1, 0x80000000
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)              # boot counter
    lw   t1, 0x00(s1)              # the store has landed
    li   t2, 1
    bne  t1, t2, second_boot

    #=================================================================
    # BOOT 1: provoke the critical error
    #=================================================================
    sw   x0, 0x04(s1)
    sw   x0, 0x0C(s1)
    lw   t1, 0x0C(s1)
    li   x31, 0x11111111           # sync: about to provoke the critical error
    ecall                          # NMIE=0: unexpected trap -> critical error

    li   t0, 0xBAD                 # unreachable
    sw   t0, 0x0C(s1)
1:  j    1b

    #=================================================================
    # BOOT 2: normal boot after the ndmreset
    #=================================================================
second_boot:
    la   t0, m_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0

    ecall                          # an ordinary, handled trap
    lw   t1, 0x04(s1)
    addi t1, t1, 0

    li   x31, 0x22222222
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test
