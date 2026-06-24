#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_smrnmi_excp_preempt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ACCEPTED-DEVIATION LOCK
#   NMI PREEMPTS AN IN-FLIGHT POSTED STORE -> FAULT DROPPED
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI HANDLER (Smrnmi)
    # Entered when nmi_i asserts and NMIE=1. On entry hardware clears
    # NMIE and saves the resume PC to mnepc. We read mnepc, store it to
    # the scratchpad, then MNRET. Under the accepted deviation the
    # preempted store is treated as posted/committed, so mnepc resumes
    # strictly PAST the store and it is NOT replayed.
    #=================================================================
    .align 2

nmi_handler:
    addi sp, sp, -8
    sw   t0,  4(sp)
    sw   t1,  0(sp)

    # nmi_count++
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Capture mnepc -- under the deviation this resumes PAST the store
    csrr t1, 0x741              # mnepc = 0x741
    sw   t1, 0x10(s1)

    lw   t1,  0(sp)
    lw   t0,  4(sp)
    addi sp, sp,  8

    .word 0x70200073            # mnret: restore NMIE=1, resume at mnepc


    #=================================================================
    # M-MODE TRAP HANDLER (mtvec) -- SPEC-STRICT TRIPWIRE
    # Under the accepted deviation this NEVER runs (the store-access-fault
    # is dropped). It is retained so that IF a future blocking-store path
    # makes the fault fire, exc_count becomes 1 -> the deviation-lock goes
    # RED (instead of livelocking) and mepc is advanced so the run still
    # terminates. Captures mcause / mepc, then steps mepc past the store.
    #=================================================================
    .align 2

trap_handler:
    addi sp, sp, -8
    sw   t0,  4(sp)
    sw   t1,  0(sp)

    # exc_count++
    lw   t0, 0x04(s1)
    addi t0, t0, 1
    sw   t0, 0x04(s1)

    # Capture mcause (expect 7)
    csrr t0, mcause
    sw   t0, 0x14(s1)

    # Capture mepc (expect faulting store PC)
    csrr t1, mepc
    sw   t1, 0x18(s1)

    # Advance mepc past the faulting store (sw is a 4-byte instruction)
    addi t1, t1, 4
    csrw mepc, t1

    lw   t1,  0(sp)
    lw   t0,  4(sp)
    addi sp, sp,  8

    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000         # scratchpad base

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)           # nmi_count
    sw   t0, 0x04(s1)           # exc_count
    sw   t0, 0x08(s1)           # nmi_handler_addr
    sw   t0, 0x0C(s1)           # store_fault_pc
    sw   t0, 0x10(s1)           # mnepc_in_nmi
    sw   t0, 0x14(s1)           # mcause_in_trap
    sw   t0, 0x18(s1)           # mepc_in_trap

    # Publish NMI handler address for the testbench
    la   t0, nmi_handler
    sw   t0, 0x08(s1)

    # Publish the faulting-store PC for the testbench (used to time NMI
    # and as the strict expected mnepc / mepc value)
    la   t0, store_fault
    sw   t0, 0x0C(s1)

    # Install the M-mode trap handler (mtvec)
    la   t0, trap_handler
    csrw mtvec, t0

    # Enable NMI: mnstatus.NMIE = 1 (bit[3]); resets to 0 per Smrnmi
    csrsi 0x744, 8

    # Initialize a sentinel register (must survive NMI + re-exec + trap)
    li   s2, 0xA5A5A5A5

    # Pre-load the store operands so NOTHING is between the pre-store
    # sentinel and the faulting store itself.
    li   t2, 0                  # unmapped store address -> access fault
    li   t3, 0xDEADC0DE         # store data

    #=================================================================
    # Pre-store sync point. The testbench latches nmi_vector on this
    # marker, then waits for probes_cpu.pc == store_fault to assert NMI
    # on the precise cycle the faulting store reaches decode.
    #
    # NOTE: this `li x31,...` is the LAST instruction before the store.
    #=================================================================
    li   x31, 0x11111111

store_fault:
    sw   t3, 0(t2)              # store to address 0. NMI preempts it
                                # while its AHB error response is in
                                # flight -> posted/committed, fault
                                # DROPPED, store NOT replayed (deviation).

    # Under the accepted deviation we reach here after: NMI taken &
    # serviced, MNRET resuming PAST the store (fault never reported,
    # mtvec handler never ran). Program completes normally.
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
