//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_srai
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SRAI
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.SRAI                |");
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
      check_cpu_reg(8,  32'hFFFFFFFF);   // Test pattern (negative)
      check_cpu_reg(9,  32'h80000000);   // Test pattern (negative)
      check_cpu_reg(10, 32'hAAAAAAAA);   // Test pattern (negative)
      check_cpu_reg(11, 32'h12345678);   // Test pattern (positive)
      check_cpu_reg(12, 32'hF0F0F0F0);   // Test pattern (negative)
      check_cpu_reg(13, 32'h0F0F0F0F);   // Test pattern (positive)
      check_cpu_reg(14, 32'h00000001);   // Test pattern (positive)
      check_cpu_reg(15, 32'hFEDCBA98);   // Test pattern (negative)
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
      $display("|         CHECK FINAL STATE AFTER ALL C.SRAI TESTS                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check marker register
      check_cpu_reg(1,  32'hDEADBEEF);   // Unchanged marker

      // Test Set 1 results (negative numbers, sign-extended) - backed up in x16-x20
      check_cpu_reg(16, 32'hFFFFFFFF);   // Backup of x8:  0xFFFFFFFF >> 1 (all 1s preserved)
      check_cpu_reg(17, 32'hF8000000);   // Backup of x9:  0x80000000 >> 4 (sign-extended)
      check_cpu_reg(18, 32'hFFAAAAAA);   // Backup of x10: 0xAAAAAAAA >> 8 (sign-extended)
      check_cpu_reg(19, 32'hFFFFF0F0);   // Backup of x12: 0xF0F0F0F0 >> 16 (sign-extended)
      check_cpu_reg(20, 32'hFFFFFFFF);   // Backup of x15: 0xFEDCBA98 >> 28 (sign-extended to -1)

      // Test Set 2 results (positive numbers, zero-filled) - backed up in x21-x24
      check_cpu_reg(21, 32'h3FFFFFFF);   // Backup of x8:  0x7FFFFFFF >> 1 (zero-filled)
      check_cpu_reg(22, 32'h00012345);   // Backup of x9:  0x12345678 >> 12 (zero-filled)
      check_cpu_reg(23, 32'h000000F0);   // Backup of x10: 0x0F0F0F0F >> 20 (zero-filled)
      check_cpu_reg(24, 32'h00000000);   // Backup of x11: 0x00000001 >> 24 (zero-filled)

      // Test Set 3 results (boundary cases) - backed up in x25-x28
      check_cpu_reg(25, 32'hFFFFFFFF);   // Backup of x8:  0x80000000 >> 31 (becomes -1)
      check_cpu_reg(26, 32'hC0000000);   // Backup of x9:  0x80000001 >> 1 (sign-extended)
      check_cpu_reg(27, 32'hFFFFFFFF);   // Backup of x10: 0xFFFFFFFF >> 1 (sign-extended, stays -1)
      check_cpu_reg(28, 32'h00000000);   // Backup of x11: 0x00000000 >> 16 (zero stays zero)

      // Test Set 4 result (multiple consecutive shifts) - backed up in x29
      check_cpu_reg(29, 32'hF8000000);   // Backup of x12: 0x80000000 >> 1 >> 1 >> 1 >> 1

      // Test Set 5 results (arithmetic vs logical) - backed up in x30, x2, x3
      check_cpu_reg(30, 32'hFF000000);   // Backup of x13: 0xF0000000 >> 4 (sign-extended)
      check_cpu_reg(2,  32'hF0000000);   // Backup of x14: 0xC0000000 >> 2 (sign-extended)
      check_cpu_reg(3,  32'h07FFFFFF);   // Backup of x15: 0x7FFFFFFF >> 4 (zero-filled, positive)

      // Test Set 6 results (odd shift amounts) - backed up in x4, x5
      check_cpu_reg(4,  32'hFFFF579B);   // Backup of x8:  0xABCDEF01 >> 15 (sign-extended)
      check_cpu_reg(5,  32'h0000091A);   // Backup of x9:  0x12345678 >> 17 (zero-filled, positive)

      // Unused registers should remain zero
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);

      // Final state of x8-x15 (from Test Set 6)
      check_cpu_reg(8,  32'hFFFF579B);   // Final value: 0xABCDEF01 >> 15
      check_cpu_reg(9,  32'h0000091A);   // Final value: 0x12345678 >> 17
      check_cpu_reg(10, 32'hFFFFFFFF);   // Final value from Test Set 3
      check_cpu_reg(11, 32'h00000000);   // Final value from Test Set 3
      check_cpu_reg(12, 32'hF8000000);   // Final value from Test Set 4
      check_cpu_reg(13, 32'hFF000000);   // Final value from Test Set 5
      check_cpu_reg(14, 32'hF0000000);   // Final value from Test Set 5
      check_cpu_reg(15, 32'h07FFFFFF);   // Final value from Test Set 5

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
