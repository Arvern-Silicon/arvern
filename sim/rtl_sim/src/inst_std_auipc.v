//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_auipc
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: AUIPC
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial
   begin
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
      $display("");
      $display(" ====================================================================");
      $display("|                     AUIPC TEST (Self-Checking)                     |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for test completion...");

      @(probes_cpu.x31==32'hDEADBEEF || probes_cpu.x31==32'hBADC0DE0);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;
      repeat(30) @(posedge free_clk);

      // Check if test passed or failed
      if (probes_cpu.x31 == 32'hBADC0DE0) begin
          $display("");
          $display("======================================================================");
          $display("ERROR: Test FAILED - x31 = 0xBADC0DE0");
          $display("----------------------------------------------------------------------");
          $display("Error Code (x30):        0x%08h", probes_cpu.x30);
          $display("  Test Number:           0x%02h", (probes_cpu.x30 >> 8) & 8'hFF);
          $display("  Check Number:          0x%02h", probes_cpu.x30 & 8'hFF);
          $display("----------------------------------------------------------------------");
          $display("Actual   (auipc result): 0x%08h", probes_cpu.x11);
          $display("Expected (label + imm):  0x%08h", probes_cpu.x12);
          $display("======================================================================");
          $display("");
          stimulus_done = 1;
          $finish;
      end

      // x31 = 0xDEADBEEF: all checks passed
      $display("");
      $display("Test PASSED - All AUIPC operations completed successfully");
      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end
