#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_smode_warl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: S-MODE WARL CSRs + SIE/SIP MIDELEG MASK
#   Coverage for the 2026-05-14 S-mode WARL CSR fixes:
#
#   scounteren (0x106): real WARL storage, low 11 bits writable.
#   senvcfg    (0x10A): WARL hardwired zero (RAZ/WI).
#   menvcfg    (0x30A): WARL hardwired zero (RAZ/WI).
#   menvcfgh   (0x31A): Ssdbltrp WARL -- only bit 27 (DTE) writable, resets
#                       to 0x08000000 (DTE=1); all other bits read 0.
#   satp       (0x180): WARL stub, MODE=Bare (RAZ/WI).
#
#   SIE/SIP mideleg mask: non-delegated SSIE/STIE/SEIE bits read as 0.
#
#   Pre-fix:
#   - scounteren reads always 0 (no storage)
#   - satp at 0x180 traps (bank not in any_bank_known)
#   - SIE read shows undelegated bits set
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: scounteren readback  (0x7E5 masked to the implemented counters)
#   0x04: senvcfg readback     (expect 0x0)
#   0x08: menvcfg readback     (expect 0x0)
#   0x0C: menvcfgh reset value (expect 0x08000000 -- DTE=1 out of reset)
#   0x10: satp readback        (expect 0x0)
#   0x14: sie readback         (expect 0x0   when mideleg=0 -- mask test)
#   0x18: sie readback         (expect 0x222 when mideleg=0x222 -- delegated)
#   0x1C: trap_count           (expect 0)
#   0x20: menvcfgh after write 0xFFFFFFFF (expect 0x08000000 -- bit 27 only)
#   0x24: menvcfgh after write 0x00000000 (expect 0x00000000 -- DTE clearable)
#   0x28: menvcfgh after DTE restore      (expect 0x08000000)
#   0x2C: sscratch after 0xAAAAAAAA       (expect 0xAAAAAAAA -- full 32-bit storage)
#   0x30: sscratch after 0x55555555       (expect 0x55555555 -- every bit flips back)
#   0x34: sscratch after 0xFFFFFFFF       (expect 0xFFFFFFFF)
#=========================================================================

main:
    j _start

    .align 2
trap_handler:
    # Any trap here is unexpected -- count it.
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)

    lw   t0, 0x1C(s1)
    addi t0, t0, 1
    sw   t0, 0x1C(s1)

    # Skip the offending instruction (advance MEPC by 4).
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1

    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x8000F000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)
    sw   t0, 0x1C(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x24(s1)
    sw   t0, 0x28(s1)
    sw   t0, 0x2C(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: SCOUNTEREN (0x106) WARL storage
    # Write 0xFFFFFFFF, read back -- only bits [10:0] exist, and of those only
    # the ones with a counter behind them latch (Priv 3.1.11: a counter-enable
    # bit for an unimplemented counter is read-only zero).
    #=================================================================

    li   t0, 0xFFFFFFFF
    csrw 0x106, t0                # scounteren
    csrr t1, 0x106
    sw   t1, 0x00(s1)             # 0x7FF masked to the implemented counters

    # Restore scounteren to a known mid value to leave the state clean.
    li   t0, 0x000007E5            # CY=1, TM=0, IR=1, plus a few HPM bits
    csrw 0x106, t0
    csrr t1, 0x106
    sw   t1, 0x00(s1)             # final readback, masked

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: SENVCFG (0x10A) WARL hardwired zero
    # Write nonzero, read back -- must read 0.
    #=================================================================

    li   t0, 0xCAFEBABE
    csrw 0x10A, t0                # senvcfg
    csrr t1, 0x10A
    sw   t1, 0x04(s1)             # expect 0

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: MENVCFG (0x30A) WARL hardwired zero;
    #          MENVCFGH (0x31A) Ssdbltrp WARL -- only bit 27 (DTE)
    #          writable, all other bits hardwired zero. Resets to
    #          0x08000000 (DTE=1: protection-by-default; the spec leaves
    #          the reset value UNSPECIFIED).
    #=================================================================

    li   t0, 0xDEADBEEF
    csrw 0x30A, t0                # menvcfg
    csrr t1, 0x30A
    sw   t1, 0x08(s1)             # expect 0

    # menvcfgh reset value: DTE=1
    csrr t1, 0x31A
    sw   t1, 0x0C(s1)             # expect 0x08000000

    # Write all-ones: only bit 27 must latch
    li   t0, 0xFFFFFFFF
    csrw 0x31A, t0                # menvcfgh
    csrr t1, 0x31A
    sw   t1, 0x20(s1)             # expect 0x08000000

    # Write zero: DTE is WARL writable both ways
    li   t0, 0x00000000
    csrw 0x31A, t0
    csrr t1, 0x31A
    sw   t1, 0x24(s1)             # expect 0x00000000

    # Restore DTE=1 (architectural reset default) before the test ends
    li   t0, 0x08000000
    csrw 0x31A, t0
    csrr t1, 0x31A
    sw   t1, 0x28(s1)             # expect 0x08000000

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: SATP (0x180) WARL stub
    # Write nonzero, read back -- must read 0 (MODE=Bare hardwired).
    #=================================================================

    li   t0, 0x800ABCDE            # SV32 with garbage PPN
    csrw 0x180, t0                # satp
    csrr t1, 0x180
    sw   t1, 0x10(s1)             # expect 0

    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: SIE/SIP mideleg masking
    # Per Priv §12.1.3 the masking applies on BOTH read and write sides:
    # writes via SIE to non-delegated bits must be ignored (the storage
    # is not updated), and reads via SIE must mask non-delegated bits.
    #=================================================================

    # Step 6a: clear mideleg, write 0x222 to SIE, verify SIE reads 0.
    # Read-side mask alone would already return 0; this also exercises
    # the write-side mask — storage stays 0 because no bits are delegated.
    li   t0, 0
    csrw mideleg, t0              # 0x303
    li   t0, 0x222                # SSIE | STIE | SEIE bits
    csrw sie, t0                  # 0x104 -- write via SIE (post-fix: write-side gated, no-op)
    csrr t1, sie
    sw   t1, 0x14(s1)             # expect 0 (mideleg=0 -> all SIE bits masked)

    # Step 6b: delegate SSI+STI+SEI; THEN write SIE again so the storage
    # actually picks up the bits (Step 6a's write was masked). Verify
    # SIE reads 0x222.
    li   t0, 0x222
    csrw mideleg, t0
    li   t0, 0x222
    csrw sie, t0                  # now mideleg-allowed, storage updates
    csrr t1, sie
    sw   t1, 0x18(s1)             # expect 0x222 (delegated + written)

    # Restore mideleg to a sane state
    li   t0, 0
    csrw mideleg, t0


    #=================================================================
    # PHASE 7: SSCRATCH (0x140) full 32-bit read/write storage
    # sscratch has no WARL narrowing -- every bit must store and read
    # back. The complementary patterns also drive each bit both ways.
    #=================================================================

    li   t0, 0xAAAAAAAA
    csrw 0x140, t0                # sscratch
    csrr t1, 0x140
    sw   t1, 0x2C(s1)             # expect 0xAAAAAAAA

    li   t0, 0x55555555           # complement: every bit flips 1 -> 0 and 0 -> 1
    csrw 0x140, t0
    csrr t1, 0x140
    sw   t1, 0x30(s1)             # expect 0x55555555

    li   t0, 0xFFFFFFFF
    csrw 0x140, t0
    csrr t1, 0x140
    sw   t1, 0x34(s1)             # expect 0xFFFFFFFF

    li   t0, 0                    # leave it clean
    csrw 0x140, t0

    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test
