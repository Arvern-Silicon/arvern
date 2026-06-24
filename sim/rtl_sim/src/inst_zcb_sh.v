//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_sh
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SH
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.SH TESTS           |");
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
      check_cpu_reg(8,  32'hDEAD0108);   // Test data: lower halfword = 0x0108
      check_cpu_reg(9,  32'hCAFE0209);   // Test data: lower halfword = 0x0209
      check_cpu_reg(10, 32'h1234030A);   // Test data: lower halfword = 0x030A
      check_cpu_reg(11, 32'h9876040B);   // Test data: lower halfword = 0x040B
      check_cpu_reg(12, 32'hABCD050C);   // Test data: lower halfword = 0x050C
      check_cpu_reg(13, 32'h5555060D);   // Test data: lower halfword = 0x060D
      check_cpu_reg(14, 32'hCCCC070E);   // Test data: lower halfword = 0x070E
      check_cpu_reg(15, 32'h3333080F);   // Test data: lower halfword = 0x080F
      check_cpu_reg(16, 32'hAAAAAAAA);   // Initial SRAM pattern
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
      check_cpu_reg(29, 32'h80000010);   // SRAM base pointer
      check_cpu_reg(30, 32'h00000000);
      check_cpu_reg(31, 32'hDEADBEEF);   // Marker for initial setup complete


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES AFTER C.SH TESTS            |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.SH tests, check that halfwords were stored correctly
      // The test stores halfwords to SRAM, then reads back as words
      // Each word should have the expected halfword pattern

      // Stored word values read back from SRAM
      check_cpu_reg(1,  32'h030A0209);   // SRAM+0:  halfwords [0x0209 at +0, 0x030A at +2]
      check_cpu_reg(2,  32'h050C040B);   // SRAM+4:  halfwords [0x040B at +4, 0x050C at +6]
      check_cpu_reg(3,  32'h070E060D);   // SRAM+8:  halfwords [0x060D at +8, 0x070E at +10]
      check_cpu_reg(4,  32'h040B080F);   // SRAM+12: halfwords [0x080F at +12, 0x040B at +14]
      check_cpu_reg(5,  32'h060D0108);   // SRAM+16: halfwords [0x0108 at +16, 0x060D at +18]
      check_cpu_reg(6,  32'h0209050C);   // SRAM+20: halfwords [0x050C at +20, 0x0209 at +22]
      check_cpu_reg(7,  32'h030A030A);   // SRAM+24: halfwords [0x030A at +24, 0x030A at +26]

      // Compressed registers (x8-x15) - test data restored after each test set
      check_cpu_reg(8,  32'hDEAD0108);   // Restored test data
      check_cpu_reg(9,  32'hCAFE0209);   // Restored test data
      check_cpu_reg(10, 32'h1234030A);   // Restored test data
      check_cpu_reg(11, 32'h9876040B);   // Restored test data
      check_cpu_reg(12, 32'hABCD050C);   // Restored test data
      check_cpu_reg(13, 32'h5555060D);   // Restored test data
      check_cpu_reg(14, 32'hCCCC070E);   // Restored test data
      check_cpu_reg(15, 32'h3333080F);   // Restored test data

      check_cpu_reg(16, 32'h040B040B);   // SRAM+28: halfwords [0x040B at +28, 0x040B at +30]

      // x17 used as temporary base pointer holder (last value: SRAM+28)
      check_cpu_reg(17, 32'h8000002C);   // x17: last temporary base (SRAM+28)
      // x18 no longer used (self-referential store removed)
      check_cpu_reg(18, 32'h00000000);   // x18: unused
      check_cpu_reg(19, 32'h00000000);   // Unchanged
      check_cpu_reg(20, 32'h00000000);   // Unchanged
      check_cpu_reg(21, 32'h00000000);   // Unchanged
      check_cpu_reg(22, 32'h00000000);   // Unchanged
      check_cpu_reg(23, 32'h00000000);   // Unchanged
      check_cpu_reg(24, 32'h00000000);   // Unchanged
      check_cpu_reg(25, 32'h00000000);   // Unchanged
      check_cpu_reg(26, 32'h00000000);   // Unchanged
      check_cpu_reg(27, 32'h00000000);   // Unchanged
      check_cpu_reg(28, 32'h00000000);   // Unchanged
      check_cpu_reg(29, 32'h80000010);   // SRAM base pointer (unchanged)
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
