//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_sextb
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SEXT.B (Zbb)
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
      $display("|             CHECK REGISTER VALUES BEFORE SEXT.B TESTS             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h00000000);   // Zero
      check_cpu_reg(2,  32'h00000001);   // 1
      check_cpu_reg(3,  32'h0000007F);   // Max positive byte
      check_cpu_reg(4,  32'h00000080);   // Min negative byte
      check_cpu_reg(5,  32'h000000FF);   // -1 as byte
      check_cpu_reg(6,  32'h00000055);   // 0x55
      check_cpu_reg(7,  32'h000000AA);   // 0xAA
      check_cpu_reg(8,  32'hFFFFFFFF);   // All ones
      check_cpu_reg(9,  32'h12345678);   // Upper bits set
      check_cpu_reg(10, 32'hABCDEFAB);   // Upper bits set
      check_cpu_reg(11, 32'h00000000);   // Not yet set
      check_cpu_reg(12, 32'h00000000);   // Not yet set
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
      $display("|             CHECK REGISTER VALUES AFTER SEXT.B TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After SEXT.B tests, check final register state
      // SEXT.B operation: rd = sign_extend(rs1[7:0])
      // Note: Many registers are reused, checking final values only

      // x1: Test 16 source data
      check_cpu_reg(1, 32'h000000C0);

      // x2: Test 16 result - sext.b(0x000000C0) = 0xFFFFFFC0
      check_cpu_reg(2, 32'hFFFFFFC0);

      // x3: Test 17 source data
      check_cpu_reg(3, 32'hFFFFFF00);

      // x4: Test 17 result - sext.b(0xFFFFFF00) = 0x00000000
      check_cpu_reg(4, 32'h00000000);

      // x5: Test 18 source data
      check_cpu_reg(5, 32'hABCD007F);

      // x6: Test 18 result - sext.b(0xABCD007F) = 0x0000007F
      check_cpu_reg(6, 32'h0000007F);

      // x7: Test 19 source data
      check_cpu_reg(7, 32'h12340080);

      // x8: Test 19 result - sext.b(0x12340080) = 0xFFFFFF80
      check_cpu_reg(8, 32'hFFFFFF80);

      // x9: Test 20 source data
      check_cpu_reg(9, 32'h567890FF);

      // x10: Test 20 result - sext.b(0x567890FF) = 0xFFFFFFFF
      check_cpu_reg(10, 32'hFFFFFFFF);

      // x11: Test 21 source data
      check_cpu_reg(11, 32'h00000010);

      // x12: Test 21 result - sext.b(0x00000010) = 0x00000010
      check_cpu_reg(12, 32'h00000010);

      // x13: Test 22 source data
      check_cpu_reg(13, 32'h000000F0);

      // x14: Test 22 result - sext.b(0x000000F0) = 0xFFFFFFF0
      check_cpu_reg(14, 32'hFFFFFFF0);

      // x15: Test 23 source data
      check_cpu_reg(15, 32'hFEDCBA02);

      // x16: Test 23 result - sext.b(0xFEDCBA02) = 0x00000002
      check_cpu_reg(16, 32'h00000002);

      // x17: Test 24 source data
      check_cpu_reg(17, 32'h11111182);

      // x18: Test 24 result - sext.b(0x11111182) = 0xFFFFFF82
      check_cpu_reg(18, 32'hFFFFFF82);

      // x19: Test 25 source data
      check_cpu_reg(19, 32'h0000003F);

      // x20: Test 25 result - sext.b(0x0000003F) = 0x0000003F
      check_cpu_reg(20, 32'h0000003F);

      // x21: Test 26 source data
      check_cpu_reg(21, 32'h000000BF);

      // x22: Test 26 result - sext.b(0x000000BF) = 0xFFFFFFBF
      check_cpu_reg(22, 32'hFFFFFFBF);

      // x23: Test 27 source data
      check_cpu_reg(23, 32'hAAAA000F);

      // x24: Test 27 result - sext.b(0xAAAA000F) = 0x0000000F
      check_cpu_reg(24, 32'h0000000F);

      // x25: Test 28 source data
      check_cpu_reg(25, 32'h5555558F);

      // x26: Test 28 result - sext.b(0x5555558F) = 0xFFFFFF8F
      check_cpu_reg(26, 32'hFFFFFF8F);

      // x27: Test 29 source data
      check_cpu_reg(27, 32'h0000007D);

      // x28: Test 29 result - sext.b(0x0000007D) = 0x0000007D
      check_cpu_reg(28, 32'h0000007D);

      // x29: Test 30 source data
      check_cpu_reg(29, 32'hFFFF0083);

      // x30: Test 30 result - sext.b(0xFFFF0083) = 0xFFFFFF83
      check_cpu_reg(30, 32'hFFFFFF83);

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
