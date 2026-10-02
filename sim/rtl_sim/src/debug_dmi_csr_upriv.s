#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_csr_upriv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DMI abstract CSR access bypasses privilege
#   The hart drops to U-mode and spins there. The testbench halts it over the
#   DMI bus while it is parked in U-mode, then uses the Debug Module's abstract
#   "Access Register" command to WRITE/READ an M-only CSR (mscratch) and READ a
#   machine counter (mcycle). The DM has full M-mode CSR visibility regardless of
#   the hart's current privilege, so these accesses must succeed (cmderr=0). If
#   the DM did NOT bypass privilege, a machine-CSR access while privilege=U would
#   fault (cmderr=3) — so cmderr=0 here is exactly what discriminates the feature.
#
#   The firmware never touches mscratch itself before the DM does. After resume
#   (still in U-mode), the firmware ecalls into the M-mode handler and reads
#   mscratch into x20; x20 == 0x0BADF00D proves the DM write landed in the
#   architectural M-only CSR while the hart was halted in U-mode.
#
#   Registers:
#     x18 : sentinel marker, must survive untouched (expect 0xA5A5A5A5)
#     x20 : mscratch read back in M-mode after resume (expect 0x0BADF00D)
#     x5  : loop counter (frozen while halted)        (t0)
#     x6  : loop bound
#     x31 : sync (11111111=in U-mode/spinning, 22222222=read back, deadbeef=done)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main
main:
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x20, 0                 # will hold the post-resume mscratch read-back

    la   t0, mtrap_handler      # M-mode trap vector, direct mode
    csrw mtvec, t0

    li   t0, 0x1800            # mstatus.MPP field
    csrc mstatus, t0           # MPP = 00 (return to U-mode)
    la   t0, umode_entry
    csrw mepc, t0
    mret                        # drop to U-mode at umode_entry

    #-------------------------------------------------------------
    # U-mode: spin (the testbench halts somewhere in here). The DM
    # injects mscratch while we are parked in U-mode. After resume
    # (still U-mode), ecall into M-mode to read mscratch back.
    #-------------------------------------------------------------
    .align 2
umode_entry:
    li   x5,  0                 # loop counter (frozen while halted)
    li   x6,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)
    li   x31, 0x11111111        # sync: in U-mode, ready to be halted
uspin:
    addi x5,  x5, 1
    blt  x5,  x6, uspin         # count up to the bound (paused while halted)

    ecall                       # enter M-mode to read the DM-written mscratch
uhang:
    j    uhang

    #-------------------------------------------------------------
    # M-mode handler: read mscratch (now in M-mode), then finish.
    #-------------------------------------------------------------
    .align 2
mtrap_handler:
    csrr x20, mscratch          # x20 = mscratch (value the DM injected while halted in U)
    li   x31, 0x22222222        # sync: mscratch read back in M-mode
    li   x31, 0xdeadbeef        # final sync: test done
hhang:
    j    hhang
