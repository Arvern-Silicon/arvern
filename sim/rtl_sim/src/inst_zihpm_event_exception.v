//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_exception
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT EXCEPTION
//   Tests HPM counter event selector for exception-taken event:
//   Phase 1 — mhpmevent3 = 0x09 (exception): expects counter3 = 4
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] excp_count;

`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Disable random IRQs immediately — this test requires no_random_irq
      random_irq_enable = 0;
      // Disable the global exception error reporter — this test intentionally raises ECALLs
      error_on_exception = 0;

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      $display("");
      $display(" ====================================================================");
      $display("|         ZIHPM EVENT EXCEPTION: HPM EXCEPTION EVENT TEST            |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 1: exception-taken event — expect counter3 = 4
      //=================================================================
      $display("Waiting for sync (0xdeadbeef) — exception-taken event...");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      excp_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

      $display("  counter3 (exception-taken, event 0x09) = %0d  %t ns", excp_count, $time);

      if (excp_count === 32'd4)
         $display("  PASS  phase1: counter3 = 4 (exception-taken)  %t ns", $time);
      else begin
         $display("  ERROR phase1: counter3 = %0d, expected 4 (exception-taken)  %t ns",
                  excp_count, $time);
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
