//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_jalr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.JALR
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.JALR              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'h00000000);
      check_cpu_reg(2,  32'h1A120002);
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
      check_cpu_reg(16, 32'h00000000);   // Call counter
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
      $display("|         CHECK FINAL STATE AFTER ALL C.JALR TESTS                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Verify backed up results in x27-x30
      check_cpu_reg(27, 32'h0000001D);   // Call counter: 29 calls executed
      check_cpu_reg(28, 32'h0000000E);   // Test counter: 14 tests executed
      check_cpu_reg(29, 32'h0000001B);   // Function body counter: 27 function calls
      check_cpu_reg(30, 32'h00000003);   // Sequential call counter: 3 (Test Set 5)

      // Verify final state of working registers
      check_cpu_reg(16, 32'h0000001D);   // Final call counter
      check_cpu_reg(17, 32'h0000000E);   // Final test counter
      check_cpu_reg(19, 32'h0000001B);   // Final function body counter
      check_cpu_reg(22, 32'h00000003);   // Final sequential call counter

      // Verify register preservation (Test Set 3)
      // x20 and x21 should contain the same value (x9 before and after call)
      if (probes_cpu.x20 != probes_cpu.x21) begin
         $display("ERROR: Register preservation failed in Test Set 3 - x9 was modified by C.JALR");
         $display("       x20 (before call) = 0x%08x", probes_cpu.x20);
         $display("       x21 (after call)  = 0x%08x", probes_cpu.x21);
      end else begin
         $display("PASS:  Register preservation Test Set 3 - x9 unchanged by C.JALR");
      end

      // Verify Test Set 7 result (addition function)
      check_cpu_reg(23, 32'h00000008);   // Result of 5 + 3 = 8

      // Verify Test Set 8 result (factorial of 3)
      check_cpu_reg(24, 32'h00000006);   // factorial(3) = 6

      // Verify Test Set 9 result (function pointer)
      check_cpu_reg(25, 32'h00000001);   // Function pointer counter (func1 was called)

      // Verify Test Set 6 (calling with x1 as source)
      // x4 should contain the original function address
      // x5 should contain the return address (different from x4)
      // We can't check exact values, but they should be different
      if (probes_cpu.x04 == probes_cpu.x05) begin
         $display("ERROR: Test Set 6 - x1 was not updated with return address");
         $display("       x4 (original x1) = 0x%08x", probes_cpu.x04);
         $display("       x5 (new x1)      = 0x%08x", probes_cpu.x05);
      end else begin
         $display("PASS:  Test Set 6 - x1 correctly updated with return address");
      end

      // x26 should contain return address from Test Set 10
      // It should be non-zero (we can't check exact value as it's a label address)
      if (probes_cpu.x26 == 32'h00000000) begin
         $display("ERROR: Test Set 10 - Return address was not saved");
      end else begin
         $display("PASS:  Test Set 10 - Return address saved in x1: 0x%08x", probes_cpu.x26);
      end

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
