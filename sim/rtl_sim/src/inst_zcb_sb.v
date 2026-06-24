//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_sb
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SB
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.SB TESTS           |");
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
      check_cpu_reg(8,  32'hDEADBE08);   // Test data: lower byte = 0x08
      check_cpu_reg(9,  32'hCAFEBA09);   // Test data: lower byte = 0x09
      check_cpu_reg(10, 32'h1234560A);   // Test data: lower byte = 0x0A
      check_cpu_reg(11, 32'h9876540B);   // Test data: lower byte = 0x0B
      check_cpu_reg(12, 32'hABCDEF0C);   // Test data: lower byte = 0x0C
      check_cpu_reg(13, 32'h5555550D);   // Test data: lower byte = 0x0D
      check_cpu_reg(14, 32'hCCCCCC0E);   // Test data: lower byte = 0x0E
      check_cpu_reg(15, 32'h33333F0F);   // Test data: lower byte = 0x0F
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
      $display("|                 CHECK REGISTER VALUES AFTER C.SB TESTS            |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.SB tests, check that bytes were stored correctly
      // The test stores individual bytes to SRAM, then reads back as words
      // Each word should have the expected byte pattern

      // Stored word values read back from SRAM
      check_cpu_reg(1,  32'h0C0B0A09);   // SRAM+0:  bytes [0x09, 0x0A, 0x0B, 0x0C]
      check_cpu_reg(2,  32'h080F0E0D);   // SRAM+4:  bytes [0x0D, 0x0E, 0x0F, 0x08]
      check_cpu_reg(3,  32'h0C0D0E0F);   // SRAM+8:  bytes [0x0F, 0x0E, 0x0D, 0x0C]
      check_cpu_reg(4,  32'h08090A0B);   // SRAM+12: bytes [0x0B, 0x0A, 0x09, 0x08]
      check_cpu_reg(5,  32'h0B0A0908);   // SRAM+16: bytes [0x08, 0x09, 0x0A, 0x0B]
      check_cpu_reg(6,  32'h0F0E0D0C);   // SRAM+20: bytes [0x0C, 0x0D, 0x0E, 0x0F]
      check_cpu_reg(7,  32'h0F0F0F0F);   // SRAM+24: bytes [0x0F, 0x0F, 0x0F, 0x0F]

      // Compressed registers (x8-x15) - test data restored after each test set
      check_cpu_reg(8,  32'hDEADBE08);   // Restored test data
      check_cpu_reg(9,  32'hCAFEBA09);   // Restored test data
      check_cpu_reg(10, 32'h1234560A);   // Restored test data
      check_cpu_reg(11, 32'h9876540B);   // Restored test data
      check_cpu_reg(12, 32'hABCDEF0C);   // Restored test data
      check_cpu_reg(13, 32'h5555550D);   // Restored test data
      check_cpu_reg(14, 32'hCCCCCC0E);   // Restored test data
      check_cpu_reg(15, 32'h33333F0F);   // Restored test data

      check_cpu_reg(16, 32'h08080808);   // SRAM+28: bytes [0x08, 0x08, 0x08, 0x08]

      // x17 used as temporary base pointer holder (last value: SRAM+28)
      check_cpu_reg(17, 32'h8000002C);   // x17: last temporary base (SRAM+28)
      // x18 no longer used (backups removed)
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
