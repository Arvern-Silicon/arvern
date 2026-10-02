#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zicntr_aclint_mtime_write
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MTIME is read-write -- the `time` CSR follows a written MTIME
#   ACLINT 1.0-rc4 Section 2.2 makes MTIME a 64-bit read-write register. This
#   drives it from the core: write both halves through the ACLINT AHB window,
#   then read the value back through the Zicntr `time`/`timeh` CSR port (a
#   different path from the AHB read -- it has its own shadow and its own
#   arbitration slot in the read FSM), and confirm it still counts afterwards.
#
#   MTIME keeps ticking, so the readback is the written value plus a small
#   drift -- never less, and never far away (a dropped write reads ~0).
#
#   Write HI first, then LO: the halves cross to the LF domain on independent
#   handshakes and the counter carries LO->HI in between.
#
#   ACLINT address map (SiFive CLINT-compatible base = 0x02000000):
#     MTIMECMP_LO[0] = 0x02004000
#     MTIMECMP_HI[0] = 0x02004004
#     MTIME_LO       = 0x0200BFF8
#     MTIME_HI       = 0x0200BFFC
#
#   Scratchpad layout (base 0x80000000):
#   0x00: time    after the write   (expect 0x20000000 + small drift)
#   0x04: timeh   after the write   (expect 0x00000055)
#   0x08: time    after a delay     (expect > 0x00)
#   0x0C: timeh   after a delay
#   0x10: 1 if the second sample is strictly greater than the first
#----------------------------------------------------------------------------

.equ ACLINT_MTIME_LO,     0x0200BFF8
.equ ACLINT_MTIME_HI,     0x0200BFFC

.equ MTIME_WR_HI,         0x00000055
.equ MTIME_WR_LO,         0x20000000

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x10(s1)

    li   x31, 0x11111111            # Sync: configured

    #---------------------------------------------------------------
    # PHASE 2: write MTIME, then read it back through `time`
    #---------------------------------------------------------------
    li   t0, ACLINT_MTIME_HI
    li   t1, MTIME_WR_HI
    sw   t1, 0(t0)                  # HI first

    li   t0, ACLINT_MTIME_LO
    li   t1, MTIME_WR_LO
    sw   t1, 0(t0)                  # then LO

    # BARRIER. `time` is a read-only shadow of mtime and a CSR read is NOT a
    # memory operation under RVWMO, so nothing orders `csrr time` against the
    # store above -- a csrr issued while the store is still being presented on
    # the bus may be served from the pre-write count. aRVern's FENCE stalls
    # until the load/store unit drains (arv_decode.v, fetch_stall_from_fence),
    # so the store has reached the ACLINT before the CSR read issues, and the
    # ACLINT then holds the read off until the value has crossed to the LF
    # domain. See doc/ahb_aclint.md, "MTIMER window".
    fence

read_t0:
    csrr t2, timeh                  # snapshot high half first
    csrr t3, time                   # then low half
    csrr t4, timeh                  # high again; retry if it changed
    bne  t2, t4, read_t0

    sw   t3, 0x00(s1)               # time  after the write
    sw   t2, 0x04(s1)               # timeh after the write
    lw   zero, 0x04(s1)             # read-back: the stores above have landed

    li   x31, 0x22222222            # Sync: written and read back

    #---------------------------------------------------------------
    # PHASE 3: it must still be counting
    #---------------------------------------------------------------
    li   t5, 256
delay:
    addi t5, t5, -1
    bnez t5, delay

read_t1:
    csrr t4, timeh
    csrr t5, time
    csrr t1, timeh                  # NOT t6 -- t6 is x31, the sync register
    bne  t4, t1, read_t1

    sw   t5, 0x08(s1)               # time  after the delay
    sw   t4, 0x0C(s1)               # timeh after the delay

    # Second sample strictly greater? Compare the low halves -- the delay is
    # far too short to wrap 32 bits, and both samples share the same high half.
    li   t0, 0
    bgeu t3, t5, no_advance         # t3 = first low, t5 = second low
    li   t0, 1
no_advance:
    sw   t0, 0x10(s1)
    lw   zero, 0x10(s1)             # read-back: the stores above have landed

    li   x31, 0x33333333            # Sync: advance checked

    #---------------------------------------------------------------
    # PHASE 4: ORDERING -- `csrr time` immediately after the store
    #
    #   The store to MTIME is a POSTED AHB write, while `time` is served by
    #   the ACLINT's separate Zicntr port. Nothing orders the two: the CSR read
    #   can be launched before the store has even reached the ACLINT's register
    #   interface, in which case it returns the PRE-WRITE count.
    #
    #   Diagnostic only -- this records which side wins, it does not assert an
    #   ordering the design does not currently provide.
    #---------------------------------------------------------------
    li   t0, ACLINT_MTIME_HI
    li   t1, 0x00000077
    sw   t1, 0(t0)
    li   t0, ACLINT_MTIME_LO
    li   t1, 0x30000000
    sw   t1, 0(t0)                  # posted write
    csrr t2, time                   # NO gap -- races the store
    sw   t2, 0x14(s1)               # time read with no intervening instruction

    lw   zero, 0x14(s1)             # read-back: the store above has landed
    li   x31, 0x44444444            # Sync: ordering probe done

    li   t0, 2000                   # hold the sync -- the testbench is still
sync4_hold:                         # working through phase 3 when this is set
    addi t0, t0, -1
    bnez t0, sync4_hold

end_of_test:
    li   x31, 0xdeadbeef
    j    end_of_test
