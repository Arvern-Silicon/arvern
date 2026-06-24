//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_xor
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.XOR
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.XOR                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'hBADC0FFE);
      check_cpu_reg(2,  32'h00000000);
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'hAAAAAAAA);   // Alternating pattern
      check_cpu_reg(9,  32'h55555555);   // Alternating pattern
      check_cpu_reg(10, 32'hFFFFFFFF);   // All 1s
      check_cpu_reg(11, 32'h00000000);   // All 0s
      check_cpu_reg(12, 32'hF0F0F0F0);   // Nibble pattern
      check_cpu_reg(13, 32'h0F0F0F0F);   // Inverse nibble
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
      $display("|         CHECK FINAL STATE AFTER ALL C.XOR TESTS                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check marker register
      check_cpu_reg(1,  32'hBADC0FFE);   // Unchanged marker

      // Test Set 1 results (alternating patterns) - backed up in x16-x17
      check_cpu_reg(16, 32'hFFFFFFFF);   // Backup of x8:  0xAAAAAAAA ^ 0x55555555
      check_cpu_reg(17, 32'hFFFFFFFF);   // Backup of x12: 0xF0F0F0F0 ^ 0x0F0F0F0F

      // Test Set 2 results (XOR with zero) - backed up in x18-x19
      check_cpu_reg(18, 32'h12345678);   // Backup of x8:  0x12345678 ^ 0 (identity)
      check_cpu_reg(19, 32'hABCDEF01);   // Backup of x10: 0xABCDEF01 ^ 0 (identity)

      // Test Set 3 results (XOR with all 1s - inversion) - backed up in x20-x21
      check_cpu_reg(20, 32'hEDCBA987);   // Backup of x8:  ~0x12345678
      check_cpu_reg(21, 32'h55555555);   // Backup of x10: ~0xAAAAAAAA

      // Test Set 4 results (self-XOR) - backed up in x22-x23
      check_cpu_reg(22, 32'h00000000);   // Backup of x12: same ^ same = 0
      check_cpu_reg(23, 32'h00000000);   // Backup of x14: same ^ same = 0

      // Test Set 5 results (complementary patterns) - backed up in x24-x25
      check_cpu_reg(24, 32'hFFFFFFFF);   // Backup of x8:  0xFF00FF00 ^ 0x00FF00FF
      check_cpu_reg(25, 32'hFFFFFFFF);   // Backup of x10: 0xF0F0F0F0 ^ 0x0F0F0F0F

      // Test Set 6 results (specific bit patterns) - backed up in x26-x27
      check_cpu_reg(26, 32'hB9F9B979);   // Backup of x12: 0x12345678 ^ 0xABCDEF01
      check_cpu_reg(27, 32'h80000001);   // Backup of x14: 0x80000000 ^ 0x00000001

      // Test Set 7 result (consecutive XORs) - backed up in x28
      check_cpu_reg(28, 32'h00000000);   // Backup of x8: 0xAAAAAAAA ^ 0x55555555 ^ 0xFFFFFFFF

      // Test Set 8 result (bit toggling) - backed up in x29
      check_cpu_reg(29, 32'h92345678);   // Backup of x11: 0x12345678 with MSB toggled

      // Test Set 9 results (various patterns) - backed up in x30, x2, x3
      check_cpu_reg(30, 32'h33333333);   // Backup of x8:  0x11111111 ^ 0x22222222
      check_cpu_reg(2,  32'hCCCCCCCC);   // Backup of x10: 0x44444444 ^ 0x88888888
      check_cpu_reg(3,  32'hFFFFFFFF);   // Backup of x12: 0xCCCCCCCC ^ 0x33333333

      // Test Set 10 result (boundary values) - backed up in x4
      check_cpu_reg(4,  32'hFFFFFFFF);   // Backup of x14: 0x7FFFFFFF ^ 0x80000000

      // Unused registers should remain zero
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);

      // Final state of x8-x15 (from Test Set 9 and 10)
      check_cpu_reg(8,  32'h33333333);   // Final value from Test Set 9
      check_cpu_reg(9,  32'h22222222);   // Final value (unchanged from last load)
      check_cpu_reg(10, 32'hCCCCCCCC);   // Final value from Test Set 9
      check_cpu_reg(11, 32'h88888888);   // Final value from Test Set 8
      check_cpu_reg(12, 32'hFFFFFFFF);   // Final value from Test Set 9
      check_cpu_reg(13, 32'h33333333);   // Final value (unchanged from last load)
      check_cpu_reg(14, 32'hFFFFFFFF);   // Final value from Test Set 10
      check_cpu_reg(15, 32'h80000000);   // Final value (unchanged from last load)

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
