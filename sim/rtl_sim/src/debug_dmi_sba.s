#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_sba
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: System Bus Access (SBA) over the DMI bus (Debug Module, Debug
#   Spec 1.0). The hart seeds three known sentinels into SRAM and then spins.
#   The testbench halts it (frozen-hart) and uses the DM's own AHB master
#   (sbcs/sbaddress0/sbdata0) to READ and WRITE system memory while halted:
#     - reads the three sentinels back over SBA,
#     - SBA-WRITES 0xDEADBEEF over the third word,
#     - exercises autoincrement block reads, sub-word (8/16-bit) access, and
#       the alignment / unsupported-size / bus-error sberror paths.
#   After resume the firmware re-reads the third word: it must be the SBA-written
#   0xDEADBEEF (proving the SBA write reached real memory), and the first
#   sentinel must be intact.
#
#   SRAM layout (base 0x80004000):
#     [0x00] = 0xCAFEBABE  (sentinel word0)
#     [0x04] = 0x12345678  (sentinel word1)
#     [0x08] = 0x0BADF00D  (seed; SBA-overwritten to 0xDEADBEEF while halted)
#     [0x10] = sub-word access scratch
#
#   Registers:
#     x10 : SRAM base 0x80004000
#     x11 : scratch (sentinel values)
#     x5  : loop counter (frozen while halted)
#     x6  : loop bound
#     x20 : post-resume read-back of [0x08]  (expect 0xDEADBEEF)
#     x21 : post-resume read-back of [0x00]  (expect 0xCAFEBABE)
#     x31 : sync (11111111=spinning, 22222222=post-resume, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x10, 0x80004000        # SRAM base

    li   x11, 0xCAFEBABE        # seed sentinel word0
    sw   x11, 0x00(x10)
    li   x11, 0x12345678        # seed sentinel word1
    sw   x11, 0x04(x10)
    li   x11, 0x0BADF00D        # seed word2 (SBA will overwrite to 0xDEADBEEF)
    sw   x11, 0x08(x10)

    li   x20, 0                 # post-resume read-back of [0x08]
    li   x21, 0                 # post-resume read-back of [0x00]
    li   x5,  0                 # loop counter (frozen while halted)
    li   x6,  0x00001000        # loop bound (long enough for the TB to halt mid-loop)

    li   x31, 0x11111111        # sync: spinning -> TB halts us here
spin:
    addi x5,  x5, 1
    blt  x5,  x6, spin          # count up to the bound (paused while halted)

    # --- after resume: confirm the SBA write reached real memory ---
    li   x10, 0x80004000
    lw   x20, 0x08(x10)         # expect 0xDEADBEEF (written over SBA while halted)
    lw   x21, 0x00(x10)         # expect 0xCAFEBABE (sentinel intact)
    or   x22, x20, x21          # consume both loads: load-use interlock guarantees
                                # x20/x21 have RETIRED before "done" is signalled
                                # (else, under wait states, the TB could sample them
                                # while the load data phase is still in flight)

    li   x31, 0x22222222        # sync: post-resume read-back done
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)
