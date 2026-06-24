//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbs_bseti
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: BSETI (Zbs)
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
      $display("|             CHECK REGISTER VALUES BEFORE BSETI TESTS             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'hFFFFFFFF);   // All ones
      check_cpu_reg(2,  32'h00000000);   // All zeros
      check_cpu_reg(3,  32'h12345678);   // Random pattern
      check_cpu_reg(4,  32'hAAAAAAAA);   // Alternating bits (10101010...)
      check_cpu_reg(5,  32'h55555555);   // Alternating bits (01010101...)
      check_cpu_reg(6,  32'h80000000);   // Only MSB set
      check_cpu_reg(7,  32'h00000001);   // Only LSB set
      check_cpu_reg(8,  32'hF0F0F0F0);   // Pattern
      check_cpu_reg(9,  32'h0F0F0F0F);   // Pattern (inverted)
      check_cpu_reg(10, 32'hDEADBEEF);   // Mixed pattern
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
      $display("|             CHECK REGISTER VALUES AFTER BSETI TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After BSETI tests, check final register state
      // BSETI operation: rd = rs1 | (1 << imm[4:0])

      // x1: Test 21 result - bseti(0x00000000, 1)
      check_cpu_reg(1, 32'h00000002);

      // x2: Test 22 result - sequential bseti operations on bits 2,3,4
      check_cpu_reg(2, 32'h0000001C);

      // x3: Test 23 result - bseti(0x3FFFFFFF, 30)
      check_cpu_reg(3, 32'h7FFFFFFF);

      // x4: Test 24 result - bseti(0x12345678, 16)
      check_cpu_reg(4, 32'h12355678);

      // x5: Test 25 result - bseti(0xA0AAAAAA, 25)
      check_cpu_reg(5, 32'hA2AAAAAA);

      // x6: Test 26 result - bseti(0x55555554, 0)
      check_cpu_reg(6, 32'h55555555);

      // x7: Test 27 result - bseti(0xD0F0F0F0, 29)
      check_cpu_reg(7, 32'hF0F0F0F0);

      // x8: Test 28 result - bseti(0x0F0F0F0F, 11)
      check_cpu_reg(8, 32'h0F0F0F0F);

      // x9: Test 29 result - bseti(0xABCDEF01, 17)
      check_cpu_reg(9, 32'hABCFEF01);

      // x10: Test 30 result - bseti(0x87654321, 22) - bit 22 already 1
      check_cpu_reg(10, 32'h87654321);

      // x11: Test 1 result - bseti(0xFFFFFFFF, 0)
      check_cpu_reg(11, 32'hFFFFFFFF);

      // x12: Test 2 result - bseti(0xFFFFFFFF, 31)
      check_cpu_reg(12, 32'hFFFFFFFF);

      // x13: Test 3 result - bseti(0xFFFFFFFF, 15)
      check_cpu_reg(13, 32'hFFFFFFFF);

      // x14: Test 4 result - bseti(0x00000000, 0)
      check_cpu_reg(14, 32'h00000001);

      // x15: Test 5 result - bseti(0x12345678, 8)
      check_cpu_reg(15, 32'h12345778);

      // x16: Test 6 result - bseti(0x12345678, 10)
      check_cpu_reg(16, 32'h12345678);

      // x17: Test 7 result - bseti(0xAAAAAAAA, 4)
      check_cpu_reg(17, 32'hAAAAAABA);

      // x18: Test 8 result - bseti(0xAAAAAAAA, 7)
      check_cpu_reg(18, 32'hAAAAAAAA);

      // x19: Test 9 result - bseti(0x55555555, 12)
      check_cpu_reg(19, 32'h55555555);

      // x20: Test 10 result - bseti(0x55555555, 16)
      check_cpu_reg(20, 32'h55555555);

      // x21: Test 11 result - bseti(0x00000000, 31)
      check_cpu_reg(21, 32'h80000000);

      // x22: Test 12 result - bseti(0x00000000, 0)
      check_cpu_reg(22, 32'h00000001);

      // x23: Test 13 result - bseti(0xF0F0F0F0, 7)
      check_cpu_reg(23, 32'hF0F0F0F0);

      // x24: Test 14 result - bseti(0xF0F0F0F0, 3)
      check_cpu_reg(24, 32'hF0F0F0F8);

      // x25: Test 15 result - bseti(0x0F0F0F0F, 20)
      check_cpu_reg(25, 32'h0F1F0F0F);

      // x26: Test 16 result - bseti(0x0F0F0F0F, 24)
      check_cpu_reg(26, 32'h0F0F0F0F);

      // x27: Test 17 result - bseti(0xDEADBEEF, 1)
      check_cpu_reg(27, 32'hDEADBEEF);

      // x28: Test 18 result - bseti(0xDEADBEEF, 5)
      check_cpu_reg(28, 32'hDEADBEEF);

      // x29: Test 19 result - bseti(0xDEADBEEF, 20)
      check_cpu_reg(29, 32'hDEBDBEEF);

      // x30: Test 20 result - bseti(0xDEADBEEF, 27)
      check_cpu_reg(30, 32'hDEADBEEF);

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
