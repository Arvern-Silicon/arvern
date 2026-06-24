//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_sext_b
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SEXT.B
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
      $display("|              CHECK REGISTER VALUES BEFORE C.SEXT.B TESTS          |");
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
      check_cpu_reg(11, 32'h87654380);   // Test data: lower byte = 0x80 (negative!)
      check_cpu_reg(12, 32'hDEADBEFF);   // Test data: lower byte = 0xFF (negative!)
      check_cpu_reg(13, 32'hCAFEBA55);   // Test data: lower byte = 0x55
      check_cpu_reg(14, 32'h9999AAAA);   // Test data: lower byte = 0xAA (negative!)
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
      $display("|              CHECK REGISTER VALUES AFTER C.SEXT.B TESTS           |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.SEXT.B tests, check that bytes were sign-extended correctly
      // Positive bytes (bit 7=0): upper 24 bits = 0x000000
      // Negative bytes (bit 7=1): upper 24 bits = 0xFFFFFF

      // Edge case results
      check_cpu_reg(1,  32'hFFFFFFFF);   // c.sext.b on 0xFFFFFFFF → 0xFFFFFFFF (0xFF sign-extended to -1)
      check_cpu_reg(2,  32'h00000000);   // c.sext.b on 0x00000000 → 0x00000000
      check_cpu_reg(3,  32'h00000042);   // c.sext.b on 0xABCDEF42 → 0x00000042 (first application, positive)
      check_cpu_reg(4,  32'h00000042);   // c.sext.b on 0x00000042 → 0x00000042 (idempotent, positive)
      check_cpu_reg(5,  32'hFFFFFFA5);   // c.sext.b on 0x5555A5A5 → 0xFFFFFFA5 (first application, negative!)
      check_cpu_reg(6,  32'h0000007E);   // c.sext.b on 0x0302017E → 0x0000007E (positive)
      check_cpu_reg(7,  32'hFFFFFF81);   // c.sext.b on 0x12345681 → 0xFFFFFF81 (negative!)

      // Compressed registers (x8-x15) - after main test and edge cases
      check_cpu_reg(8,  32'hFFFFFFFF);   // After edge case test: c.sext.b on 0xFFFFFFFF
      check_cpu_reg(9,  32'h00000000);   // After edge case test: c.sext.b on 0x00000000
      check_cpu_reg(10, 32'h00000042);   // After edge case test: c.sext.b twice on 0xABCDEF42
      check_cpu_reg(11, 32'hFFFFFFA5);   // After edge case test: c.sext.b on 0x5555A5A5 (negative!)
      check_cpu_reg(12, 32'h0000007E);   // After edge case test: c.sext.b on 0x0302017E
      check_cpu_reg(13, 32'hFFFFFF81);   // After edge case test: c.sext.b on 0x12345681 (negative!)
      check_cpu_reg(14, 32'hFFFFFFFE);   // After edge case test: c.sext.b on 0xDEAD00FE (negative -2!)
      check_cpu_reg(15, 32'h00000001);   // After edge case test: c.sext.b on 0xCAFE0001

      check_cpu_reg(16, 32'h00000000);   // Unchanged

      // Backup of original values before c.sext.b (from main test)
      check_cpu_reg(17, 32'hFFFFFF00);   // Original x8  before c.sext.b
      check_cpu_reg(18, 32'h12345601);   // Original x9  before c.sext.b
      check_cpu_reg(19, 32'hABCDEF7F);   // Original x10 before c.sext.b
      check_cpu_reg(20, 32'h87654380);   // Original x11 before c.sext.b
      check_cpu_reg(21, 32'hDEADBEFF);   // Original x12 before c.sext.b
      check_cpu_reg(22, 32'hCAFEBA55);   // Original x13 before c.sext.b
      check_cpu_reg(23, 32'h9999AAAA);   // Original x14 before c.sext.b
      check_cpu_reg(24, 32'h33335A5A);   // Original x15 before c.sext.b

      check_cpu_reg(25, 32'hFFFFFFA5);   // Backup of second idempotent test (0xA5 sign-extended, negative)
      check_cpu_reg(26, 32'hFFFFFFFE);   // c.sext.b on 0xDEAD00FE → 0xFFFFFFFE (negative -2)
      check_cpu_reg(27, 32'h00000001);   // c.sext.b on 0xCAFE0001 → 0x00000001 (positive)
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
