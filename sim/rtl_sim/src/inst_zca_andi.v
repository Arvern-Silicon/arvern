//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_andi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.ANDI
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.ANDI                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'hCAFEBABE);
      check_cpu_reg(2,  32'h00000000);
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'hFFFFFFFF);   // Test pattern
      check_cpu_reg(9,  32'hAAAAAAAA);   // Test pattern
      check_cpu_reg(10, 32'h12345678);   // Test pattern
      check_cpu_reg(11, 32'hF0F0F0F0);   // Test pattern
      check_cpu_reg(12, 32'h0F0F0F0F);   // Test pattern
      check_cpu_reg(13, 32'hDEADBEEF);   // Test pattern
      check_cpu_reg(14, 32'h80000001);   // Test pattern
      check_cpu_reg(15, 32'h00000000);   // Test pattern
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
      $display("|         CHECK FINAL STATE AFTER ALL C.ANDI TESTS                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check marker register
      check_cpu_reg(1,  32'hCAFEBABE);   // Unchanged marker

      // Test Set 1 results (positive immediates) - backed up in x16-x20
      check_cpu_reg(16, 32'h0000001F);   // Backup of x8:  0xFFFFFFFF & 0x0000001F = 31
      check_cpu_reg(17, 32'h0000000A);   // Backup of x9:  0xAAAAAAAA & 0x0000000F = 10
      check_cpu_reg(18, 32'h00000000);   // Backup of x10: 0x12345678 & 0x00000007 = 0
      check_cpu_reg(19, 32'h00000000);   // Backup of x11: 0xF0F0F0F0 & 0x00000003 = 0
      check_cpu_reg(20, 32'h00000001);   // Backup of x12: 0x0F0F0F0F & 0x00000001 = 1

      // Test Set 2 results (negative immediates) - backed up in x21-x25
      check_cpu_reg(21, 32'hFFFFFFFF);   // Backup of x8:  0xFFFFFFFF & 0xFFFFFFFF = all 1s
      check_cpu_reg(22, 32'h12345678);   // Backup of x9:  0x12345678 & 0xFFFFFFFE = 0x12345678
      check_cpu_reg(23, 32'hAAAAAAA8);   // Backup of x10: 0xAAAAAAAA & 0xFFFFFFFC = 0xAAAAAAA8
      check_cpu_reg(24, 32'hF0F0F0F0);   // Backup of x11: 0xF0F0F0F0 & 0xFFFFFFF8 = 0xF0F0F0F0
      check_cpu_reg(25, 32'h00000000);   // Backup of x12: 0x00000000 & 0xFFFFFFF0 = 0

      // Test Set 3 results (boundary cases) - backed up in x26-x28
      check_cpu_reg(26, 32'h00000000);   // Backup of x13: 0xFFFFFFFF & 0x00000000 = 0
      check_cpu_reg(27, 32'h80000000);   // Backup of x14: 0x80000001 & 0xFFFFFFE0 = 0x80000000
      check_cpu_reg(28, 32'h0000000F);   // Backup of x15: 0xDEADBEEF & 0x0000001F = 0x0000000F

      // Test Set 4 results (bit masking) - backed up in x29, x30, x2
      check_cpu_reg(29, 32'h00000008);   // Backup of x8:  0x12345678 & 0x0000000F = 8
      check_cpu_reg(30, 32'hFFFFFFF0);   // Backup of x9:  0xFFFFFFFF & 0xFFFFFFF0 = 0xFFFFFFF0
      check_cpu_reg(2,  32'hABCDEF01);   // Backup of x10: 0xABCDEF01 & 0xFFFFFFFF = 0xABCDEF01

      // Test Set 5 result (consecutive ANDs) - backed up in x3
      check_cpu_reg(3,  32'h00000003);   // Backup of x11: 31 & 15 & 7 & 3 = 3

      // Test Set 6 results (pattern masking) - backed up in x4-x6
      check_cpu_reg(4,  32'h00000005);   // Backup of x12: 0x55555555 & 0x0000000F = 5
      check_cpu_reg(5,  32'hAAAAAAA8);   // Backup of x13: 0xAAAAAAAA & 0xFFFFFFFD = 0xAAAAAAA8
      check_cpu_reg(6,  32'h00000010);   // Backup of x14: 0xF0F0F0F0 & 0x00000010 = 16

      // Test Set 7 results (odd immediates) - backed up in x7, x9
      check_cpu_reg(7,  32'h00000010);   // Backup of x15: 0x12345678 & 0x00000015 = 16
      check_cpu_reg(9,  32'hFFFFFFEF);   // Backup of x8:  0xFFFFFFFF & 0xFFFFFFEF = 0xFFFFFFEF

      // Final state of x8-x15
      check_cpu_reg(8,  32'hFFFFFFEF);   // Final value from Test Set 7
      check_cpu_reg(10, 32'hABCDEF01);   // Final value from Test Set 4
      check_cpu_reg(11, 32'h00000003);   // Final value from Test Set 5
      check_cpu_reg(12, 32'h00000005);   // Final value from Test Set 6
      check_cpu_reg(13, 32'hAAAAAAA8);   // Final value from Test Set 6
      check_cpu_reg(14, 32'h00000010);   // Final value from Test Set 6
      check_cpu_reg(15, 32'h00000010);   // Final value from Test Set 7

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
