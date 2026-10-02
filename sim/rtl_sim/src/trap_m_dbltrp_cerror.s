#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_m_dbltrp_cerror
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Smdbltrp critical-error state, reached with MDT CLEAR
#
#   "A trap that occurs when executing in M-mode with mnstatus.NMIE set to 0 is
#   an unexpected trap" -- independently of MDT. NMIE is software-SET-only, so
#   the only way to be running with NMIE=0 after boot is inside an RNMI handler.
#
#   The firmware arms NMIE, clears MDT, then takes a pin RNMI. Inside the RNMI
#   handler NMIE is 0 and MDT is still 0, so the illegal instruction there is an
#   unexpected trap purely by the NMIE rule. With no RNMI deliverable there is
#   nothing to divert to, so the hart enters the critical-error state.
#
#   MDT is verified to be 0 at that moment and published, so a pass cannot be
#   attributed to the MDT arm of the detection.
#
#   There is no way out -- the testbench ends the run on lockup_o, so this test
#   has no 0xdeadbeef sync.
#
# Scratchpad (base 0x80000000):
#   0x00 rnmi_entries   0x04 mstatush (MDT) seen inside the RNMI handler
#   0x08 mncause in the handler  0x0C written ONLY if execution wrongly continued
#   0x10 rnmi_handler address (for the testbench)
#----------------------------------------------------------------------------

.equ MSTATUSH, 0x310
.equ MNSTATUS, 0x744
.equ MNCAUSE,  0x742

.section .text
.global main

main:
    j _start

    #=================================================================
    # M TRAP HANDLER -- must never be entered. If the critical error
    # failed to form, the illegal instruction below would land here.
    #=================================================================
    .align 2
m_handler:
    li   t0, 0xBAD
    sw   t0, 0x0C(s1)
    mret

    #=================================================================
    # RNMI HANDLER -- runs with NMIE=0. MDT is 0 here, so the fault
    # below is unexpected purely by the NMIE rule.
    #=================================================================
    .align 2
rnmi_handler:
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    csrr t0, MSTATUSH
    sw   t0, 0x04(s1)          # must read 0 -- MDT is NOT what triggers this
    csrr t0, MNCAUSE
    sw   t0, 0x08(s1)

    li   x31, 0x22222222       # Sync: in the RNMI handler, about to fault

h_fault_pc:
    .word 0xFFFFFFFF           # unexpected trap (NMIE=0) -> critical error

    # Unreachable. If the core kept going, this store is the evidence.
    li   t0, 0xBAD
    sw   t0, 0x0C(s1)
    .word 0x70200073           # mnret

    #=================================================================
    # MAIN
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   x0, 0x00(s1)
    sw   x0, 0x04(s1)
    sw   x0, 0x08(s1)
    sw   x0, 0x0C(s1)

    la   t0, rnmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x10(s1)          # testbench programs nmi_vector from here

    la   t0, m_handler
    csrw mtvec, t0

    csrsi MNSTATUS, 8          # NMIE = 1 -- traps are deliverable again
    csrw  MSTATUSH, x0         # MDT = 0 -- so the critical error cannot come from MDT

    li   x31, 0x11111111       # Sync: armed; testbench programs nmi_vector, then pulses NMI

wait_nmi:
    j    wait_nmi              # the RNMI arrives here
