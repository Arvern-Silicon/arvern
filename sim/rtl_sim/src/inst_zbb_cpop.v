//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_cpop
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CPOP (Zbb)
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
      $display("|               CHECK REGISTER VALUES BEFORE CPOP TESTS             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h00000000);   // All zeros
      check_cpu_reg(2,  32'hFFFFFFFF);   // All ones
      check_cpu_reg(3,  32'h00000001);   // Bit 0 set
      check_cpu_reg(4,  32'h80000000);   // Bit 31 set
      check_cpu_reg(5,  32'h0000000F);   // Lower nibble
      check_cpu_reg(6,  32'hF0000000);   // Upper nibble
      check_cpu_reg(7,  32'h000000FF);   // Lower byte
      check_cpu_reg(8,  32'hFF000000);   // Upper byte
      check_cpu_reg(9,  32'h0000FFFF);   // Lower half
      check_cpu_reg(10, 32'hFFFF0000);   // Upper half
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
      $display("|               CHECK REGISTER VALUES AFTER CPOP TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After CPOP tests, check final register state
      // CPOP operation: rd = count_population(rs1)
      // Note: Many registers are reused, checking final values only

      // x1: Test 16 source data
      check_cpu_reg(1, 32'h88888888);

      // x2: Test 16 result - cpop(0x88888888) = 8
      check_cpu_reg(2, 32'h00000008);

      // x3: Test 17 source data
      check_cpu_reg(3, 32'h00000007);

      // x4: Test 17 result - cpop(0x00000007) = 3
      check_cpu_reg(4, 32'h00000003);

      // x5: Test 18 source data
      check_cpu_reg(5, 32'h00FFFFFF);

      // x6: Test 18 result - cpop(0x00FFFFFF) = 24
      check_cpu_reg(6, 32'h00000018);

      // x7: Test 19 source data
      check_cpu_reg(7, 32'hF000000F);

      // x8: Test 19 result - cpop(0xF000000F) = 8
      check_cpu_reg(8, 32'h00000008);

      // x9: Test 20 source data
      check_cpu_reg(9, 32'h0000001F);

      // x10: Test 20 result - cpop(0x0000001F) = 5
      check_cpu_reg(10, 32'h00000005);

      // x11: Test 21 source data
      check_cpu_reg(11, 32'hF8000000);

      // x12: Test 21 result - cpop(0xF8000000) = 5
      check_cpu_reg(12, 32'h00000005);

      // x13: Test 22 source data
      check_cpu_reg(13, 32'h00FFFF00);

      // x14: Test 22 result - cpop(0x00FFFF00) = 16
      check_cpu_reg(14, 32'h00000010);

      // x15: Test 23 source data
      check_cpu_reg(15, 32'h11111111);

      // x16: Test 23 result - cpop(0x11111111) = 8
      check_cpu_reg(16, 32'h00000008);

      // x17: Test 24 source data
      check_cpu_reg(17, 32'hEEEEEEEE);

      // x18: Test 24 result - cpop(0xEEEEEEEE) = 24
      check_cpu_reg(18, 32'h00000018);

      // x19: Test 25 source data
      check_cpu_reg(19, 32'h00010000);

      // x20: Test 25 result - cpop(0x00010000) = 1
      check_cpu_reg(20, 32'h00000001);

      // x21: Test 26 source data
      check_cpu_reg(21, 32'h80000001);

      // x22: Test 26 result - cpop(0x80000001) = 2
      check_cpu_reg(22, 32'h00000002);

      // x23: Test 27 source data
      check_cpu_reg(23, 32'h0000007F);

      // x24: Test 27 result - cpop(0x0000007F) = 7
      check_cpu_reg(24, 32'h00000007);

      // x25: Test 28 source data
      check_cpu_reg(25, 32'h000001FF);

      // x26: Test 28 result - cpop(0x000001FF) = 9
      check_cpu_reg(26, 32'h00000009);

      // x27: Test 29 source data
      check_cpu_reg(27, 32'h18244281);

      // x28: Test 29 result - cpop(0x18244281) = 8
      check_cpu_reg(28, 32'h00000008);

      // x29: Test 30 source data
      check_cpu_reg(29, 32'hFFFFFFFE);

      // x30: Test 30 result - cpop(0xFFFFFFFE) = 31
      check_cpu_reg(30, 32'h0000001F);

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
