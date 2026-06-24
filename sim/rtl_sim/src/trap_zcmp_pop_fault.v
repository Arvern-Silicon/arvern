//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_zcmp_pop_fault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CM.POP LOAD ACCESS-FAULT ABORT
//   Discriminators (read from scratchpad after recovery):
//   trap_count    @ 0x00 -- must equal 1 (post-fix). Pre-fix may be >1 if
//   sequencer re-faults during handler entry.
//   last MCAUSE   @ 0x04 -- expect 0x5 (load access fault)
//   s0 captured   @ 0x10 -- expect 0xA0A0A0A0 (pre-pop sentinel)
//   s2 captured   @ 0x18 -- expect 0xA2A2A2A2 (pre-pop sentinel)
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

      // We expect at least one access-fault trap in this test by design.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init complete
      //=================================================================
      $display("");
      $display(" PHASE 1: init complete");
      @(probes_cpu.x31==32'h11111111);


      //=================================================================
      // PHASE 2: cm.pop with sp=0 -> wait for recovery
      //=================================================================
      $display("");
      $display(" PHASE 2: cm.pop {ra,s0-s2}, 16 at sp=0");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 3: end-of-test sentinel + scratchpad checks
      //
      // Use wait() (level) not @() (edge) -- x31 may already be 0xdeadbeef
      // by the time we reach this wait.
      //=================================================================
      $display("");
      $display(" PHASE 3: scratchpad checks");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(10) @(posedge free_clk);

      // Must take EXACTLY one access fault (the very first load).
      // Pre-fix bug: sequencer keeps issuing AHB transfers after trap entry,
      // each one's error response re-triggers trap_pending_set during the
      // handler -> trap_count > 1.
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // mcause must be 0x5 (load access fault).
      check_mem_value(`SPAD(32'h04), 32'h00000005);

      // s0 / s2 must still hold their pre-pop sentinel values.
      check_mem_value(`SPAD(32'h10), 32'hA0A0A0A0);
      check_mem_value(`SPAD(32'h18), 32'hA2A2A2A2);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end
