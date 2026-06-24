//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_lw
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.LW
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.LW TESTS            |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, compressed registers should be cleared
      check_cpu_reg(1,  32'hAABBCCDD);   // Used for storing test data
      check_cpu_reg(2,  32'h11223344);   // Used for storing test data
      check_cpu_reg(3,  32'h55667788);   // Used for storing test data
      check_cpu_reg(4,  32'h99AABBCC);   // Used for storing test data
      check_cpu_reg(5,  32'hDEADBEEF);   // Used for storing test data
      check_cpu_reg(6,  32'hCAFEBABE);   // Used for storing test data
      check_cpu_reg(7,  32'h12345678);   // Used for storing test data
      check_cpu_reg(8,  32'h80000010);   // Base pointer to SRAM
      check_cpu_reg(9,  32'h00000000);   // Cleared for testing
      check_cpu_reg(10, 32'h00000000);   // Cleared for testing
      check_cpu_reg(11, 32'h00000000);   // Cleared for testing
      check_cpu_reg(12, 32'h00000000);   // Cleared for testing
      check_cpu_reg(13, 32'h00000000);   // Cleared for testing
      check_cpu_reg(14, 32'h00000000);   // Cleared for testing
      check_cpu_reg(15, 32'h00000000);   // Cleared for testing
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
      check_cpu_reg(29, 32'h80000010);   // SRAM base pointer
      check_cpu_reg(30, 32'h00000000);
      check_cpu_reg(31, 32'hDEADBEEF);   // Marker for initial setup complete


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES AFTER C.LW TESTS             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.LW tests, check loaded values
      // The test loads data from SRAM using various compressed load instructions
      // Values are backed up to non-compressed registers for verification

      // Backup registers from fourth load set (c.lw with x11 as base)
      check_cpu_reg(1,  32'hDEADBEEF);   // Backup of x12: c.lw x12, 16(x11)
      check_cpu_reg(2,  32'hCAFEBABE);   // Backup of x13: c.lw x13, 20(x11)
      check_cpu_reg(3,  32'h87654321);   // Backup of x14: c.lw x14, 28(x11)
      check_cpu_reg(4,  32'h87654321);   // Backup of x15: c.lw x15, 124(x12) - max offset
      check_cpu_reg(5,  32'hDEADBEEF);   // Unchanged original data
      check_cpu_reg(6,  32'hCAFEBABE);   // Unchanged original data
      check_cpu_reg(7,  32'h12345678);   // Unchanged original data

      // Compressed registers (x8-x15) - final state after all operations
      check_cpu_reg(8,  32'h80000010);   // Base pointer (unchanged)
      check_cpu_reg(9,  32'h80000014);   // Modified to SRAM+4 (base pointer)
      check_cpu_reg(10, 32'h80000018);   // Modified to SRAM+8 (base pointer)
      check_cpu_reg(11, 32'h80000010);   // Modified to SRAM+0 (base pointer)
      check_cpu_reg(12, 32'h7FFFFFB0);   // Modified to SRAM-96 (base pointer) = 0x80000010 - 0x60
      check_cpu_reg(13, 32'hCAFEBABE);   // Final load: c.lw x13, 20(x11)
      check_cpu_reg(14, 32'h87654321);   // Final load: c.lw x14, 28(x11)
      check_cpu_reg(15, 32'h87654321);   // Final load: c.lw x15, 124(x12)

      // Backup registers from first load set (c.lw with x8 as base)
      check_cpu_reg(16, 32'hAABBCCDD);   // Backup of x9:  c.lw x9,  0(x8)
      check_cpu_reg(17, 32'h11223344);   // Backup of x10: c.lw x10, 4(x8)
      check_cpu_reg(18, 32'h55667788);   // Backup of x11: c.lw x11, 8(x8)
      check_cpu_reg(19, 32'h99AABBCC);   // Backup of x12: c.lw x12, 12(x8)
      check_cpu_reg(20, 32'hDEADBEEF);   // Backup of x13: c.lw x13, 16(x8)
      check_cpu_reg(21, 32'hCAFEBABE);   // Backup of x14: c.lw x14, 20(x8)
      check_cpu_reg(22, 32'h12345678);   // Backup of x15: c.lw x15, 24(x8)

      // Backup registers from second load set (c.lw with x9 as base)
      check_cpu_reg(23, 32'h11223344);   // Backup of x10: c.lw x10, 0(x9)
      check_cpu_reg(24, 32'h55667788);   // Backup of x11: c.lw x11, 4(x9)
      check_cpu_reg(25, 32'h99AABBCC);   // Backup of x12: c.lw x12, 8(x9)
      check_cpu_reg(26, 32'h87654321);   // Backup of x13: c.lw x13, 24(x9)

      // Backup registers from third load set (c.lw with x10 as base)
      check_cpu_reg(27, 32'h55667788);   // Backup of x14: c.lw x14, 0(x10)
      check_cpu_reg(28, 32'h99AABBCC);   // Backup of x15: c.lw x15, 4(x10)

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
