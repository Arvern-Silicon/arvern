//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_ctz
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CTZ (Zbb)
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
      $display("|               CHECK REGISTER VALUES BEFORE CTZ TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h00000001);   // Bit 0 set
      check_cpu_reg(2,  32'h00000002);   // Bit 1 set
      check_cpu_reg(3,  32'h80000000);   // Bit 31 set
      check_cpu_reg(4,  32'h00000000);   // All zeros
      check_cpu_reg(5,  32'hFFFFFFFF);   // All ones
      check_cpu_reg(6,  32'h00010000);   // Bit 16 set
      check_cpu_reg(7,  32'h00000100);   // Bit 8 set
      check_cpu_reg(8,  32'h00000004);   // Bit 2 set
      check_cpu_reg(9,  32'h00000008);   // Bit 3 set
      check_cpu_reg(10, 32'h00000010);   // Bit 4 set
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
      $display("|               CHECK REGISTER VALUES AFTER CTZ TESTS               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After CTZ tests, check final register state
      // CTZ operation: rd = count_trailing_zeros(rs1)
      // Note: Many registers are reused, checking final values only

      // x1: Test 16 source data
      check_cpu_reg(1, 32'hAAAAAAAA);

      // x2: Test 16 result - ctz(0xAAAAAAAA) = 1
      check_cpu_reg(2, 32'h00000001);

      // x3: Test 17 source data
      check_cpu_reg(3, 32'hFFFFFFF0);

      // x4: Test 17 result - ctz(0xFFFFFFF0) = 4
      check_cpu_reg(4, 32'h00000004);

      // x5: Test 18 source data
      check_cpu_reg(5, 32'h08000000);

      // x6: Test 18 result - ctz(0x08000000) = 27
      check_cpu_reg(6, 32'h0000001B);

      // x7: Test 19 source data
      check_cpu_reg(7, 32'h40000000);

      // x8: Test 19 result - ctz(0x40000000) = 30
      check_cpu_reg(8, 32'h0000001E);

      // x9: Test 20 source data
      check_cpu_reg(9, 32'h00000100);

      // x10: Test 20 result - ctz(0x00000100) = 8
      check_cpu_reg(10, 32'h00000008);

      // x11: Test 21 source data
      check_cpu_reg(11, 32'h00008000);

      // x12: Test 21 result - ctz(0x00008000) = 15
      check_cpu_reg(12, 32'h0000000F);

      // x13: Test 22 source data
      check_cpu_reg(13, 32'h01000000);

      // x14: Test 22 result - ctz(0x01000000) = 24
      check_cpu_reg(14, 32'h00000018);

      // x15: Test 23 source data
      check_cpu_reg(15, 32'h10000000);

      // x16: Test 23 result - ctz(0x10000000) = 28
      check_cpu_reg(16, 32'h0000001C);

      // x17: Test 24 source data
      check_cpu_reg(17, 32'h20000000);

      // x18: Test 24 result - ctz(0x20000000) = 29
      check_cpu_reg(18, 32'h0000001D);

      // x19: Test 25 source data
      check_cpu_reg(19, 32'h00000200);

      // x20: Test 25 result - ctz(0x00000200) = 9
      check_cpu_reg(20, 32'h00000009);

      // x21: Test 26 source data
      check_cpu_reg(21, 32'h00000400);

      // x22: Test 26 result - ctz(0x00000400) = 10
      check_cpu_reg(22, 32'h0000000A);

      // x23: Test 27 source data
      check_cpu_reg(23, 32'h00001000);

      // x24: Test 27 result - ctz(0x00001000) = 12
      check_cpu_reg(24, 32'h0000000C);

      // x25: Test 28 source data
      check_cpu_reg(25, 32'h00002000);

      // x26: Test 28 result - ctz(0x00002000) = 13
      check_cpu_reg(26, 32'h0000000D);

      // x27: Test 29 source data
      check_cpu_reg(27, 32'h00004000);

      // x28: Test 29 result - ctz(0x00004000) = 14
      check_cpu_reg(28, 32'h0000000E);

      // x29: Test 30 source data
      check_cpu_reg(29, 32'h55555555);

      // x30: Test 30 result - ctz(0x55555555) = 0
      check_cpu_reg(30, 32'h00000000);

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
