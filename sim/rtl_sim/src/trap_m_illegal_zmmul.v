//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_m_illegal_zmmul
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZMMUL  -> DIV/REM ILLEGAL
//   Requires M_EXTENSION==1 (Zmmul). MUL/MULH legal, DIV/REM illegal.
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

      $display("");
      $display(" PHASE 1: init");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display(" PHASE 2: MUL (LEGAL, should compute)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);                  // no trap yet
      check_mem_value(`SPAD(32'h20), 32'h70B88D78);                  // MUL result

      $display("");
      $display(" PHASE 3: DIV (ILLEGAL under Zmmul)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000001);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h30), 32'hEEEEEEE5);

      $display("");
      $display(" PHASE 4: DIVU (ILLEGAL)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000002);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h40), 32'hFFFFFFF6);

      $display("");
      $display(" PHASE 5: REM (ILLEGAL)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000003);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h50), 32'h11111117);

      $display("");
      $display(" PHASE 6: REMU (ILLEGAL)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000004);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h60), 32'h22222228);

      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end
