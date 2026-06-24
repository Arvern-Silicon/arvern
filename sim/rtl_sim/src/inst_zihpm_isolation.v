//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_isolation
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM COUNTER ISOLATION
//   Verifies that counter3 (branch-taken, 0x05) and counter4 (branch-
//   not-taken, 0x06) count independently when open simultaneously:
//   counter3 == 7 (branch-taken)
//   counter4 == 5 (branch-not-taken)
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] taken_count;
reg [31:0] nottaken_count;

`define SPAD(byte_off) (byte_off/4)

initial
   begin
      // Disable random IRQs: exact counts require no spurious branches
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
      $display("|          ZIHPM ISOLATION: DUAL-COUNTER EVENT ISOLATION TEST        |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // Wait for end of test
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      //=================================================================
      // Read and verify both counter results
      //=================================================================
      taken_count    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      nottaken_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

      $display("  counter3 (branch-taken,     event 0x05) = %0d  %t ns",
               taken_count, $time);
      $display("  counter4 (branch-not-taken, event 0x06) = %0d  %t ns",
               nottaken_count, $time);
      $display("");

      // counter3: branch-taken — must be exactly 7
      if (taken_count === 32'd7)
         $display("  PASS  counter3 = 7 (branch-taken event isolated)  %t ns", $time);
      else begin
         $display("  ERROR counter3 = %0d, expected 7 (branch-taken)  %t ns",
                  taken_count, $time);
         error = error + 1;
      end

      // counter4: branch-not-taken — must be exactly 5
      if (nottaken_count === 32'd5)
         $display("  PASS  counter4 = 5 (branch-not-taken event isolated)  %t ns", $time);
      else begin
         $display("  ERROR counter4 = %0d, expected 5 (branch-not-taken)  %t ns",
                  nottaken_count, $time);
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
