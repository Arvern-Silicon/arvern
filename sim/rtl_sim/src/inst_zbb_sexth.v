//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_sexth
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SEXT.H (Zbb)
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
      $display("|             CHECK REGISTER VALUES BEFORE SEXT.H TESTS             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h00000000);   // Zero
      check_cpu_reg(2,  32'h00000001);   // 1
      check_cpu_reg(3,  32'h00007FFF);   // Max positive halfword
      check_cpu_reg(4,  32'h00008000);   // Min negative halfword
      check_cpu_reg(5,  32'h0000FFFF);   // -1 as halfword
      check_cpu_reg(6,  32'h00005555);   // 0x5555
      check_cpu_reg(7,  32'h0000AAAA);   // 0xAAAA
      check_cpu_reg(8,  32'hFFFFFFFF);   // All ones
      check_cpu_reg(9,  32'h12345678);   // Upper bits set
      check_cpu_reg(10, 32'hABCDABCD);   // Upper bits set
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
      $display("|             CHECK REGISTER VALUES AFTER SEXT.H TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After SEXT.H tests, check final register state
      // SEXT.H operation: rd = sign_extend(rs1[15:0])
      // Note: Many registers are reused, checking final values only

      // x1: Test 16 source data
      check_cpu_reg(1, 32'h0000C000);

      // x2: Test 16 result - sext.h(0x0000C000) = 0xFFFFC000
      check_cpu_reg(2, 32'hFFFFC000);

      // x3: Test 17 source data
      check_cpu_reg(3, 32'hFFFF0000);

      // x4: Test 17 result - sext.h(0xFFFF0000) = 0x00000000
      check_cpu_reg(4, 32'h00000000);

      // x5: Test 18 source data
      check_cpu_reg(5, 32'hABCD7FFF);

      // x6: Test 18 result - sext.h(0xABCD7FFF) = 0x00007FFF
      check_cpu_reg(6, 32'h00007FFF);

      // x7: Test 19 source data
      check_cpu_reg(7, 32'h12348000);

      // x8: Test 19 result - sext.h(0x12348000) = 0xFFFF8000
      check_cpu_reg(8, 32'hFFFF8000);

      // x9: Test 20 source data
      check_cpu_reg(9, 32'h5678FFFF);

      // x10: Test 20 result - sext.h(0x5678FFFF) = 0xFFFFFFFF
      check_cpu_reg(10, 32'hFFFFFFFF);

      // x11: Test 21 source data
      check_cpu_reg(11, 32'h00000100);

      // x12: Test 21 result - sext.h(0x00000100) = 0x00000100
      check_cpu_reg(12, 32'h00000100);

      // x13: Test 22 source data
      check_cpu_reg(13, 32'h0000FF00);

      // x14: Test 22 result - sext.h(0x0000FF00) = 0xFFFFFF00
      check_cpu_reg(14, 32'hFFFFFF00);

      // x15: Test 23 source data
      check_cpu_reg(15, 32'hFEDC0002);

      // x16: Test 23 result - sext.h(0xFEDC0002) = 0x00000002
      check_cpu_reg(16, 32'h00000002);

      // x17: Test 24 source data
      check_cpu_reg(17, 32'h11118002);

      // x18: Test 24 result - sext.h(0x11118002) = 0xFFFF8002
      check_cpu_reg(18, 32'hFFFF8002);

      // x19: Test 25 source data
      check_cpu_reg(19, 32'h00003FFF);

      // x20: Test 25 result - sext.h(0x00003FFF) = 0x00003FFF
      check_cpu_reg(20, 32'h00003FFF);

      // x21: Test 26 source data
      check_cpu_reg(21, 32'h0000BFFF);

      // x22: Test 26 result - sext.h(0x0000BFFF) = 0xFFFFBFFF
      check_cpu_reg(22, 32'hFFFFBFFF);

      // x23: Test 27 source data
      check_cpu_reg(23, 32'hAAAA00FF);

      // x24: Test 27 result - sext.h(0xAAAA00FF) = 0x000000FF
      check_cpu_reg(24, 32'h000000FF);

      // x25: Test 28 source data
      check_cpu_reg(25, 32'h555580FF);

      // x26: Test 28 result - sext.h(0x555580FF) = 0xFFFF80FF
      check_cpu_reg(26, 32'hFFFF80FF);

      // x27: Test 29 source data
      check_cpu_reg(27, 32'h00001234);

      // x28: Test 29 result - sext.h(0x00001234) = 0x00001234
      check_cpu_reg(28, 32'h00001234);

      // x29: Test 30 source data
      check_cpu_reg(29, 32'hFFFF9876);

      // x30: Test 30 result - sext.h(0xFFFF9876) = 0xFFFF9876
      check_cpu_reg(30, 32'hFFFF9876);

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
