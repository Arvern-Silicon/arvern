//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_lh
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.LH
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.LH TESTS           |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state
      check_cpu_reg(1,  32'h7FFF0001);   // Initial test data
      check_cpu_reg(2,  32'h80007FFE);   // Initial test data
      check_cpu_reg(3,  32'hFFFF1234);   // Initial test data
      check_cpu_reg(4,  32'hABCD5678);   // Initial test data
      check_cpu_reg(5,  32'hDEADBEEF);   // Initial test data
      check_cpu_reg(6,  32'hCAFEBABE);   // Initial test data
      check_cpu_reg(7,  32'h87654321);   // Initial test data
      check_cpu_reg(8,  32'h80000010);   // Base pointer to SRAM
      check_cpu_reg(9,  32'h00000000);   // Cleared for testing
      check_cpu_reg(10, 32'h00000000);   // Cleared for testing
      check_cpu_reg(11, 32'h00000000);   // Cleared for testing
      check_cpu_reg(12, 32'h00000000);   // Cleared for testing
      check_cpu_reg(13, 32'h00000000);   // Cleared for testing
      check_cpu_reg(14, 32'h00000000);   // Cleared for testing
      check_cpu_reg(15, 32'h00000000);   // Cleared for testing
      check_cpu_reg(16, 32'h9ABC0123);   // Initial test data
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
      $display("|                 CHECK REGISTER VALUES AFTER C.LH TESTS            |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.LH tests, check loaded values
      // The test loads halfwords from SRAM using compressed load halfword with sign-extension
      // Values are sign-extended (upper 16 bits = sign bit replicated)
      // Positive values (bit 15=0): upper 16 bits = 0x0000
      // Negative values (bit 15=1): upper 16 bits = 0xFFFF

      // Backup registers from final sets
      check_cpu_reg(1,  32'h00004321);   // Backup from set 7: x15 from SRAM+24 (sign-extend 0x4321, positive)
      check_cpu_reg(2,  32'hFFFF8765);   // Backup from set 7: x8  from SRAM+26 (sign-extend 0x8765, negative)
      check_cpu_reg(3,  32'hFFFF1234);   // Unchanged from initial
      check_cpu_reg(4,  32'hABCD5678);   // Unchanged from initial
      check_cpu_reg(5,  32'hDEADBEEF);   // Unchanged from initial
      check_cpu_reg(6,  32'hCAFEBABE);   // Unchanged from initial
      check_cpu_reg(7,  32'h87654321);   // Unchanged from initial

      // Compressed registers (x8-x15) - final state after all operations
      check_cpu_reg(8,  32'h00000123);   // Final load: c.lh x8,  0(x15) from SRAM+28 (sign-extend 0x0123, positive)
      check_cpu_reg(9,  32'hFFFF9ABC);   // Final load: c.lh x9,  2(x15) from SRAM+30 (sign-extend 0x9ABC, negative)
      check_cpu_reg(10, 32'h80000018);   // Modified to SRAM+8 (base pointer): x29+8
      check_cpu_reg(11, 32'h8000001C);   // Modified to SRAM+12 (base pointer): x29+12
      check_cpu_reg(12, 32'h80000020);   // Modified to SRAM+16 (base pointer): x29+16
      check_cpu_reg(13, 32'h80000024);   // Modified to SRAM+20 (base pointer): x29+20
      check_cpu_reg(14, 32'h80000028);   // Modified to SRAM+24 (base pointer): x29+24
      check_cpu_reg(15, 32'h8000002C);   // Modified to SRAM+28 (base pointer): x29+28

      check_cpu_reg(16, 32'h9ABC0123);   // Unchanged from initial

      // Backups from various test sets - verifying sign-extension
      check_cpu_reg(17, 32'h00000001);   // Backup from set 1: x9  from SRAM+0  (sign-extend 0x0001, positive)
      check_cpu_reg(18, 32'h00007FFF);   // Backup from set 1: x10 from SRAM+2  (sign-extend 0x7FFF, positive max)
      check_cpu_reg(19, 32'h00007FFE);   // Backup from set 2: x10 from SRAM+4  (sign-extend 0x7FFE, positive)
      check_cpu_reg(20, 32'hFFFF8000);   // Backup from set 2: x11 from SRAM+6  (sign-extend 0x8000, negative min)
      check_cpu_reg(21, 32'h00001234);   // Backup from set 3: x11 from SRAM+8  (sign-extend 0x1234, positive)
      check_cpu_reg(22, 32'hFFFFFFFF);   // Backup from set 3: x12 from SRAM+10 (sign-extend 0xFFFF, -1)
      check_cpu_reg(23, 32'h00005678);   // Backup from set 4: x12 from SRAM+12 (sign-extend 0x5678, positive)
      check_cpu_reg(24, 32'hFFFFABCD);   // Backup from set 4: x13 from SRAM+14 (sign-extend 0xABCD, negative)
      check_cpu_reg(25, 32'hFFFFBEEF);   // Backup from set 5: x13 from SRAM+16 (sign-extend 0xBEEF, negative)
      check_cpu_reg(26, 32'hFFFFDEAD);   // Backup from set 5: x14 from SRAM+18 (sign-extend 0xDEAD, negative)
      check_cpu_reg(27, 32'hFFFFBABE);   // Backup from set 6: x14 from SRAM+20 (sign-extend 0xBABE, negative)
      check_cpu_reg(28, 32'hFFFFCAFE);   // Backup from set 6: x15 from SRAM+22 (sign-extend 0xCAFE, negative)

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
