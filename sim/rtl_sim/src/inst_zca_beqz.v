//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_beqz
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.BEQZ
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.BEQZ             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'hBEEF0001);
      check_cpu_reg(2,  32'h00000000);
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'h00000000);
      check_cpu_reg(9,  32'h00000000);
      check_cpu_reg(10, 32'h00000000);
      check_cpu_reg(11, 32'h00000000);
      check_cpu_reg(12, 32'h00000000);
      check_cpu_reg(13, 32'h00000000);
      check_cpu_reg(14, 32'h00000000);
      check_cpu_reg(15, 32'h00000000);
      check_cpu_reg(16, 32'h00000000);   // Taken counter
      check_cpu_reg(17, 32'h00000000);   // Not-taken counter
      check_cpu_reg(18, 32'h00000000);   // Test counter
      check_cpu_reg(19, 32'h00000000);
      check_cpu_reg(20, 32'h00000000);
      check_cpu_reg(21, 32'h00000000);
      check_cpu_reg(22, 32'h00000000);
      check_cpu_reg(23, 32'h00000000);
      check_cpu_reg(24, 32'h00000000);
      check_cpu_reg(25, 32'h00000000);
      check_cpu_reg(26, 32'h00000000);
      check_cpu_reg(27, 32'h00000000);
      check_cpu_reg(28, 32'h00000000);
      check_cpu_reg(29, 32'h00000000);
      check_cpu_reg(30, 32'h00000000);
      check_cpu_reg(31, 32'hAAAAAAAA);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|         CHECK FINAL STATE AFTER ALL C.BEQZ TESTS                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Verify backed up results in x22-x27
      check_cpu_reg(22, 32'h00000012);   // Taken counter: 18 branches taken (including max offset tests)
      check_cpu_reg(23, 32'h00000004);   // Not-taken counter: 4 branches not taken
      check_cpu_reg(24, 32'h0000000C);   // Test counter: 12 tests executed (including max offset tests)
      check_cpu_reg(25, 32'h00000003);   // Loop body counter: 3 iterations
      check_cpu_reg(26, 32'h00000000);   // x10 before branch (Test Set 10)
      check_cpu_reg(27, 32'h00000000);   // x10 after branch (Test Set 10, unchanged)

      // Verify final state of working registers
      check_cpu_reg(16, 32'h00000012);   // Final taken counter
      check_cpu_reg(17, 32'h00000004);   // Final not-taken counter
      check_cpu_reg(18, 32'h0000000C);   // Final test counter
      check_cpu_reg(19, 32'h00000003);   // Final loop body counter
      check_cpu_reg(20, 32'h00000000);   // Final x10 backup before branch
      check_cpu_reg(21, 32'h00000000);   // Final x10 backup after branch

      // Verify x1 unchanged (C.BEQZ doesn't modify any registers)
      check_cpu_reg(1,  32'hBEEF0001);   // x1 unchanged

      // Verify test registers x8-x15 (should be 0 from Test Set 7)
      check_cpu_reg(8,  32'h00000000);   // x8 = 0 from Test Set 8
      check_cpu_reg(9,  32'h00000000);   // x9 = 0 from Test Set 9
      check_cpu_reg(10, 32'h00000000);   // x10 = 0 from Test Set 10
      check_cpu_reg(11, 32'h00000000);   // x11 = 0 from Test Set 7
      check_cpu_reg(12, 32'h00000000);   // x12 = 0 from Test Set 6
      check_cpu_reg(13, 32'h00000000);   // x13 = 0 from Test Set 7
      check_cpu_reg(14, 32'h00000000);   // x14 = 0 from Test Set 7
      check_cpu_reg(15, 32'h00000000);   // x15 = 0 from Test Set 7

      check_cpu_reg(31, 32'hDEADBEEF);   // Test complete marker

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end
