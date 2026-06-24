#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_smrnmi_mnret_raw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MNRET RAW HAZARD ON MNEPC
#   Reproducer for the MNRET / mnepc RAW hazard:
#
#   fetch_stall_from_xret guards MRET and SRET against an in-flight CSR
#   write to MEPC/SEPC, but the gate term in arv_decode.v omits MNRET. A
#   back-to-back `csrw mnepc, t0; mnret` sequence therefore dispatches
#   MNRET while the csrw is still in EX (ex_csr_busy=1). mnret_taken fires
#   combinationally, trap_branch_target_comb reads the OLD mnepc_mnepc_reg,
#   and at the next clock edge trap_branch_target_r captures the OLD value
#   while mnepc_mnepc_reg updates with the NEW value -- mnret jumps to the
#   stale address.
#
#   Pre-fix: mnret resumes at the original NMI entry PC (inside spin_loop).
#   x31 stays at 0xC0DEC0DE; test times out at the bench-side x31
#   check window.
#   Post-fix: fetch_stall_from_xret extended to include MNRET; the back-
#   to-back csrw/mnret stalls one cycle, mnret reads the NEW mnepc
#   and jumps to mnret_new_target. x31 becomes 0xdeadbeef.
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI handler entry point. Testbench drives nmi_vector to this PC
    # after reading it from the scratchpad.
    #
    # The handler issues NO instructions between the csrw and the mnret
    # so the RAW window is reachable. `la t0, mnret_new_target` expands
    # to auipc+addi which precede the csrw; the csrw + mnret are
    # consecutive in instruction memory.
    #=================================================================
    .align 2
nmi_handler:
    la   t0, mnret_new_target
    csrw 0x741, t0                 # mnepc <- mnret_new_target
    .word 0x70200073               # mnret -- back-to-back, bug trigger


    #=================================================================
    # Safe fallback mtvec (must never fire).
    #=================================================================
    .align 2
safe_handler:
    mret


_start:
    li   sp, 0x80010000
    li   s1, 0x80000000            # scratchpad base

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)              # nmi_handler addr (testbench drives nmi_vector from here)

    # Publish NMI handler address for the testbench.
    la   t0, nmi_handler
    sw   t0, 0x08(s1)

    # Install safe mtvec (should never fire).
    la   t0, safe_handler
    csrw mtvec, t0

    # Enable NMI: mnstatus.NMIE = 1 (bit[3]).
    csrsi 0x744, 8

    li   x31, 0x11111111           # init done -- testbench latches nmi_vector

    # Spin loop. Testbench pulses NMI here. mnepc is captured by hardware
    # as the spin_target PC on NMI entry.
    li   x31, 0xC0DEC0DE
spin_target:
    j    spin_target


    #=================================================================
    # Post-fix landing zone: mnret with the NEW mnepc value jumps here.
    # Sentinel write tells the testbench we resumed at the correct PC.
    #=================================================================
    .align 2
mnret_new_target:
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
