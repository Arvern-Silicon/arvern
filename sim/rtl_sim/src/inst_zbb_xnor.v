//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_xnor
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: XNOR (Zbb)
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
      $display("|              CHECK REGISTER VALUES BEFORE XNOR TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'hFFFFFFFF);   // All 1s
      check_cpu_reg(2,  32'h00000000);   // All 0s
      check_cpu_reg(3,  32'hAAAAAAAA);   // Alternating 10101010...
      check_cpu_reg(4,  32'h55555555);   // Alternating 01010101...
      check_cpu_reg(5,  32'hF0F0F0F0);   // Nibble pattern
      check_cpu_reg(6,  32'h0F0F0F0F);   // Inverted nibble pattern
      check_cpu_reg(7,  32'hFF00FF00);   // Byte pattern
      check_cpu_reg(8,  32'h00FF00FF);   // Inverted byte pattern
      check_cpu_reg(9,  32'h12345678);   // Test data 1
      check_cpu_reg(10, 32'hFEDCBA98);   // Test data 2
      check_cpu_reg(11, 32'h0000FFFF);   // Lower halfword all 1s
      check_cpu_reg(12, 32'hFFFF0000);   // Upper halfword all 1s
      check_cpu_reg(13, 32'h00000000);   // Not yet set
      check_cpu_reg(14, 32'h00000000);   // Not yet set
      check_cpu_reg(15, 32'h00000000);   // Not yet set
      check_cpu_reg(16, 32'h00000000);   // Not yet set
      check_cpu_reg(17, 32'h00000000);   // Not yet set
      check_cpu_reg(18, 32'h00000000);   // Not yet set
      check_cpu_reg(19, 32'h00000000);   // Not yet set
      check_cpu_reg(20, 32'h00000000);   // Not yet set
      check_cpu_reg(21, 32'h00000000);   // Not yet set
      check_cpu_reg(22, 32'h00000000);   // Not yet set
      check_cpu_reg(23, 32'h00000000);   // Not yet set
      check_cpu_reg(24, 32'h00000000);   // Not yet set
      check_cpu_reg(25, 32'h00000000);   // Not yet set
      check_cpu_reg(26, 32'h00000000);   // Not yet set
      check_cpu_reg(27, 32'h00000000);   // Not yet set
      check_cpu_reg(28, 32'h00000000);   // Not yet set
      check_cpu_reg(29, 32'h00000000);   // Not yet set
      check_cpu_reg(30, 32'h00000000);   // Not yet set
      check_cpu_reg(31, 32'hDEADBEEF);   // Marker for initial setup complete


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|              CHECK REGISTER VALUES AFTER XNOR TESTS               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After XNOR tests, check that operations were performed correctly
      // XNOR operation: rd = ~(rs1 ^ rs2)

      // Note: Test 1 result (x13) is not checked here as it's overwritten by Test 18
      // Test 1's functionality (XNOR of equal values = 0xFFFFFFFF) is verified in Tests 3, 5, 6, 14

      // Test 2: ~(0xFFFFFFFF ^ 0x00000000) = 0x00000000
      check_cpu_reg(14, 32'h00000000);

      // Test 3: ~(0x00000000 ^ 0x00000000) = 0xFFFFFFFF
      check_cpu_reg(15, 32'hFFFFFFFF);

      // Test 4: ~(0xAAAAAAAA ^ 0x55555555) = 0x00000000
      check_cpu_reg(16, 32'h00000000);

      // Test 5: ~(0xAAAAAAAA ^ 0xAAAAAAAA) = 0xFFFFFFFF
      check_cpu_reg(17, 32'hFFFFFFFF);

      // Test 6: ~(0x55555555 ^ 0x55555555) = 0xFFFFFFFF
      check_cpu_reg(18, 32'hFFFFFFFF);

      // Test 7: ~(0xF0F0F0F0 ^ 0x0F0F0F0F) = 0x00000000
      check_cpu_reg(19, 32'h00000000);

      // Test 8: ~(0xFF00FF00 ^ 0x00FF00FF) = 0x00000000
      check_cpu_reg(20, 32'h00000000);

      // Test 9: ~(0x12345678 ^ 0xFEDCBA98) = 0x1317131F
      check_cpu_reg(21, 32'h1317131F);

      // Test 10: ~(0x12345678 ^ 0x00000000) = 0xEDCBA987
      check_cpu_reg(22, 32'hEDCBA987);

      // Test 11: ~(0x12345678 ^ 0xFFFFFFFF) = 0x12345678
      check_cpu_reg(23, 32'h12345678);

      // Test 12: ~(0xF00F0FF0 ^ 0x0FF0F00F) = 0x00000000
      check_cpu_reg(24, 32'h00000000);

      // x25 is still the mask value from test 12
      check_cpu_reg(25, 32'h0FF0F00F);

      // Test 13: XOR vs XNOR comparison
      // XOR:  0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF
      check_cpu_reg(26, 32'hFFFFFFFF);
      // XNOR: ~(0xAAAAAAAA ^ 0x55555555) = 0x00000000
      check_cpu_reg(27, 32'h00000000);

      // x28 and x29 are test data for test 14
      check_cpu_reg(28, 32'hDEADBEEF);
      check_cpu_reg(29, 32'hDEADBEEF);

      // Test 14: ~(0xDEADBEEF ^ 0xDEADBEEF) = 0xFFFFFFFF (equal values)
      check_cpu_reg(30, 32'hFFFFFFFF);

      // Test 15 changes x1, x2, x3
      // x1 is reloaded with 0xDEADBEEF
      check_cpu_reg(1, 32'hDEADBEEF);
      // x2 is reloaded with 0xDEADBEE0
      check_cpu_reg(2, 32'hDEADBEE0);
      // Test 15: ~(0xDEADBEEF ^ 0xDEADBEE0) = 0xFFFFFFF0
      check_cpu_reg(3, 32'hFFFFFFF0);

      // Test 16 changes x4, x5, x6, x7
      check_cpu_reg(4, 32'hABCD1234);
      check_cpu_reg(5, 32'h56789ABC);
      // Test 16a: ~(0xABCD1234 ^ 0x56789ABC) = 0x024A7777
      check_cpu_reg(6, 32'h024A7777);
      // Test 16b: ~(0x56789ABC ^ 0xABCD1234) = 0x024A7777 (commutative)
      check_cpu_reg(7, 32'h024A7777);

      // Test 17 changes x8, x9, x10
      check_cpu_reg(8, 32'h80000000);
      check_cpu_reg(9, 32'h00000000);
      // Test 17: ~(0x80000000 ^ 0x00000000) = 0x7FFFFFFF
      check_cpu_reg(10, 32'h7FFFFFFF);

      // Test 18 changes x11, x12, x13
      check_cpu_reg(11, 32'h5A5A5A5A);
      check_cpu_reg(12, 32'hA5A5A5A5);
      // Test 18: ~(0x5A5A5A5A ^ 0xA5A5A5A5) = 0x00000000
      check_cpu_reg(13, 32'h00000000);

      check_cpu_reg(31, 32'h12345678);   // Test complete marker

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end
