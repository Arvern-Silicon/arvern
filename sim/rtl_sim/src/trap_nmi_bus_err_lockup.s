#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_bus_err_lockup
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: a data-bus error must not lift the critical-error state
#
#   The critical-error state (Smdbltrp, mnstatus.NMIE=0) is sticky: only reset
#   leaves it. A bus error is not a rescue signal -- a critically-errored core
#   still generating bus errors must not resurrect itself on its own faults.
#
#   The sequence is: store faults (captured, held pending by NMIE=0) -> drain ->
#   trap while MDT is set -> critical error. That leaves a real pending bus
#   error sitting under an active lockup_o, which must not lift.
#
# Scratchpad (base 0x80000000):
#   0x00 nmi_count (must stay 0)   0x08 nmi_handler addr
#----------------------------------------------------------------------------

.equ FAULT_ADDR, 0x00000000

.section .text
.global main

main:
    j _start

    .align 2
nmi_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)

    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    la   t1, escape_cleanup
    csrw mepc, t1

    la   t1, nmi_exit
    csrw 0x741, t1             # mnepc = nmi_exit

    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    .word 0x70200073           # mnret

nmi_exit:
    mret                       # clears in_m_excp_trap, returns to escape_cleanup

    .align 2
m_trap_handler:
    # MDT is set by this handler's own trap entry and deliberately not cleared,
    # so this fault is an unexpected double trap.
    .word 0xFFFFFFFF

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)

    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x08(s1)
    lw   zero, 0x08(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    # NMIE deliberately left at its reset value of 0: the bus error must be
    # PENDING, not delivered, when the lockup forms.

    li   x31, 0x11111111       # tb programs nmi_vector

    li   t3, 20
wait_vec:
    addi t3, t3, -1
    bnez t3, wait_vec

    # Fault first and let the data phase drain, so the pending bus error is
    # already captured when the critical error forms.
    li   t1, FAULT_ADDR
    li   t0, 0xDEAD
    sw   t0, 0(t1)

    li   t3, 40
drain:
    addi t3, t3, -1
    bnez t3, drain

    li   x31, 0x22222222       # bus error now pending; about to lock up

    .word 0xFFFFFFFF           # first exception -> m_trap_handler -> lockup

escape_cleanup:
    li   x31, 0xdeadbeef       # only reachable via the PIN escape

end_of_test:
    j    end_of_test
