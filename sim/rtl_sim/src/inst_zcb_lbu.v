//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcb_lbu
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.LBU
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.LBU TESTS          |");
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
      check_cpu_reg(16, 32'h87654321);   // Used for storing test data
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
      $display("|                 CHECK REGISTER VALUES AFTER C.LBU TESTS           |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After C.LBU tests, check loaded values
      // The test loads individual bytes from SRAM using compressed load byte unsigned
      // Values are backed up to non-compressed registers for verification

      // Backup registers from first load set (c.lbu from SRAM+0 with x8 as base)
      check_cpu_reg(1,  32'h000000CC);   // Backup from set 4: x12 from SRAM+12 byte 0
      check_cpu_reg(2,  32'h000000BB);   // Backup from set 4: x13 from SRAM+13 byte 1
      check_cpu_reg(3,  32'h000000AA);   // Backup from set 4: x14 from SRAM+14 byte 2
      check_cpu_reg(4,  32'h00000099);   // Backup from set 4: x15 from SRAM+15 byte 3
      check_cpu_reg(5,  32'h000000EF);   // Backup from set 5: x13 from SRAM+16 byte 0
      check_cpu_reg(6,  32'h000000BE);   // Backup from set 5: x14 from SRAM+17 byte 1
      check_cpu_reg(7,  32'h000000AD);   // Backup from set 5: x15 from SRAM+18 byte 2

      // Compressed registers (x8-x15) - final state after all operations
      check_cpu_reg(8,  32'h000000FE);   // Final load: c.lbu x8,  2(x13) from SRAM+22
      check_cpu_reg(9,  32'h000000CA);   // Final load: c.lbu x9,  3(x13) from SRAM+23
      check_cpu_reg(10, 32'h80000018);   // Modified to SRAM+8 (base pointer): x29+8 = 0x80000010+8
      check_cpu_reg(11, 32'h8000001C);   // Modified to SRAM+12 (base pointer): x29+12 = 0x80000010+12
      check_cpu_reg(12, 32'h80000020);   // Modified to SRAM+16 (base pointer): x29+16 = 0x80000010+16
      check_cpu_reg(13, 32'h80000024);   // Modified to SRAM+20 (base pointer): x29+20 = 0x80000010+20
      check_cpu_reg(14, 32'h000000BE);   // Final load: c.lbu x14, 0(x13) from SRAM+20
      check_cpu_reg(15, 32'h000000BA);   // Final load: c.lbu x15, 1(x13) from SRAM+21

      check_cpu_reg(16, 32'h87654321);   // Unchanged (used for initial test data)
      check_cpu_reg(17, 32'h000000DD);   // Backup from set 1: x9  from SRAM+0  byte 0
      check_cpu_reg(18, 32'h000000CC);   // Backup from set 1: x10 from SRAM+1  byte 1
      check_cpu_reg(19, 32'h000000BB);   // Backup from set 1: x11 from SRAM+2  byte 2
      check_cpu_reg(20, 32'h000000AA);   // Backup from set 1: x12 from SRAM+3  byte 3

      check_cpu_reg(21, 32'h00000044);   // Backup from set 2: x10 from SRAM+4  byte 0
      check_cpu_reg(22, 32'h00000033);   // Backup from set 2: x11 from SRAM+5  byte 1
      check_cpu_reg(23, 32'h00000022);   // Backup from set 2: x12 from SRAM+6  byte 2
      check_cpu_reg(24, 32'h00000011);   // Backup from set 2: x13 from SRAM+7  byte 3

      check_cpu_reg(25, 32'h00000088);   // Backup from set 3: x11 from SRAM+8  byte 0
      check_cpu_reg(26, 32'h00000077);   // Backup from set 3: x12 from SRAM+9  byte 1
      check_cpu_reg(27, 32'h00000066);   // Backup from set 3: x13 from SRAM+10 byte 2
      check_cpu_reg(28, 32'h00000055);   // Backup from set 3: x14 from SRAM+11 byte 3

      check_cpu_reg(29, 32'h80000010);   // SRAM base pointer (unchanged)
      check_cpu_reg(30, 32'h000000DE);   // Backup from set 5: x8  from SRAM+19 byte 3
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
