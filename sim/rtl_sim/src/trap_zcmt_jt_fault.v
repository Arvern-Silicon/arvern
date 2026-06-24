//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_zcmt_jt_fault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CM.JT/JALT LOAD ACCESS-FAULT TRAP
//   Verifies that an unmapped JVT[i] load takes a load access-fault trap and
//   the JT FSM does not livelock. Requires C_EXTENSION>=4 (Zcmt).
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

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

      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init
      //=================================================================
      $display("");
      $display(" PHASE 1: init");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // PHASE 2: cm.jt 0 with JVT=0 -> load access fault must deliver
      //=================================================================
      $display("");
      $display(" PHASE 2: cm.jt with unmapped JVT load");
      $display("Waiting for cm.jt entry marker...");
      @(probes_cpu.x31==32'h12121212);

      $display("Waiting for the firmware (post-trap recovery)...");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);                  // 1 trap delivered
      check_mem_value(`SPAD(32'h04), 32'h00000005);                  // MCAUSE = load access fault


      //=================================================================
      // PHASE 3: cm.jalt 32 -> same fault path on the JALT variant
      //=================================================================
      $display("");
      $display(" PHASE 3: cm.jalt with unmapped JVT load");
      $display("Waiting for cm.jalt entry marker...");
      @(probes_cpu.x31==32'h32323232);

      $display("Waiting for the firmware (post-trap recovery)...");
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);                  // 2 traps total
      check_mem_value(`SPAD(32'h04), 32'h00000005);                  // MCAUSE = load access fault


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end
