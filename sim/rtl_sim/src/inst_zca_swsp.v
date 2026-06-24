//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_swsp
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SWSP
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.SWSP              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'h57050001);
      check_cpu_reg(2,  32'h80000400);   // SP
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'h12345678);
      check_cpu_reg(9,  32'hABCDEF01);
      check_cpu_reg(10, 32'hFFFFFFFF);
      check_cpu_reg(11, 32'h00000000);
      check_cpu_reg(12, 32'h80000000);
      check_cpu_reg(13, 32'h7FFFFFFF);
      check_cpu_reg(14, 32'hAAAAAAAA);
      check_cpu_reg(15, 32'h55555555);
      check_cpu_reg(16, 32'h11111111);
      check_cpu_reg(17, 32'h22222222);
      check_cpu_reg(18, 32'h33333333);
      check_cpu_reg(19, 32'h44444444);
      check_cpu_reg(20, 32'hDEADCAFE);
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
      $display("|         CHECK FINAL STATE AFTER ALL C.SWSP TESTS                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Test Set 1 verification - data loaded back to x21-x24
      check_cpu_reg(21, 32'h12345678);   // Loaded from [SP+0]  (stored from x8)
      check_cpu_reg(22, 32'hABCDEF01);   // Loaded from [SP+4]  (stored from x9)
      check_cpu_reg(23, 32'hFFFFFFFF);   // Loaded from [SP+8]  (stored from x10)
      check_cpu_reg(24, 32'h00000000);   // Loaded from [SP+12] (stored from x11)

      // SP verification - backed up in x25
      check_cpu_reg(25, 32'h80000400);   // SP unchanged

      // Source register verification - backed up in x26-x27
      check_cpu_reg(26, 32'h12345678);   // x8 unchanged after store
      check_cpu_reg(27, 32'hABCDEF01);   // x9 unchanged after store

      // Test Set 2 verification - data loaded back to x28-x29
      check_cpu_reg(28, 32'h80000000);   // Loaded from [SP+16] (stored from x12)
      check_cpu_reg(29, 32'h7FFFFFFF);   // Loaded from [SP+20] (stored from x13)

      // Test Set 3 verification - data loaded back to x30, x3
      check_cpu_reg(30, 32'hAAAAAAAA);   // Loaded from [SP+24] (stored from x14)
      check_cpu_reg(3,  32'h55555555);   // Loaded from [SP+28] (stored from x15)

      // Test Set 4 verification - data loaded back to x4-x5
      check_cpu_reg(4,  32'h11111111);   // Loaded from [SP+32] (stored from x16)
      check_cpu_reg(5,  32'h22222222);   // Loaded from [SP+36] (stored from x17)

      // Test Set 5 verification - data loaded back to x6
      check_cpu_reg(6,  32'h33333333);   // Loaded from [SP+64] (stored from x18)

      // Test Set 6 verification - data loaded back to x7
      check_cpu_reg(7,  32'h44444444);   // Loaded from [SP+128] (stored from x19)

      // Test Set 7 verification - data loaded back to x11
      check_cpu_reg(11, 32'hDEADCAFE);   // Loaded from [SP+252] (stored from x20, max offset)

      // Test Set 8 verification - data loaded back to x13
      check_cpu_reg(13, 32'h57050001);   // Loaded from [SP+40] (stored from x1)

      // Test Set 9 verification - data loaded back to x14
      check_cpu_reg(14, 32'hABCDEF01);   // Loaded from [SP+44] (last write was x9, overwrite test)

      // Test Set 10 verification - data loaded back to x15-x16
      check_cpu_reg(15, 32'h80000400);   // Loaded from [SP+48] (stored from x25 which is SP)
      check_cpu_reg(16, 32'h12345678);   // Loaded from [SP+52] (stored from x26 which is x8 backup)

      // Test Set 11 verification - data loaded back to x17
      check_cpu_reg(17, 32'h00000000);   // Loaded from [SP+56] (stored from x0, always zero)

      // Final state - verify source registers that should remain unchanged
      check_cpu_reg(1,  32'h57050001);   // x1 unchanged
      check_cpu_reg(2,  32'h80000400);   // SP unchanged
      check_cpu_reg(8,  32'h12345678);   // x8 unchanged (source reg)
      check_cpu_reg(9,  32'hABCDEF01);   // x9 unchanged (source reg)
      check_cpu_reg(10, 32'hFFFFFFFF);   // x10 unchanged (source reg)
      check_cpu_reg(12, 32'h80000000);   // x12 unchanged (source reg)
      check_cpu_reg(18, 32'h33333333);   // x18 unchanged (source reg)
      check_cpu_reg(19, 32'h44444444);   // x19 unchanged (source reg)
      check_cpu_reg(20, 32'hDEADCAFE);   // x20 unchanged (source reg)

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
