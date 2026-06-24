//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_load
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT LOAD
//   Tests HPM counter event selector for load dispatched event:
//   Phase 1 — mhpmevent3 = 0x07 (load): expects counter3 = 8
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] load_count;

`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Disable random IRQs immediately — this test requires no_random_irq
      random_irq_enable = 0;

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      $display("");
      $display(" ====================================================================");
      $display("|             ZIHPM EVENT LOAD: HPM LOAD EVENT TEST                  |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 1: load-dispatched event — expect counter3 = 8
      //=================================================================
      $display("Waiting for sync (0xdeadbeef) — load dispatched event...");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      load_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

      $display("  counter3 (load dispatched, event 0x07) = %0d  %t ns", load_count, $time);

      if (load_count === 32'd8)
         $display("  PASS  phase1: counter3 = 8 (load dispatched)  %t ns", $time);
      else begin
         $display("  ERROR phase1: counter3 = %0d, expected 8 (load dispatched)  %t ns",
                  load_count, $time);
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
