#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_seip_csrrs_rmw
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MIP[9] / SEIP CSRRS/CSRRC RMW spec-conformance per Priv §3.1.9
#              P207-208.
#
#   The spec splits MIP.SEIP into a software-writable bit B and a read-only
#   wire-OR with the external interrupt signal E. The architectural read
#   returned in rd is `B || E`, but the *write-back* of a CSRRS/CSRRC only
#   updates B with the un-OR'd value:
#
#     csrrs t0, mip, t1  =>  t0 = B || E ;  B = B || t1[9]    (E NOT in write)
#     csrrc t0, mip, t1  =>  t0 = B || E ;  B = B & ~t1[9]    (E NOT in write)
#
#   The headline assertion of this test is at sync 0x44444444: after a
#   csrrs RMW whose t1 mask does NOT include bit 9, while E was asserted,
#   B must remain 0. When E later deasserts, MIP[9] must read 0 -- proving
#   the external signal E did NOT participate in the write-back of B.
#
#   The test is M-mode only. mstatus.MIE = 0 and mie.SEIE = 0 throughout,
#   and mideleg.SEI = 0, so no trap can fire even with MIP[9] visibly high.
#   The testbench drives irq_s_external around each sync point per the
#   sync-point ladder below. Each checkpoint stores its MIP[9] read into a
#   distinct stable register that the testbench inspects via check_cpu_reg.
#
#   Stable result register map (each is written exactly once):
#     s2 = MIP[9] at sync 0xFFFFFFFF  (E=0 init,        expect 0)
#     s3 = MIP[9] at sync 0x11111111  (E=1,             expect 1)
#     s4 = MIP[9] at sync 0x22222222  (csrrs rs1=x0,    rd expect 1)
#     s5 = t0[9]  at sync 0x33333333  (csrrs RMW mask=MSIP, rd expect 1)
#     s6 = MIP[9] at sync 0x44444444  (after E deassert,    expect 0)  <-- HEADLINE
#     s7 = MIP[9] at sync 0x55555555  (after csrrc clear + E deassert, expect 0)
#     s8 = MIP[9] at sync 0x66666666a (after csrrw set,  E=0,    expect 1)
#     s9 = MIP[9] at sync 0x66666666b (after csrrw clear, E=0,   expect 0)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    #=========================================================================
    # ONE-TIME M-MODE SETUP
    #=========================================================================

    # Belt-and-suspenders gating so no SEI can ever fire:
    #   mstatus.MIE = 0  (machine-mode interrupts globally off)
    #   mie         = 0  (all per-cause enables off, incl. SEIE bit 9)
    #   mideleg     = 0  (nothing delegated to S-mode)
    csrw mstatus, zero
    csrw mie,     zero
    csrw mideleg, zero

    # Also clear MIP.SEIP (the SW-writable B bit) so we start from a known
    # B=0 state. (Reset value is 0 anyway, but being explicit.)
    li   t0, (1 << 9)
    csrc mip, t0

    # Initialize all stable result registers to a sentinel so a missed
    # checkpoint is obvious.
    li   s2, 0xBADBAD00
    li   s3, 0xBADBAD11
    li   s4, 0xBADBAD22
    li   s5, 0xBADBAD33
    li   s6, 0xBADBAD44
    li   s7, 0xBADBAD55
    li   s8, 0xBADBAD66
    li   s9, 0xBADBAD67

    #=========================================================================
    # SYNC 0xFFFFFFFF: init done, E=0, expect MIP[9] = 0
    #
    # Drive x31 first so the testbench arrives at the sync; the testbench
    # holds irq_s_external = 0 (its reset value). Then read MIP and capture
    # bit 9 into s2.
    #=========================================================================
    li   x31, 0xFFFFFFFF

    # Give the TB a few cycles to honour the sync (it doesn't drive the pin
    # at this sync but we wait anyway so the pattern is uniform).
    li   t4, 32
sync_init_wait:
    addi t4, t4, -1
    bnez t4, sync_init_wait

    csrr t0, mip
    srli t0, t0, 9
    andi s2, t0, 0x1            # s2 = MIP[9] (expect 0)

    #=========================================================================
    # SYNC 0x11111111: TB asserts E=1, expect MIP[9] reads 1
    #=========================================================================
    li   x31, 0x11111111

    # Wait long enough for the TB to drive irq_s_external high AND for the
    # 2-FF synchroniser to clock it into the core (same pattern as
    # trap_irq_ssip_hw uses around its sync points).
    li   t4, 64
sync_e_high_wait:
    addi t4, t4, -1
    bnez t4, sync_e_high_wait

    csrr t0, mip
    srli t0, t0, 9
    andi s3, t0, 0x1            # s3 = MIP[9] (expect 1, OR'd read shows E)

    #=========================================================================
    # SYNC 0x22222222: csrrs t0, mip, x0  (rs1 register literally x0)
    #
    # Per spec, rs1==x0 suppresses the write entirely. The read still
    # returns B || E = 0 || 1 = 1. B remains 0 (unchanged). E remains
    # asserted by the TB throughout this sync.
    #=========================================================================
    li   x31, 0x22222222

    # No TB-side action expected here -- E remains high. Tiny settle wait
    # to keep the cadence uniform.
    li   t4, 32
sync_x0_wait:
    addi t4, t4, -1
    bnez t4, sync_x0_wait

    csrrs t0, mip, x0           # spec rs1==x0 => true no-write
    srli  t0, t0, 9
    andi  s4, t0, 0x1           # s4 = rd[9] (expect 1)

    #=========================================================================
    # SYNC 0x33333333: csrrs t0, mip, t1  with t1 = (1 << 3) = MSIP mask
    #
    # This is the critical RMW. Per Priv §3.1.9 P208:
    #   rd  <- B || E         (= 0 || 1 = 1)
    #   B   <- B || t1[9]     (= 0 || 0 = 0)   -- E does NOT participate.
    #
    # Under the spec-conformant RTL: B stays 0.
    # Under the old (now-removed) deviation: B would have latched to 1.
    # The discriminating observation is delayed to sync 0x44444444 where
    # we deassert E and re-read MIP.
    #
    # NB: bit 3 is MSIP (M-mode software interrupt pending). MIP[3] is
    # spec'd read-only from CSR writes -- the write to MSIP[3] takes
    # effect only on the SW-writable subset of the bit, which is moot for
    # this test (no MSIE enable, MIE off). We pick bit 3 because it is
    # not bit 9, hence the test isolates the spec rule that E does not
    # flow into B's write-back.
    #=========================================================================
    li   x31, 0x33333333

    # Settle wait -- E held high by TB.
    li   t4, 32
sync_rmw_wait:
    addi t4, t4, -1
    bnez t4, sync_rmw_wait

    li    t1, (1 << 3)
    csrrs t0, mip, t1           # rd = B||E ; B := B || t1[9] = 0
    srli  t0, t0, 9
    andi  s5, t0, 0x1           # s5 = rd[9] from the RMW (expect 1)

    #=========================================================================
    # SYNC 0x44444444: TB deasserts E; expect MIP[9] reads 0  <-- HEADLINE
    #
    # If the RMW above did NOT latch B (spec-conformant), then with E=0
    # and B=0, MIP[9] = 0.
    # If the RMW DID latch B (old deviation), MIP[9] would stick at 1.
    #=========================================================================
    li   x31, 0x44444444

    # Wait for TB to drop irq_s_external + 2-FF sync to propagate.
    li   t4, 128
sync_deassert_wait:
    addi t4, t4, -1
    bnez t4, sync_deassert_wait

    csrr t0, mip
    srli t0, t0, 9
    andi s6, t0, 0x1            # s6 = MIP[9] (expect 0 -- HEADLINE)

    #=========================================================================
    # SYNC 0x55555555: csrrc variant
    #
    # TB re-asserts E=1. Firmware executes:
    #   csrrc t0, mip, t1   with t1 = 0xFFFFFFFF  (clear-all mask)
    # Per spec:
    #   rd <- B || E          (= 0 || 1 = 1)
    #   B  <- B & ~t1[9]      (= 0 & ~1 = 0)
    # Then TB drops E. MIP[9] must read 0.
    #=========================================================================
    li   x31, 0x55555555

    # Wait for TB to re-assert E.
    li   t4, 64
sync_csrrc_wait_assert:
    addi t4, t4, -1
    bnez t4, sync_csrrc_wait_assert

    li    t1, 0xFFFFFFFF
    csrrc t0, mip, t1           # rd = B||E ; B := B & ~t1[9] = 0

    # Now wait for the TB to deassert E again. The TB sequences:
    # assert before this sync -> wait for next x31 -> deassert.
    # We use an intermediate sync value so the TB knows when to deassert.
    li   x31, 0x55555556         # TB sync: please drop E

    li   t4, 128
sync_csrrc_wait_deassert:
    addi t4, t4, -1
    bnez t4, sync_csrrc_wait_deassert

    csrr t0, mip
    srli t0, t0, 9
    andi s7, t0, 0x1            # s7 = MIP[9] (expect 0)

    #=========================================================================
    # SYNC 0x66666666a: csrrw still works as the conventional B-write path
    #
    # E is held low by the TB. Firmware uses csrrw to set B = 1, then
    # reads MIP[9] -- expect 1 (B=1, E=0).
    #=========================================================================
    li   x31, 0x66666666         # TB sync: keep E low for both csrrw checks

    # Settle wait -- TB action: keep E=0 (already deasserted).
    li   t4, 32
sync_csrrw_set_wait:
    addi t4, t4, -1
    bnez t4, sync_csrrw_set_wait

    li    t1, (1 << 9)
    csrrw t0, mip, t1           # B := t1[9] = 1   (csrrw writes literal t1)

    csrr t0, mip
    srli t0, t0, 9
    andi s8, t0, 0x1            # s8 = MIP[9] (expect 1)

    # csrrw clear: write 0 (rs1 = x0 in csrrw IS a write of 0)
    csrrw t0, mip, x0           # B := 0

    csrr t0, mip
    srli t0, t0, 9
    andi s9, t0, 0x1            # s9 = MIP[9] (expect 0)

    #=========================================================================
    # SYNC 0xdeadbeef: end of test
    #=========================================================================
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test
