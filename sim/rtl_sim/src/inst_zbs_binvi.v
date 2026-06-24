//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbs_binvi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: BINVI (Zbs)
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
      $display("|             CHECK REGISTER VALUES BEFORE BINVI TESTS             |");
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
      $display("|             CHECK REGISTER VALUES AFTER BINVI TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // After BINVI tests, check final register state
      // BINVI operation: rd = rs1 ^ (1 << imm[4:0])

      // x1: Test 21 result - binvi(0xFFFFFFFF, 1)
      check_cpu_reg(1, 32'hFFFFFFFD);

      // x2: Test 22 result - sequential binvi operations on bits 2,3,4
      check_cpu_reg(2, 32'h0000001C);

      // x3: Test 23 result - binvi(0x7FFFFFFF, 30)
      check_cpu_reg(3, 32'h3FFFFFFF);

      // x4: Test 24 result - binvi(0x12345678, 16)
      check_cpu_reg(4, 32'h12355678);

      // x5: Test 25 result - binvi(0xAAAAAAAA, 25)
      check_cpu_reg(5, 32'hA8AAAAAA);

      // x6: Test 26 result - binvi(0x55555555, 0)
      check_cpu_reg(6, 32'h55555554);

      // x7: Test 27 result - binvi(0xF0F0F0F0, 29)
      check_cpu_reg(7, 32'hD0F0F0F0);

      // x8: Test 28 result - binvi(0x0F0F0F0F, 11)
      check_cpu_reg(8, 32'h0F0F070F);

      // x9: Test 29 result - binvi(0xABCDEF01, 17)
      check_cpu_reg(9, 32'hABCFEF01);

      // x10: Test 30 result - binvi(0x87654321, 22)
      check_cpu_reg(10, 32'h87254321);

      // x11: Test 1 result - binvi(0xFFFFFFFF, 0)
      check_cpu_reg(11, 32'hFFFFFFFE);

      // x12: Test 2 result - binvi(0xFFFFFFFF, 31)
      check_cpu_reg(12, 32'h7FFFFFFF);

      // x13: Test 3 result - binvi(0xFFFFFFFF, 15)
      check_cpu_reg(13, 32'hFFFF7FFF);

      // x14: Test 4 result - binvi(0x00000000, 0)
      check_cpu_reg(14, 32'h00000001);

      // x15: Test 5 result - binvi(0x12345678, 8)
      check_cpu_reg(15, 32'h12345778);

      // x16: Test 6 result - binvi(0x12345678, 10)
      check_cpu_reg(16, 32'h12345278);

      // x17: Test 7 result - binvi(0xAAAAAAAA, 4)
      check_cpu_reg(17, 32'hAAAAAABA);

      // x18: Test 8 result - binvi(0xAAAAAAAA, 7)
      check_cpu_reg(18, 32'hAAAAAA2A);

      // x19: Test 9 result - binvi(0x55555555, 12)
      check_cpu_reg(19, 32'h55554555);

      // x20: Test 10 result - binvi(0x55555555, 16)
      check_cpu_reg(20, 32'h55545555);

      // x21: Test 11 result - binvi(0x80000000, 31)
      check_cpu_reg(21, 32'h00000000);

      // x22: Test 12 result - binvi(0x00000001, 0)
      check_cpu_reg(22, 32'h00000000);

      // x23: Test 13 result - binvi(0xF0F0F0F0, 7)
      check_cpu_reg(23, 32'hF0F0F070);

      // x24: Test 14 result - binvi(0xF0F0F0F0, 3)
      check_cpu_reg(24, 32'hF0F0F0F8);

      // x25: Test 15 result - binvi(0x0F0F0F0F, 20)
      check_cpu_reg(25, 32'h0F1F0F0F);

      // x26: Test 16 result - binvi(0x0F0F0F0F, 24)
      check_cpu_reg(26, 32'h0E0F0F0F);

      // x27: Test 17 result - binvi(0xDEADBEEF, 1)
      check_cpu_reg(27, 32'hDEADBEED);

      // x28: Test 18 result - binvi(0xDEADBEEF, 5)
      check_cpu_reg(28, 32'hDEADBECF);

      // x29: Test 19 result - binvi(0xDEADBEEF, 20)
      check_cpu_reg(29, 32'hDEBDBEEF);

      // x30: Test 20 result - binvi(0xDEADBEEF, 27)
      check_cpu_reg(30, 32'hD6ADBEEF);

      check_cpu_reg(31, 32'h12345678);   // Test complete marker


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       CHECK REGISTER VALUES AFTER ADDITIONAL BINVI TESTS         |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hCAFEBABE);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // --- Gap 1: in-place bit-31 flip (rd = rs1, imm = 31) ---
      // Test 31: binvi(0x3F800000, 31) -> 0xBF800000
      check_cpu_reg(5,  32'hBF800000);

      // Test 32: binvi(0xC0000000, 31) -> 0x40000000
      check_cpu_reg(6,  32'h40000000);

      // Test 33: binvi(0xBF800000, 31) -> 0x3F800000  (s0/x8 register, exact minver register)
      check_cpu_reg(8,  32'h3F800000);

      // --- Gap 2: binvi as fall-through of a NOT-taken branch ---
      // Test 34: branch not-taken -> binvi executed: binvi(0xC0000000, 31) -> 0x40000000
      check_cpu_reg(3,  32'h40000000);

      // Test 35: branch taken -> binvi skipped: x4 must remain 0x3F800000
      check_cpu_reg(4,  32'h3F800000);

      // --- Gap 3: binvi immediately followed by jal ---
      // Test 36: in-place binvi then jal: binvi(0xC0000000, 31) -> 0x40000000
      check_cpu_reg(9,  32'h40000000);

      // Test 37: binvi rd!=rs1 then jal: x2 (rs1) unchanged, x10 (rd) = flipped
      check_cpu_reg(2,  32'hBF800000);   // rs1 must be unchanged
      check_cpu_reg(10, 32'h3F800000);   // rd must hold binvi result

      check_cpu_reg(31, 32'hCAFEBABE);   // Sync marker

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end
