#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_wfi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI WFI
#   NMI wakes WFI verification:
#   - Processor executes WFI and stalls
#   - NMI fires -> wfi_wakeup asserted -> NMI handler entered
#   - mnepc = address of WFI instruction (saved to scratchpad)
#   - Handler advances mnepc by 4 so mnret returns past WFI
#   - mnret resumes at lw after WFI; nmi_count > 0 so loop exits
#
#   Scratchpad layout (base 0x80000000):
#   0x000: nmi_count         (incremented each NMI entry)
#   0x004: mnepc_wfi         (original mnepc saved at NMI entry = WFI addr)
#   0x008: nmi_handler_addr  (address of nmi_handler, for testbench)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI HANDLER (Smrnmi)
    # Saves original mnepc (WFI address), increments nmi_count.
    # Advances mnepc by 4 so mnret returns to instruction after WFI.
    # Issues mnret to resume past WFI.
    #=================================================================
    .align 2

nmi_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)

    # Increment NMI count
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Save original MNEPC (WFI instruction address)
    csrr t1, 0x741             # mnepc = 0x741
    sw   t1, 0x04(s1)          # mnepc_wfi (for testbench to verify)

    # Advance mnepc by 4 so mnret returns to instruction after WFI
    # (WFI is always a 4-byte instruction)
    addi t1, t1, 4
    csrw 0x741, t1             # update mnepc to WFI+4

    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16

    .word 0x70200073           # mnret: restore NMIE=1, jump to mnepc (WFI+4)

    #=================================================================
    # SAFE MTVEC (regular exception fallback — should not fire here)
    #=================================================================
    .align 2

safe_mtvec:
    mret

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)          # nmi_count
    sw   t0, 0x04(s1)          # mnepc_wfi
    sw   t0, 0x08(s1)          # nmi_handler_addr

    # Store nmi_handler address in scratchpad for testbench to read
    la   t0, nmi_handler
    sw   t0, 0x08(s1)          # nmi_handler_addr

    # Install safe mtvec (regular exceptions go here)
    la   t0, safe_mtvec
    csrw mtvec, t0

    # Enable NMI (NMIE resets to 0 per Smrnmi spec; must be set before NMI can be taken)
    csrsi 0x744, 8             # mnstatus.NMIE = 1

    li   x31, 0x11111111       # Sync: init done, handler address stored
                               # Testbench reads nmi_handler_addr, sets nmi_vector

    # Signal: about to execute WFI — testbench must assert NMI soon
    li   x31, 0x22222222

    # WFI loop: execute WFI then check if NMI was taken.
    # After NMI fires:
    #   1. wfi_wakeup asserted -> processor wakes up
    #   2. NMI handler runs, saves mnepc (WFI addr), advances mnepc to WFI+4
    #   3. mnret returns to WFI+4 (the lw instruction below)
    #   4. lw loads nmi_count (= 1), bnez exits loop
wfi_loop:
    wfi                        # Stall until NMI wakeup
    lw   t0, 0x00(s1)          # Check nmi_count (reached here after mnret to WFI+4)
    bnez t0, wfi_done          # If NMI was taken, exit loop
    j    wfi_loop              # Otherwise wait again

wfi_done:
    li   x31, 0xdeadbeef       # Sync: all done

end_of_test:
    j    end_of_test
