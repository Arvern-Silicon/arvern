#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_lockup
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI LOCKUP
#   NMI lockup escape test -- two phases:
#
#   Phase 1 (positive): NMI escapes lockup
#   - irqkill_cfg[3]=1 (escape enabled)
#   - CPU enters lockup via double M-mode exception
#   - NMI fires -> nmi_handler -> fixes mepc to escape_cleanup, sets
#   mnepc=nmi_exit, executes mnret -> goes to nmi_exit -> mret clears
#   in_m_excp_trap -> returns to escape_cleanup
#   - CPU escapes lockup (lockup_o deasserts)
#
#   Phase 2 (negative): NMI does NOT escape lockup
#   - irqkill_cfg[3]=0 (escape disabled, reset default)
#   - CPU enters lockup again via same mechanism
#   - NMI fires but CPU remains locked (fetch stays stalled)
#   - lockup_o remains asserted
#
#   Scratchpad layout (base 0x80000000):
#   0x00: nmi_count         (incremented each NMI handler entry)
#   0x04: m_trap_count      (incremented each M-mode trap handler entry)
#   0x08: nmi_handler_addr  (for testbench to set nmi_vector)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI HANDLER (Smrnmi)
    # Entered when NMI fires while CPU is in lockup (Phase 1 only,
    # when irqkill_cfg[3]=1 allows escape).
    # Increments nmi_count, fixes MEPC to escape_cleanup, sets
    # mnepc to nmi_exit, then executes mnret -> goes to nmi_exit.
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

    # Fix MEPC to point to escape_cleanup (safe recovery point after lockup)
    la   t1, escape_cleanup
    csrw mepc, t1

    # Set mnepc to nmi_exit (mnret will jump there; mret there clears in_m_excp_trap)
    la   t1, nmi_exit
    csrw 0x741, t1             # mnepc = nmi_exit

    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16

    .word 0x70200073           # mnret -> jumps to mnepc = nmi_exit

    #=================================================================
    # NMI_EXIT: intermediate trampoline executed after mnret
    # Executes mret which clears in_m_excp_trap and returns to
    # MEPC = escape_cleanup, allowing full lockup escape.
    #=================================================================
nmi_exit:
    mret                       # clears in_m_excp_trap, returns to escape_cleanup

    #=================================================================
    # M-MODE TRAP HANDLER
    # Entered on first illegal instruction from M-mode context.
    # Increments m_trap_count, then executes a second illegal
    # instruction -> go_to_lockup=1 -> in_lockup=1 -> fetch stalled.
    #=================================================================
    .align 2

m_trap_handler:
    addi sp, sp, -8
    sw   t0, 4(sp)
    sw   t1, 0(sp)

    # Increment M-mode trap count
    lw   t0, 0x04(s1)
    addi t0, t0, 1
    sw   t0, 0x04(s1)

    lw   t1, 0(sp)
    lw   t0, 4(sp)
    addi sp, sp, 8

    # Second illegal instruction while in M-mode exception handler.
    # in_m_excp_trap=1 -> go_to_lockup=1 -> in_lockup=1 -> fetch stalled.
    .word 0xFFFFFFFF           # -> lockup (never returns without NMI escape)

    mret                       # Never reached

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)          # nmi_count
    sw   t0, 0x04(s1)          # m_trap_count
    sw   t0, 0x08(s1)          # nmi_handler_addr

    # Store nmi_handler address in scratchpad for testbench to configure nmi_vector
    la   t0, nmi_handler
    sw   t0, 0x08(s1)          # nmi_handler_addr

    #=================================================================
    # PHASE 1: NMI escapes lockup (escape enabled via irqkill_cfg[3]=1)
    #=================================================================

    # Enable NMI lockup escape: irqkill_cfg = 0xF (bit[3]=1)
    li   t0, 0xF
    csrw 0x7FF, t0             # irqkill_cfg = 1111 (bit3=1 = escape enabled)

    # Install M-mode trap handler
    la   t0, m_trap_handler
    csrw mtvec, t0

    # Enable NMI (NMIE resets to 0 per Smrnmi spec; must be set before NMI can be taken)
    csrsi 0x744, 8             # mnstatus.NMIE = 1

    li   x31, 0x11111111       # Sync: init done, nmi_handler_addr stored, escape enabled

    # Trigger first M-mode exception.
    # -> m_trap_handler entered (in_m_excp_trap=1).
    # -> handler executes second .word 0xFFFFFFFF -> lockup.
    # CPU stalls here until NMI fires -> nmi_handler runs -> nmi_exit -> escape_cleanup.
    .word 0xFFFFFFFF

    # Never reached directly -- CPU is stalled in lockup until NMI escape.

    #=================================================================
    # ESCAPE CLEANUP: reached after NMI escape sequence completes
    # (nmi_handler fixes MEPC here, mret in nmi_exit returns here)
    #=================================================================
escape_cleanup:
    li   x31, 0x12121212       # Sync: Phase 1 done -- CPU escaped lockup!

    #=================================================================
    # PHASE 2: NMI does NOT escape lockup (escape disabled via irqkill_cfg[3]=0)
    #=================================================================

    # Disable NMI lockup escape: irqkill_cfg = 0x7 (bit[3]=0)
    li   t0, 0x7
    csrw 0x7FF, t0             # irqkill_cfg = 0111 (bit3=0 = escape disabled)

    # Reset m_trap_count for Phase 2 tracking
    li   t0, 0
    sw   t0, 0x04(s1)

    li   x31, 0x22222222       # Sync: ready for Phase 2 lockup

    # Trigger lockup again.
    # -> m_trap_handler entered -> second illegal -> lockup.
    # NMI fires but irqkill_cfg[3]=0 so CPU stays locked (fetch stays stalled).
    .word 0xFFFFFFFF

    # Never reached: CPU is permanently stalled in lockup for Phase 2.
end_of_test:
    j    end_of_test
