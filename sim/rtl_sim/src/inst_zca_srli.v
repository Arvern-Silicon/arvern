//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_srli
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SRLI
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.SRLI                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'hDEADBEEF);
      check_cpu_reg(2,  32'h00000000);
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'hFFFFFFFF);   // Test pattern
      check_cpu_reg(9,  32'h80000000);   // Test pattern
      check_cpu_reg(10, 32'hAAAAAAAA);   // Test pattern
      check_cpu_reg(11, 32'h12345678);   // Test pattern
      check_cpu_reg(12, 32'hF0F0F0F0);   // Test pattern
      check_cpu_reg(13, 32'h0F0F0F0F);   // Test pattern
      check_cpu_reg(14, 32'h00000001);   // Test pattern
      check_cpu_reg(15, 32'hFEDCBA98);   // Test pattern
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
      $display("|         CHECK FINAL STATE AFTER ALL C.SRLI TESTS                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check marker register
      check_cpu_reg(1,  32'hDEADBEEF);   // Unchanged marker

      // Test Set 2 results (backed up in x24-x30, x2)
      check_cpu_reg(2,  32'h000055E6);   // Backup of x15: 0xABCDEF01 >> 17
      check_cpu_reg(24, 32'h7FFFFFFF);   // Backup of x8:  0xFFFFFFFF >> 1 (min shift)
      check_cpu_reg(25, 32'h00000001);   // Backup of x9:  0x80000000 >> 31 (max shift)
      check_cpu_reg(26, 32'h00005555);   // Backup of x10: 0x55555555 >> 16
      check_cpu_reg(27, 32'h0F000000);   // Backup of x11: 0xF0000000 >> 4
      check_cpu_reg(28, 32'h000000FF);   // Backup of x12: 0x0000FFFF >> 8
      check_cpu_reg(29, 32'h30303030);   // Backup of x13: 0xC0C0C0C0 >> 2
      check_cpu_reg(30, 32'h00002468);   // Backup of x14: 0x12345678 >> 15

      // Test Set 3 result (backed up in x3)
      check_cpu_reg(3,  32'h08000000);   // Backup of x8: 0x80000000 >> 1 >> 1 >> 1 >> 1

      // Test Set 4 results (backed up in x4, x5)
      check_cpu_reg(4,  32'h0F000000);   // Backup of x9:  0xF0000000 >> 4 (zero-fill)
      check_cpu_reg(5,  32'h40000000);   // Backup of x10: 0x80000001 >> 1

      // Unused registers should remain zero
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);

      // Final state of x8-x15 (from Test Set 4)
      check_cpu_reg(8,  32'h08000000);   // Final value after multiple shifts
      check_cpu_reg(9,  32'h0F000000);   // Final value: 0xF0000000 >> 4
      check_cpu_reg(10, 32'h40000000);   // Final value: 0x80000001 >> 1
      check_cpu_reg(11, 32'h0F000000);   // Final value from Test Set 2
      check_cpu_reg(12, 32'h000000FF);   // Final value from Test Set 2
      check_cpu_reg(13, 32'h30303030);   // Final value from Test Set 2
      check_cpu_reg(14, 32'h00002468);   // Final value from Test Set 2
      check_cpu_reg(15, 32'h000055E6);   // Final value from Test Set 2

      // Test Set 1 results (backed up in x16-x23)
      check_cpu_reg(16, 32'h7FFFFFFF);   // Backup of x8:  0xFFFFFFFF >> 1
      check_cpu_reg(17, 32'h08000000);   // Backup of x9:  0x80000000 >> 4
      check_cpu_reg(18, 32'h00AAAAAA);   // Backup of x10: 0xAAAAAAAA >> 8
      check_cpu_reg(19, 32'h00012345);   // Backup of x11: 0x12345678 >> 12
      check_cpu_reg(20, 32'h0000F0F0);   // Backup of x12: 0xF0F0F0F0 >> 16
      check_cpu_reg(21, 32'h000000F0);   // Backup of x13: 0x0F0F0F0F >> 20
      check_cpu_reg(22, 32'h00000000);   // Backup of x14: 0x00000001 >> 24
      check_cpu_reg(23, 32'h0000000F);   // Backup of x15: 0xFEDCBA98 >> 28

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
