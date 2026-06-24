//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_sw
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SW
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.SW TESTS            |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register values
      check_cpu_reg(1,  32'hAABBCCDD);   // Saved original data
      check_cpu_reg(2,  32'h11223344);   // Saved original data
      check_cpu_reg(3,  32'h55667788);   // Saved original data
      check_cpu_reg(4,  32'h99AABBCC);   // Saved original data
      check_cpu_reg(5,  32'hDEADBEEF);   // Saved original data
      check_cpu_reg(6,  32'hCAFEBABE);   // Saved original data
      check_cpu_reg(7,  32'h12345678);   // Saved original data
      check_cpu_reg(8,  32'hAABBCCDD);   // Test data
      check_cpu_reg(9,  32'h11223344);   // Test data
      check_cpu_reg(10, 32'h55667788);   // Test data
      check_cpu_reg(11, 32'h99AABBCC);   // Test data
      check_cpu_reg(12, 32'hDEADBEEF);   // Test data
      check_cpu_reg(13, 32'hCAFEBABE);   // Test data
      check_cpu_reg(14, 32'h12345678);   // Test data
      check_cpu_reg(15, 32'h87654321);   // Test data
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
      $display("|                 CHECK SRAM VALUES AFTER C.SW TESTS                 |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check stored values in SRAM
      // Note: SRAM base is 0x80000010, indexed at offset -16 bytes
      // So SRAM[0] corresponds to memory address 0x80000000
      // Our stores start at 0x80000010, which is SRAM[4]

      check_mem_value(4,  32'hAABBCCDD);  // SRAM+0:  c.sw x8,  0(x10)
      check_mem_value(5,  32'h11223344);  // SRAM+4:  c.sw x9,  4(x10)
      check_mem_value(6,  32'h99AABBCC);  // SRAM+8:  c.sw x11, 8(x10)
      check_mem_value(7,  32'hDEADBEEF);  // SRAM+12: c.sw x12, 12(x10)
      check_mem_value(8,  32'hCAFEBABE);  // SRAM+16: c.sw x13, 16(x10)
      check_mem_value(9,  32'h12345678);  // SRAM+20: c.sw x14, 20(x10)
      check_mem_value(10, 32'h87654321);  // SRAM+24: c.sw x15, 24(x10)
      check_mem_value(11, 32'hAABBCCDD);  // SRAM+28: c.sw x8,  0(x11)
      check_mem_value(12, 32'h11223344);  // SRAM+32: c.sw x9,  4(x11)
      check_mem_value(13, 32'h80000010);  // SRAM+36: c.sw x10, 8(x11) - x10 holds base pointer
      check_mem_value(14, 32'hCAFEBABE);  // SRAM+40: c.sw x13, 0(x12)
      check_mem_value(15, 32'h12345678);  // SRAM+44: c.sw x14, 4(x12)
      check_mem_value(16, 32'h87654321);  // SRAM+48: c.sw x15, 8(x12)
      check_mem_value(17, 32'hAABBCCDD);  // SRAM+52: c.sw x8,  52(x13)
      check_mem_value(18, 32'h11223344);  // SRAM+56: c.sw x9,  56(x13)
      check_mem_value(19, 32'h12345678);  // SRAM+60: c.sw x14, 60(x13)
      check_mem_value(20, 32'h87654321);  // SRAM+64: c.sw x15, 124(x14)
      check_mem_value(21, 32'hAABBCCDD);  // SRAM+68: c.sw x8,  0(x15)
      check_mem_value(22, 32'h11223344);  // SRAM+72: c.sw x9,  4(x15)
      check_mem_value(23, 32'h80000010);  // SRAM+76: c.sw x10, 8(x15) - x10 holds base pointer
      check_mem_value(24, 32'h8000002C);  // SRAM+80: c.sw x11, 12(x15) - x11 = SRAM+28
      check_mem_value(25, 32'h80000038);  // SRAM+84: c.sw x12, 16(x15) - x12 = SRAM+40
      check_mem_value(26, 32'h80000010);  // SRAM+88: c.sw x13, 20(x15) - x13 = SRAM+0
      check_mem_value(27, 32'h7FFFFFD4);  // SRAM+92: c.sw x14, 24(x15) - x14 = SRAM-60
      check_mem_value(28, 32'h11223344);  // SRAM+96: c.sw x9,  0(x8)

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES AFTER C.SW TESTS             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      // After C.SW tests, some registers have been modified to hold pointers
      check_cpu_reg(1,  32'hAABBCCDD);   // Unchanged
      check_cpu_reg(2,  32'h11223344);   // Unchanged
      check_cpu_reg(3,  32'h55667788);   // Unchanged
      check_cpu_reg(4,  32'h99AABBCC);   // Unchanged
      check_cpu_reg(5,  32'hDEADBEEF);   // Unchanged
      check_cpu_reg(6,  32'hCAFEBABE);   // Unchanged
      check_cpu_reg(7,  32'h12345678);   // Unchanged

      // Compressed registers - modified during test
      check_cpu_reg(8,  32'h80000070);   // x8 = SRAM base + 96
      check_cpu_reg(9,  32'h11223344);   // Original test data (unchanged)
      check_cpu_reg(10, 32'h80000010);   // x10 = SRAM base pointer
      check_cpu_reg(11, 32'h8000002C);   // x11 = SRAM base + 28
      check_cpu_reg(12, 32'h80000038);   // x12 = SRAM base + 40
      check_cpu_reg(13, 32'h80000010);   // x13 = SRAM base + 0
      check_cpu_reg(14, 32'h7FFFFFD4);   // x14 = SRAM base - 60
      check_cpu_reg(15, 32'h80000054);   // x15 = SRAM base + 68

      check_cpu_reg(16, 32'h00000000);   // Unchanged
      check_cpu_reg(17, 32'h00000000);   // Unchanged
      check_cpu_reg(18, 32'h00000000);   // Unchanged
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
