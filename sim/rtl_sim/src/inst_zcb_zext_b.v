//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_zext_b
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.ZEXT.B
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
      $display("|              CHECK REGISTER VALUES BEFORE C.ZEXT.B TESTS          |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h00000000);   // Not yet set
      check_cpu_reg(2,  32'h00000000);   // Not yet set
      check_cpu_reg(3,  32'h00000000);   // Not yet set
      check_cpu_reg(4,  32'h00000000);   // Not yet set
      check_cpu_reg(5,  32'h00000000);   // Not yet set
      check_cpu_reg(6,  32'h00000000);   // Not yet set
      check_cpu_reg(7,  32'h00000000);   // Not yet set
      check_cpu_reg(8,  32'hFFFFFF00);   // Test data: lower byte = 0x00, upper bits all 1s
      check_cpu_reg(9,  32'h12345601);   // Test data: lower byte = 0x01
      check_cpu_reg(10, 32'hABCDEF7F);   // Test data: lower byte = 0x7F
      check_cpu_reg(11, 32'h87654380);   // Test data: lower byte = 0x80
      check_cpu_reg(12, 32'hDEADBEFF);   // Test data: lower byte = 0xFF
      check_cpu_reg(13, 32'hCAFEBA55);   // Test data: lower byte = 0x55
      check_cpu_reg(14, 32'h9999AAAA);   // Test data: lower byte = 0xAA
      check_cpu_reg(15, 32'h33335A5A);   // Test data: lower byte = 0x5A
      check_cpu_reg(16, 32'h00000000);
      check_cpu_reg(17, 32'h00000000);
      check_cpu_reg(18, 32'h00000000);
      check_cpu_reg(19, 32'h00000000);
      check_cpu_reg(20, 32'h00000000);
      check_cpu_reg(21, 32'h00000000);
      check_cpu_reg(22, 32'h00000000);
      check_cpu_reg(23, 32'h00000000);
      check_cpu_reg(24, 32'h00000000);
      check_cpu_reg(25, 32'h00000000);
      check_cpu_reg(26, 32'h00000000);
      check_cpu_reg(27, 32'h00000000);
      check_cpu_reg(28, 32'h00000000);
      check_cpu_reg(29, 32'h00000000);
      check_cpu_reg(30, 32'h00000000);
      check_cpu_reg(31, 32'hDEADBEEF);   // Marker for initial setup complete


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|              CHECK REGISTER VALUES AFTER C.ZEXT.B TESTS           |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.ZEXT.B tests, check that bytes were zero-extended correctly
      // All compressed registers should have upper 24 bits cleared

      // Edge case results
      check_cpu_reg(1,  32'h000000FF);   // c.zext.b on 0xFFFFFFFF → 0x000000FF
      check_cpu_reg(2,  32'h00000000);   // c.zext.b on 0x00000000 → 0x00000000
      check_cpu_reg(3,  32'h00000042);   // c.zext.b on 0xABCDEF42 → 0x00000042 (first application)
      check_cpu_reg(4,  32'h00000042);   // c.zext.b on 0x00000042 → 0x00000042 (idempotent)
      check_cpu_reg(5,  32'h000000A5);   // c.zext.b on 0x5555A5A5 → 0x000000A5
      check_cpu_reg(6,  32'h00000000);   // c.zext.b on 0x03020100 → 0x00000000
      check_cpu_reg(7,  32'h000000FF);   // c.zext.b on 0x123456FF → 0x000000FF (NOT negative!)

      // Compressed registers (x8-x15) - after main test and edge cases
      check_cpu_reg(8,  32'h000000FF);   // After edge case test: c.zext.b on 0xFFFFFFFF
      check_cpu_reg(9,  32'h00000000);   // After edge case test: c.zext.b on 0x00000000
      check_cpu_reg(10, 32'h00000042);   // After edge case test: c.zext.b twice on 0xABCDEF42
      check_cpu_reg(11, 32'h000000A5);   // After edge case test: c.zext.b on 0x5555A5A5
      check_cpu_reg(12, 32'h00000000);   // After edge case test: c.zext.b on 0x03020100
      check_cpu_reg(13, 32'h000000FF);   // After edge case test: c.zext.b on 0x123456FF
      check_cpu_reg(14, 32'h000000AA);   // After main test: c.zext.b on 0x9999AAAA (not modified by edge cases)
      check_cpu_reg(15, 32'h0000005A);   // After main test: c.zext.b on 0x33335A5A (not modified by edge cases)

      check_cpu_reg(16, 32'h00000000);   // Unchanged

      // Backup of original values before c.zext.b (from main test)
      check_cpu_reg(17, 32'hFFFFFF00);   // Original x8  before c.zext.b
      check_cpu_reg(18, 32'h12345601);   // Original x9  before c.zext.b
      check_cpu_reg(19, 32'hABCDEF7F);   // Original x10 before c.zext.b
      check_cpu_reg(20, 32'h87654380);   // Original x11 before c.zext.b
      check_cpu_reg(21, 32'hDEADBEFF);   // Original x12 before c.zext.b
      check_cpu_reg(22, 32'hCAFEBA55);   // Original x13 before c.zext.b
      check_cpu_reg(23, 32'h9999AAAA);   // Original x14 before c.zext.b
      check_cpu_reg(24, 32'h33335A5A);   // Original x15 before c.zext.b

      check_cpu_reg(25, 32'h00000000);   // Unchanged
      check_cpu_reg(26, 32'h00000000);   // Unchanged
      check_cpu_reg(27, 32'h00000000);   // Unchanged
      check_cpu_reg(28, 32'h00000000);   // Unchanged
      check_cpu_reg(29, 32'h00000000);   // Unchanged
      check_cpu_reg(30, 32'h00000000);   // Unchanged
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
