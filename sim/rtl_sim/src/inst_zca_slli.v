//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_slli
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SLLI
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.SLLI               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'h511ED111);
      check_cpu_reg(2,  32'h00000000);
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'h00000001);   // Single bit
      check_cpu_reg(9,  32'h00000080);   // Bit 7 set
      check_cpu_reg(10, 32'h00005555);   // Alternating pattern
      check_cpu_reg(11, 32'h12345678);   // Test pattern
      check_cpu_reg(12, 32'h0F0F0F0F);   // Nibble pattern
      check_cpu_reg(13, 32'h000000FF);   // Byte
      check_cpu_reg(14, 32'h00000001);   // Single bit
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
      $display("|         CHECK FINAL STATE AFTER ALL C.SLLI TESTS                 |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check marker register
      check_cpu_reg(1,  32'h511ED111);   // Unchanged marker

      // Test Set 1 results (basic shifts) - backed up in x16-x23
      check_cpu_reg(16, 32'h00000002);   // Backup of x8:  0x00000001 << 1
      check_cpu_reg(17, 32'h00000800);   // Backup of x9:  0x00000080 << 4
      check_cpu_reg(18, 32'h000AA000);   // Backup of x10: 0x00005555 << 8 (overwritten by Test Set 6)
      check_cpu_reg(19, 32'h23456780);   // Backup of x11: 0x12345678 << 12 (overwritten by Test Set 6)
      check_cpu_reg(20, 32'h07878780);   // Backup of x12: 0x0F0F0F0F << 16 (overwritten by Test Set 7)
      check_cpu_reg(21, 32'h22222200);   // Backup of x13: 0x000000FF << 20 (overwritten by Test Set 7)
      check_cpu_reg(22, 32'h01000000);   // Backup of x14: 0x00000001 << 24
      check_cpu_reg(23, 32'h80000000);   // Backup of x15: 0xFEDCBA98 << 28

      // Test Set 2 results (boundary cases) - backed up in x24-x30, x2
      check_cpu_reg(24, 32'hFFFFFFFE);   // Backup of x8:  0xFFFFFFFF << 1 (min shift)
      check_cpu_reg(25, 32'h00005500);   // Backup of x9:  0x00000001 << 31 (overwritten by Test Set 6)
      check_cpu_reg(26, 32'h000AA000);   // Backup of x10: 0xAAAAAAAA << 16 (overwritten by Test Set 6)
      check_cpu_reg(27, 32'h23456780);   // Backup of x11: 0xF0000000 << 4 (overwritten by Test Set 6)
      check_cpu_reg(28, 32'h00FFFF00);   // Backup of x12: 0x0000FFFF << 8
      check_cpu_reg(29, 32'h03030300);   // Backup of x13: 0xC0C0C0C0 << 2
      check_cpu_reg(30, 32'h2B3C0000);   // Backup of x14: 0x12345678 << 15
      check_cpu_reg(2,  32'hDE020000);   // Backup of x15: 0xABCDEF01 << 17

      // Test Set 3 result (consecutive shifts) - backed up in x3
      check_cpu_reg(3,  32'h00000010);   // Backup of x8: 1 << 1 << 1 << 1 << 1 = 16

      // Test Set 4 results (overflow) - backed up in x4-x5
      check_cpu_reg(4,  32'h00000000);   // Backup of x9:  0x80000000 << 1 (overflow to zero)
      check_cpu_reg(5,  32'h80000000);   // Backup of x10: 0x00000001 << 31 (set MSB)

      // Test Set 5 result (zero value) - backed up in x6
      check_cpu_reg(6,  32'h00000000);   // Backup of x11: 0x00000000 << 16 (zero stays zero)

      // Test Set 6 results (non-compressed registers) - backed up in x7, x18, x19, x25-x27
      check_cpu_reg(7,  32'h00005500);   // Backup of x25: 0x00000055 << 8

      // Unused registers should remain zero (those not overwritten)
      // x18, x19, x20, x21 were reused, x25-x27 hold final values

      // Final state of x8-x15
      check_cpu_reg(8,  32'h00000010);   // Final value from Test Set 3
      check_cpu_reg(9,  32'h00000000);   // Final value from Test Set 4
      check_cpu_reg(10, 32'h80000000);   // Final value from Test Set 4
      check_cpu_reg(11, 32'h00000000);   // Final value from Test Set 5
      check_cpu_reg(12, 32'h07878780);   // Final value from Test Set 7
      check_cpu_reg(13, 32'h22222200);   // Final value from Test Set 7
      check_cpu_reg(14, 32'h2B3C0000);   // Final value from Test Set 1
      check_cpu_reg(15, 32'hDE020000);   // Final value from Test Set 2

      // Final state of non-compressed registers used in Test Set 6
      check_cpu_reg(25, 32'h00005500);   // Final value from Test Set 6
      check_cpu_reg(26, 32'h000AA000);   // Final value from Test Set 6
      check_cpu_reg(27, 32'h23456780);   // Final value from Test Set 6

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
