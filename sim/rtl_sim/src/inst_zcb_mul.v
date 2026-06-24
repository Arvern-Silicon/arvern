//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_mul
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.MUL
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.MUL                |");
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
      check_cpu_reg(8,  32'h00000002);   // 2
      check_cpu_reg(9,  32'h00000003);   // 3
      check_cpu_reg(10, 32'h00000005);   // 5
      check_cpu_reg(11, 32'h00000007);   // 7
      check_cpu_reg(12, 32'h0000000A);   // 10
      check_cpu_reg(13, 32'h00000064);   // 100
      check_cpu_reg(14, 32'h000003E8);   // 1000
      check_cpu_reg(15, 32'h00002710);   // 10000
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
      $display("|         CHECK FINAL STATE AFTER ALL C.MUL TESTS                   |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check marker register
      check_cpu_reg(1,  32'hBADC0FFE);   // Unchanged marker

      // Test Set 1 results (basic small multiplications) - backed up in x16-x18
      check_cpu_reg(16, 32'h00000006);   // Backup of x8:  2 * 3 = 6
      check_cpu_reg(17, 32'h00000023);   // Backup of x10: 5 * 7 = 35 (0x23)
      check_cpu_reg(18, 32'h000003E8);   // Backup of x12: 10 * 100 = 1000 (0x3E8)

      // Test Set 2 results (multiply by zero - annihilation) - backed up in x19-x20
      check_cpu_reg(19, 32'h00000000);   // Backup of x8:  0x12345678 * 0 = 0
      check_cpu_reg(20, 32'h00000000);   // Backup of x10: 0xABCDEF01 * 0 = 0

      // Test Set 3 results (multiply by one - identity) - backed up in x21-x22
      check_cpu_reg(21, 32'h12345678);   // Backup of x8:  0x12345678 * 1 = 0x12345678
      check_cpu_reg(22, 32'hABCDEF01);   // Backup of x10: 0xABCDEF01 * 1 = 0xABCDEF01

      // Test Set 4 results (negative numbers) - backed up in x23-x24
      check_cpu_reg(23, 32'hFFFFFFFB);   // Backup of x12: -1 * 5 = -5 (0xFFFFFFFB)
      check_cpu_reg(24, 32'h00000001);   // Backup of x14: -1 * -1 = 1

      // Test Set 5 results (powers of two) - backed up in x25-x26
      check_cpu_reg(25, 32'h00000040);   // Backup of x8:  16 * 4 = 64 (0x40)
      check_cpu_reg(26, 32'h00000800);   // Backup of x10: 256 * 8 = 2048 (0x800)

      // Test Set 6 results (large numbers and overflow) - backed up in x27-x28
      check_cpu_reg(27, 32'h00000000);   // Backup of x12: 0x10000000 * 16 = 0 (overflow)
      check_cpu_reg(28, 32'hFFFFFFE2);   // Backup of x10: -6 * 5 = -30 (0xFFFFFFE2) - from Test Set 11, overwrote earlier

      // Test Set 7 results (boundary values) - backed up in x29-x30
      check_cpu_reg(29, 32'hFFFFFFFE);   // Backup of x8:  0x7FFFFFFF * 2 = 0xFFFFFFFE
      check_cpu_reg(30, 32'h00000000);   // Backup of x10: 0x80000000 * 2 = 0 (overflow)

      // Test Set 8 results (squares) - backed up in x2-x3
      check_cpu_reg(2,  32'h00000004);   // Backup of x12: 2 * 2 = 4
      check_cpu_reg(3,  32'h00000064);   // Backup of x14: 10 * 10 = 100 (0x64)

      // Test Set 9 results (specific patterns) - backed up in x4-x5
      check_cpu_reg(4,  32'hFFFFFFFF);   // Backup of x8:  0xFFFF * 0x10001 = 0xFFFFFFFF (lower 32 bits: (2^16-1)*(2^16+1) = 2^32-1)
      check_cpu_reg(5,  32'h00000000);   // Backup of x10: 256 * 16777216 = 0 (overflow)

      // Test Set 10 result (consecutive multiplications) - backed up in x6
      check_cpu_reg(6,  32'h0000001E);   // Backup of x12: 2 * 3 * 5 = 30 (0x1E)

      // Test Set 11 results (small negatives) - backed up in x7, x28 (already checked)
      check_cpu_reg(7,  32'hFFFFFFFA);   // Backup of x8: -2 * 3 = -6 (0xFFFFFFFA)

      // Test Set 12 final values (bit patterns) - remain in registers
      check_cpu_reg(8,  32'hFFFFFFFA);   // Final value from Test Set 11
      check_cpu_reg(9,  32'h00000003);   // Final value from Test Set 11
      check_cpu_reg(10, 32'hFFFFFFE2);   // Final value from Test Set 11
      check_cpu_reg(11, 32'h00000005);   // Final value from Test Set 11
      check_cpu_reg(12, 32'h55555554);   // Final value from Test Set 12: 0xAAAAAAAA * 2
      check_cpu_reg(13, 32'h00000002);   // Final value from Test Set 12
      check_cpu_reg(14, 32'hFFFFFFFF);   // Final value from Test Set 12: 0x55555555 * 3
      check_cpu_reg(15, 32'h00000003);   // Final value from Test Set 12

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
