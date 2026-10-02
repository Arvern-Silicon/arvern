//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_zcb_illegal_nozbb
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZCB WITHOUT ZBB -> C.SEXT.B / C.ZEXT.H / C.SEXT.H ILLEGAL
//   Requires C_EXTENSION>=2 and B_EXTENSION==0. The three Zbb-dependent Zcb
//   encodings must trap as illegal instruction (mcause=2) and leave rd
//   untouched; c.zext.b and c.not must execute without a trap.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

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
      // PHASE 2: C.SEXT.B s0 -> illegal, s0 preserved
      //=================================================================
      $display("");
      $display(" PHASE 2: C.SEXT.B without Zbb");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000001);                  // trap_count
      check_mem_value(`SPAD(32'h04), 32'h00000002);                  // MCAUSE=2
      check_mem_value(`SPAD(32'h20), 32'hAAAAAA81);                  // s0 preserved


      //=================================================================
      // PHASE 3: C.ZEXT.H s1 -> illegal, s1 preserved
      //=================================================================
      $display("");
      $display(" PHASE 3: C.ZEXT.H without Zbb");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000002);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h30), 32'hBBBB8002);


      //=================================================================
      // PHASE 4: C.SEXT.H a0 -> illegal, a0 preserved
      //=================================================================
      $display("");
      $display(" PHASE 4: C.SEXT.H without Zbb");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000003);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h40), 32'hCCCC8003);


      //=================================================================
      // PHASE 5: C.ZEXT.B a1 -> executes, no trap
      //=================================================================
      $display("");
      $display(" PHASE 5: C.ZEXT.B (Zcb only)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000003);                  // no new trap
      check_mem_value(`SPAD(32'h50), 32'h000000F8);


      //=================================================================
      // PHASE 6: C.NOT a2 -> executes, no trap
      //=================================================================
      $display("");
      $display(" PHASE 6: C.NOT (Zcb only)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000003);                  // no new trap
      check_mem_value(`SPAD(32'h60), 32'hF0F0F0F0);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end
