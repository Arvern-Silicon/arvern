//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_zext_h
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.ZEXT.H
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
      $display("|              CHECK REGISTER VALUES BEFORE C.ZEXT.H TESTS          |");
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
      check_cpu_reg(8,  32'hFFFF0000);   // Test data: lower halfword = 0x0000, upper bits all 1s
      check_cpu_reg(9,  32'h12340001);   // Test data: lower halfword = 0x0001
      check_cpu_reg(10, 32'hABCD7FFF);   // Test data: lower halfword = 0x7FFF
      check_cpu_reg(11, 32'h87658000);   // Test data: lower halfword = 0x8000
      check_cpu_reg(12, 32'hDEADFFFF);   // Test data: lower halfword = 0xFFFF
      check_cpu_reg(13, 32'hCAFE5555);   // Test data: lower halfword = 0x5555
      check_cpu_reg(14, 32'h9999AAAA);   // Test data: lower halfword = 0xAAAA
      check_cpu_reg(15, 32'h33335A5A);   // Test data: lower halfword = 0x5A5A
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
      $display("|              CHECK REGISTER VALUES AFTER C.ZEXT.H TESTS           |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.ZEXT.H tests, check that halfwords were zero-extended correctly
      // All compressed registers should have upper 16 bits cleared

      // Edge case results
      check_cpu_reg(1,  32'h0000FFFF);   // c.zext.h on 0xFFFFFFFF → 0x0000FFFF
      check_cpu_reg(2,  32'h00000000);   // c.zext.h on 0x00000000 → 0x00000000
      check_cpu_reg(3,  32'h00001234);   // c.zext.h on 0xABCD1234 → 0x00001234 (first application)
      check_cpu_reg(4,  32'h00001234);   // c.zext.h on 0x00001234 → 0x00001234 (idempotent)
      check_cpu_reg(5,  32'h0000A5A5);   // c.zext.h on 0x5555A5A5 → 0x0000A5A5
      check_cpu_reg(6,  32'h00000100);   // c.zext.h on 0x03020100 → 0x00000100
      check_cpu_reg(7,  32'h00009876);   // c.zext.h on 0x12349876 → 0x00009876 (NOT negative!)

      // Compressed registers (x8-x15) - after main test and edge cases
      check_cpu_reg(8,  32'h0000FFFF);   // After edge case test: c.zext.h on 0xFFFFFFFF
      check_cpu_reg(9,  32'h00000000);   // After edge case test: c.zext.h on 0x00000000
      check_cpu_reg(10, 32'h00001234);   // After edge case test: c.zext.h twice on 0xABCD1234
      check_cpu_reg(11, 32'h0000A5A5);   // After edge case test: c.zext.h on 0x5555A5A5
      check_cpu_reg(12, 32'h00000100);   // After edge case test: c.zext.h on 0x03020100
      check_cpu_reg(13, 32'h00009876);   // After edge case test: c.zext.h on 0x12349876
      check_cpu_reg(14, 32'h00008001);   // After edge case test: c.zext.h on 0xDEAD8001 (NOT negative!)
      check_cpu_reg(15, 32'h00007FFE);   // After edge case test: c.zext.h on 0xCAFE7FFE

      check_cpu_reg(16, 32'h00000000);   // Unchanged

      // Backup of original values before c.zext.h (from main test)
      check_cpu_reg(17, 32'hFFFF0000);   // Original x8  before c.zext.h
      check_cpu_reg(18, 32'h12340001);   // Original x9  before c.zext.h
      check_cpu_reg(19, 32'hABCD7FFF);   // Original x10 before c.zext.h
      check_cpu_reg(20, 32'h87658000);   // Original x11 before c.zext.h
      check_cpu_reg(21, 32'hDEADFFFF);   // Original x12 before c.zext.h
      check_cpu_reg(22, 32'hCAFE5555);   // Original x13 before c.zext.h
      check_cpu_reg(23, 32'h9999AAAA);   // Original x14 before c.zext.h
      check_cpu_reg(24, 32'h33335A5A);   // Original x15 before c.zext.h

      check_cpu_reg(25, 32'h00008001);   // Edge case: c.zext.h on 0xDEAD8001 (backup of x14)
      check_cpu_reg(26, 32'h00007FFE);   // Edge case: c.zext.h on 0xCAFE7FFE (backup of x15)
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
