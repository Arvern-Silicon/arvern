//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbb_orcb
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ORC.B (Zbb)
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
      $display("|             CHECK REGISTER VALUES BEFORE ORC.B TESTS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);

      // After initial setup, check register state with test data
      check_cpu_reg(1,  32'h00000000);   // All bytes zero
      check_cpu_reg(2,  32'hFFFFFFFF);   // All bytes 0xFF
      check_cpu_reg(3,  32'h00000001);   // Only LSB of byte 0 set
      check_cpu_reg(4,  32'h01000000);   // Only LSB of byte 3 set
      check_cpu_reg(5,  32'h00010000);   // Only LSB of byte 2 set
      check_cpu_reg(6,  32'h00000100);   // Only LSB of byte 1 set
      check_cpu_reg(7,  32'h80000000);   // Only MSB of byte 3 set
      check_cpu_reg(8,  32'h00800000);   // Only MSB of byte 2 set
      check_cpu_reg(9,  32'h00008000);   // Only MSB of byte 1 set
      check_cpu_reg(10, 32'h00000080);   // Only MSB of byte 0 set
      check_cpu_reg(11, 32'h00000000);   // Not yet set
      check_cpu_reg(12, 32'h00000000);   // Not yet set
      check_cpu_reg(13, 32'h00000000);   // Not yet set
      check_cpu_reg(14, 32'h00000000);   // Not yet set
      check_cpu_reg(15, 32'h00000000);   // Not yet set
      check_cpu_reg(16, 32'h00000000);   // Not yet set
      check_cpu_reg(17, 32'h00000000);   // Not yet set
      check_cpu_reg(18, 32'h00000000);   // Not yet set
      check_cpu_reg(19, 32'h00000000);   // Not yet set
      check_cpu_reg(20, 32'h00000000);   // Not yet set
      check_cpu_reg(21, 32'h00000000);   // Not yet set
      check_cpu_reg(22, 32'h00000000);   // Not yet set
      check_cpu_reg(23, 32'h00000000);   // Not yet set
      check_cpu_reg(24, 32'h00000000);   // Not yet set
      check_cpu_reg(25, 32'h00000000);   // Not yet set
      check_cpu_reg(26, 32'h00000000);   // Not yet set
      check_cpu_reg(27, 32'h00000000);   // Not yet set
      check_cpu_reg(28, 32'h00000000);   // Not yet set
      check_cpu_reg(29, 32'h00000000);   // Not yet set
      check_cpu_reg(30, 32'h00000000);   // Not yet set
      check_cpu_reg(31, 32'hDEADBEEF);   // Marker for initial setup complete


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             CHECK REGISTER VALUES AFTER ORC.B TESTS               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h12345678);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // After ORC.B tests, check final register state
      // ORC.B operation: rd[i*8+7:i*8] = {8{|rs1[i*8+7:i*8]}} for i=0,1,2,3

      // x1: Test 21 result - orc.b(0x00000000)
      check_cpu_reg(1, 32'h00000000);

      // x2: Test 22 result - orc.b(0x000000FF)
      check_cpu_reg(2, 32'h000000FF);

      // x3: Test 23 result - orc.b(0x0000FF00)
      check_cpu_reg(3, 32'h0000FF00);

      // x4: Test 24 result - orc.b(0x00FF0000)
      check_cpu_reg(4, 32'h00FF0000);

      // x5: Test 25 result - orc.b(0xFF000000)
      check_cpu_reg(5, 32'hFF000000);

      // x6: Test 26 result - orc.b(0xF0F0F0F0)
      check_cpu_reg(6, 32'hFFFFFFFF);

      // x7: Test 27 result - orc.b(0x0F0F0F0F)
      check_cpu_reg(7, 32'hFFFFFFFF);

      // x8: Test 28 result - orc.b(0x00000001)
      check_cpu_reg(8, 32'h000000FF);

      // x9: Test 29 result - orc.b(0x00010000)
      check_cpu_reg(9, 32'h00FF0000);

      // x10: Test 30 result - orc.b(0x01000000)
      check_cpu_reg(10, 32'hFF000000);

      // x11: Test 1 result - orc.b(0x00000000)
      check_cpu_reg(11, 32'h00000000);

      // x12: Test 2 result - orc.b(0xFFFFFFFF)
      check_cpu_reg(12, 32'hFFFFFFFF);

      // x13: Test 3 result - orc.b(0x00000001)
      check_cpu_reg(13, 32'h000000FF);

      // x14: Test 4 result - orc.b(0x01000000)
      check_cpu_reg(14, 32'hFF000000);

      // x15: Test 5 result - orc.b(0x00010000)
      check_cpu_reg(15, 32'h00FF0000);

      // x16: Test 6 result - orc.b(0x00000100)
      check_cpu_reg(16, 32'h0000FF00);

      // x17: Test 7 result - orc.b(0x80000000)
      check_cpu_reg(17, 32'hFF000000);

      // x18: Test 8 result - orc.b(0x00800000)
      check_cpu_reg(18, 32'h00FF0000);

      // x19: Test 9 result - orc.b(0x00008000)
      check_cpu_reg(19, 32'h0000FF00);

      // x20: Test 10 result - orc.b(0x00000080)
      check_cpu_reg(20, 32'h000000FF);

      // x21: Test 11 result - orc.b(0x12345678)
      check_cpu_reg(21, 32'hFFFFFFFF);

      // x22: Test 12 result - orc.b(0x00FF0000)
      check_cpu_reg(22, 32'h00FF0000);

      // x23: Test 13 result - orc.b(0xFF00FF00)
      check_cpu_reg(23, 32'hFF00FF00);

      // x24: Test 14 result - orc.b(0x00FF00FF)
      check_cpu_reg(24, 32'h00FF00FF);

      // x25: Test 15 result - orc.b(0x01010101)
      check_cpu_reg(25, 32'hFFFFFFFF);

      // x26: Test 16 result - orc.b(0x80808080)
      check_cpu_reg(26, 32'hFFFFFFFF);

      // x27: Test 17 result - orc.b(0xAA00AA00)
      check_cpu_reg(27, 32'hFF00FF00);

      // x28: Test 18 result - orc.b(0x00550055)
      check_cpu_reg(28, 32'h00FF00FF);

      // x29: Test 19 result - orc.b(0xDEADBEEF)
      check_cpu_reg(29, 32'hFFFFFFFF);

      // x30: Test 20 result - orc.b(0x10203040)
      check_cpu_reg(30, 32'hFFFFFFFF);

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
