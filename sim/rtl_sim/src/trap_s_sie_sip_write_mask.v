//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_s_sie_sip_write_mask
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SIE/SIP WRITE-SIDE mideleg MASKING (Priv §12.1.3)
//   Discriminator: with mideleg=0, S-mode writes to SIE/SIP must NOT change
//   MIE/MIP. Pre-fix: S-mode writes leak through → M-mode bits corrupted.
//
//   Pre-fix : Phase 2 mie != 0, Phase 3 mie != 0x222, Phase 4 mip&2 == 0 → FAIL
//   Post-fix: Phase 2 mie == 0, Phase 3 mie == 0x222, Phase 4 mip&2 == 2 → PASS
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Test relies on ECALL traps for mode escape; suppress error logging
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: CHECK INITIALIZATION                          |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // PHASE 2 (Variant A — SET): S-mode csrw sie, 0x222 with mideleg=0
      // MIE must remain 0 (no leak from non-delegated S writes).
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("| PHASE 2 (Variant A SET): S-mode SIE write must NOT leak to MIE     |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Sanity: ECALL fired once
      $display("");
      $display("--- trap_count after Phase 2 (expect 1 ECALL) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // *** DISCRIMINATOR ***
      $display("--- Phase 2 MIE readback (expect 0 — S write must be masked) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);


      //=================================================================
      // PHASE 3 (Variant B — CLEAR): S-mode csrw sie, 0 with mideleg=0
      // MIE must retain its M-set bits (0x222).
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("| PHASE 3 (Variant B CLR): S-mode SIE write=0 must NOT clear MIE     |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count after Phase 3 (expect 2) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      // *** DISCRIMINATOR ***
      $display("--- Phase 3 MIE readback (expect 0x222 — M's bits preserved) ---");
      check_mem_value(`SPAD(32'h08), 32'h00000222);


      //=================================================================
      // PHASE 4 (Variant B' — SIP CLEAR): S-mode csrw sip, 0 with mideleg=0
      // MIP.SSIP (bit 1) must retain its M-set value of 1.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("| PHASE 4 (Variant B' CLR): S-mode SIP write=0 must NOT clear SSIP   |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count after Phase 4 (expect 3) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000003);

      // *** DISCRIMINATOR ***
      // We check MIP[1] (SSIP) is still 1. Read back via scratchpad.
      // mip readback may include other bits driven by hardware (MEIP, MSIP from
      // platform pins) so we check bit 1 specifically.
      $display("--- Phase 4 MIP readback bit 1 should be 1 (SSIP preserved) ---");
      // Use a fuzzy check: scratchpad value AND 0x2 must equal 0x2.
      // No fuzzy-check helper exists in the bench harness; instead, the
      // firmware was given mip=0x2 initially (only SSIP set, all other M-bits 0),
      // so the expected MIP readback is just 0x2 unless other M-bits got set
      // by hardware in the meantime. We assert the full value is 0x2.
      check_mem_value(`SPAD(32'h0C), 32'h00000002);


      //=================================================================
      // END OF TEST
      // Use level wait() instead of edge @() — the firmware may already
      // be at 0xdeadbeef by the time we reach this line (short test path).
      // Per feedback_x31_sentinel_edge_vs_level.md.
      //=================================================================
      wait (probes_cpu.x31==32'hdeadbeef);
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end
