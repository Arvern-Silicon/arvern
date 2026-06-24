//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_sext_h
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SEXT.H
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
      $display("|              CHECK REGISTER VALUES BEFORE C.SEXT.H TESTS          |");
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
      check_cpu_reg(11, 32'h87658000);   // Test data: lower halfword = 0x8000 (negative!)
      check_cpu_reg(12, 32'hDEADFFFF);   // Test data: lower halfword = 0xFFFF (negative!)
      check_cpu_reg(13, 32'hCAFE5555);   // Test data: lower halfword = 0x5555
      check_cpu_reg(14, 32'h9999AAAA);   // Test data: lower halfword = 0xAAAA (negative!)
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
      $display("|              CHECK REGISTER VALUES AFTER C.SEXT.H TESTS           |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.SEXT.H tests, check that halfwords were sign-extended correctly
      // Positive halfwords (bit 15=0): upper 16 bits = 0x0000
      // Negative halfwords (bit 15=1): upper 16 bits = 0xFFFF

      // Edge case results
      check_cpu_reg(1,  32'hFFFFFFFF);   // c.sext.h on 0xFFFFFFFF → 0xFFFFFFFF (0xFFFF sign-extended to -1)
      check_cpu_reg(2,  32'h00000000);   // c.sext.h on 0x00000000 → 0x00000000
      check_cpu_reg(3,  32'h00001234);   // c.sext.h on 0xABCD1234 → 0x00001234 (first application, positive)
      check_cpu_reg(4,  32'h00001234);   // c.sext.h on 0x00001234 → 0x00001234 (idempotent, positive)
      check_cpu_reg(5,  32'hFFFFA5A5);   // c.sext.h on 0x5555A5A5 → 0xFFFFA5A5 (first application, negative!)
      check_cpu_reg(6,  32'h00007FFE);   // c.sext.h on 0x03027FFE → 0x00007FFE (positive)
      check_cpu_reg(7,  32'hFFFF8001);   // c.sext.h on 0x12348001 → 0xFFFF8001 (negative!)

      // Compressed registers (x8-x15) - after main test and edge cases
      check_cpu_reg(8,  32'hFFFFFFFF);   // After edge case test: c.sext.h on 0xFFFFFFFF
      check_cpu_reg(9,  32'h00000000);   // After edge case test: c.sext.h on 0x00000000
      check_cpu_reg(10, 32'h00001234);   // After edge case test: c.sext.h twice on 0xABCD1234
      check_cpu_reg(11, 32'hFFFFA5A5);   // After edge case test: c.sext.h on 0x5555A5A5 (negative!)
      check_cpu_reg(12, 32'h00007FFE);   // After edge case test: c.sext.h on 0x03027FFE
      check_cpu_reg(13, 32'hFFFF8001);   // After edge case test: c.sext.h on 0x12348001 (negative!)
      check_cpu_reg(14, 32'hFFFF9876);   // After edge case test: c.sext.h on 0xDEAD9876 (negative!)
      check_cpu_reg(15, 32'h00000001);   // After edge case test: c.sext.h on 0xCAFE0001

      check_cpu_reg(16, 32'h00000000);   // Unchanged

      // Backup of original values before c.sext.h (from main test)
      check_cpu_reg(17, 32'hFFFF0000);   // Original x8  before c.sext.h
      check_cpu_reg(18, 32'h12340001);   // Original x9  before c.sext.h
      check_cpu_reg(19, 32'hABCD7FFF);   // Original x10 before c.sext.h
      check_cpu_reg(20, 32'h87658000);   // Original x11 before c.sext.h
      check_cpu_reg(21, 32'hDEADFFFF);   // Original x12 before c.sext.h
      check_cpu_reg(22, 32'hCAFE5555);   // Original x13 before c.sext.h
      check_cpu_reg(23, 32'h9999AAAA);   // Original x14 before c.sext.h
      check_cpu_reg(24, 32'h33335A5A);   // Original x15 before c.sext.h

      check_cpu_reg(25, 32'hFFFFA5A5);   // Backup of second idempotent test (0xA5A5 sign-extended, negative)
      check_cpu_reg(26, 32'hFFFF9876);   // c.sext.h on 0xDEAD9876 → 0xFFFF9876 (negative)
      check_cpu_reg(27, 32'h00000001);   // c.sext.h on 0xCAFE0001 → 0x00000001 (positive)
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
