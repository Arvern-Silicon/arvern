//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_ror
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ROR (Zbb)
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
      $display("|             CHECK REGISTER VALUES BEFORE ROR TESTS                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h00000000);   // All zeros
      check_cpu_reg(2,  32'hFFFFFFFF);   // All ones
      check_cpu_reg(3,  32'h80000000);   // Single bit at position 31
      check_cpu_reg(4,  32'h00000001);   // Single bit at position 0
      check_cpu_reg(5,  32'hAAAAAAAA);   // Alternating bits (10101010...)
      check_cpu_reg(6,  32'h55555555);   // Alternating bits (01010101...)
      check_cpu_reg(7,  32'h12345678);   // Mixed pattern
      check_cpu_reg(8,  32'hDEADBEEF);   // Mixed pattern
      check_cpu_reg(9,  32'hF0F0F0F0);   // Nibble pattern
      check_cpu_reg(10, 32'h0F0F0F0F);   // Nibble pattern
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
      $display("|             CHECK REGISTER VALUES AFTER ROR TESTS                 |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After ROR tests, check final register state
      // ROR operation: rd = (rs1 >> rs2[4:0]) | (rs1 << (32 - rs2[4:0]))

      // x1: Test 21 result - ror(0x80000000, 16)
      check_cpu_reg(1, 32'h00008000);

      // x2: Test 22 result - ror(0x00000001, 16)
      check_cpu_reg(2, 32'h00010000);

      // x3: Test 23 result - ror(0x12345678, 12)
      check_cpu_reg(3, 32'h67812345);

      // x4: Test 24 result - ror(0xFFFF0000, 8)
      check_cpu_reg(4, 32'h00FFFF00);

      // x5: Test 25 result - ror(0x0000FFFF, 8)
      check_cpu_reg(5, 32'hFF0000FF);

      // x6: Test 26 result - ror(0x0000000F, 4)
      check_cpu_reg(6, 32'hF0000000);

      // x7: Test 27 result - ror(0xF0000000, 28)
      check_cpu_reg(7, 32'h0000000F);

      // x8: Test 28 result - ror(0x80000007, 1)
      check_cpu_reg(8, 32'hC0000003);

      // x9: Test 29 result - ror(0xC0000000, 30)
      check_cpu_reg(9, 32'h00000003);

      // x10: Test 30 result - ror(0x12345678, 24)
      check_cpu_reg(10, 32'h34567812);

      // x11: Test 1 result - ror(0x00000000, 1)
      check_cpu_reg(11, 32'h00000000);

      // x12: Test 2 result - ror(0xFFFFFFFF, 1)
      check_cpu_reg(12, 32'hFFFFFFFF);

      // x13: Test 3 result - ror(0x00000001, 1)
      check_cpu_reg(13, 32'h80000000);

      // x14: Test 4 result - ror(0x80000000, 1)
      check_cpu_reg(14, 32'h40000000);

      // x15: Test 5 result - ror(0xAAAAAAAA, 1)
      check_cpu_reg(15, 32'h55555555);

      // x16: Test 6 result - ror(0x55555555, 1)
      check_cpu_reg(16, 32'hAAAAAAAA);

      // x17: Test 7 result - ror(0x12345678, 0)
      check_cpu_reg(17, 32'h12345678);

      // x18: Test 8 result - ror(0x12345678, 4)
      check_cpu_reg(18, 32'h81234567);

      // x19: Test 9 result - ror(0x12345678, 8)
      check_cpu_reg(19, 32'h78123456);

      // x20: Test 10 result - ror(0x12345678, 16)
      check_cpu_reg(20, 32'h56781234);

      // x21: Test 11 result - ror(0x00000001, 4)
      check_cpu_reg(21, 32'h10000000);

      // x22: Test 12 result - ror(0x80000000, 31)
      check_cpu_reg(22, 32'h00000001);

      // x23: Test 13 result - ror(0xDEADBEEF, 4)
      check_cpu_reg(23, 32'hFDEADBEE);

      // x24: Test 14 result - ror(0xDEADBEEF, 8)
      check_cpu_reg(24, 32'hEFDEADBE);

      // x25: Test 15 result - ror(0xDEADBEEF, 16)
      check_cpu_reg(25, 32'hBEEFDEAD);

      // x26: Test 16 result - ror(0xF0F0F0F0, 4)
      check_cpu_reg(26, 32'h0F0F0F0F);

      // x27: Test 17 result - ror(0x0F0F0F0F, 4)
      check_cpu_reg(27, 32'hF0F0F0F0);

      // x28: Test 18 result - ror(0x12345678, 32) = ror(0x12345678, 0)
      check_cpu_reg(28, 32'h12345678);

      // x29: Test 19 result - ror(0x12345678, 33) = ror(0x12345678, 1)
      check_cpu_reg(29, 32'h091A2B3C);

      // x30: Test 20 result - ror(0xAAAAAAAA, 16)
      check_cpu_reg(30, 32'hAAAAAAAA);

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
