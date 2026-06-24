//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_jr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.JR
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.JR                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'h1600D001);
      check_cpu_reg(2,  32'h00000000);
      check_cpu_reg(3,  32'h00000000);
      check_cpu_reg(4,  32'h00000000);
      check_cpu_reg(5,  32'h00000000);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'h00000000);
      check_cpu_reg(9,  32'h00000000);
      check_cpu_reg(10, 32'h00000000);
      check_cpu_reg(11, 32'h00000000);
      check_cpu_reg(12, 32'h00000000);
      check_cpu_reg(13, 32'h00000000);
      check_cpu_reg(14, 32'h00000000);
      check_cpu_reg(15, 32'h00000000);
      check_cpu_reg(16, 32'h00000000);   // Jump counter
      check_cpu_reg(17, 32'h00000000);   // Test counter
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
      $display("|         CHECK FINAL STATE AFTER ALL C.JR TESTS                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Verify backed up results in x26-x30
      check_cpu_reg(26, 32'h0000000D);   // Jump counter: 13 jumps executed
      check_cpu_reg(27, 32'h0000000A);   // Test counter: 10 tests executed
      check_cpu_reg(28, 32'h00000000);   // Skipped counter: 0 (all instructions after jumps were skipped)
      check_cpu_reg(29, 32'h00000003);   // Chain counter: 3 (Test Set 4)
      check_cpu_reg(30, 32'h00000001);   // Function body counter: 1 (Test Set 7)

      // Verify final state of working registers
      check_cpu_reg(16, 32'h0000000D);   // Final jump counter
      check_cpu_reg(17, 32'h0000000A);   // Final test counter
      check_cpu_reg(18, 32'h00000000);   // Final skipped counter
      check_cpu_reg(19, 32'h00000003);   // Final chain counter
      check_cpu_reg(23, 32'h00000001);   // Final function body counter

      // Verify register preservation (Test Set 5)
      // x20 and x21 should contain the same value (x12 before and after jump)
      // We can't check the exact value because it's a label address, but they should be equal
      // For now, we'll just check they're non-zero
      // Actually, the testbench can check they're equal
      if (probes_cpu.x20 != probes_cpu.x21) begin
         $display("ERROR: Register preservation failed in Test Set 5 - x12 was modified by C.JR");
         $display("       x20 (before jump) = 0x%08x", probes_cpu.x20);
         $display("       x21 (after jump)  = 0x%08x", probes_cpu.x21);
      end else begin
         $display("PASS:  Register preservation Test Set 5 - x12 unchanged by C.JR");
      end

      // Verify register preservation (Test Set 9)
      // x24 and x25 should contain the same value (x1 before and after jump)
      if (probes_cpu.x24 != probes_cpu.x25) begin
         $display("ERROR: Register preservation failed in Test Set 9 - x1 was modified by C.JR");
         $display("       x24 (before jump) = 0x%08x", probes_cpu.x24);
         $display("       x25 (after jump)  = 0x%08x", probes_cpu.x25);
      end else begin
         $display("PASS:  Register preservation Test Set 9 - x1 unchanged by C.JR");
      end

      // Verify jump table test (Test Set 6)
      check_cpu_reg(22, 32'h00000001);   // Case 0 executed

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
