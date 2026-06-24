//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zba_sh2add
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SH2ADD (Zba)
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
      $display("|             CHECK REGISTER VALUES BEFORE SH2ADD TESTS            |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h00000000);   // Zero
      check_cpu_reg(2,  32'h10000000);   // Base address example
      check_cpu_reg(3,  32'h00000001);   // Index 1
      check_cpu_reg(4,  32'h00000005);   // Index 5
      check_cpu_reg(5,  32'h0000000A);   // Index 10
      check_cpu_reg(6,  32'hFFFFFFFF);   // All ones
      check_cpu_reg(7,  32'h12345678);   // Random pattern
      check_cpu_reg(8,  32'h80000000);   // Maximum negative
      check_cpu_reg(9,  32'h7FFFFFFF);   // Maximum positive
      check_cpu_reg(10, 32'h00000100);   // Index 256
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
      $display("|             CHECK REGISTER VALUES AFTER SH2ADD TESTS             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After SH2ADD tests, check final register state
      // SH2ADD operation: rd = rs2 + (rs1 << 2)

      // x1: Test 30 loads 0xFEDCBA98 (overwrites test 21 result)
      check_cpu_reg(1, 32'hFEDCBA98);

      // x2: Test 22 result - sh2add(0x20000000, 0x0000000A)
      check_cpu_reg(2, 32'h20000028);

      // x3: Test 23 result - sh2add(0xFFFFFFFC, 0x00000001)
      check_cpu_reg(3, 32'h00000000);

      // x4: Test 24 result - sh2add(0x10000000, 0x00000200)
      check_cpu_reg(4, 32'h10000800);

      // x5: Test 25 result - sh2add(0xABCDEF00, 0x00000001)
      check_cpu_reg(5, 32'hABCDEF04);

      // x6: Test 26 result - sh2add(0x00000100, 0xFFFFFFF0)
      check_cpu_reg(6, 32'h000000C0);

      // x7: Test 27 result - sh2add(0x00000004, 0x1FFFFFFF)
      check_cpu_reg(7, 32'h80000000);

      // x8: Test 28 result - sh2add(0x00000003, 0x00000003)
      check_cpu_reg(8, 32'h0000000F);

      // x9: Test 29 result - sh2add(0x00000000, 0x55555555)
      check_cpu_reg(9, 32'h55555554);

      // x10: Test 30 result - sh2add(0xFEDCBA98, 0x12345678)
      check_cpu_reg(10, 32'h47AE1478);

      // x11: Test 1 result - sh2add(0x00000000, 0x00000000)
      check_cpu_reg(11, 32'h00000000);

      // x12: Test 2 result - sh2add(0x10000000, 0x00000001)
      check_cpu_reg(12, 32'h10000004);

      // x13: Test 3 result - sh2add(0x10000000, 0x00000005)
      check_cpu_reg(13, 32'h10000014);

      // x14: Test 4 result - sh2add(0x10000000, 0x0000000A)
      check_cpu_reg(14, 32'h10000028);

      // x15: Test 5 result - sh2add(0x00000000, 0x00000100)
      check_cpu_reg(15, 32'h00000400);

      // x16: Test 6 result - sh2add(0xFFFFFFFF, 0xFFFFFFFF)
      check_cpu_reg(16, 32'hFFFFFFFB);

      // x17: Test 7 result - sh2add(0x12345678, 0x00000001)
      check_cpu_reg(17, 32'h1234567C);

      // x18: Test 8 result - sh2add(0x7FFFFFFF, 0x00000001)
      check_cpu_reg(18, 32'h80000003);

      // x19: Test 9 result - sh2add(0x80000000, 0x00000001)
      check_cpu_reg(19, 32'h80000004);

      // x20: Test 10 result - sh2add(0x00000000, 0x12345678)
      check_cpu_reg(20, 32'h48D159E0);

      // x21: Test 11 result - sh2add(0x20000000, 0x00001000)
      check_cpu_reg(21, 32'h20004000);

      // x22: Test 12 result - sh2add(0x00000100, 0x40000000)
      check_cpu_reg(22, 32'h00000100);

      // x23: Test 13 result - sh2add(0xFFFF0000, 0x00000010)
      check_cpu_reg(23, 32'hFFFF0040);

      // x24: Test 14 result - sh2add(0x00000008, 0x00000002)
      check_cpu_reg(24, 32'h00000010);

      // x25: Test 15 result - sh2add(0x55555555, 0xAAAAAAAA)
      check_cpu_reg(25, 32'hFFFFFFFD);

      // x26: Test 16 result - sh2add(0x12345678, 0x00000000)
      check_cpu_reg(26, 32'h12345678);

      // x27: Test 17 result - sh2add(0x00000004, 0x1FFFFFFF)
      check_cpu_reg(27, 32'h80000000);

      // x28: Test 18 result - sh2add(0x00000000, 0x20000000)
      check_cpu_reg(28, 32'h80000000);

      // x29: Test 19 result - sh2add(0x80000000, 0xC0000000)
      check_cpu_reg(29, 32'h80000000);

      // x30: Test 20 result - sh2add(0x05060708, 0x01020304)
      check_cpu_reg(30, 32'h090E1318);

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
