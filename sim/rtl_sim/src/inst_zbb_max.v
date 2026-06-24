//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_max
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MAX (Zbb)
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
      $display("|               CHECK REGISTER VALUES BEFORE MAX TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h0000000A);   // 10
      check_cpu_reg(2,  32'h00000014);   // 20
      check_cpu_reg(3,  32'hFFFFFFF6);   // -10
      check_cpu_reg(4,  32'hFFFFFFEC);   // -20
      check_cpu_reg(5,  32'h00000000);   // 0
      check_cpu_reg(6,  32'h7FFFFFFF);   // INT_MAX
      check_cpu_reg(7,  32'h80000000);   // INT_MIN
      check_cpu_reg(8,  32'h00000001);   // 1
      check_cpu_reg(9,  32'hFFFFFFFF);   // -1
      check_cpu_reg(10, 32'h00000064);   // 100
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
      $display("|               CHECK REGISTER VALUES AFTER MAX TESTS               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After MAX tests, check final register state
      // MAX operation: rd = max(rs1, rs2) - signed comparison
      // Note: Many registers are reused, checking final values only

      // x1: Test 21 source data
      check_cpu_reg(1, 32'hFFFFFFFF);

      // x2: Test 21 source data
      check_cpu_reg(2, 32'h00000001);

      // x3: Test 21 result - max(-1, 1) = 1
      check_cpu_reg(3, 32'h00000001);

      // x4: Test 22 source data
      check_cpu_reg(4, 32'h000F4240);

      // x5: Test 22 source data
      check_cpu_reg(5, 32'h001E8480);

      // x6: Test 22 result - max(1000000, 2000000) = 2000000
      check_cpu_reg(6, 32'h001E8480);

      // x7: Test 23 source data
      check_cpu_reg(7, 32'hFFF0BDC0);

      // x8: Test 23 source data
      check_cpu_reg(8, 32'hFFE17B80);

      // x9: Test 23 result - max(-1000000, -2000000) = -1000000
      check_cpu_reg(9, 32'hFFF0BDC0);

      // x10: Test 24 source data
      check_cpu_reg(10, 32'h00000063);

      // x11: Test 24 source data
      check_cpu_reg(11, 32'h00000064);

      // x12: Test 24 result - max(99, 100) = 100
      check_cpu_reg(12, 32'h00000064);

      // x13: Test 25 source data
      check_cpu_reg(13, 32'hFFFFFF9C);

      // x14: Test 25 source data
      check_cpu_reg(14, 32'hFFFFFF9D);

      // x15: Test 25 result - max(-100, -99) = -99
      check_cpu_reg(15, 32'hFFFFFF9D);

      // x16: Test 26 source data
      check_cpu_reg(16, 32'h00000080);

      // x17: Test 26 source data
      check_cpu_reg(17, 32'h00000100);

      // x18: Test 26 result - max(128, 256) = 256
      check_cpu_reg(18, 32'h00000100);

      // x19: Test 27 source data
      check_cpu_reg(19, 32'hFFFFFF80);

      // x20: Test 27 source data
      check_cpu_reg(20, 32'hFFFFFF00);

      // x21: Test 27 result - max(-128, -256) = -128
      check_cpu_reg(21, 32'hFFFFFF80);

      // x22: Test 28 source data
      check_cpu_reg(22, 32'h00000032);

      // x23: Test 28 source data
      check_cpu_reg(23, 32'hFFFFFF9C);

      // x24: Test 28 result - max(50, -100) = 50
      check_cpu_reg(24, 32'h00000032);

      // x25: Test 29 source data
      check_cpu_reg(25, 32'h7FFFFFFF);

      // x26: Test 29 source data
      check_cpu_reg(26, 32'h7FFFFFFF);

      // x27: Test 29 result - max(INT_MAX, INT_MAX) = INT_MAX
      check_cpu_reg(27, 32'h7FFFFFFF);

      // x28: Test 30 source data
      check_cpu_reg(28, 32'h80000000);

      // x29: Test 30 source data
      check_cpu_reg(29, 32'h80000000);

      // x30: Test 30 result - max(INT_MIN, INT_MIN) = INT_MIN
      check_cpu_reg(30, 32'h80000000);

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
