//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_no_event
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM NO-EVENT / RESERVED
//   Verifies that event selector 0x00 (disabled) and reserved selectors
//   0x13 and 0x1F keep the counter frozen.
//   Expected: all three phase counts == 0.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] p1_disabled_count;
reg [31:0] p2_reserved13_count;
reg [31:0] p3_reserved1f_count;

`define SPAD(byte_off) (byte_off/4)

initial
   begin
      // Disable random IRQs: exact zero-count checks require no spurious events
      random_irq_enable = 0;

      @(posedge free_clk);
      @(posedge hresetn);

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      $display("");
      $display(" ====================================================================");
      $display("|         ZIHPM NO-EVENT: EVENT 0x00 AND RESERVED SELECTORS          |");
      $display(" ====================================================================");
      $display("");


      //=================================================================
      // PHASE 1: event 0x00 (disabled) — counter must stay at 0
      //=================================================================
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      p1_disabled_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      $display("  Phase 1 (event 0x00 disabled): count = %0d  %t ns",
               p1_disabled_count, $time);

      if (p1_disabled_count === 32'd0)
         $display("  PASS  phase1: event 0x00 keeps counter frozen (count=0)  %t ns", $time);
      else begin
         $display("  ERROR phase1: event 0x00 count=%0d, expected 0 — counter should be frozen  %t ns",
                  p1_disabled_count, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE 2: event 0x13 (reserved) — counter must stay at 0
      //=================================================================
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      p2_reserved13_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
      $display("");
      $display("  Phase 2 (event 0x13 reserved): count = %0d  %t ns",
               p2_reserved13_count, $time);

      if (p2_reserved13_count === 32'd0)
         $display("  PASS  phase2: event 0x13 (reserved) keeps counter frozen (count=0)  %t ns", $time);
      else begin
         $display("  ERROR phase2: event 0x13 count=%0d, expected 0 — reserved selector must freeze  %t ns",
                  p2_reserved13_count, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE 3: event 0x1F (reserved) — counter must stay at 0
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      p3_reserved1f_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
      $display("");
      $display("  Phase 3 (event 0x1F reserved): count = %0d  %t ns",
               p3_reserved1f_count, $time);

      if (p3_reserved1f_count === 32'd0)
         $display("  PASS  phase3: event 0x1F (reserved) keeps counter frozen (count=0)  %t ns", $time);
      else begin
         $display("  ERROR phase3: event 0x1F count=%0d, expected 0 — reserved selector must freeze  %t ns",
                  p3_reserved1f_count, $time);
         error = error + 1;
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end
