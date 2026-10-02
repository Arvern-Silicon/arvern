#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_mstatus_warl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: mstatus SUM/MXR/TVM WARL CONFORMANCE
#   With S-mode advertised in misa, mstatus bits 19 (MXR) and 20 (TVM) must be
#   WARL writable per RISC-V Privileged spec. Bit 18 (SUM) must NOT be: the spec
#   makes it read-only 0 if S-mode is not supported OR if satp.MODE is read-only
#   zero, and aRVern satp is a RAZ/WI Bare-only stub, so the second clause bites.
#   MXR and SUM are also visible in sstatus.
#
#   This CPU implements S/U-mode but has no paged virtual memory, so the bits
#   have no functional effect — they exist purely for software contract
#   (read-back-after-write idioms in conforming S-mode kernels).
#
#   Phase 2: write SUM=1 via mstatus; read back mstatus and sstatus
#   Phase 3: write MXR=1 via sstatus; read back sstatus and mstatus
#   Phase 4: write TVM=1 via mstatus; read back mstatus (TVM not in sstat)
#   Phase 5: clear all three via mstatus; verify back to 0
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
# Phase 2: attempt SUM=1 via mstatus (must not stick)
#   0x20: mstatus after  (bit 18 must stay 0 -- SUM is hardwired)
#   0x24: sstatus after  (bit 18 must stay 0)
#
# Phase 3: MXR=1 via sstatus
#   0x30: sstatus after  (bit 19 must be 1)
#   0x34: mstatus after  (bit 19 must be 1)
#
# Phase 4: TVM=1 via mstatus
#   0x40: mstatus after  (bit 20 must be 1)
#   0x44: sstatus after  (bit 20 must be 0 — TVM not in sstatus view)
#
# Phase 5: clear all via mstatus
#   0x50: mstatus after  (bits 20:18 must be 0)
#   0x54: sstatus after  (bits 19:18 must be 0)
#
# PHASE 6: MPP WARL -- reserved encoding 2'b10
#   0x60: mstatus after setting MPP=2'b11   (MPP must read 2'b11)
#   0x64: mstatus after writing MPP=2'b10   (MPP must WARL to 2'b00)
#=========================================================================

# mstatus bit masks:
#   SUM = 1<<18 = 0x40000
#   MXR = 1<<19 = 0x80000
#   TVM = 1<<20 = 0x100000
#   ALL = 0x1C0000

main:
    j _start

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    li   t0, 0
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x44(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x54(s1)

    # Clear mstatus SUM/MXR/TVM at start (in case prior state nonzero).
    li   t0, 0x1C0000
    csrc mstatus, t0

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: write SUM=1 via mstatus, read back mstatus and sstatus.
    # Both views must reflect bit 18 set.
    #=================================================================

    li   t0, 0x40000
    # Smdbltrp: MDT resets to 1 and blocks MIE from being set, so clear it first.
    csrw mstatush, x0

    csrs mstatus, t0           # set mstatus.SUM
    csrr t0, mstatus
    sw   t0, 0x20(s1)
    csrr t1, sstatus
    sw   t1, 0x24(s1)
    lw   t2, 0x24(s1)          # load-back to drain SW

    # Clear before next phase
    li   t0, 0x40000
    csrc mstatus, t0

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: write MXR=1 via sstatus, read back sstatus and mstatus.
    # Both views must reflect bit 19 set. Tests the sstatus_wr alias
    # path into the shared MXR flop.
    #=================================================================

    li   t0, 0x80000
    csrs sstatus, t0           # set sstatus.MXR
    csrr t0, sstatus
    sw   t0, 0x30(s1)
    csrr t1, mstatus
    sw   t1, 0x34(s1)
    lw   t2, 0x34(s1)

    # Clear before next phase
    li   t0, 0x80000
    csrc mstatus, t0

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: write TVM=1 via mstatus. TVM is M-only (not in sstatus).
    # mstatus bit 20 must read 1; sstatus bit 20 must read 0.
    #=================================================================

    li   t0, 0x100000
    csrs mstatus, t0
    csrr t0, mstatus
    sw   t0, 0x40(s1)
    csrr t1, sstatus
    sw   t1, 0x44(s1)
    lw   t2, 0x44(s1)

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: clear all three bits via mstatus. Verify both views
    # report SUM/MXR/TVM cleared.
    #=================================================================

    li   t0, 0x1C0000
    csrc mstatus, t0
    csrr t0, mstatus
    sw   t0, 0x50(s1)
    csrr t1, sstatus
    sw   t1, 0x54(s1)
    lw   t2, 0x54(s1)

    li   x31, 0x55555555

    #=================================================================
    # PHASE 6: MPP WARL. 2'b10 is RESERVED (it would select H-mode,
    # which aRVern does not implement), so a write of it must land on
    # some supported value. aRVern picks U (2'b00), matching sail-riscv
    # -- riscv-arch-test Sm_mcsr-00's cp_mcsrwalk compares against that
    # choice, so it is a deliberate alignment and not free to change.
    #=================================================================

    # Start from MPP = M (2'b11) so the reserved write is a real change.
    li   t0, 0x1800
    csrs mstatus, t0
    csrr t0, mstatus
    sw   t0, 0x60(s1)               # MPP must read back 2'b11

    # Write the reserved encoding 2'b10: set bit 12, clear bit 11.
    csrr t0, mstatus
    li   t1, ~0x1800
    and  t0, t0, t1                 # clear MPP
    li   t1, 0x1000                 # MPP = 2'b10 (reserved)
    or   t0, t0, t1
    csrw mstatus, t0
    csrr t0, mstatus
    sw   t0, 0x64(s1)               # MPP must have WARL'd to 2'b00
    lw   t2, 0x64(s1)

    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test
