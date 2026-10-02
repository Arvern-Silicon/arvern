#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dmi_wfi_read
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NON-HALTING DMI access during WFI sleep (Sdext)
#   The non-halting discriminator for the DMI keepalive. The hart sleeps on WFI
#   (clock gated, hclk_en_o low). The debugger then issues a DMI access that does
#   NOT halt the hart (a bare dmstatus read). The pending DMI request ungates the
#   core clock just long enough for the access to complete, then the clock
#   re-gates and the hart stays asleep -- it did NOT enter Debug Mode and did NOT
#   run past the WFI. Only the armed machine-external IRQ (raised by the testbench
#   AFTER the read) wakes the WFI naturally.
#
#   The WFI wake condition is mie & mip (independent of clock activity), so the
#   hart stays parked at WFI through the read. mie.MEIE is enabled and
#   mstatus.MIE is set, so on wake the external IRQ traps to the handler, which
#   masks MEIE and returns to WFI+4 (dpc/mepc = WFI+4). x20 is set only after the
#   WFI returns, proving the read alone did not advance the firmware.
#
#   Registers:
#     x18 : sentinel marker, must survive untouched  (expect 0xA5A5A5A5)
#     x20 : ran-past-WFI marker, set after WFI wake   (expect 0x0000D09E)
#     x31 : sync (11111111=about to sleep, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x20, 0                 # ran-past-WFI marker (set only after WFI wake)

    la   t0, irq_handler        # mtvec = handler, direct mode (mode bits 0)
    csrw mtvec, t0

    li   t0, 0x800              # mie.MEIE (bit 11) = machine external IRQ enable
    csrw mie, t0
    li   t0, 0x8               # mstatus.MIE (bit 3) = global IRQ enable
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0

    li   x31, 0x11111111        # sync: about to enter WFI sleep
    wfi                          # sleeps (clock gated). The TB's non-halting DMI
                                 # read happens here; only the armed external IRQ
                                 # wakes it. dpc/mepc = WFI+4, so we proceed past.
    li   x20, 0x0000D09E        # reached only after the WFI wakes (post-handler)
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)

    .align 2
irq_handler:
    li   t0,  0x800            # clear mie.MEIE so the level IRQ won't re-fire
    csrc mie, t0
    mret
