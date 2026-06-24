//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_sub
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SUB
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.SUB                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'hC0FFEE00);
      check_cpu_reg(2,  32'h00000000);
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'h00000100);   // 256
      check_cpu_reg(9,  32'h00000050);   // 80
      check_cpu_reg(10, 32'h7FFFFFFF);   // Max positive
      check_cpu_reg(11, 32'h00000001);   // 1
      check_cpu_reg(12, 32'h80000000);   // Min negative
      check_cpu_reg(13, 32'hFFFFFFFF);   // -1
      check_cpu_reg(14, 32'h12345678);   // Test pattern
      check_cpu_reg(15, 32'hABCDEF01);   // Test pattern
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
      check_cpu_reg(31, 32'hAAAAAAAA);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|         CHECK FINAL STATE AFTER ALL C.SUB TESTS                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check marker register
      check_cpu_reg(1,  32'hC0FFEE00);   // Unchanged marker

      // Test Set 1 results (basic subtraction) - backed up in x16-x18
      check_cpu_reg(16, 32'h000000B0);   // Backup of x8:  256 - 80 = 176
      check_cpu_reg(17, 32'h7FFFFFFE);   // Backup of x10: 0x7FFFFFFF - 1
      check_cpu_reg(18, 32'h12345628);   // Backup of x14: 0x12345678 - 0x50

      // Test Set 2 results (negative results) - backed up in x19-x20
      check_cpu_reg(19, 32'hFFFFFF50);   // Backup of x8:  80 - 256 = -176
      check_cpu_reg(20, 32'hFFFFFFFF);   // Backup of x10: 0 - 1 = -1

      // Test Set 3 results (underflow/overflow) - backed up in x21-x22
      check_cpu_reg(21, 32'h7FFFFFFF);   // Backup of x8:  0x80000000 - 1 (underflow)
      check_cpu_reg(22, 32'h80000000);   // Backup of x10: 0x7FFFFFFF - (-1) (overflow)

      // Test Set 4 results (negative - negative) - backed up in x23-x24
      check_cpu_reg(23, 32'h00000000);   // Backup of x12: -1 - (-1) = 0
      check_cpu_reg(24, 32'h00000000);   // Backup of x14: min_neg - min_neg = 0

      // Test Set 5 results (pattern subtraction) - backed up in x25-x26
      check_cpu_reg(25, 32'h01234567);   // Backup of x8:  0x12345678 - 0x11111111
      check_cpu_reg(26, 32'h55555555);   // Backup of x10: 0xAAAAAAAA - 0x55555555

      // Test Set 6 results (zero operands) - backed up in x27-x28
      check_cpu_reg(27, 32'h00000000);   // Backup of x12: 0 - 0 = 0
      check_cpu_reg(28, 32'h12345678);   // Backup of x14: 0x12345678 - 0

      // Test Set 7 result (consecutive subtractions) - backed up in x29
      check_cpu_reg(29, 32'h00000EEF);   // Backup of x8: 4096 - 256 - 16 - 1 = 3823

      // Test Set 8 results (self-subtraction) - backed up in x30, x2
      check_cpu_reg(30, 32'h00000000);   // Backup of x9:  self - self = 0
      check_cpu_reg(2,  32'h00000000);   // Backup of x10: self - self = 0

      // Test Set 9 results (all register combinations) - backed up in x3-x5
      check_cpu_reg(3,  32'hE0000000);   // Backup of x8:  0xF0000000 - 0x10000000
      check_cpu_reg(4,  32'hFFFFFE01);   // Backup of x10: 0xFFFFFF00 - 0xFF
      check_cpu_reg(5,  32'hCAFDEFC0);   // Backup of x12: 0xCAFEBABE - 0x0000CAFE

      // Final state of x8-x15 (from Test Set 9)
      check_cpu_reg(8,  32'hE0000000);   // Final value from Test Set 9
      check_cpu_reg(9,  32'h10000000);   // Final value (unchanged from last load)
      check_cpu_reg(10, 32'hFFFFFE01);   // Final value from Test Set 9
      check_cpu_reg(11, 32'h000000FF);   // Final value (unchanged from last load)
      check_cpu_reg(12, 32'hCAFDEFC0);   // Final value from Test Set 9
      check_cpu_reg(13, 32'h0000CAFE);   // Final value (unchanged from last load)
      check_cpu_reg(14, 32'h12345678);   // Final value (unchanged from Test Set 6)
      check_cpu_reg(15, 32'h00000000);   // Final value (unchanged from initial)

      check_cpu_reg(31, 32'hDEADBEEF);   // Test complete marker

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end
