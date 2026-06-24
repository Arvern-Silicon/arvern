//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_not
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.NOT
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.NOT                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'hB171AB1E);
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
      $display("|         CHECK FINAL STATE AFTER ALL C.NOT TESTS                   |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check marker register
      check_cpu_reg(1,  32'hB171AB1E);   // Unchanged marker

      // Test Set 1 results (first NOT operations) - backed up in x16-x23
      check_cpu_reg(16, 32'h55555555);   // Backup of x8:  ~0xAAAAAAAA = 0x55555555
      check_cpu_reg(17, 32'hAAAAAAAA);   // Backup of x9:  ~0x55555555 = 0xAAAAAAAA
      check_cpu_reg(18, 32'h00000000);   // Backup of x10: ~0xFFFFFFFF = 0x00000000
      check_cpu_reg(19, 32'hFFFFFFFF);   // Backup of x11: ~0x00000000 = 0xFFFFFFFF
      check_cpu_reg(20, 32'h0F0F0F0F);   // Backup of x12: ~0xF0F0F0F0 = 0x0F0F0F0F
      check_cpu_reg(21, 32'hF0F0F0F0);   // Backup of x13: ~0x0F0F0F0F = 0xF0F0F0F0
      check_cpu_reg(22, 32'hEDCBA987);   // Backup of x14: ~0x12345678 = 0xEDCBA987
      check_cpu_reg(23, 32'h543210FE);   // Backup of x15: ~0xABCDEF01 = 0x543210FE

      // Test Set 2 results (double NOT - idempotency) - backed up in x24-x27
      check_cpu_reg(24, 32'hAAAAAAAA);   // Backup of x8:  ~~0xAAAAAAAA = 0xAAAAAAAA (original)
      check_cpu_reg(25, 32'hFFFFFFFF);   // Backup of x10: ~~0xFFFFFFFF = 0xFFFFFFFF (original)
      check_cpu_reg(26, 32'hF0F0F0F0);   // Backup of x12: ~~0xF0F0F0F0 = 0xF0F0F0F0 (original)
      check_cpu_reg(27, 32'h12345678);   // Backup of x14: ~~0x12345678 = 0x12345678 (original)

      // Test Set 3 results (boundary patterns) - backed up in x28-x30, x2
      // NOTE: x28 is overwritten in Test Set 5, so we don't check it here
      check_cpu_reg(29, 32'hFFFFFFFE);   // Backup of x9:  ~0x00000001 = 0xFFFFFFFE
      check_cpu_reg(30, 32'h00FF00FF);   // Backup of x10: ~0xFF00FF00 = 0x00FF00FF
      check_cpu_reg(2,  32'hFF00FF00);   // Backup of x11: ~0x00FF00FF = 0xFF00FF00

      // Test Set 4 results (complex patterns) - backed up in x3-x6
      check_cpu_reg(3,  32'h5A5A5A5A);   // Backup of x12: ~0xA5A5A5A5 = 0x5A5A5A5A
      check_cpu_reg(4,  32'hA5A5A5A5);   // Backup of x13: ~0x5A5A5A5A = 0xA5A5A5A5
      check_cpu_reg(5,  32'h3C3C3C3C);   // Backup of x14: ~0xC3C3C3C3 = 0x3C3C3C3C
      check_cpu_reg(6,  32'hC3C3C3C3);   // Backup of x15: ~0x3C3C3C3C = 0xC3C3C3C3

      // Test Set 5 results (triple NOT) - backed up in x7, x28 (reused)
      check_cpu_reg(7,  32'h21524110);   // Backup of x8:  ~~~0xDEADBEEF = ~0xDEADBEEF = 0x21524110
      check_cpu_reg(28, 32'h35014541);   // Backup of x9:  ~~~0xCAFEBABE = ~0xCAFEBABE = 0x35014541 (overwrote earlier value)

      // Test Set 6 final values (not backed up, remain in registers)
      check_cpu_reg(8,  32'h21524110);   // Final value from Test Set 5
      check_cpu_reg(9,  32'h35014541);   // Final value from Test Set 5
      check_cpu_reg(10, 32'hFFFFFFFF);   // Final value from Test Set 6: ~0x00000000
      check_cpu_reg(11, 32'h00000000);   // Final value from Test Set 6: ~0xFFFFFFFF
      check_cpu_reg(12, 32'hFEFEFEFE);   // Final value from Test Set 6: ~0x01010101
      check_cpu_reg(13, 32'h7F7F7F7F);   // Final value from Test Set 6: ~0x80808080
      check_cpu_reg(14, 32'h3C3C3C3C);   // Final value from Test Set 4 (unchanged after)
      check_cpu_reg(15, 32'hC3C3C3C3);   // Final value from Test Set 4 (unchanged after)

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
