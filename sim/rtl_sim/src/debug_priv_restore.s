#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_priv_restore
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DEBUG HALTREQ privilege restore (Sdext)
#   On debug entry dcsr.prv captures the current privilege; on resume the hart's
#   privilege is restored from dcsr.prv (the `priv_mode_next_comb ... dbg_dcsr_prv`
#   redirect injection). This test halts the hart while it runs in U-mode and
#   proves resume lands back in U-mode — not M.
#
#   The discriminator is privilege-sensitive behaviour, not just "did it resume":
#   after resume the firmware (which must still be in U-mode) executes an M-only
#   CSR read (csrr mscratch). In U-mode that raises illegal-instruction; the
#   M-mode handler confirms mcause==2 AND mstatus.MPP==00 (trapped FROM U), and
#   only then sets the success flag. If resume had wrongly restored M, the csrr
#   would succeed, no trap would fire, the success flag would never be set, and
#   the "should be unreachable" marker (x22) would be written instead.
#
#   Registers:
#     x23 : success flag, set by handler   (expect 0x0000600D)
#     x22 : unreachable-if-correct marker   (expect 0x00000000)
#     x18  : sentinel marker                 (expect 0xA5A5A5A5)
#     x31 : sync (11111111=in U-mode/ready, 22222222=verified, deadbeef=done)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main
main:
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   x18,  0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x22, 0                 # unreachable-if-correct marker
    li   x23, 0                 # success flag (handler sets 0x600D)

    la   t0, mtrap_handler      # M-mode trap vector, direct mode
    csrw mtvec, t0

    li   t0, 0x1800            # mstatus.MPP field
    csrc mstatus, t0           # MPP = 00 (return to U-mode)
    la   t0, umode_entry
    csrw mepc, t0
    mret                        # drop to U-mode at umode_entry

    #-------------------------------------------------------------
    # U-mode: spin (the testbench halts somewhere in here), then do
    # an M-only CSR access that MUST trap because we are in U-mode.
    #-------------------------------------------------------------
    .align 2
umode_entry:
    li   x31, 0x11111111        # sync: in U-mode, ready to be halted
    li   t1, 2000
uspin:
    addi t1, t1, -1            # spin window for the async halt to land in U-mode
    bnez t1, uspin

    csrr t0, mscratch           # M-only CSR: illegal-instruction in U-mode -> trap
    li   x22, 0x00000BAD        # only reached if NO trap fired (priv wrongly M)
uhang:
    j    uhang

    #-------------------------------------------------------------
    # M-mode handler: confirm the fault really came from U-mode.
    #-------------------------------------------------------------
    .align 2
mtrap_handler:
    csrr t0, mcause
    li   t1, 2                  # illegal instruction
    bne  t0, t1, trap_bad       # wrong cause -> fail marker
    csrr t2, mstatus
    srli t2, t2, 11
    andi t2, t2, 3              # MPP field
    bnez t2, trap_bad           # MPP must be 00 (trapped from U-mode)

    li   x23, 0x0000600D        # success: hart was genuinely in U-mode after resume
    li   x31, 0x22222222        # sync: privilege restore verified
    li   x31, 0xdeadbeef        # final sync: test done
hhang:
    j    hhang

trap_bad:
    li   x22, 0x00000BAD        # fault came from the wrong privilege / cause
    li   x31, 0xdeadbeef        # still terminate so the testbench can flag it
    j    hhang
