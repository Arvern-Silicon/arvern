//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_lwsp
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.LWSP
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.LWSP              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values (all cleared after stack setup)
      check_cpu_reg(1,  32'h1E570001);
      check_cpu_reg(2,  32'h80000400);   // SP
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
      $display("|         CHECK FINAL STATE AFTER ALL C.LWSP TESTS                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Test Set 1 results (basic loads) - backed up in x21-x24
      check_cpu_reg(21, 32'h12345678);   // Backup of x8:  loaded from [SP+0]
      check_cpu_reg(22, 32'hABCDEF01);   // Backup of x9:  loaded from [SP+4]
      check_cpu_reg(23, 32'hFFFFFFFF);   // Backup of x10: loaded from [SP+8]
      check_cpu_reg(24, 32'h00000000);   // Backup of x11: loaded from [SP+12]

      // Test Set 1 SP verification - backed up in x25
      check_cpu_reg(25, 32'hFFFFFFFF);   // Backup of x2 (SP): unchanged (overwritten by Test Set 10)

      // Test Set 2 results (boundary values) - backed up in x26-x27
      check_cpu_reg(26, 32'h00000000);   // Backup of x12: loaded from [SP+16] (overwritten by Test Set 10)
      check_cpu_reg(27, 32'h7FFFFFFF);   // Backup of x13: loaded from [SP+20]

      // Test Set 3 results (alternating patterns) - backed up in x28-x29
      check_cpu_reg(28, 32'hAAAAAAAA);   // Backup of x14: loaded from [SP+24]
      check_cpu_reg(29, 32'h55555555);   // Backup of x15: loaded from [SP+28]

      // Test Set 4 results (medium offsets) - backed up in x3-x4
      check_cpu_reg(3,  32'h11111111);   // Backup of x16: loaded from [SP+32]
      check_cpu_reg(4,  32'h22222222);   // Backup of x17: loaded from [SP+36]

      // Test Set 5 result (larger offset) - backed up in x5
      check_cpu_reg(5,  32'h33333333);   // Backup of x18: loaded from [SP+64]

      // Test Set 6 result (even larger offset) - backed up in x6
      check_cpu_reg(6,  32'h44444444);   // Backup of x19: loaded from [SP+128]

      // Test Set 7 result (max offset) - backed up in x7
      check_cpu_reg(7,  32'hDEADCAFE);   // Backup of x20: loaded from [SP+252]

      // Test Set 8 result (load to x1) - backed up in x30
      check_cpu_reg(30, 32'h12345678);   // Backup of x1: loaded from [SP+0]

      // Final state of x1-x20 (after all test sets)
      check_cpu_reg(1,  32'h12345678);   // Final value from Test Set 8
      check_cpu_reg(2,  32'h80000400);   // SP unchanged throughout
      // x3-x7 already checked (backups from Test Sets 4-7)
      check_cpu_reg(8,  32'hABCDEF01);   // Final value from Test Set 9
      check_cpu_reg(9,  32'hABCDEF01);   // Final value from Test Set 9 (same as x8)
      check_cpu_reg(10, 32'hFFFFFFFF);   // Final value from Test Set 1
      check_cpu_reg(11, 32'h00000000);   // Final value from Test Set 1
      check_cpu_reg(12, 32'h80000000);   // Final value from Test Set 2
      check_cpu_reg(13, 32'h7FFFFFFF);   // Final value from Test Set 2
      check_cpu_reg(14, 32'hAAAAAAAA);   // Final value from Test Set 3
      check_cpu_reg(15, 32'h55555555);   // Final value from Test Set 3
      check_cpu_reg(16, 32'h11111111);   // Final value from Test Set 4
      check_cpu_reg(17, 32'h22222222);   // Final value from Test Set 4
      check_cpu_reg(18, 32'h33333333);   // Final value from Test Set 5
      check_cpu_reg(19, 32'h44444444);   // Final value from Test Set 6
      check_cpu_reg(20, 32'hDEADCAFE);   // Final value from Test Set 7

      // Non-compressed registers from Test Set 10
      check_cpu_reg(25, 32'hFFFFFFFF);   // Final value from Test Set 10
      check_cpu_reg(26, 32'h00000000);   // Final value from Test Set 10

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
