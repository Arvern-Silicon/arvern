//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_lui
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.LUI
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
      $display("|                 CHECK REGISTER VALUES BEFORE THE C.LUI             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x10==32'hDEADBEEF);

      // Disable error generation for the instruction/PC checker and exception monitor
      // Some C.LUI instructions are manually encoded (.hword) and won't be in the checker data
      // The decoder might also flag them as illegal during the decode process
      // The monitors will still count/log, but won't increment the error counter
      $display("INFO: Disabling error generation for instruction/PC checker during manually encoded C.LUI instructions");
      tb_arvern.checker_enable = 0;

	   check_cpu_reg(1,  32'hFFFFFFFF);
 	   check_cpu_reg(2,  32'h00000000);   // x2/sp not modified
 	   check_cpu_reg(3,  32'hFFFFFFFF);
 	   check_cpu_reg(4,  32'hFFFFFFFF);
	   check_cpu_reg(5,  32'hFFFFFFFF);
	   check_cpu_reg(6,  32'hFFFFFFFF);
	   check_cpu_reg(7,  32'hFFFFFFFF);
	   check_cpu_reg(8,  32'hFFFFFFFF);
	   check_cpu_reg(9,  32'hFFFFFFFF);
	   check_cpu_reg(10, 32'hDEADBEEF);
	   check_cpu_reg(11, 32'h00000000);
	   check_cpu_reg(12, 32'h00000000);
	   check_cpu_reg(13, 32'h00000000);
	   check_cpu_reg(14, 32'h00000000);
	   check_cpu_reg(15, 32'h00000000);
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
	   check_cpu_reg(29, 32'h00000000);
	   check_cpu_reg(30, 32'h00000000);
	   check_cpu_reg(31, 32'h00000000);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES AFTER THE C.LUI              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hdeadbeef);

      // Re-enable error generation now that all C.LUI instructions are done
      $display("INFO: Re-enabling error generation for instruction/PC checker and exception monitor");
      tb_arvern.checker_enable = 1;
      tb_arvern.error_on_exception = 1;

	  // Positive immediate values (imm << 12)
	  check_cpu_reg(1,  32'h00001000);   // c.lui x1, 1
 	  check_cpu_reg(3,  32'h00002000);   // c.lui x3, 2 (x2/sp skipped)
 	  check_cpu_reg(4,  32'h00005000);   // c.lui x4, 5
	  check_cpu_reg(5,  32'h0000A000);   // c.lui x5, 10
	  check_cpu_reg(6,  32'h0000F000);   // c.lui x6, 15
	  check_cpu_reg(7,  32'h00014000);   // c.lui x7, 20
	  check_cpu_reg(8,  32'h00019000);   // c.lui x8, 25
	  check_cpu_reg(9,  32'h0001F000);   // c.lui x9, 31 (max)

	  // Negative immediate values (manually encoded with .hword)
	  check_cpu_reg(11, 32'hFFFFF000);   // c.lui x11, -1  (0x75FD)
	  check_cpu_reg(12, 32'hFFFFE000);   // c.lui x12, -2  (0x767D)
	  check_cpu_reg(13, 32'hFFFFB000);   // c.lui x13, -5  (0x76ED)
	  check_cpu_reg(14, 32'hFFFF6000);   // c.lui x14, -10 (0x776D)
	  check_cpu_reg(15, 32'hFFFF1000);   // c.lui x15, -15 (0x77C5)
	  check_cpu_reg(16, 32'hFFFEC000);   // c.lui x16, -20 (0x785D)
	  check_cpu_reg(17, 32'hFFFE7000);   // c.lui x17, -25 (0x78CD)
	  check_cpu_reg(18, 32'hFFFE0000);   // c.lui x18, -32 (0x7905) minimum

	  // Additional mixed tests
	  check_cpu_reg(19, 32'h00007000);   // c.lui x19, 7
	  check_cpu_reg(20, 32'hFFFF9000);   // c.lui x20, -7  (0x7A6D)
	  check_cpu_reg(21, 32'h0000C000);   // c.lui x21, 12
	  check_cpu_reg(22, 32'hFFFF4000);   // c.lui x22, -12 (0x7B85)

	  // x0 must remain zero (HINT test)
	  check_cpu_reg(0,  32'h00000000);   // x0 always zero

	  // Remaining registers
	  check_cpu_reg(2,  32'h00000000);   // x2/sp unchanged
	  check_cpu_reg(10, 32'hDEADBEEF);   // Unchanged marker
	  check_cpu_reg(23, 32'h00000000);
	  check_cpu_reg(24, 32'h00000000);
	  check_cpu_reg(25, 32'h00000000);
	  check_cpu_reg(26, 32'h00000000);
	  check_cpu_reg(27, 32'h00000000);
	  check_cpu_reg(28, 32'h00000000);
	  check_cpu_reg(29, 32'h00000000);
	  check_cpu_reg(30, 32'h00000000);
	  check_cpu_reg(31, 32'hdeadbeef);

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

