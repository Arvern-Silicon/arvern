//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_add
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.ADD
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.ADD               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'hADD1711E);
      check_cpu_reg(2,  32'h00000000);
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'h00000100);   // 256
      check_cpu_reg(9,  32'h00000050);   // 80
      check_cpu_reg(10, 32'h00000001);   // 1
      check_cpu_reg(11, 32'h00000002);   // 2
      check_cpu_reg(12, 32'h7FFFFFFF);   // Max positive
      check_cpu_reg(13, 32'h00000001);   // 1
      check_cpu_reg(14, 32'h80000000);   // Min negative
      check_cpu_reg(15, 32'hFFFFFFFF);   // -1
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
      $display("|         CHECK FINAL STATE AFTER ALL C.ADD TESTS                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Test Set 1 results (basic addition) - backed up in x16-x19
      check_cpu_reg(16, 32'h00000150);   // Backup of x8:  0x00000100 + 0x00000050
      check_cpu_reg(17, 32'h00000003);   // Backup of x10: 0x00000001 + 0x00000002
      check_cpu_reg(18, 32'h00000050);   // Backup of x9:  source unchanged
      check_cpu_reg(19, 32'h00000002);   // Backup of x11: source unchanged

      // Test Set 2 results (overflow) - backed up in x20-x22
      check_cpu_reg(20, 32'h80000000);   // Backup of x12: 0x7FFFFFFF + 0x00000001
      check_cpu_reg(21, 32'h80000000);   // Backup of x8:  0x7FFFFFFF + 0x00000001
      check_cpu_reg(22, 32'h00000001);   // Backup of x13: source unchanged

      // Test Set 3 result (underflow) - backed up in x23
      check_cpu_reg(23, 32'h00000000);   // Backup of x10: 0x80000000 + 0x80000000

      // Test Set 4 results (adding with -1) - backed up in x24-x25
      check_cpu_reg(24, 32'h00000000);   // Backup of x8:  0xFFFFFFFF + 0x00000001
      check_cpu_reg(25, 32'h00000300);   // Backup of x10: 0xFFFFFFFF + 0xFFFFFFFF

      // Test Set 5: Identity property (n + 0 = n) not backed up - trivial property

      // Test Set 6 result (consecutive additions) - backed up in x28
      check_cpu_reg(28, 32'h00000005);   // Backup of x8: 1+1+1+1+1 = 5

      // Test Set 7 results (mixed positive/negative) - backed up in x29-x30
      check_cpu_reg(29, 32'h00000FFF);   // Backup of x10: 0x00001000 + 0xFFFFFFFF
      check_cpu_reg(30, 32'hFFFFFFFF);   // Backup of x12: 0x7FFFFFFF + 0x80000000

      // Test Set 8 results (non-compressed registers) - backed up in x2-x3
      check_cpu_reg(2,  32'h00000300);   // Backup of x25: 0x00000100 + 0x00000200
      check_cpu_reg(3,  32'hADD1711D);   // Backup of x1:  0xADD1711E + 0xFFFFFFFF

      // Test Set 9 results (self-addition) - backed up in x4-x5
      check_cpu_reg(4,  32'h00000020);   // Backup of x14: 0x00000010 * 2
      check_cpu_reg(5,  32'h00000000);   // Backup of x15: 0x80000000 * 2 (overflow)

      // Test Set 10 results (pattern addition) - backed up in x6-x7
      check_cpu_reg(6,  32'h23456789);   // Backup of x8:  0x12345678 + 0x11111111
      check_cpu_reg(7,  32'hFFFFFFFF);   // Backup of x10: 0xAAAAAAAA + 0x55555555

      // Final state of x1-x15 (after all test sets)
      check_cpu_reg(1,  32'hADD1711D);   // Final value from Test Set 8
      // x2, x3 already checked (backups from Test Set 8)
      // x4, x5 already checked (backups from Test Set 9)
      // x6, x7 already checked (backups from Test Set 10)
      check_cpu_reg(8,  32'h23456789);   // Final value from Test Set 10
      check_cpu_reg(9,  32'h11111111);   // Final value from Test Set 10
      check_cpu_reg(10, 32'hFFFFFFFF);   // Final value from Test Set 10
      check_cpu_reg(11, 32'h55555555);   // Final value from Test Set 10
      check_cpu_reg(12, 32'hFFFFFFFF);   // Final value from Test Set 7
      check_cpu_reg(13, 32'h80000000);   // Final value from Test Set 7
      check_cpu_reg(14, 32'h00000020);   // Final value from Test Set 9
      check_cpu_reg(15, 32'h00000000);   // Final value from Test Set 9

      // Final state of non-compressed registers from Test Set 8
      check_cpu_reg(25, 32'h00000300);   // Final value from Test Set 8
      check_cpu_reg(26, 32'h00000200);   // Final value from Test Set 8
      check_cpu_reg(27, 32'hFFFFFFFF);   // Final value from Test Set 8

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
