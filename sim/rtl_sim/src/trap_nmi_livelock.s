#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_livelock
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI LIVELOCK SUPPRESSION
#   Verifies that after mnret, nmi_detect is suppressed for one instruction
#   cycle even if nmi_i stays asserted.  Without the fix, mnret immediately
#   re-enables NMIE and the handler is re-entered before any instruction
#   executes, causing infinite livelock.
#
#   The RTL fix: nmi_suppress_post_mnret register is set on mnret_taken and
#   cleared when a valid instruction arrives in ID.  This guarantees at least
#   one instruction of forward progress between NMI handler invocations.
#
#   Scratchpad layout (base 0x80000000):
#   0x00: nmi_count      (incremented each NMI handler entry)
#   0x04: progress_count (incremented each p1_loop iteration)
#   0x08: nmi_handler_addr (for testbench to configure nmi_vector)
#
#   Sync values:
#   0x11111111 - init done, nmi_handler_addr stored
#   0x12121212 - about to enter phase 1 loop (testbench asserts nmi)
#   0x22222222 - phase 1 done (nmi_count >= 3, forward progress confirmed)
#   0xdeadbeef - end of test
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI HANDLER (Smrnmi)
    # Entered when nmi_i asserts and NMIE=1.
    # On entry: hardware clears NMIE, saves PC to mnepc.
    # Increments nmi_count and issues mnret to resume at mnepc.
    # With the livelock-suppression fix, at least one instruction of
    # the main loop executes before the handler can be re-entered.
    #=================================================================
    .align 2

nmi_handler:
    addi sp, sp, -8
    sw   t0, 4(sp)
    sw   t1, 0(sp)

    # Increment nmi_count at scratchpad[0x00]
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    lw   t1, 0(sp)
    lw   t0, 4(sp)
    addi sp, sp, 8

    .word 0x70200073         # mnret: restore NMIE=1, jump to mnepc


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    # Initialize stack pointer
    li   sp, 0x80010000

    # Initialize scratchpad base pointer (kept throughout test in s1)
    li   s1, 0x80000000

    # Zero scratchpad area
    li   t0, 0
    sw   t0, 0x00(s1)          # nmi_count      = 0
    sw   t0, 0x04(s1)          # progress_count = 0
    sw   t0, 0x08(s1)          # nmi_handler_addr = 0

    # Store nmi_handler address for testbench to configure nmi_vector
    la   t0, nmi_handler
    sw   t0, 0x08(s1)
    lw   t3, 0x08(s1)          # fence: wait for SW AHB data phase before sync

    # Enable NMI (NMIE resets to 0 per Smrnmi spec; must be set before NMI can be taken)
    csrsi 0x744, 8             # mnstatus.NMIE = 1

    # Signal: init done, handler address stored
    li   x31, 0x11111111


    #=================================================================
    # PHASE 1: NMI livelock suppression (positive test)
    #
    # nmi_i is held high by the testbench while the firmware runs
    # the progress loop below.  Each loop iteration increments
    # progress_count, proving forward progress is made.  The NMI
    # handler increments nmi_count on every re-entry.
    #
    # Without the fix: mnret immediately re-triggers NMI, handler
    # loops forever, progress_count never advances — livelock.
    #
    # With the fix: one instruction executes between handler exits
    # and re-entries, so progress_count grows alongside nmi_count.
    #
    # The test waits until nmi_count >= 3, then deasserts nmi from
    # the testbench side and signals phase 1 complete.
    #=================================================================

    # Signal: about to enter phase 1 loop — testbench asserts nmi here
    li   x31, 0x12121212

p1_loop:
    lw   t0, 0x04(s1)          # load progress_count
    addi t0, t0, 1
    sw   t0, 0x04(s1)          # increment it (proves forward progress)

    lw   t1, 0x00(s1)          # load nmi_count
    li   t2, 3
    blt  t1, t2, p1_loop       # loop until nmi_count >= 3

    # Signal: phase 1 done (nmi_count >= 3, forward progress was made)
    li   x31, 0x22222222


    #=================================================================
    # END OF TEST
    #=================================================================
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
