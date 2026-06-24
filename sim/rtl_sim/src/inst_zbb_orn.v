//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_orn
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ORN (Zbb)
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
      $display("|               CHECK REGISTER VALUES BEFORE ORN TESTS              |");
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
      $display("|               CHECK REGISTER VALUES AFTER ORN TESTS               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After ORN tests, check that operations were performed correctly
      // ORN operation: rd = rs1 | ~rs2

      // Test 1: 0xFFFFFFFF | ~0x00000000 = 0xFFFFFFFF
      check_cpu_reg(13, 32'hFFFFFFFF);

      // Test 2: 0x00000000 | ~0x00000000 = 0xFFFFFFFF
      check_cpu_reg(14, 32'hFFFFFFFF);

      // Test 3: 0xFFFFFFFF | ~0xFFFFFFFF = 0xFFFFFFFF
      check_cpu_reg(15, 32'hFFFFFFFF);

      // Test 4: 0x00000000 | ~0xFFFFFFFF = 0x00000000
      check_cpu_reg(16, 32'h00000000);

      // Test 5: 0xAAAAAAAA | ~0x55555555 = 0xAAAAAAAA
      check_cpu_reg(17, 32'hAAAAAAAA);

      // Test 6: 0x55555555 | ~0xAAAAAAAA = 0x55555555
      check_cpu_reg(18, 32'h55555555);

      // Test 7: 0xF0F0F0F0 | ~0x0F0F0F0F = 0xF0F0F0F0
      check_cpu_reg(19, 32'hF0F0F0F0);

      // Test 8: 0xFF00FF00 | ~0x00FF00FF = 0xFF00FF00
      check_cpu_reg(20, 32'hFF00FF00);

      // Test 9: 0x12345678 | ~0x0000FFFF = 0xFFFF5678
      check_cpu_reg(21, 32'hFFFF5678);

      // Test 10: 0xFEDCBA98 | ~0xFFFF0000 = 0xFEDCFFFF
      check_cpu_reg(22, 32'hFEDCFFFF);

      // Test 11: 0x0FF000FF | ~0xF00FF00F = 0x0FF00FFF
      check_cpu_reg(23, 32'h0FF00FFF);

      // x24 is still the mask value from test 11
      check_cpu_reg(24, 32'hF00FF00F);

      // Test 12: OR vs ORN comparison
      // OR:  0xAAAAAAAA | 0x55555555 = 0xFFFFFFFF
      check_cpu_reg(25, 32'hFFFFFFFF);
      // ORN: 0xAAAAAAAA | ~0x55555555 = 0xAAAAAAAA
      check_cpu_reg(26, 32'hAAAAAAAA);

      // x27 and x28 are test data for test 13
      check_cpu_reg(27, 32'h00001000);
      check_cpu_reg(28, 32'hFF0F0FFF);

      // Test 13: 0x00001000 | ~0xFF0F0FFF = 0x00F0F000
      check_cpu_reg(29, 32'h00F0F000);

      // x30 is test data
      check_cpu_reg(30, 32'h7FFFFFFF);

      // Test 14: 0x7FFFFFFF | ~0x7FFFFFFF = 0xFFFFFFFF (stored in x2)
      check_cpu_reg(2, 32'hFFFFFFFF);

      // x1 is test data from test 14
      check_cpu_reg(1, 32'h7FFFFFFF);

      // Test 15 changes x3, x4, x5
      // x3 is reloaded with 0x00000000
      check_cpu_reg(3, 32'h00000000);
      // x4 is reloaded with 0xF0F0F0F0
      check_cpu_reg(4, 32'hF0F0F0F0);
      // Test 15: 0x00000000 | ~0xF0F0F0F0 = 0x0F0F0F0F (stored in x5)
      check_cpu_reg(5, 32'h0F0F0F0F);

      // x6-x12 remain unchanged from initial values
      check_cpu_reg(6,  32'h0F0F0F0F);
      check_cpu_reg(7,  32'hFF00FF00);
      check_cpu_reg(8,  32'h00FF00FF);
      check_cpu_reg(9,  32'h12345678);
      check_cpu_reg(10, 32'hFEDCBA98);
      check_cpu_reg(11, 32'h0000FFFF);
      check_cpu_reg(12, 32'hFFFF0000);

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
