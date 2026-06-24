//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_rev8
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: REV8 (Zbb)
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
      $display("|             CHECK REGISTER VALUES BEFORE REV8 TESTS               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h00000000);   // All zeros
      check_cpu_reg(2,  32'hFFFFFFFF);   // All ones
      check_cpu_reg(3,  32'h12345678);   // Sequential bytes
      check_cpu_reg(4,  32'hDEADBEEF);   // Mixed pattern
      check_cpu_reg(5,  32'h000000FF);   // Only byte 0 set
      check_cpu_reg(6,  32'h0000FF00);   // Only byte 1 set
      check_cpu_reg(7,  32'h00FF0000);   // Only byte 2 set
      check_cpu_reg(8,  32'hFF000000);   // Only byte 3 set
      check_cpu_reg(9,  32'h01020304);   // Sequential pattern
      check_cpu_reg(10, 32'hAABBCCDD);   // Distinct bytes
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
      $display("|             CHECK REGISTER VALUES AFTER REV8 TESTS                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After REV8 tests, check final register state
      // REV8 operation: rd[31:24] = rs1[7:0], rd[23:16] = rs1[15:8],
      //                 rd[15:8] = rs1[23:16], rd[7:0] = rs1[31:24]

      // x1: Test 21 result - rev8(0x12345678) twice = original
      check_cpu_reg(1, 32'h12345678);

      // x2: Test 22 result - rev8(0x00112233)
      check_cpu_reg(2, 32'h33221100);

      // x3: Test 23 result - rev8(0x44556677)
      check_cpu_reg(3, 32'h77665544);

      // x4: Test 24 result - rev8(0x8899AABB)
      check_cpu_reg(4, 32'hBBAA9988);

      // x5: Test 25 result - rev8(0xCCDDEEFF)
      check_cpu_reg(5, 32'hFFEEDDCC);

      // x6: Test 26 result - rev8(0x0000FFFF)
      check_cpu_reg(6, 32'hFFFF0000);

      // x7: Test 27 result - rev8(0xFFFF0000)
      check_cpu_reg(7, 32'h0000FFFF);

      // x8: Test 28 result - rev8(0x7FFFFFFF)
      check_cpu_reg(8, 32'hFFFFFF7F);

      // x9: Test 29 result - rev8(0x80808080)
      check_cpu_reg(9, 32'h80808080);

      // x10: Test 30 result - rev8(0x01010101)
      check_cpu_reg(10, 32'h01010101);

      // x11: Test 1 result - rev8(0x00000000)
      check_cpu_reg(11, 32'h00000000);

      // x12: Test 2 result - rev8(0xFFFFFFFF)
      check_cpu_reg(12, 32'hFFFFFFFF);

      // x13: Test 3 result - rev8(0x12345678)
      check_cpu_reg(13, 32'h78563412);

      // x14: Test 4 result - rev8(0xDEADBEEF)
      check_cpu_reg(14, 32'hEFBEADDE);

      // x15: Test 5 result - rev8(0x000000FF)
      check_cpu_reg(15, 32'hFF000000);

      // x16: Test 6 result - rev8(0x0000FF00)
      check_cpu_reg(16, 32'h00FF0000);

      // x17: Test 7 result - rev8(0x00FF0000)
      check_cpu_reg(17, 32'h0000FF00);

      // x18: Test 8 result - rev8(0xFF000000)
      check_cpu_reg(18, 32'h000000FF);

      // x19: Test 9 result - rev8(0x01020304)
      check_cpu_reg(19, 32'h04030201);

      // x20: Test 10 result - rev8(0xAABBCCDD)
      check_cpu_reg(20, 32'hDDCCBBAA);

      // x21: Test 11 result - rev8(0x12344321)
      check_cpu_reg(21, 32'h21433412);

      // x22: Test 12 result - rev8(0xA5A5A5A5)
      check_cpu_reg(22, 32'hA5A5A5A5);

      // x23: Test 13 result - rev8(0x00FF00FF)
      check_cpu_reg(23, 32'hFF00FF00);

      // x24: Test 14 result - rev8(0xFF00FF00)
      check_cpu_reg(24, 32'h00FF00FF);

      // x25: Test 15 result - rev8(0x80000000)
      check_cpu_reg(25, 32'h00000080);

      // x26: Test 16 result - rev8(0x00000001)
      check_cpu_reg(26, 32'h01000000);

      // x27: Test 17 result - rev8(0xF0F0F0F0)
      check_cpu_reg(27, 32'hF0F0F0F0);

      // x28: Test 18 result - rev8(0x0F0F0F0F)
      check_cpu_reg(28, 32'h0F0F0F0F);

      // x29: Test 19 result - rev8(0xFEDCBA98)
      check_cpu_reg(29, 32'h98BADCFE);

      // x30: Test 20 result - rev8(0x11223344)
      check_cpu_reg(30, 32'h44332211);

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
