//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_mv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.MV
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.MV                 |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'h00000000);
      check_cpu_reg(2,  32'h00000000);
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'h12345678);   // Test pattern
      check_cpu_reg(9,  32'hABCDEF01);   // Test pattern
      check_cpu_reg(10, 32'hFFFFFFFF);   // All 1s
      check_cpu_reg(11, 32'h00000000);   // All 0s
      check_cpu_reg(12, 32'h80000000);   // Min negative
      check_cpu_reg(13, 32'h7FFFFFFF);   // Max positive
      check_cpu_reg(14, 32'hAAAAAAAA);   // Alternating pattern
      check_cpu_reg(15, 32'h55555555);   // Alternating pattern
      check_cpu_reg(16, 32'h00000000);
      check_cpu_reg(17, 32'h00000000);
      check_cpu_reg(18, 32'h00000000);
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
      $display("|         CHECK FINAL STATE AFTER ALL C.MV TESTS                   |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check marker register (was x1 initially, now changed)
      // x1 is modified during tests, so we don't check it as a marker

      // Test Set 1 results (basic moves) - backed up in x16-x19
      check_cpu_reg(16, 32'h12345678);   // Backup of x1: copied from x8
      check_cpu_reg(17, 32'hABCDEF01);   // Backup of x2: copied from x9
      check_cpu_reg(18, 32'hFFFFFFFF);   // Backup of x3: copied from x10
      check_cpu_reg(19, 32'h00000000);   // Backup of x4: copied from x11

      // Test Set 1 source verification - backed up in x20-x23
      check_cpu_reg(20, 32'h12345678);   // x8 unchanged after move
      check_cpu_reg(21, 32'hABCDEF01);   // x9 unchanged after move
      check_cpu_reg(22, 32'hFFFFFFFF);   // x10 unchanged after move
      check_cpu_reg(23, 32'h00000000);   // x11 unchanged after move

      // Test Set 2 results (boundary values) - backed up in x24-x25
      check_cpu_reg(24, 32'h80000000);   // Backup of x5: copied from x12 (min negative)
      check_cpu_reg(25, 32'h12345678);   // Backup of x6: copied from x13 (max positive)

      // Test Set 3 results (alternating patterns) - backed up in x28-x29
      check_cpu_reg(28, 32'hAAAAAAAA);   // Backup of x7: copied from x14
      check_cpu_reg(29, 32'h55555555);   // Backup of x1: copied from x15

      // Final state of x1-x15 (after all test sets)
      check_cpu_reg(1,  32'h7FFFFFFF);   // Final value from Test Set 7
      check_cpu_reg(2,  32'h12345678);   // Final value from Test Set 8
      check_cpu_reg(3,  32'hABCDEF01);   // Final value from Test Set 8
      check_cpu_reg(4,  32'h00000000);   // Final value from Test Set 9
      check_cpu_reg(5,  32'h12345678);   // Final value from Test Set 4 (copy chain)
      check_cpu_reg(6,  32'h80000000);   // Final value from Test Set 6
      check_cpu_reg(7,  32'h80000000);   // Final value from Test Set 6
      check_cpu_reg(8,  32'h12345678);   // Final value from Test Set 10
      check_cpu_reg(9,  32'hABCDEF01);   // Final value from Test Set 10
      check_cpu_reg(10, 32'h7FFFFFFF);   // Final value from Test Set 10
      check_cpu_reg(11, 32'h00000000);   // Unchanged (never destination)
      check_cpu_reg(12, 32'h80000000);   // Unchanged (never destination)
      check_cpu_reg(13, 32'h7FFFFFFF);   // Unchanged (never destination)
      check_cpu_reg(14, 32'hAAAAAAAA);   // Unchanged (never destination)
      check_cpu_reg(15, 32'h55555555);   // Unchanged (never destination)

      // Non-compressed registers used in Test Set 5 and 7
      check_cpu_reg(25, 32'h12345678);   // Final value from Test Set 5
      check_cpu_reg(26, 32'hABCDEF01);   // Final value from Test Set 5
      check_cpu_reg(27, 32'h7FFFFFFF);   // Final value from Test Set 7

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
