//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_clz
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CLZ (Zbb)
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
      $display("|               CHECK REGISTER VALUES BEFORE CLZ TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h80000000);   // Bit 31 set
      check_cpu_reg(2,  32'h40000000);   // Bit 30 set
      check_cpu_reg(3,  32'h00000001);   // Bit 0 set
      check_cpu_reg(4,  32'h00000000);   // All zeros
      check_cpu_reg(5,  32'hFFFFFFFF);   // All ones
      check_cpu_reg(6,  32'h00010000);   // Bit 16 set
      check_cpu_reg(7,  32'h00000100);   // Bit 8 set
      check_cpu_reg(8,  32'h20000000);   // Bit 29 set
      check_cpu_reg(9,  32'h10000000);   // Bit 28 set
      check_cpu_reg(10, 32'h08000000);   // Bit 27 set
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
      $display("|               CHECK REGISTER VALUES AFTER CLZ TESTS               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After CLZ tests, check final register state
      // CLZ operation: rd = count_leading_zeros(rs1)
      // Note: Tests 16-17 are retested as Test 31 with different destination registers
      // to debug potential ALU issues

      // x5: Test 18 source data
      check_cpu_reg(5, 32'h00000010);

      // x6: Test 18 result - clz(0x00000010) = 27
      check_cpu_reg(6, 32'h0000001B);

      // x7: Test 19 source data
      check_cpu_reg(7, 32'h00000002);

      // x8: Test 19 result - clz(0x00000002) = 30
      check_cpu_reg(8, 32'h0000001E);

      // x9: Test 20 source data
      check_cpu_reg(9, 32'h00800000);

      // x10: Test 20 result - clz(0x00800000) = 8
      check_cpu_reg(10, 32'h00000008);

      // x11: Test 21 source data
      check_cpu_reg(11, 32'h00008000);

      // x12: Test 21 result - clz(0x00008000) = 16
      check_cpu_reg(12, 32'h00000010);

      // x13: Test 22 source data
      check_cpu_reg(13, 32'h00000080);

      // x14: Test 22 result - clz(0x00000080) = 24
      check_cpu_reg(14, 32'h00000018);

      // x15: Test 23 source data
      check_cpu_reg(15, 32'h00000008);

      // x16: Test 23 result - clz(0x00000008) = 28
      check_cpu_reg(16, 32'h0000001C);

      // x17: Test 24 source data
      check_cpu_reg(17, 32'h00000004);

      // x18: Test 24 result - clz(0x00000004) = 29
      check_cpu_reg(18, 32'h0000001D);

      // x19: Test 25 source data
      check_cpu_reg(19, 32'h00400000);

      // x20: Test 25 result - clz(0x00400000) = 9
      check_cpu_reg(20, 32'h00000009);

      // x21: Test 26 source data
      check_cpu_reg(21, 32'h00200000);

      // x22: Test 26 result - clz(0x00200000) = 10
      check_cpu_reg(22, 32'h0000000A);

      // x23: Test 27 source data
      check_cpu_reg(23, 32'h00080000);

      // x24: Test 27 result - clz(0x00080000) = 12
      check_cpu_reg(24, 32'h0000000C);

      // x25: Test 28 source data
      check_cpu_reg(25, 32'h00040000);

      // x26: Test 28 result - clz(0x00040000) = 13
      check_cpu_reg(26, 32'h0000000D);

      // x27: Test 29 source data
      check_cpu_reg(27, 32'h00020000);

      // x28: Test 29 result - clz(0x00020000) = 14
      check_cpu_reg(28, 32'h0000000E);

      // x29: Test 30 source data
      check_cpu_reg(29, 32'h55555555);

      // x1: Test 30 result - clz(0x55555555) = 1 (changed destination to x1)
      check_cpu_reg(1, 32'h00000001);

      // Test 31: Retest failing cases with different destinations
      // x2: Test 31a source (0xAAAAAAAA)
      check_cpu_reg(2, 32'hAAAAAAAA);

      // x30: Test 31a result - clz(0xAAAAAAAA) = 0
      check_cpu_reg(30, 32'h00000000);

      // x4: Test 31b source (0x0FFFFFFF)
      check_cpu_reg(4, 32'h0FFFFFFF);

      // x3: Test 31b result - clz(0x0FFFFFFF) = 4
      check_cpu_reg(3, 32'h00000004);

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
