//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_lsu
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT LSU
//   Verifies the LSU-stall HPM event counter (event selector 0x02).
//
//   Checks that mhpmcounter3 >= 4 after executing 4 load-use hazard pairs.
//   In zero-WS mode each hazard pair causes exactly 1 LSU stall cycle.
//   With SRAM wait states the count is higher — the >= 4 bound is always met.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] lsu_count;

`define SPAD(byte_off) (byte_off/4)

initial
   begin
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

      random_irq_enable = 1;

      $display("");
      $display(" ====================================================================");
      $display("|               ZIHPM EVENT LSU: LSU STALL COUNTER TEST              |");
      $display(" ====================================================================");
      $display("");

      // Wait for end of test (level-sensitive in case back-to-back)
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;        // disable random IRQs before reading results
      repeat(3) @(posedge free_clk);

      //=================================================================
      // Read and verify LSU-stall counter
      //=================================================================
      lsu_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

      $display("  LSU stall count = %0d (after 4 load-use hazard pairs)", lsu_count);

      // >= 4: hazard stalls guarantee minimum 4; SRAM wait states add more
      if (lsu_count >= 32'd4)
         $display("  PASS  LSU stall count=%0d >= 4 (4 load-use hazard pairs)  %t ns",
                  lsu_count, $time);
      else begin
         $display("  ERROR LSU stall count=%0d < 4 (expected >= 4 from 4 load-use hazard pairs)  %t ns",
                  lsu_count, $time);
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
