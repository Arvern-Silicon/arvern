//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_lhu
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.LHU
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.LHU TESTS          |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state
      check_cpu_reg(1,  32'hAABBCCDD);   // Initial test data
      check_cpu_reg(2,  32'h11223344);   // Initial test data
      check_cpu_reg(3,  32'h55667788);   // Initial test data
      check_cpu_reg(4,  32'h99AABBCC);   // Initial test data
      check_cpu_reg(5,  32'hDEADBEEF);   // Initial test data
      check_cpu_reg(6,  32'hCAFEBABE);   // Initial test data
      check_cpu_reg(7,  32'h12345678);   // Initial test data
      check_cpu_reg(8,  32'h80000010);   // Base pointer to SRAM
      check_cpu_reg(9,  32'h00000000);   // Cleared for testing
      check_cpu_reg(10, 32'h00000000);   // Cleared for testing
      check_cpu_reg(11, 32'h00000000);   // Cleared for testing
      check_cpu_reg(12, 32'h00000000);   // Cleared for testing
      check_cpu_reg(13, 32'h00000000);   // Cleared for testing
      check_cpu_reg(14, 32'h00000000);   // Cleared for testing
      check_cpu_reg(15, 32'h00000000);   // Cleared for testing
      check_cpu_reg(16, 32'h87654321);   // Initial test data
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
      $display("|                 CHECK REGISTER VALUES AFTER C.LHU TESTS           |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.LHU tests, check loaded values
      // The test loads halfwords from SRAM using compressed load halfword unsigned
      // Values are zero-extended (upper 16 bits = 0) and backed up to other registers

      // Backup registers from final sets
      check_cpu_reg(1,  32'h00005678);   // Backup from set 7: x15 from SRAM+24 (halfword at offset 0)
      check_cpu_reg(2,  32'h00001234);   // Backup from set 7: x8  from SRAM+26 (halfword at offset 2)
      check_cpu_reg(3,  32'h55667788);   // Unchanged from initial
      check_cpu_reg(4,  32'h99AABBCC);   // Unchanged from initial
      check_cpu_reg(5,  32'hDEADBEEF);   // Unchanged from initial
      check_cpu_reg(6,  32'hCAFEBABE);   // Unchanged from initial
      check_cpu_reg(7,  32'h12345678);   // Unchanged from initial

      // Compressed registers (x8-x15) - final state after all operations
      check_cpu_reg(8,  32'h00004321);   // Final load: c.lhu x8,  0(x15) from SRAM+28 (halfword at offset 0)
      check_cpu_reg(9,  32'h00008765);   // Final load: c.lhu x9,  2(x15) from SRAM+30 (halfword at offset 2)
      check_cpu_reg(10, 32'h80000018);   // Modified to SRAM+8 (base pointer): x29+8
      check_cpu_reg(11, 32'h8000001C);   // Modified to SRAM+12 (base pointer): x29+12
      check_cpu_reg(12, 32'h80000020);   // Modified to SRAM+16 (base pointer): x29+16
      check_cpu_reg(13, 32'h80000024);   // Modified to SRAM+20 (base pointer): x29+20
      check_cpu_reg(14, 32'h80000028);   // Modified to SRAM+24 (base pointer): x29+24
      check_cpu_reg(15, 32'h8000002C);   // Modified to SRAM+28 (base pointer): x29+28

      check_cpu_reg(16, 32'h87654321);   // Unchanged from initial

      // Backups from various test sets
      check_cpu_reg(17, 32'h0000CCDD);   // Backup from set 1: x9  from SRAM+0  (halfword at offset 0)
      check_cpu_reg(18, 32'h0000AABB);   // Backup from set 1: x10 from SRAM+2  (halfword at offset 2)
      check_cpu_reg(19, 32'h00003344);   // Backup from set 2: x10 from SRAM+4  (halfword at offset 0)
      check_cpu_reg(20, 32'h00001122);   // Backup from set 2: x11 from SRAM+6  (halfword at offset 2)
      check_cpu_reg(21, 32'h00007788);   // Backup from set 3: x11 from SRAM+8  (halfword at offset 0)
      check_cpu_reg(22, 32'h00005566);   // Backup from set 3: x12 from SRAM+10 (halfword at offset 2)
      check_cpu_reg(23, 32'h0000BBCC);   // Backup from set 4: x12 from SRAM+12 (halfword at offset 0)
      check_cpu_reg(24, 32'h000099AA);   // Backup from set 4: x13 from SRAM+14 (halfword at offset 2)
      check_cpu_reg(25, 32'h0000BEEF);   // Backup from set 5: x13 from SRAM+16 (halfword at offset 0)
      check_cpu_reg(26, 32'h0000DEAD);   // Backup from set 5: x14 from SRAM+18 (halfword at offset 2)
      check_cpu_reg(27, 32'h0000BABE);   // Backup from set 6: x14 from SRAM+20 (halfword at offset 0)
      check_cpu_reg(28, 32'h0000CAFE);   // Backup from set 6: x15 from SRAM+22 (halfword at offset 2)

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
