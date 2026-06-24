//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_nop
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.NOP
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.NOP                 |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'h12345678);
      check_cpu_reg(2,  32'hDEADBEEF);
      check_cpu_reg(3,  32'hCAFEBABE);
      check_cpu_reg(4,  32'hABCDEF01);
      check_cpu_reg(5,  32'h11223344);
      check_cpu_reg(6,  32'h55667788);
      check_cpu_reg(7,  32'h99AABBCC);
      check_cpu_reg(8,  32'hDDEEFF00);
      check_cpu_reg(9,  32'h12341234);
      check_cpu_reg(10, 32'h56785678);
      check_cpu_reg(11, 32'h9ABC9ABC);
      check_cpu_reg(12, 32'hDEF0DEF0);
      check_cpu_reg(13, 32'h13571357);
      check_cpu_reg(14, 32'h24682468);
      check_cpu_reg(15, 32'h369C369C);
      check_cpu_reg(16, 32'h48D048D0);
      check_cpu_reg(17, 32'h5A5A5A5A);
      check_cpu_reg(18, 32'h6B6B6B6B);
      check_cpu_reg(19, 32'h7C7C7C7C);
      check_cpu_reg(20, 32'h8D8D8D8D);
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
      $display("|           CHECK AFTER FIRST SET OF C.NOP (10 NOPs)                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hBBBBBBBB);

      // All registers should remain unchanged after NOPs
      check_cpu_reg(1,  32'h12345678);
      check_cpu_reg(2,  32'hDEADBEEF);
      check_cpu_reg(3,  32'hCAFEBABE);
      check_cpu_reg(4,  32'hABCDEF01);
      check_cpu_reg(5,  32'h11223344);
      check_cpu_reg(6,  32'h55667788);
      check_cpu_reg(7,  32'h99AABBCC);
      check_cpu_reg(8,  32'hDDEEFF00);
      check_cpu_reg(9,  32'h12341234);
      check_cpu_reg(10, 32'h56785678);
      check_cpu_reg(11, 32'h9ABC9ABC);
      check_cpu_reg(12, 32'hDEF0DEF0);
      check_cpu_reg(13, 32'h13571357);
      check_cpu_reg(14, 32'h24682468);
      check_cpu_reg(15, 32'h369C369C);
      check_cpu_reg(16, 32'h48D048D0);
      check_cpu_reg(17, 32'h5A5A5A5A);
      check_cpu_reg(18, 32'h6B6B6B6B);
      check_cpu_reg(19, 32'h7C7C7C7C);
      check_cpu_reg(20, 32'h8D8D8D8D);
      check_cpu_reg(21, 32'h00000000);   // Still unchanged
      check_cpu_reg(22, 32'h00000000);   // Still unchanged
      check_cpu_reg(23, 32'h00000000);   // Still unchanged
      check_cpu_reg(24, 32'h00000000);   // Still unchanged
      check_cpu_reg(25, 32'h00000000);
      check_cpu_reg(26, 32'h00000000);
      check_cpu_reg(27, 32'h00000000);
      check_cpu_reg(28, 32'h00000000);
      check_cpu_reg(29, 32'h00000000);
      check_cpu_reg(30, 32'h00000000);
      check_cpu_reg(31, 32'hBBBBBBBB);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|         CHECK AFTER MIXED C.NOP AND OPERATIONS                    |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hCCCCCCCC);

      // Check that NOPs didn't affect operations between them
      check_cpu_reg(1,  32'h12345678);   // Unchanged
      check_cpu_reg(2,  32'hDEADBEEF);   // Unchanged
      check_cpu_reg(3,  32'hCAFEBABE);   // Unchanged
      check_cpu_reg(4,  32'hABCDEF01);   // Unchanged
      check_cpu_reg(5,  32'h11223344);   // Unchanged
      check_cpu_reg(6,  32'h55667788);   // Unchanged
      check_cpu_reg(7,  32'h99AABBCC);   // Unchanged
      check_cpu_reg(8,  32'hDDEEFF00);   // Unchanged
      check_cpu_reg(9,  32'h12341234);   // Unchanged
      check_cpu_reg(10, 32'h56785678);   // Unchanged
      check_cpu_reg(11, 32'h9ABC9ABC);   // Unchanged
      check_cpu_reg(12, 32'hDEF0DEF0);   // Unchanged
      check_cpu_reg(13, 32'h13571357);   // Unchanged
      check_cpu_reg(14, 32'h24682468);   // Unchanged
      check_cpu_reg(15, 32'h369C369C);   // Unchanged
      check_cpu_reg(16, 32'h48D048D0);   // Unchanged
      check_cpu_reg(17, 32'h5A5A5A5A);   // Unchanged
      check_cpu_reg(18, 32'h6B6B6B6B);   // Unchanged
      check_cpu_reg(19, 32'h7C7C7C7C);   // Unchanged
      check_cpu_reg(20, 32'h8D8D8D8D);   // Unchanged
      check_cpu_reg(21, 32'h0000000F);   // Modified: c.li x21, 10; c.addi x21, 5
      check_cpu_reg(22, 32'hFFFFFFF9);   // Modified: c.li x22, -7
      check_cpu_reg(23, 32'h00000000);   // Still unchanged (will be modified later)
      check_cpu_reg(24, 32'h00000000);   // Still unchanged (will be modified later)
      check_cpu_reg(25, 32'h00000000);
      check_cpu_reg(26, 32'h00000000);
      check_cpu_reg(27, 32'h00000000);
      check_cpu_reg(28, 32'h00000000);
      check_cpu_reg(29, 32'h00000000);   // Still unchanged (will be modified later)
      check_cpu_reg(30, 32'h00000000);
      check_cpu_reg(31, 32'hCCCCCCCC);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|         CHECK FINAL STATE AFTER ALL C.NOP TESTS                   |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Final state - verify NOPs didn't affect anything
      check_cpu_reg(1,  32'h12345678);   // Unchanged
      check_cpu_reg(2,  32'hDEADBEEF);   // Unchanged
      check_cpu_reg(3,  32'hCAFEBABE);   // Unchanged
      check_cpu_reg(4,  32'hABCDEF01);   // Unchanged
      check_cpu_reg(5,  32'h11223344);   // Unchanged
      check_cpu_reg(6,  32'h55667788);   // Unchanged
      check_cpu_reg(7,  32'h99AABBCC);   // Unchanged
      check_cpu_reg(8,  32'hDDEEFF00);   // Unchanged
      check_cpu_reg(9,  32'h12341234);   // Unchanged
      check_cpu_reg(10, 32'h56785678);   // Unchanged
      check_cpu_reg(11, 32'h9ABC9ABC);   // Unchanged
      check_cpu_reg(12, 32'hDEF0DEF0);   // Unchanged
      check_cpu_reg(13, 32'h13571357);   // Unchanged
      check_cpu_reg(14, 32'h24682468);   // Unchanged
      check_cpu_reg(15, 32'h369C369C);   // Unchanged
      check_cpu_reg(16, 32'h48D048D0);   // Unchanged
      check_cpu_reg(17, 32'h5A5A5A5A);   // Unchanged
      check_cpu_reg(18, 32'h6B6B6B6B);   // Unchanged
      check_cpu_reg(19, 32'h7C7C7C7C);   // Unchanged
      check_cpu_reg(20, 32'h8D8D8D8D);   // Unchanged
      check_cpu_reg(21, 32'h0000000F);   // Modified by operations (not NOPs)
      check_cpu_reg(22, 32'hFFFFFFF9);   // Modified by operations (not NOPs)
      check_cpu_reg(23, 32'h00000015);   // Modified: c.li x23, 21
      check_cpu_reg(24, 32'h00000015);   // Modified: lw x24, 0(x29) - loaded from SRAM
      check_cpu_reg(25, 32'h00000000);   // Unchanged
      check_cpu_reg(26, 32'h00000000);   // Unchanged
      check_cpu_reg(27, 32'h00000000);   // Unchanged
      check_cpu_reg(28, 32'h00000000);   // Unchanged
      check_cpu_reg(29, 32'h80000010);   // Modified: li x29, 0x80000010
      check_cpu_reg(30, 32'h00000000);   // Unchanged
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
